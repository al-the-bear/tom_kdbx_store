/// A KDBX file's entry history behind the sync history port.
library;

import 'package:kdbx/kdbx.dart';
import 'package:tom_core_sync/tom_core_sync.dart';

import 'record_store.dart';

/// Retains prior versions of records in their entries' `KdbxEntry.history`.
///
/// A version is a detached history entry ([TomKdbxRecordStore.historySnapshot])
/// that the caller fills, and its locator is its **position** in the entry's
/// history, as a decimal string. Positions shift when an earlier version is
/// removed, which is why [prune] answers the protected locators it moved: a
/// conflict record left pointing at its old position would address the wrong
/// version, which reads as a successful load showing the wrong superseded
/// side.
///
/// Writes are synchronous, as the KDBX library's are, so a save that is itself
/// synchronous can use the store without awaiting.
class TomKdbxHistoryStore implements TomHistoryStore<KdbxEntry> {
  /// The file's records.
  final TomKdbxRecordStore records;

  /// Which entries are records whose history this store keeps — the caller's
  /// decision, since only it knows which fields mark a record.
  final bool Function(KdbxEntry entry) isRecord;

  /// Records whose history is append-only and never pruned, for an entry
  /// whose past versions something still names.
  final Set<String> appendOnly;

  TomKdbxHistoryStore(
    this.records, {
    required this.isRecord,
    this.appendOnly = const {},
  });

  /// The live root-group entry of [recordId], or null.
  KdbxEntry? _live(String recordId) => records.rootEntry(recordId);

  /// Appends [snapshot] to the history of [recordId]'s live entry.
  ///
  /// Throws a [StateError] when the record has no live entry: a record that
  /// is not in the file has no history to retain a version in.
  @override
  String retain(String recordId, KdbxEntry snapshot) {
    final entry = _live(recordId);
    if (entry == null) {
      throw StateError('record $recordId has no live entry to retain into');
    }
    entry.history.add(snapshot);
    return '${entry.history.length - 1}';
  }

  @override
  bool holds(String recordId, String locator) {
    final entry = _live(recordId);
    final index = int.tryParse(locator);
    return entry != null &&
        index != null &&
        index >= 0 &&
        index < entry.history.length;
  }

  @override
  KdbxEntry? read(String recordId, String locator) => holds(recordId, locator)
      ? _live(recordId)!.history[int.parse(locator)]
      : null;

  @override
  List<String> versionsOf(String recordId) => [
    for (var i = 0; i < (_live(recordId)?.history.length ?? 0); i++) '$i',
  ];

  /// Walks every record entry in the file, the recycle bin included: a deleted
  /// record is recycled with its history, so a walk over live records only
  /// would leave exactly the history that has stopped growing untouched.
  @override
  Map<String, String> prune({
    int depth = tomHistoryDepth,
    Map<String, String> protected = const {},
  }) {
    if (depth < 0) return const {};
    final byId = <String, KdbxEntry>{};
    for (final entry in records.allEntries()) {
      if (!isRecord(entry)) continue;
      byId.putIfAbsent(TomKdbxRecordStore.idOf(entry), () => entry);
    }
    // A live entry wins over a stray copy of the same id elsewhere.
    for (final entry in records.group.entries) {
      if (isRecord(entry)) byId[TomKdbxRecordStore.idOf(entry)] = entry;
    }
    final moved = <String, String>{};
    for (final record in byId.entries) {
      if (appendOnly.contains(record.key)) continue;
      final kept = protected[record.key];
      final index = records.pruneHistory(
        record.value,
        depth,
        protectedIndex: kept == null ? null : int.tryParse(kept),
      );
      if (index != null && '$index' != kept) moved[record.key] = '$index';
    }
    return moved;
  }
}
