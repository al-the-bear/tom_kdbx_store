/// What another KeePass client does to a file and this package never does —
/// filing an entry under a folder, emptying it out of the recycle bin — and
/// how the record store sees the result.
library;

import 'package:test/test.dart';
import 'package:tom_kdbx_store/testing.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

const idA = '0a000000-0000-4000-8000-000000000001';
const idB = '0b000000-0000-4000-8000-000000000002';

KdbxFile _newFile() => KdbxFormat().create(
  Credentials(ProtectedValue.fromString('pw')),
  'records',
);

void main() {
  test('KDBX-FOREIGN-1: an entry filed under a folder leaves the root group '
      'and is not a live record any more', () {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    final entry = records.createWithId(idA);
    final folder = TomKdbxForeignClient(file).fileUnder(entry, 'Filed');
    expect(folder.name.get(), 'Filed');
    expect(entry.parent, same(folder));
    expect(records.rootEntry(idA), isNull);
    expect(records.allEntries().map(TomKdbxRecordStore.idOf), contains(idA));
  });

  test('KDBX-FOREIGN-2: a purged entry is gone and recorded as deleted; '
      'another record is not', () {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    final entry = records.createWithId(idA);
    records.createWithId(idB);
    expect(records.isRecordedDeleted(idA), isFalse);
    records.delete(entry);
    expect(
      records.isRecordedDeleted(idA),
      isFalse,
      reason: 'the recycle bin is not a permanent deletion',
    );
    TomKdbxForeignClient(file).purge(entry);
    expect(
      records.allEntries().map(TomKdbxRecordStore.idOf),
      isNot(contains(idA)),
    );
    expect(records.isRecordedDeleted(idA), isTrue);
    expect(records.isRecordedDeleted(idB), isFalse);
  });

  test('KDBX-FOREIGN-3: a record written again is no longer recorded as '
      'deleted', () {
    final file = _newFile();
    final records = TomKdbxRecordStore(file);
    final entry = records.createWithId(idA);
    records.delete(entry);
    TomKdbxForeignClient(file).purge(entry);
    final back = TomKdbxRecordStore(file).restoreOrCreate(idA);
    records.markLive(back);
    expect(records.isRecordedDeleted(idA), isFalse);
  });
}
