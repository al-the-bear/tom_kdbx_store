/// The key derivation of a file: the Argon2 a new file is created with, what
/// [KdbxFile.argon2] reads in a file, and that a save keeps it — for files
/// this package creates and for the Argon2id files KeePassXC and KeePass 2.x
/// wrote into the corpus. With `keepassxc-cli` on the machine, KeePassXC
/// reports the same KDF for what this package wrote (else those tests skip).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';
import 'package:tom_kpasslib/tom_kpasslib.dart' as kp;

const corpus = 'test/corpus';
const keepassxcApp = '/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli';
const password = 'kdf-demo';
final credentials = Credentials(ProtectedValue.fromString(password));

String? findKeePassXc() {
  if (File(keepassxcApp).existsSync()) return keepassxcApp;
  final which = Process.runSync('which', ['keepassxc-cli']);
  final path = (which.stdout as String).trim();
  return which.exitCode == 0 && path.isNotEmpty ? path : null;
}

/// KeePassXC's `KDF:` line for the file at [path], e.g.
/// `Argon2id (3 rounds, 65536 KB)`.
Future<String> keePassXcKdf(
  String cli,
  String path, {
  String? password,
  String? keyFile,
}) async {
  final process = await Process.start(cli, [
    'db-info',
    '-q',
    if (keyFile != null) ...['-k', keyFile],
    if (password == null) '--no-password',
    path,
  ]);
  if (password != null) process.stdin.writeln(password);
  await process.stdin.close();
  final out = await process.stdout.transform(utf8.decoder).join();
  final error = await process.stderr.transform(utf8.decoder).join();
  expect(await process.exitCode, 0, reason: error);
  return RegExp(r'^KDF: (.*)$', multiLine: true).firstMatch(out)!.group(1)!;
}

/// The Argon2 settings in [bytes]'s header (password [password]), read by
/// tom_kpasslib directly.
Future<kp.KdbxArgon2Settings?> headerArgon2(Uint8List bytes) async {
  final db = await kp.KdbxDatabase.fromBytes(
    data: bytes,
    credentials: kp.KdbxCredentials(
      password: kp.ProtectedData.fromString(password),
    ),
  );
  return db.header.argon2Settings;
}

