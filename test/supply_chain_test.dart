/// The `kdbx` dependency is the workspace's fork at its pinned branch — the
/// same pin every consumer of the fork uses — and nothing redirects it.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const kdbxRepoUrl = 'https://github.com/al-the-bear/tom_kdbx.git';
const kdbxRepoRef = 'tom/2.4.2-patches';

void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  test('KDBX-SUPPLY-1: kdbx is a git dependency on the fork at the pinned '
      'branch, spelled with the repository\'s own name', () {
    final kdbx = (pubspec['dependencies'] as YamlMap)['kdbx'];
    expect(kdbx, isA<YamlMap>(), reason: 'a git dependency, not a version');
    final git = (kdbx as YamlMap)['git'] as YamlMap;
    expect(git['url'], kdbxRepoUrl);
    expect(git['ref'], kdbxRepoRef);
  });

  test('KDBX-SUPPLY-2: no pubspec_overrides.yaml redirects it', () {
    final overrides = File('pubspec_overrides.yaml');
    if (!overrides.existsSync()) return;
    final yaml = loadYaml(overrides.readAsStringSync()) as YamlMap?;
    final names = (yaml?['dependency_overrides'] as YamlMap?)?.keys ?? [];
    expect(names, isNot(contains('kdbx')));
  });

  test('KDBX-SUPPLY-3: the resolved kdbx is that git source', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue, reason: 'run `dart pub get` first');
    final packages =
        (loadYaml(lock.readAsStringSync()) as YamlMap)['packages'] as YamlMap;
    final kdbx = packages['kdbx'] as YamlMap;
    expect(kdbx['source'], 'git');
    final description = kdbx['description'] as YamlMap;
    expect(description['url'], kdbxRepoUrl);
    expect(description['ref'], kdbxRepoRef);
  });
}
