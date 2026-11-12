/// The KDBX compatibility corpus (test/corpus/README.md): files written by
/// KeePass 2.x, KeePassXC, tom_kdbx, this package's 0.1.0 (on tom_kdbx) and
/// tom_kpasslib, over KDBX 3.1 / 4.0 / 4.1, Argon2d / Argon2id / AES-KDF, AES / ChaCha20,
/// password / key file / both.
///
/// For every file: this package reads what KeePassXC reads in it (its XML
/// export and the attachments it exports), the header states the version,
/// KDF and cipher the manifest names, and the file written back by this
/// package reads the same. With `keepassxc-cli` on the machine, KeePassXC
/// reads the written-back file the same as well (else that test skips).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';
import 'package:tom_kpasslib/tom_kpasslib.dart' as kp;

import 'support/corpus_model.dart';

const corpus = 'test/corpus';
const keepassxc = '/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli';

String? _findKeePassXc() {
  if (File(keepassxc).existsSync()) return keepassxc;
  final which = Process.runSync('which', ['keepassxc-cli']);
  final path = (which.stdout as String).trim();
  return which.exitCode == 0 && path.isNotEmpty ? path : null;
}

void main() {
  final manifest =
      (jsonDecode(File('$corpus/manifest.json').readAsStringSync()) as List)
          .cast<Map<String, Object?>>();
  final cli = _findKeePassXc();

  Uint8List? keyFileOf(Map<String, Object?> entry) => entry['keyFile'] == null
      ? null
      : File('$corpus/keys/${entry['keyFile']}').readAsBytesSync();

  Credentials credentialsOf(Map<String, Object?> entry) =>
      Credentials.composite(
        entry['password'] == null
            ? null
            : ProtectedValue.fromString(entry['password']! as String),
        keyFileOf(entry),
      );

  String stem(Map<String, Object?> entry) =>
      '$corpus/${(entry['file']! as String).replaceFirst(RegExp(r'\.kdbx$'), '')}';

  Map<String, Object?> expectedModel(Map<String, Object?> entry) =>
      modelFromKeePassXcXml(
        File('${stem(entry)}.keepassxc.xml').readAsStringSync(),
      );

  Map<String, Object?> expectedAttachments(Map<String, Object?> entry) =>
      jsonDecode(
            File(
              '${stem(entry)}.keepassxc.attachments.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  Future<KdbxFile> read(Map<String, Object?> entry, Uint8List bytes) =>
      KdbxFormat().read(bytes, credentialsOf(entry));

  test('CORPUS-0: the corpus holds every writer, version, KDF, cipher and key '
      'kind the README names', () {
    expect(manifest, hasLength(22));
    String all(String key) => manifest.map((e) => e[key]).join(' ');
    for (final writer in [
      'KeePass 2.',
      'KeePassXC',
      'tom_kdbx 2',
      'tom_kdbx_store 0.1.0',
      'tom_kpasslib',
    ]) {
      expect(all('writer'), contains(writer));
    }
    expect(
      manifest.map((e) => e['version']),
      containsAll(['3.1', '4.0', '4.1']),
    );
    expect(
      manifest.map((e) => e['kdf']),
      containsAll(['argon2d', 'argon2id', 'aes-kdf']),
    );
    expect(manifest.map((e) => e['cipher']), containsAll(['aes', 'chacha20']));
    expect(manifest.where((e) => e['keyFile'] == null), isNotEmpty);
    expect(manifest.where((e) => e['password'] == null), isNotEmpty);
    expect(
      manifest.where((e) => e['password'] != null && e['keyFile'] != null),
      isNotEmpty,
    );
  });

  for (final entry in manifest) {
    final name = entry['file']! as String;
    final bytes = File('$corpus/$name').readAsBytesSync();

    test('CORPUS-1 $name: reads what KeePassXC reads, with the header the '
        'manifest names', () async {
      final file = await read(entry, bytes);
      expect(modelFromStore(file), expectedModel(entry));
      expect(attachmentsFromStore(file), expectedAttachments(entry));

      final header = (await kp.KdbxDatabase.fromBytes(
        data: bytes,
        credentials: kp.KdbxCredentials(
          password: entry['password'] == null
              ? null
              : kp.ProtectedData.fromString(entry['password']! as String),
          keyData: keyFileOf(entry),
        ),
      )).header;
      if (entry['version'] case final String version
          when !version.startsWith('KeePassXC')) {
        expect('${header.version.$1}.${header.version.$2}', version);
        expect(
          header.dataCipherUuid!.string,
          entry['cipher'] == 'aes' ? kp.CipherId.aes : kp.CipherId.chaCha20,
        );
        final kdf = header.version.$1 < 4
            ? 'aes-kdf'
            : header.aesKdfRounds != null
            ? 'aes-kdf'
            : header.argon2Settings!.type.name;
        expect(kdf, entry['kdf']);
      }
    });

    test(
      'CORPUS-2 $name: written back by this package, it reads the same',
      () async {
        final file = await read(entry, bytes);
        final again = await read(entry, await file.save());
        expect(modelFromStore(again), expectedModel(entry));
        expect(attachmentsFromStore(again), expectedAttachments(entry));
      },
    );

    test('CORPUS-3 $name: written back by this package, KeePassXC reads it '
        'the same', () async {
      final file = await read(entry, bytes);
      final dir = Directory.systemTemp.createTempSync('kdbx_corpus_');
      try {
        final written = File('${dir.path}/$name')
          ..writeAsBytesSync(await file.save());
        final process = await Process.start(cli!, [
          'export',
          '-q',
          '-f',
          'xml',
          if (entry['keyFile'] != null) ...[
            '-k',
            '$corpus/keys/${entry['keyFile']}',
          ],
          if (entry['password'] == null) '--no-password',
          written.path,
        ]);
        if (entry['password'] != null) process.stdin.writeln(entry['password']);
        await process.stdin.close();
        final xml = await process.stdout.transform(utf8.decoder).join();
        final error = await process.stderr.transform(utf8.decoder).join();
        expect(await process.exitCode, 0, reason: error);
        expect(modelFromKeePassXcXml(xml), expectedModel(entry));
      } finally {
        dir.deleteSync(recursive: true);
      }
    }, skip: cli == null ? 'keepassxc-cli is not on this machine' : null);
  }

  test('CORPUS-4: the key files are KeePass formats 2.0, 1.0 and 64 hex '
      'digits', () {
    String text(String name) => File('$corpus/keys/$name').readAsStringSync();
    expect(text('corpus_v2.keyx'), contains('<Version>2.0</Version>'));
    expect(text('corpus_v1.key'), contains('<Version>1.00</Version>'));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(text('corpus_hex.key')), isTrue);
    expect(
      sha256.convert(utf8.encode(text('corpus_hex.key'))).bytes,
      hasLength(32),
    );
  });
}
