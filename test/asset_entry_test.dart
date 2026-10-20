/// Assets in a KDBX file: binaries on one reserved entry, the metadata map on
/// the same entry, retirements in its history.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

const types = TomAssetTypes({'text/plain': (extension: 'txt', kind: 'text')});

const entryId = '00000000-0000-4000-8000-0000000000a1';
final content = KdbxKey('app.content');
final typeKey = KdbxKey('app.type');
final layout = TomKdbxAssetEntry(
  types: types,
  entryId: entryId,
  contentKey: content,
  title: 'App Assets',
  markers: {typeKey: 'assets'},
);

final credentials = Credentials(ProtectedValue.fromString('pw'));

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

TomAsset ingest(TomAssetStore store, String text) => store.ingest(
  bytesOf(text),
  mime: 'text/plain',
  ceiling: const TomObjectCeiling(),
);

void main() {
  test('KDBX-ASSETS-1: a write puts each live asset on the reserved entry as '
      'a binary keyed by id, with the metadata map and the markers', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'a'));
    final store = TomAssetStore(types: types);
    final a = ingest(store, 'a');
    layout.write(records, store, {a.id});

    final entry = records.rootEntry(entryId)!;
    expect(entry.getBinary(KdbxKey(a.id))!.value, bytesOf('a'));
    expect(entry.getString(KdbxKeyCommon.TITLE)!.getText(), 'App Assets');
    expect(entry.getString(typeKey)!.getText(), 'assets');
    expect(entry.getString(content)!.getText(), contains(a.id));
  });

  test('KDBX-ASSETS-2: nothing live and no entry writes no entry', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'a'));
    final store = TomAssetStore(types: types);
    ingest(store, 'dropped');
    layout.write(records, store, const {});
    expect(records.rootEntry(entryId), isNull);
    expect(store.assets, isEmpty, reason: 'retired from the live store');
  });

  test(
    'KDBX-ASSETS-3: a write that changes nothing pushes no history; one '
    'that retires an asset keeps it in the history, where it resolves',
    () async {
      final file = KdbxFormat().create(credentials, 'a');
      final store = TomAssetStore(types: types);
      final a = ingest(store, 'a');
      final b = ingest(store, 'b');
      layout.write(TomKdbxRecordStore(file), store, {a.id, b.id});

      // A container as a later session finds it.
      final reread = await KdbxFormat().read(
        Uint8List.fromList(await file.save()),
        credentials,
      );
      final records = TomKdbxRecordStore(reread);
      final entry = records.rootEntry(entryId)!;
      final loaded = TomAssetStore(types: types);
      layout.read(entry, loaded);
      final history = entry.history.length;

      layout.write(records, loaded, {a.id, b.id});
      expect(entry.history.length, history, reason: 'unchanged');

      layout.write(records, loaded, {a.id});
      expect(entry.getBinary(KdbxKey(b.id)), isNull);
      expect(loaded.assets.keys, [a.id]);
      final resolved = await loaded.resolve(b.id);
      expect(resolved, isA<TomAssetHistorical>());
      expect(
        await (resolved as TomAssetHistorical).asset.bytes(),
        bytesOf('b'),
      );
    },
  );

  test('KDBX-ASSETS-4: a read adopts every asset, verified, and survives a '
      'save and reopen', () async {
    final file = KdbxFormat().create(credentials, 'a');
    final store = TomAssetStore(types: types);
    final a = ingest(store, 'a');
    layout.write(TomKdbxRecordStore(file), store, {a.id});
    final reread = await KdbxFormat().read(
      Uint8List.fromList(await file.save()),
      credentials,
    );
    final loaded = TomAssetStore(types: types);
    layout.read(TomKdbxRecordStore(reread).rootEntry(entryId)!, loaded);
    expect(loaded.assets[a.id]!.isLoaded, isTrue);
    expect(loaded.assets[a.id]!.loadedBytes, bytesOf('a'));
  });

  test('KDBX-ASSETS-5: a binary the metadata names but the entry lacks is '
      'skipped; bytes that do not hash to their id are an error; an unknown '
      'kind is refused', () {
    final records = TomKdbxRecordStore(KdbxFormat().create(credentials, 'a'));
    final entry = records.createWithId(entryId);
    final id = tomSha256Hex(bytesOf('a'));
    entry.setString(
      content,
      PlainValue(
        tomEmitCanonicalFragment({
          id: {'mime': 'text/plain', 'kind': 'text', 'bytes': 1},
        }),
      ),
    );
    final store = TomAssetStore(types: types);
    layout.read(entry, store);
    expect(store.assets, isEmpty);

    entry.createBinary(isProtected: false, name: id, bytes: bytesOf('b'));
    expect(
      () => layout.read(entry, TomAssetStore(types: types)),
      throwsA(isA<TomAssetCorruptException>()),
    );

    entry.setString(
      content,
      PlainValue(
        tomEmitCanonicalFragment({
          id: {'mime': 'text/plain', 'kind': 'image', 'bytes': 1},
        }),
      ),
    );
    expect(
      () => layout.read(entry, TomAssetStore(types: types)),
      throwsFormatException,
    );
  });
}