void main() {
  final cli = findKeePassXc();
  final skipCli = cli == null ? 'keepassxc-cli is not on this machine' : null;
  final manifest =
      (jsonDecode(File('$corpus/manifest.json').readAsStringSync()) as List)
          .cast<Map<String, Object?>>();

  Credentials corpusCredentials(Map<String, Object?> entry) =>
      Credentials.composite(
        entry['password'] == null
            ? null
            : ProtectedValue.fromString(entry['password']! as String),
        entry['keyFile'] == null
            ? null
            : File('$corpus/keys/${entry['keyFile']}').readAsBytesSync(),
      );

  const argon2id = KdbxArgon2(
    type: KdbxArgon2Type.argon2id,
    memory: 8 << 20,
    iterations: 3,
    parallelism: 2,
  );

  test('KDF-1: without a choice a new file is Argon2d, 1 MiB, 2 iterations, '
      '1 lane, and a save keeps it', () async {
    final file = KdbxFormat().create(credentials, 'd');
    expect(file.argon2, KdbxArgon2.defaults);
    expect(KdbxArgon2.defaults.type, KdbxArgon2Type.argon2d);
    final reread = await KdbxFormat().read(await file.save(), credentials);
    expect(reread.argon2, KdbxArgon2.defaults);
  });

  test('KDF-2: a file created with Argon2id carries it in its header, and a '
      'save of the reread file keeps it', () async {
    final file = KdbxFormat().create(credentials, 'id', argon2: argon2id);
    expect(file.argon2, argon2id);
    final bytes = await file.save();

    final header = await headerArgon2(bytes);
    expect(header!.type, kp.Argon2Type.argon2id);
    expect(header.memory, 8 << 20);
    expect(header.iterations, 3);
    expect(header.parallelism, 2);
    expect(header.version, kp.Argon2Version.v13);

    final reread = await KdbxFormat().read(bytes, credentials);
    expect(reread.argon2, argon2id);
    final again = await KdbxFormat().read(await reread.save(), credentials);
    expect(again.argon2, argon2id);
  });

  test('KDF-3: KeePassXC opens a file created with Argon2id and reports '
      'the same KDF', () async {
    final file = KdbxFormat().create(credentials, 'kxc', argon2: argon2id);
    final dir = Directory.systemTemp.createTempSync('kdbx_kdf_');
    try {
      final written = File('${dir.path}/argon2id.kdbx')
        ..writeAsBytesSync(await file.save());
      expect(
        await keePassXcKdf(cli!, written.path, password: password),
        'Argon2id (3 rounds, 8192 KB)',
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, skip: skipCli);

  final argon2idFiles = [
    for (final entry in manifest)
      if (entry['kdf'] == 'argon2id' &&
          (entry['writer']! as String).startsWith(RegExp('KeePass')))
        entry,
  ];

  test('KDF-4: the corpus holds Argon2id files written by KeePassXC and by '
      'KeePass 2.x', () {
    final writers = {
      for (final e in argon2idFiles) (e['writer']! as String).split(' ').first,
    };
    expect(writers, containsAll(['KeePassXC', 'KeePass']));
  });

  for (final entry in argon2idFiles) {
    final name = entry['file']! as String;
    test('KDF-5 $name: read as Argon2id, and written back with the same '
        'Argon2', () async {
      final bytes = File('$corpus/$name').readAsBytesSync();
      final file = await KdbxFormat().read(bytes, corpusCredentials(entry));
      final kdf = file.argon2!;
      expect(kdf.type, KdbxArgon2Type.argon2id);
      final reread = await KdbxFormat().read(
        await file.save(),
        corpusCredentials(entry),
      );
      expect(reread.argon2, kdf);
    });

    test('KDF-6 $name: KeePassXC reports the same KDF for the file and for '
        'what this package wrote back', () async {
      final bytes = File('$corpus/$name').readAsBytesSync();
      final file = await KdbxFormat().read(bytes, corpusCredentials(entry));
      final kdf = file.argon2!;
      final keyFile = entry['keyFile'] == null
          ? null
          : '$corpus/keys/${entry['keyFile']}';
      final pw = entry['password'] as String?;
      final original = await keePassXcKdf(
        cli!,
        '$corpus/$name',
        password: pw,
        keyFile: keyFile,
      );
      expect(
        original,
        'Argon2id (${kdf.iterations} rounds, ${kdf.memory ~/ 1024} KB)',
      );
      final dir = Directory.systemTemp.createTempSync('kdbx_kdf_');
      try {
        final written = File('${dir.path}/$name')
          ..writeAsBytesSync(await file.save());
        expect(
          await keePassXcKdf(cli, written.path, password: pw, keyFile: keyFile),
          original,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, skip: skipCli);
  }

  test(
    'KDF-7: a file with AES-KDF, and a KDBX 3 file, have no Argon2',
    () async {
      for (final name in ['kxc_created_both.kdbx', 'kp31_aeskdf_aes_pw.kdbx']) {
        final entry = manifest.firstWhere((e) => e['file'] == name);
        final file = await KdbxFormat().read(
          File('$corpus/$name').readAsBytesSync(),
          corpusCredentials(entry),
        );
        expect(file.argon2, isNull, reason: name);
      }
    },
  );

  test('KDF-8: an Argon2 outside its ranges is refused', () {
    for (final bad in const [
      KdbxArgon2(type: KdbxArgon2Type.argon2id, memory: 1000, iterations: 3),
      KdbxArgon2(type: KdbxArgon2Type.argon2id, memory: 1 << 20, iterations: 0),
      KdbxArgon2(
        type: KdbxArgon2Type.argon2id,
        memory: 1 << 20,
        iterations: 1,
        parallelism: 0,
      ),
    ]) {
      expect(
        () => KdbxFormat().create(credentials, 'bad', argon2: bad),
        throwsArgumentError,
        reason: '$bad',
      );
    }
  });
}
