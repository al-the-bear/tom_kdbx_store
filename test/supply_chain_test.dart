/// The KDBX format is `tom_kpasslib`, the workspace's fork published on
/// pub.dev, taken by version — and nothing redirects it to another source, and
/// neither the GPL-3 `tom_kdbx` nor upstream `kdbx` is in the graph.
library;

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The oldest release of the fork this package works with: 1.1.2+tom.2 reads
/// a binary's protected flag the right way round, 1.1.2+tom.3 keeps a KDBX 3
/// file's protected values beside a protected binary.
final minimumRelease = Version.parse('1.1.2+tom.3');

/// KDBX libraries that must not be in the graph: `tom_kdbx` and `kdbx` are
/// GPL-3 (AuthPass's kdbx.dart), `kpasslib` would be a second copy of the
/// fork's code beside it.
const excluded = ['tom_kdbx', 'kdbx', 'kpasslib'];

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final dependencies = pubspec['dependencies'] as YamlMap;

  test('KDBX-SUPPLY-1: tom_kpasslib is a version constraint that admits the '
      'minimum release, and no other KDBX library is a dependency', () {
    final spec = dependencies['tom_kpasslib'];
    expect(spec, isA<String>(), reason: 'a version, not a git or path source');
    expect(
      VersionConstraint.parse(spec as String).allows(minimumRelease),
      isTrue,
    );
    for (final name in excluded) {
      expect(dependencies.containsKey(name), isFalse, reason: name);
    }
  });

  test('KDBX-SUPPLY-2: no pubspec_overrides.yaml redirects it', () {
    final overrides = File('pubspec_overrides.yaml');
    if (!overrides.existsSync()) return;
    final yaml = loadYaml(overrides.readAsStringSync()) as YamlMap?;
    final names = (yaml?['dependency_overrides'] as YamlMap?)?.keys ?? [];
    for (final name in ['tom_kpasslib', ...excluded]) {
      expect(names, isNot(contains(name)));
    }
  });

  test('KDBX-SUPPLY-3: the resolved tom_kpasslib comes from pub.dev, at the '
      'minimum release or later, and no other KDBX library is resolved', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue, reason: 'run `dart pub get` first');
    final packages =
        (loadYaml(lock.readAsStringSync()) as YamlMap)['packages'] as YamlMap;
    final fork = packages['tom_kpasslib'] as YamlMap;
    expect(fork['source'], 'hosted');
    expect((fork['description'] as YamlMap)['url'], 'https://pub.dev');
    expect(Version.parse(fork['version'] as String) >= minimumRelease, isTrue);
    for (final name in excluded) {
      expect(
        packages.containsKey(name),
        isFalse,
        reason: 'a second KDBX implementation in the same graph: $name',
      );
    }
  });

  test(
    'KDBX-SUPPLY-4: only lib/src/kdbx_model.dart imports the KDBX library',
    () {
      final importers = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File &&
              file.path.endsWith('.dart') &&
              file.readAsStringSync().contains('package:tom_kpasslib/'))
            file.path.replaceAll(r'\', '/'),
      ];
      expect(importers, ['lib/src/kdbx_model.dart']);
    },
  );
}
