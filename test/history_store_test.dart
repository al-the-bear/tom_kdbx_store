/// Entry history behind the sync history port: retain, read, prune with a
/// protected version that moves.
library;

import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

final content = KdbxKey('app.content');
final typeKey = KdbxKey('app.type');
final credentials = Credentials(ProtectedValue.fromString('pw'));

const recordId = '00000000-0000-4000-8000-0000000000b1';
const assetId = '00000000-0000-4000-8000-0000000000b2';

TomKdbxHistoryStore historyOf(TomKdbxRecordStore records) =>
    TomKdbxHistoryStore(
      records,
      isRecord: (entry) => entry.getString(typeKey) != null,
      appendOnly: const {assetId},
    );

KdbxEntry recordIn(TomKdbxRecordStore records, String id) =>
    records.createWithId(id)..setString(typeKey, PlainValue('note'));

KdbxEntry snapshot(TomKdbxRecordStore records, String id, String text) =>
    records.historySnapshot(id)..setString(content, PlainValue(text));

void main() {
  test('KDBX-HISTORY-1: a retained version is addressed by its position and '
      'reads back', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'h'));
    recordIn(records, recordId);
    final history = historyOf(records);
    final first = history.retain(recordId, snapshot(records, recordId, 'one'));
    final second = history.retain(recordId, snapshot(records, recordId, 'two'));
    expect([first, second], ['0', '1']);
    expect(history.versionsOf(recordId), ['0', '1']);
    expect(
      history.read(recordId, second)!.getString(content)!.getText(),
      'two',
    );
    expect(history.holds(recordId, '2'), isFalse);
    expect(history.holds(recordId, 'x'), isFalse);
    expect(
      () => history.retain(
        '00000000-0000-4000-8000-0000000000ff',
        snapshot(records, recordId, 'none'),
      ),
      throwsStateError,
    );
  });

  test('KDBX-HISTORY-2: pruning keeps the newest versions and answers where a '
      'protected version moved to', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'h'));
    recordIn(records, recordId);
    final history = historyOf(records);
    for (var i = 0; i < 5; i++) {
      history.retain(recordId, snapshot(records, recordId, 'v$i'));
    }
    final moved = history.prune(depth: 2, protected: {recordId: '1'});
    expect(moved, {recordId: '0'});
    expect(
      [
        for (final locator in history.versionsOf(recordId))
          history.read(recordId, locator)!.getString(content)!.getText(),
      ],
      ['v1', 'v3', 'v4'],
    );
  });

  test('KDBX-HISTORY-3: an append-only record and a non-record entry are '
      'never pruned, and a negative depth keeps everything', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'h'));
    final assets = recordIn(records, assetId);
    final foreign = records.createWithId(
      '00000000-0000-4000-8000-0000000000c1',
    );
    for (var i = 0; i < 3; i++) {
      assets.history.add(snapshot(records, assetId, 'a$i'));
      foreign.history.add(snapshot(records, assetId, 'f$i'));
    }
    final history = historyOf(records);
    expect(history.prune(depth: -1), isEmpty);
    history.prune(depth: 1);
    expect(assets.history, hasLength(3));
    expect(foreign.history, hasLength(3));
  });
}
