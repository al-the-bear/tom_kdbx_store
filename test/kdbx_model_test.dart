/// The package's KDBX types over `tom_kpasslib`: the behaviour consumers rely
/// on beyond the record and settings stores — when history is pushed, times
/// and tags, field and binary listings, protected values across a save, a
/// rejected key, and a file written by `tom_kdbx`, the library the package
/// used before.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

final credentials = Credentials(ProtectedValue.fromString('pw'));
const field = KdbxKey('app.field');

Future<KdbxFile> reopen(KdbxFile file, [Credentials? with_]) async =>
    KdbxFormat().read(await file.save(), with_ ?? credentials);

KdbxEntry newEntry(KdbxFile file) {
  final entry = KdbxEntry.create(file, file.body.rootGroup);
  file.body.rootGroup.addEntry(entry);
  return entry;
}

void main() {
  test('KDBX-MODEL-1: a new entry pushes no history; its first change after a '
      'save pushes one snapshot, further changes none, a same-value write '
      'nothing', () async {
    final file = KdbxFormat().create(credentials, 'm');
    final entry = newEntry(file)..setString(field, PlainValue('1'));
    entry.setString(field, PlainValue('2'));
    expect(entry.history, isEmpty);

    final reread = await reopen(file);
    final again = reread.body.rootGroup.entries.single;
    again.setString(field, PlainValue('2'));
    expect(again.history, isEmpty, reason: 'the same value is no change');
    again.setString(field, PlainValue('3'));
    again.setString(field, PlainValue('4'));
    expect(again.history, hasLength(1));
    expect(again.history.single.getString(field)?.getText(), '2');

    await reread.save();
    again.modify(() {
      again.setString(field, PlainValue('5'));
      again.setString(KdbxKeyCommon.TITLE, PlainValue('t'));
    });
    expect(again.history.map((e) => e.getString(field)?.getText()), ['2', '4']);
  });

  test('KDBX-MODEL-2: a new entry has no fields; protected and plain values '
      'keep their kind across a save', () async {
    final file = KdbxFormat().create(credentials, 'm');
    final entry = newEntry(file);
    expect(entry.stringEntries, isEmpty);
    expect(entry.getString(KdbxKeyCommon.PASSWORD), isNull);
    entry
      ..setString(KdbxKeyCommon.TITLE, PlainValue('title'))
      ..setString(KdbxKeyCommon.PASSWORD, ProtectedValue.fromString('secret'));
    final back = (await reopen(file)).body.rootGroup.entries.single;
    expect(back.getString(KdbxKeyCommon.TITLE), PlainValue('title'));
    expect(back.getString(KdbxKeyCommon.PASSWORD), isA<ProtectedValue>());
    expect(back.getString(KdbxKeyCommon.PASSWORD)!.getText(), 'secret');
    expect(
      {for (final e in back.stringEntries) e.key: e.value!.getText()},
      {KdbxKeyCommon.TITLE: 'title', KdbxKeyCommon.PASSWORD: 'secret'},
    );
  });

  test('KDBX-MODEL-3: times set explicitly survive a save, and setting one is '
      'not a change; a change sets the last modification to now', () async {
    final file = KdbxFormat().create(credentials, 'm');
    final entry = newEntry(file);
    final created = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final modified = DateTime.utc(2026, 6, 7, 8, 9, 10);
    entry
      ..setString(field, PlainValue('x'))
      ..times.creationTime.set(created)
      ..times.lastModificationTime.set(modified);
    final back = (await reopen(file)).body.rootGroup.entries.single;
    expect(back.times.creationTime.get(), created);
    expect(back.times.lastModificationTime.get(), modified);
    back.times.lastModificationTime.set(created);
    expect(back.history, isEmpty, reason: 'a time is not a change');
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    back.setString(field, PlainValue('y'));
    expect(back.times.lastModificationTime.get()!.isAfter(before), isTrue);
  });

  test('KDBX-MODEL-4: tags are one string separated by ";", and survive a '
      'save', () async {
    final file = KdbxFormat().create(credentials, 'm');
    final entry = newEntry(file);
    expect(entry.tags.get(), isNull);
    entry.tags.set('work;home');
    expect(entry.tags.get(), 'work;home');
    final back = (await reopen(file)).body.rootGroup.entries.single;
    expect(back.tags.get(), 'work;home');
    back.tags.set(null);
    expect(back.tags.get(), isNull);
  });

  test('KDBX-MODEL-5: binaries are listed, read back after a save, take a '
      'unique name when theirs is taken, and are removed', () async {
    final file = KdbxFormat().create(credentials, 'm');
    final entry = newEntry(file);
    entry
      ..createBinary(
        isProtected: false,
        name: 'dir/a.txt',
        bytes: Uint8List.fromList(utf8.encode('one')),
      )
      ..createBinary(
        isProtected: true,
        name: 'a.txt',
        bytes: Uint8List.fromList(utf8.encode('two')),
      );
    expect(entry.binaryEntries.map((b) => b.key.key), ['a.txt', 'a1.txt']);
    final back = (await reopen(file)).body.rootGroup.entries.single;
    expect(utf8.decode(back.getBinary(const KdbxKey('a.txt'))!.value), 'one');
    expect(back.getBinary(const KdbxKey('a1.txt'))!.isProtected, isTrue);
    back.removeBinary(const KdbxKey('a.txt'));
    expect(back.binaryEntries.map((b) => b.key.key), ['a1.txt']);
    expect(
      back.history.single.getBinary(const KdbxKey('a.txt')),
      isNotNull,
      reason: 'the version before the removal keeps it',
    );
  });

  test('KDBX-MODEL-6: a wrong key is refused with KdbxInvalidKeyException; a '
      'key file opens a file created with one', () async {
    final file = KdbxFormat().create(credentials, 'm');
    await expectLater(
      reopen(file, Credentials(ProtectedValue.fromString('wrong'))),
      throwsA(isA<KdbxInvalidKeyException>()),
    );
    final keyFile = Uint8List.fromList(List.generate(32, (i) => i));
    final withKeyFile = Credentials.composite(null, keyFile);
    final keyed = KdbxFormat().create(withKeyFile, 'k');
    newEntry(keyed).setString(field, PlainValue('keyed'));
    final back = await reopen(keyed, withKeyFile);
    expect(
      back.body.rootGroup.entries.single.getString(field)!.getText(),
      'keyed',
    );
  });

  test('KDBX-MODEL-7: a new file has no recycle bin until something is '
      'deleted, and meta custom data can be removed', () async {
    final file = KdbxFormat().create(credentials, 'm');
    expect(file.body.rootGroup.groups, isEmpty);
    file.deleteEntry(newEntry(file));
    expect(file.body.rootGroup.groups, hasLength(1));
    final meta = file.body.meta.customData..['k'] = 'v';
    expect(meta['k'], 'v');
    expect(meta.remove('k'), 'v');
    expect((await reopen(file)).body.meta.customData.containsKey('k'), isFalse);
  });

  test('KDBX-MODEL-8: a file written by tom_kdbx opens with everything it '
      'holds', () async {
    final file = await KdbxFormat().read(
      File('test/fixtures/tom_kdbx_written.kdbx').readAsBytesSync(),
      Credentials(ProtectedValue.fromString('interop')),
    );
    final entry = file.body.rootGroup.entries.single;
    expect(entry.getString(KdbxKeyCommon.TITLE)!.getText(), 'interop title');
    expect(entry.getString(KdbxKeyCommon.PASSWORD), isA<ProtectedValue>());
    expect(
      entry.getString(KdbxKeyCommon.PASSWORD)!.getText(),
      'interop secret',
    );
    expect(entry.getString(const KdbxKey('Note'))!.getText(), 'unicode ✓ äöü');
    expect(
      utf8.decode(entry.getBinary(const KdbxKey('a.txt'))!.value),
      'attached bytes',
    );
    expect(file.body.meta.customData['k'], 'v');
  });

  test('KDBX-MODEL-9: label, database name, recycle bin, re-keying, and '
      'credentials compared by hash', () async {
    final file = KdbxFormat().create(credentials, 'probe');
    expect(file.body.meta.databaseName.get(), 'probe');
    expect(file.recycleBin, isNull);
    final entry = newEntry(file)..label = 'Introduction';
    expect(entry.label, 'Introduction');
    file.deleteEntry(entry);
    expect(file.recycleBin!.entries, [entry]);

    final other = Credentials(ProtectedValue.fromString('other'));
    expect(other.getHash(), isNot(credentials.getHash()));
    expect(
      Credentials(ProtectedValue.fromString('pw')).getHash(),
      credentials.getHash(),
    );
    file.credentials = other;
    final bytes = await file.save();
    await expectLater(
      KdbxFormat().read(bytes, credentials),
      throwsA(isA<KdbxInvalidKeyException>()),
    );
    final rekeyed = await KdbxFormat().read(bytes, other);
    expect(rekeyed.recycleBin!.entries.single.label, 'Introduction');
  });
}
