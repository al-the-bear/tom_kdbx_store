/// The record store: identity by UUID, deletion into the recycle bin and back,
/// detached history snapshots, pruning that keeps a protected snapshot, and
/// reserved entries.
library;

import 'dart:typed_data';

// The recycle-bin purge another KDBX client performs is a kdbx extension
// method the curated export does not carry.
import 'package:tom_kdbx/tom_kdbx.dart' show KdbxDao;
import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

const idA = '0a000000-0000-4000-8000-000000000001';
const idB = '0b000000-0000-4000-8000-000000000002';
const reserved = '00000000-0000-4000-8000-000000000099';

final _value = KdbxKey('app.value');

final _credentials = Credentials(ProtectedValue.fromString('pw'));

KdbxFile _newFile() => KdbxFormat().create(_credentials, 'records');

String? _valueOf(KdbxEntry entry) => entry.getString(_value)?.getText();

void main() {
  test('KDBX-RECORDS-1: a record created by id carries that id as its UUID, '
      'and is found again', () {
    final records = TomKdbxRecordStore(_newFile());
    final entry = records.createWithId(idA);
    expect(TomKdbxRecordStore.idOf(entry), idA);
    expect(records.rootEntry(idA), same(entry));
    expect(records.rootEntries().keys, [idA]);
    expect(records.rootEntry(idB), isNull);
  });

  test('KDBX-RECORDS-2: a canonical id round-trips through a KDBX UUID, and a '
      'malformed one is refused', () {
    expect(tomCanonicalFromKdbxUuid(tomKdbxUuidFromCanonical(idA)), idA);
    expect(() => tomKdbxUuidFromCanonical('not-a-uuid'), throwsFormatException);
  });

  test('KDBX-RECORDS-3: a deleted record returns as the same entry, with its '
      'history, not as a second entry with the same UUID', () async {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    final entry = records.createWithId(idA)..setString(_value, PlainValue('2'));
    entry.history.add(
      records.historySnapshot(idA)..setString(_value, PlainValue('1')),
    );
    final history = entry.history.length;

    records.delete(entry);
    expect(records.rootEntry(idA), isNull);

    final back = TomKdbxRecordStore(file).restoreOrCreate(idA);
    expect(back, same(entry));
    expect(back.parent, file.body.rootGroup);
    expect(back.history.length, greaterThanOrEqualTo(history));
    expect(
      file.body.rootGroup.getAllEntries().where(
        (e) => TomKdbxRecordStore.idOf(e) == idA,
      ),
      hasLength(1),
    );
  });

  test('KDBX-RECORDS-4: an id the file never held, or whose recycled entry is '
      'gone, is minted fresh', () {
    final records = TomKdbxRecordStore(_newFile());
    final entry = records.restoreOrCreate(idB);
    expect(TomKdbxRecordStore.idOf(entry), idB);
    expect(entry.history, isEmpty);
  });

  test('KDBX-RECORDS-5: a written record is cleared of a deletion record, so '
      'a merge cannot drop it', () async {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    final entry = records.createWithId(idA);
    records.delete(entry);
    // Emptying the recycle bin records the UUID as permanently deleted.
    file.deleteEntry(entry);
    final back = TomKdbxRecordStore(file).restoreOrCreate(idA);
    records.markLive(back);
    final bytes = Uint8List.fromList(await file.save());
    final reread = await KdbxFormat().read(bytes, _credentials);
    expect(TomKdbxRecordStore(reread).rootEntry(idA), isNotNull);
  });

  test('KDBX-RECORDS-6: a history snapshot is detached and takes the record\'s '
      'UUID', () {
    final records = TomKdbxRecordStore(_newFile());
    final live = records.createWithId(idA);
    final snapshot = records.historySnapshot(idA)
      ..setString(_value, PlainValue('retained'));
    live.history.add(snapshot);
    expect(TomKdbxRecordStore.idOf(snapshot), idA);
    expect(records.rootEntries().keys, [idA], reason: 'not added to a group');
    expect(_valueOf(live.history.last), 'retained');
  });

  test('KDBX-RECORDS-7: pruning keeps the newest snapshots and a protected '
      'one wherever it falls, and says where that one moved', () {
    final records = TomKdbxRecordStore(_newFile());
    final entry = records.createWithId(idA);
    for (var i = 0; i < 6; i++) {
      entry.history.add(
        records.historySnapshot(idA)..setString(_value, PlainValue('v$i')),
      );
    }
    final moved = records.pruneHistory(entry, 2, protectedIndex: 1);
    expect(entry.history.map(_valueOf), ['v1', 'v4', 'v5']);
    expect(moved, 0);
    expect(_valueOf(entry.history[moved!]), 'v1');
  });

  test('KDBX-RECORDS-8: within the depth nothing is pruned, and a protected '
      'index out of range protects nothing', () {
    final records = TomKdbxRecordStore(_newFile());
    final entry = records.createWithId(idA);
    for (var i = 0; i < 3; i++) {
      entry.history.add(
        records.historySnapshot(idA)..setString(_value, PlainValue('v$i')),
      );
    }
    expect(records.pruneHistory(entry, 5, protectedIndex: 2), 2);
    expect(entry.history, hasLength(3));
    expect(records.pruneHistory(entry, 1, protectedIndex: 9), isNull);
    expect(entry.history.map(_valueOf), ['v2']);
    expect(records.pruneHistory(entry, -1), isNull, reason: 'keep everything');
    expect(entry.history, hasLength(1));
  });

  test('KDBX-RECORDS-9: a reserved entry sits beside the records at its fixed '
      'id, and meta custom data belongs to the file', () async {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    records.createWithId(idA);
    records.createWithId(reserved).setString(_value, PlainValue('file-scoped'));
    records.meta['app.root'] = idA;

    final reread = await KdbxFormat().read(
      Uint8List.fromList(await file.save()),
      _credentials,
    );
    final again = TomKdbxRecordStore(reread);
    expect(again.rootEntries().keys, containsAll([idA, reserved]));
    expect(_valueOf(again.rootEntry(reserved)!), 'file-scoped');
    expect(again.meta['app.root'], idA);
  });
}
