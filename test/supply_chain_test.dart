/// The KDBX format is `tom_kdbx`, the workspace's fork published on pub.dev,
/// taken by version — and nothing redirects it to another source.
library;

import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The first release of the fork under its own name.
final firstRelease = Version.parse('2.4.2+tom.4');

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final dependencies = pubspec['dependencies'] as YamlMap;

  test('KDBX-SUPPLY-1: tom_kdbx is a version constraint that admits the first '
      'release, and upstream kdbx is not a dependency', () {
    final spec = dependencies['tom_kdbx'];
    expect(spec, isA<String>(), reason: 'a version, not a git or path source');
    expect(VersionConstraint.parse(spec as String).allows(firstRelease), isTrue);
    expect(dependencies.containsKey('kdbx'), isFalse);
  });

  test('KDBX-SUPPLY-2: no pubspec_overrides.yaml redirects it', () {
    final overrides = File('pubspec_overrides.yaml');
    if (!overrides.existsSync()) return;
    final yaml = loadYaml(overrides.readAsStringSync()) as YamlMap?;
    final names = (yaml?['dependency_overrides'] as YamlMap?)?.keys ?? [];
    expect(names, isNot(contains('tom_kdbx')));
    expect(names, isNot(contains('kdbx')));
  });

  test('KDBX-SUPPLY-3: the resolved tom_kdbx comes from pub.dev, at the first '
      'release or later, and no kdbx is resolved beside it', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue, reason: 'run `dart pub get` first');
    final packages =
        (loadYaml(lock.readAsStringSync()) as YamlMap)['packages'] as YamlMap;
    final tomKdbx = packages['tom_kdbx'] as YamlMap;
    expect(tomKdbx['source'], 'hosted');
    expect(
      (tomKdbx['description'] as YamlMap)['url'],
      'https://pub.dev',
    );
    expect(
      Version.parse(tomKdbx['version'] as String) >= firstRelease,
      isTrue,
    );
    expect(packages.containsKey('kdbx'), isFalse,
        reason: 'a second KDBX implementation in the same graph');
  });
}
