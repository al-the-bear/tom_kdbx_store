/// A KDBX file as a store of records: one entry per record, its UUID the
/// record's id.
library;

import 'package:tom_kdbx/tom_kdbx.dart';

import 'uuid_convert.dart';

/// A KDBX file used as a store of **records**, each a root-group entry whose
/// UUID is the record's id.
///
/// What it provides is the mechanics every such store needs and none should
/// write twice:
///
/// - **Identity.** A record's id is a canonical UUID string, and the entry's
///   UUID is the same 16 bytes, so the file needs no id field and no index.
/// - **History.** A write through `KdbxEntry.setString` pushes the previous
///   state to `KdbxEntry.history`; [historySnapshot] makes a detached entry for
///   a version that must be retained without becoming current, and
///   [pruneHistory] keeps the newest versions while protecting one a caller
///   still names.
/// - **Deletion and return.** [delete] moves an entry to the recycle bin, the
///   way KeePass-family applications do. A record that comes back is
///   **restored** from wherever it went ([restoreOrCreate]) — not minted
///   again, which would leave two entries sharing a UUID, a malformed file for
///   every reader of the format, and sever the record's history. Every entry
///   written is cleared of a deletion record ([markLive]), because another
///   client may have emptied the recycle bin, which records the UUID as
///   permanently deleted.
/// - **Reserved entries.** Data that belongs to the file rather than to a
///   record lives on an entry at a fixed UUID, minted by [createWithId] and
///   found by [rootEntry].
/// - **Meta custom data**, through [meta].
///
/// What a record *contains* — which string fields, which types, which entries
/// are records at all — is the caller's: the store never reads a field.
class TomKdbxRecordStore {
  /// The file the records live in.
  final KdbxFile file;

  /// Entries of this file that are not live records — recycled by an earlier
  /// write, or moved out of the root group — indexed by id. Built at the first
  /// [restoreOrCreate] that needs it, once, because an ordinary write has no
  /// returning records at all and a per-call walk made restoring many records
  /// quadratic.
  Map<String, KdbxEntry>? _recyclable;

  TomKdbxRecordStore(this.file);

  /// The group records live in: the file's root group.
  KdbxGroup get group => file.body.rootGroup;

  /// The file's meta custom data, for values that belong to the file.
  KdbxCustomData get meta => file.body.meta.customData;

  /// The canonical id of [entry].
  static String idOf(KdbxEntry entry) => tomCanonicalFromKdbxUuid(entry.uuid);

  /// The root-group entries, by id, in file order — every record, and every
  /// reserved or foreign entry beside them; the caller tells them apart.
  Map<String, KdbxEntry> rootEntries() => {
    for (final entry in group.entries) idOf(entry): entry,
  };

  /// The root-group entry with [id], or null.
  KdbxEntry? rootEntry(String id) {
    for (final entry in group.entries) {
      if (idOf(entry) == id) return entry;
    }
    return null;
  }

  /// Every entry in the file, the recycle bin and subgroups included.
  Iterable<KdbxEntry> allEntries() => group.getAllEntries();

  /// A new root-group entry whose UUID is [id].
  KdbxEntry createWithId(String id) {
    final entry = KdbxEntry.create(file, group)
      ..assignUuid(tomKdbxUuidFromCanonical(id));
    group.addEntry(entry);
    return entry;
  }

  /// The entry for a record [id] that is not live in the root group: the
  /// recycled entry moved back when the file still holds it, otherwise a new
  /// one ([createWithId]).
  ///
  /// When the recycled entry is gone — another client emptied the recycle bin
  /// between two writes — the record's history really was destroyed there, and
  /// starting a new entry is the only thing left to do.
  ///
  /// First match wins on a repeated UUID outside the root group: two entries
  /// sharing one is a malformed file this store never writes, and the rule
  /// states the choice rather than leaving it to iteration order.
  KdbxEntry restoreOrCreate(String id) {
    final recyclable = _recyclable ??= _indexRecyclable();
    final entry = recyclable.remove(id);
    if (entry == null) return createWithId(id);
    file.move(entry, group);
    return entry;
  }

  Map<String, KdbxEntry> _indexRecyclable() {
    final index = <String, KdbxEntry>{};
    for (final entry in group.getAllEntries()) {
      if (entry.parent == group) continue; // a live root-group entry
      index.putIfAbsent(idOf(entry), () => entry);
    }
    return index;
  }

  /// Clears any record of [entry] as permanently deleted.
  ///
  /// A client that emptied the recycle bin records the UUID as deleted, and a
  /// client merging two copies removes an entry older than that record — so an
  /// entry being written must not carry one. A restored or new entry never has
  /// a record, so the call costs a lookup that finds nothing.
  void markLive(KdbxEntry entry) => file.clearDeletion(entry.uuid);

  /// Whether a record [id] is recorded as permanently deleted — the record a
  /// client that emptied the recycle bin leaves, which a merge of two copies
  /// reads as "delete this entry". [markLive] clears it.
  bool isRecordedDeleted(String id) =>
      file.isDeleted(tomKdbxUuidFromCanonical(id));

  /// Moves [entry] to the recycle bin, with its history.
  void delete(KdbxEntry entry) => file.deleteEntry(entry);

  /// A detached history-only entry with the UUID [id], to be filled and added
  /// to a live entry's `history` — where KDBX serializes it. It is never added
  /// to a group.
  KdbxEntry historySnapshot(String id) =>
      KdbxEntry.create(file, group, isHistoryEntry: true)
        ..assignUuid(tomKdbxUuidFromCanonical(id));

  /// Drops all but the newest [depth] history snapshots of [entry], keeping
  /// [protectedIndex] wherever it falls, and returns where that snapshot now
  /// is (null when none was protected or it did not exist).
  ///
  /// A snapshot is addressed by its **position** in `KdbxEntry.history`, and
  /// removing an earlier element shifts it — a caller that names one must take
  /// the returned index, or it addresses the wrong version. The protected
  /// index is kept even below the depth: a pointer at a retained state is a
  /// correctness guarantee, and the depth only a size one. A negative [depth]
  /// keeps everything.
  int? pruneHistory(KdbxEntry entry, int depth, {int? protectedIndex}) {
    final total = entry.history.length;
    final protects =
        protectedIndex != null && protectedIndex >= 0 && protectedIndex < total;
    if (depth < 0 || total <= depth) return protects ? protectedIndex : null;
    final keep = <int>{
      for (var i = total - depth; i < total; i++) i,
      if (protects) protectedIndex,
    };
    final kept = keep.toList()..sort();
    if (kept.length < total) {
      final snapshots = [for (final i in kept) entry.history[i]];
      entry.history
        ..clear()
        ..addAll(snapshots);
    }
    return protects ? kept.indexOf(protectedIndex) : null;
  }
}
