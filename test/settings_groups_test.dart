/// The settings groups this package defines — `keys`, `identity`,
/// `locations` — and the store they are built on, which knows none of them.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_core_settings/tom_core_settings.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

import 'support/memory_storage.dart';

/// [source] without `//` and `/* */` comments, so a doc comment may still
/// explain the registry while code may not name a group.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  final credentials = Credentials(ProtectedValue.fromString('settings-pw'));

  TomKdbxSettingsStore newSettings() =>
      TomKdbxSettingsStore.create(KdbxFormat(), credentials, namespace: 'app');

  // ───────────────────────────────────────────────────────────────────────
  group('KDBX-GROUPS-A the `keys` group', () {
    test(
      'KDBX-GROUPS-1: the two default scopes round-trip through the store',
      () async {
        final settings = newSettings();
        final keys = TomKdbxKeyStore(settings);

        await keys.saveDefaultKey(
          const TomKeyMaterial(passphrase: 'doc-default'),
        );
        await keys.saveCollaborationDefaultKey(
          const TomKeyMaterial(passphrase: 'collab-default'),
        );

        expect((await keys.loadDefaultKey())!.passphrase, 'doc-default');
        expect(
          (await keys.loadCollaborationDefaultKey())!.passphrase,
          'collab-default',
        );
        // Title = scope. Two scopes, two entries, one group.
        expect(settings.entries(TomKdbxKeyStore.groupName), hasLength(2));
        expect(settings.groupNames, contains(TomKdbxKeyStore.groupName));
      },
    );

    test(
      'KDBX-GROUPS-2: a per-file override is keyed by the locator, not the Title',
      () async {
        final settings = newSettings();
        final keys = TomKdbxKeyStore(settings);
        const locator = 'mem:/repo/handbook.kdbx';

        await keys.saveOverride(
          locator,
          const TomKeyMaterial(passphrase: 'per-file'),
        );

        // The entry the user sees in a password manager carries a readable
        // Title — but the lookup must not depend on it, so renaming it in
        // a password manager may not break the override.
        final entry = settings
            .entries(TomKdbxKeyStore.groupName)
            .singleWhere((e) => e.getString(KdbxKeyCommon.URL) != null);
        entry.setString(KdbxKeyCommon.TITLE, PlainValue('renamed by hand'));

        final overrides = await keys.loadOverrides();
        expect(overrides.keys, [locator]);
        expect(overrides[locator]!.passphrase, 'per-file');

        await keys.removeOverride(locator);
        expect(await keys.loadOverrides(), isEmpty);
      },
    );

    test(
      'KDBX-GROUPS-3: the passphrase is protected, the key-file locator is not',
      () async {
        final settings = newSettings();
        final keys = TomKdbxKeyStore(settings);
        await keys.saveDefaultKey(
          const TomKeyMaterial(
            passphrase: 'secret',
            keyFileLocator: 'mem:/repo/keyfile.bin',
          ),
        );

        final entry = settings.requireEntryByTitle(
          TomKdbxKeyStore.groupName,
          TomKdbxKeyStore.documentsDefaultScope,
        );
        // The secret is a ProtectedValue. The *path* to a key file is
        // not the secret — the bytes are, and the bytes are never stored.
        expect(entry.getString(KdbxKeyCommon.PASSWORD), isA<ProtectedValue>());
        expect(
          entry.getString(TomKdbxKeyStore(settings).keyFileField),
          isA<PlainValue>(),
        );
        expect(
          (await keys.loadDefaultKey())!.keyFileLocator,
          'mem:/repo/keyfile.bin',
        );
      },
    );

    test('KDBX-GROUPS-4: a null default key forgets the scope', () async {
      final keys = TomKdbxKeyStore(newSettings());
      await keys.saveDefaultKey(const TomKeyMaterial(passphrase: 'x'));
      await keys.saveDefaultKey(null);
      expect(await keys.loadDefaultKey(), isNull);
    });

    test(
      'KDBX-GROUPS-5: material that states only a key-file locator is not resolvable',
      () async {
        final keys = TomKdbxKeyStore(newSettings());
        await keys.saveOverride(
          'mem:/a.kdbx',
          const TomKeyMaterial(keyFileLocator: 'mem:/k.bin'),
        );
        final material = (await keys.loadOverrides())['mem:/a.kdbx']!;
        // Not empty — it states something — but not enough to build credentials
        // from without reading the key file. The distinction is what lets a key
        // controller skip it instead of throwing at start-up.
        expect(material.isEmpty, isFalse);
        expect(material.isResolvable, isFalse);
        expect(material.toCredentials, throwsA(isA<StateError>()));
      },
    );

    test(
      'KDBX-GROUPS-6: with a storage backend the key-file locator resolves to bytes',
      () async {
        final storage = MemoryStorage()
          ..seed('mem:/keys/master.bin', Uint8List.fromList([1, 2, 3, 4]));

        final settings = newSettings();
        await TomKdbxKeyStore(settings).saveOverride(
          'mem:/a.kdbx',
          const TomKeyMaterial(keyFileLocator: 'mem:/keys/master.bin'),
        );

        final resolving = TomKdbxKeyStore(settings, keyFiles: storage);
        final material = (await resolving.loadOverrides())['mem:/a.kdbx']!;
        expect(material.keyFileBytes, [1, 2, 3, 4]);
        expect(material.isResolvable, isTrue);
      },
    );

    test(
      'KDBX-GROUPS-7: an unreadable key file degrades, it does not throw',
      () async {
        final storage = MemoryStorage();
        final settings = newSettings();
        await TomKdbxKeyStore(settings).saveOverride(
          'mem:/a.kdbx',
          const TomKeyMaterial(keyFileLocator: 'mem:/gone.bin'),
        );
        final resolving = TomKdbxKeyStore(settings, keyFiles: storage);
        final material = (await resolving.loadOverrides())['mem:/a.kdbx']!;
        expect(material.keyFileBytes, isNull);
        expect(material.isResolvable, isFalse);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  group('KDBX-GROUPS-B the `identity` group', () {
    test('KDBX-GROUPS-8: display name and author id round-trip', () {
      final settings = newSettings();
      TomKdbxIdentityStore(settings).write(
        const TomIdentity(displayName: 'Alexis Kyaw', authorId: 'alexis'),
      );
      expect(TomKdbxIdentityStore(settings).read().displayName, 'Alexis Kyaw');
      expect(TomKdbxIdentityStore(settings).read().authorId, 'alexis');
      expect(settings.entries(TomIdentity.groupName), hasLength(1));
    });

    test(
      'KDBX-GROUPS-9: an absent group is the unknown identity, not an error',
      () {
        expect(TomKdbxIdentityStore(newSettings()).read(), TomIdentity.unknown);
        expect(TomIdentity.unknown.authorId, 'unknown');
      },
    );

    test('KDBX-GROUPS-10: writing the unknown identity removes the entry', () {
      final settings = newSettings();
      TomKdbxIdentityStore(
        settings,
      ).write(const TomIdentity(displayName: 'A', authorId: 'a'));
      TomKdbxIdentityStore(settings).write(TomIdentity.unknown);
      expect(settings.entries(TomIdentity.groupName), isEmpty);
    });

    test(
      'KDBX-GROUPS-11: a second entry does not make the group unreadable',
      () {
        // Same leniency `readFragment` applies: a container written by a build
        // with a different idea of the group still yields a value. Settings are
        // advisory, and an unreadable settings file is worse than a
        // conservatively-read one.
        final settings = newSettings();
        TomKdbxIdentityStore(
          settings,
        ).write(const TomIdentity(displayName: 'First', authorId: 'first'));
        settings
            .requireEntryByTitle(TomIdentity.groupName, 'Second')
            .setString(KdbxKeyCommon.USER_NAME, PlainValue('second'));
        expect(TomKdbxIdentityStore(settings).read().authorId, 'first');
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────
  group('KDBX-GROUPS-C the `locations` group', () {
    test('KDBX-GROUPS-12: locations round-trip and are keyed by locator', () {
      final settings = newSettings();
      final locations = TomKdbxLocationStore(settings)
        ..put(
          const TomStorageLocation(
            displayName: 'Handbook',
            locator: 'github:al-the-bear/handbook',
          ),
        )
        ..put(
          const TomStorageLocation(
            displayName: 'Local notes',
            locator: 'file:/Users/a/notes',
          ),
        );

      expect(locations.locations, hasLength(2));
      expect(
        locations.locations
            .singleWhere((l) => l.locator == 'github:al-the-bear/handbook')
            .displayName,
        'Handbook',
      );

      // Two locations may share a display name; the locator is the identity.
      locations.put(
        const TomStorageLocation(
          displayName: 'Handbook',
          locator: 'file:/Users/a/notes',
        ),
      );
      expect(locations.locations, hasLength(2));
      expect(
        locations.locations
            .singleWhere((l) => l.locator == 'file:/Users/a/notes')
            .displayName,
        'Handbook',
      );

      locations.remove('file:/Users/a/notes');
      expect(locations.locations, hasLength(1));
    });

    test('KDBX-GROUPS-13: a location holds no secret', () {
      final settings = newSettings();
      TomKdbxLocationStore(settings).put(
        const TomStorageLocation(
          displayName: 'Handbook',
          locator: 'github:al-the-bear/handbook',
        ),
      );
      final entry = settings.entries(TomStorageLocation.groupName).single;
      expect(entry.getString(KdbxKeyCommon.PASSWORD), isNull);
    });
  });

  group('KDBX-GROUPS-G the store knows no group', () {
    late String source;

    setUpAll(() {
      final file = File('lib/src/settings_store.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'the settings store moved — this check must follow it',
      );
      source = _withoutComments(file.readAsStringSync());
    });

    test('KDBX-GROUPS-25: no group name of this package appears in the store '
        'source', () {
      for (final group in const ['tokens', 'keys', 'identity', 'locations']) {
        expect(source, isNot(contains("'$group'")), reason: group);
        expect(source, isNot(contains('"$group"')), reason: group);
      }
    });

    test('KDBX-GROUPS-26: no group enum and no per-group switch', () {
      expect(source, isNot(matches(RegExp(r'\benum\b'))));
      expect(source, isNot(matches(RegExp(r'\bswitch\b'))));
    });

    test('KDBX-GROUPS-27: the store offers exactly the generic accessors', () {
      // Anti-vacuity for the two checks above: they would both pass on an
      // empty file.
      for (final member in const [
        'groupNames',
        'group(',
        'entries(',
        'entryByTitle(',
        'requireEntryByTitle(',
        'createEntry(',
        'removeEntryByTitle(',
        'readFragment(',
        'writeFragment(',
      ]) {
        expect(source, contains(member));
      }
    });
  });
}
