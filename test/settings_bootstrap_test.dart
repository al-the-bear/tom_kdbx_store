/// The settings bootstrap's container half: the device's one minted key opens
/// the settings container, and a lost key does not replace it.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_core_storage/settings.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

import 'support/memory_storage.dart';

const deviceLocator = 'mem:/support/device.yaml';
const settingsLocator = 'mem:/support/settings.kdbx';

void main() {
  late MemoryStorage storage;

  setUp(() => storage = MemoryStorage());

  TomKdbxSettingsBootstrap bootstrapWith(
    TomSecretStore secrets,
    TomKdbxKeyProvider keys,
  ) => TomKdbxSettingsBootstrap(
    device: TomDeviceSettings(locator: deviceLocator, storage: storage),
    secrets: secrets,
    keys: keys,
    storage: storage,
    locator: settingsLocator,
    namespace: 'app',
  );

  test('KDBX-BOOT-1: a first run mints a key, records the handle, and the '
      'container opens with it', () async {
    final secrets = TomInMemorySecretStore();
    final container = await bootstrapWith(
      secrets,
      TomKdbxKeyProvider(),
    ).ensure();

    expect(container.hasKey, isTrue);
    expect(container.namespace, 'app');
    final store = await container.load();
    expect(store.isSettingsContainer, isTrue);

    // The one per-device secret is in the secret store; only its handle is in
    // device settings, which hold no secret.
    final device = TomDeviceSettings(locator: deviceLocator, storage: storage);
    await device.load();
    final minted = await secrets.read(device.settingsKeyHandle!);
    expect(minted, isNotNull);
    expect(
      utf8.decode(storage.files[deviceLocator]!),
      isNot(contains(minted!)),
    );
  });

  test(
    'KDBX-BOOT-2: a minted key is long and differs between devices',
    () async {
      final secretsA = TomInMemorySecretStore();
      await bootstrapWith(secretsA, TomKdbxKeyProvider()).ensure();
      final deviceA = TomDeviceSettings(
        locator: deviceLocator,
        storage: storage,
      );
      await deviceA.load();
      final a = (await secretsA.read(deviceA.settingsKeyHandle!))!;

      storage = MemoryStorage();
      final secretsB = TomInMemorySecretStore();
      await bootstrapWith(secretsB, TomKdbxKeyProvider()).ensure();
      final deviceB = TomDeviceSettings(
        locator: deviceLocator,
        storage: storage,
      );
      await deviceB.load();
      final b = (await secretsB.read(deviceB.settingsKeyHandle!))!;

      expect(a.length, greaterThanOrEqualTo(32));
      expect(a, isNot(b));
    },
  );

  test('KDBX-BOOT-3: a second run reuses the stored key and reads back the '
      'file', () async {
    final secrets = TomInMemorySecretStore();
    final first = await bootstrapWith(secrets, TomKdbxKeyProvider()).ensure();
    final store = await first.load();
    TomKdbxIdentityStore(
      store,
    ).write(const TomIdentity(displayName: 'Alexis', authorId: 'alexis'));
    await first.save(message: 'first run');

    final second = await bootstrapWith(secrets, TomKdbxKeyProvider()).ensure();
    expect(TomKdbxIdentityStore(await second.load()).read().authorId, 'alexis');
    expect(
      storage.commits,
      hasLength(2),
      reason: 'device settings + container',
    );
  });

  test('KDBX-BOOT-4: a lost secret does not silently replace the settings '
      'file', () async {
    final secrets = TomInMemorySecretStore();
    final first = await bootstrapWith(secrets, TomKdbxKeyProvider()).ensure();
    await first.load();
    await first.save();

    // The keychain was wiped; the bootstrap mints again, and the *existing*
    // container then refuses to open — the honest outcome. An empty container
    // written over the user's settings would not be.
    await secrets.clear();
    final second = await bootstrapWith(secrets, TomKdbxKeyProvider()).ensure();
    await expectLater(second.load(), throwsA(isA<TomKeyRequiredException>()));
    await expectLater(second.save(), completion(isNull));
  });
}
