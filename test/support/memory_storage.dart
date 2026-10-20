/// A single-file [TomStorage] over a map, with compare-and-swap heads.
library;

import 'dart:typed_data';

import 'package:tom_core_storage/tom_core_storage.dart';

/// Holds one byte string per locator and refuses a commit whose expected head
/// is not the current one, as every real backend does.
class MemoryStorage extends TomStorage {
  final Map<String, Uint8List> files = {};
  final Map<String, int> _revisions = {};

  /// The commit messages of every commit that landed, in order.
  final List<String?> commits = [];

  /// Whether [locator] holds a file.
  bool exists(String locator) => files.containsKey(locator);

  /// Puts [bytes] at [locator] as if committed by someone else.
  void seed(String locator, Uint8List bytes) {
    files[locator] = bytes;
    _revisions[locator] = (_revisions[locator] ?? 0) + 1;
  }

  @override
  bool handles(String locator) => locator.startsWith('mem:');

  @override
  Future<List<TomStorageEntry>> list(String locator) async => const [];

  @override
  Future<Uint8List> readBytes(String locator) async {
    final bytes = files[locator];
    if (bytes == null) throw TomContainerNotFoundException(locator);
    return bytes;
  }

  @override
  Future<TomBundleMedium> readBundle(String locator) async =>
      throw TomContainerNotFoundException(locator);

  @override
  Future<String> commit(
    String locator,
    TomChangeset changeset, {
    String? expectedHead,
    String? message,
    TomCommitProgressSink? onProgress,
  }) async {
    final current = await headOf(locator);
    if (current != expectedHead) {
      throw TomCasConflictException(
        locator,
        expectedHead: expectedHead,
        actualHead: current,
      );
    }
    seed(locator, changeset.containerBytes);
    commits.add(message);
    return (await headOf(locator))!;
  }

  @override
  Future<void> delete(String locator) async {
    files.remove(locator);
    _revisions.remove(locator);
  }

  @override
  Future<String?> headOf(String locator) async {
    final revision = _revisions[locator];
    return revision == null ? null : 'r$revision';
  }
}
