/// A container written by a newer **major** settings layout is refused with
/// both versions named, and is not relabelled by the refusal.
library;

import 'package:test/test.dart';
import 'package:tom_core_settings/tom_core_settings.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

import 'support/memory_storage.dart';

const _locator = 'mem:/device/settings.kdbx';
const _namespace = 'app';
const _versionKey = '$_namespace.settingsVersion';

TomKdbxSettingsContainer _container(MemoryStorage storage) =>
    TomKdbxSettingsContainer(
      locator: _locator,
      storage: storage,
      namespace: _namespace,
      keys: TomKdbxKeyProvider()
        ..registerKeyFor(_locator, const TomKeyMaterial(passphrase: 'k')),
    );

/// A saved container whose marker says [version] (null: no marker at all).
Future<MemoryStorage> _writtenAs(String? version) async {
  final storage = MemoryStorage();
  final container = _container(storage);
  final store = await container.load();
  TomKdbxIdentityStore(
    store,
  ).write(const TomIdentity(authorId: 'alexis', displayName: 'Alexis'));
  final customData = store.file.body.meta.customData;
  if (version == null) {
    customData.remove(_versionKey);
  } else {
    customData[_versionKey] = version;
  }
  await container.save();
  return storage;
}

void main() {
  test('KDBX-VERSION-1: a newer major layout is refused, naming both versions, '
      'and the container is not relabelled', () async {
    final storage = await _writtenAs('2.0');
    final reopened = _container(storage);

    await expectLater(
      reopened.load(),
      throwsA(
        isA<TomKdbxSettingsVersionException>()
            .having((e) => e.found, 'found', '2.0')
            .having((e) => e.supported, 'supported', '1.0')
            .having(
              (e) => e.message,
              'message',
              allOf(contains('2.0'), contains('1.0')),
            )
            .having((e) => e.locator, 'locator', _locator),
      ),
    );
    expect(
      reopened.isLoaded,
      isFalse,
      reason: 'a refused container is not held, so no write can follow it',
    );

    // Still refused: the refusal did not stamp this build's version on it.
    await expectLater(
      _container(storage).load(),
      throwsA(isA<TomKdbxSettingsVersionException>()),
    );
  });

  test('KDBX-VERSION-2: the same major, a newer minor, opens — minor versions '
      'are additive', () async {
    final store = await _container(await _writtenAs('1.7')).load();
    expect(TomKdbxIdentityStore(store).read().authorId, 'alexis');
  });

  test('KDBX-VERSION-3: a container with no marker, or one this build cannot '
      'parse, opens — a malformed marker is not a reason to lock settings '
      'away', () async {
    for (final version in [null, 'next', '']) {
      final store = await _container(await _writtenAs(version)).load();
      expect(
        TomKdbxIdentityStore(store).read().authorId,
        'alexis',
        reason: 'marker $version',
      );
      expect(store.isSettingsContainer, isTrue);
    }
  });

  test('KDBX-VERSION-4: the markers carry the namespace, so two applications\' '
      'containers are told apart', () async {
    final storage = MemoryStorage();
    final store = await _container(storage).load();
    expect(store.file.body.meta.customData['app.settings'], 'true');
    expect(store.file.body.meta.customData[_versionKey], '1.0');
    final other = TomKdbxSettingsStore(store.file, namespace: 'other');
    expect(other.isSettingsContainer, isFalse);
  });
}
