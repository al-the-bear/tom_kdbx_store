/// The one operation that removes a settings container.
///
/// A wiped keychain leaves the settings container intact and unopenable. A
/// settings interface offers to start fresh; this is what that runs, and it has
/// to refuse every case in which the old file could still be read.
library;

import 'package:test/test.dart';
import 'package:tom_core_storage/settings.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

import 'support/memory_storage.dart';

const locator = 'mem:/device/settings.kdbx';

TomKdbxSettingsContainer _container(
  MemoryStorage storage,
  String at,
  TomKdbxKeyProvider keys,
) => TomKdbxSettingsContainer(
  locator: at,
  storage: storage,
  keys: keys,
  namespace: 'app',
);

Future<MemoryStorage> _written() async {
  final storage = MemoryStorage();
  final container = _container(
    storage,
    locator,
    TomKdbxKeyProvider()
      ..registerKeyFor(locator, const TomKeyMaterial(passphrase: 'old')),
  );
  final store = await container.load();
  TomKdbxIdentityStore(
    store,
  ).write(const TomIdentity(authorId: 'alexis', displayName: 'Alexis'));
  await container.save();
  return storage;
}

TomKdbxSettingsContainer _reopened(MemoryStorage storage, String passphrase) =>
    _container(
      storage,
      locator,
      TomKdbxKeyProvider()
        ..registerKeyFor(locator, TomKeyMaterial(passphrase: passphrase)),
    );

Future<String> _authorOf(TomKdbxSettingsContainer container) async =>
    TomKdbxIdentityStore(await container.load()).read().authorId;

void main() {
  test('KDBX-DISCARD-1: a locked container is replaced by a fresh one, and the '
      'backup is the old file, openable with the old key', () async {
    final storage = await _written();
    final locked = _reopened(storage, 'minted-after-a-wipe');
    await expectLater(locked.load(), throwsA(isA<TomKeyRequiredException>()));

    final backup = await locked.discardUnopenable(
      keepBackup: true,
      now: DateTime.utc(2026, 10, 1, 14, 30, 5),
    );
    expect(backup, '$locator.locked-20261001-143005');

    // The new container opens with the new key and states nothing.
    expect(
      await _authorOf(_reopened(storage, 'minted-after-a-wipe')),
      TomIdentity.unknownAuthorId,
    );

    // The backup is the old file: the old key still opens it.
    final old = _container(
      storage,
      backup!,
      TomKdbxKeyProvider()
        ..registerKeyFor(backup, const TomKeyMaterial(passphrase: 'old')),
    );
    expect(await _authorOf(old), 'alexis');
  });

  test(
    'KDBX-DISCARD-2: without a backup nothing of the old file remains',
    () async {
      final storage = await _written();
      final locked = _reopened(storage, 'new');
      final at = DateTime.utc(2026, 10, 1, 9);
      expect(
        await locked.discardUnopenable(keepBackup: false, now: at),
        isNull,
      );
      expect(storage.exists('$locator.locked-20261001-090000'), isFalse);
      expect(
        storage.exists(locator),
        isTrue,
        reason: 'a fresh container was committed in its place',
      );
    },
  );

  test(
    'KDBX-DISCARD-3: a container that opens is refused and left as it was',
    () async {
      final storage = await _written();
      await expectLater(
        _reopened(storage, 'old').discardUnopenable(keepBackup: true),
        throwsA(isA<StateError>()),
      );
      expect(await _authorOf(_reopened(storage, 'old')), 'alexis');
    },
  );

  test('KDBX-DISCARD-4: with no key configured the file is not locked, and is '
      'refused', () async {
    final storage = await _written();
    final keyless = _container(storage, locator, TomKdbxKeyProvider());
    await expectLater(
      keyless.discardUnopenable(keepBackup: false),
      throwsA(isA<StateError>()),
    );
    expect(await _authorOf(_reopened(storage, 'old')), 'alexis');
  });
}
