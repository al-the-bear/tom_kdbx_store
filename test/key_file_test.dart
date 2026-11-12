/// A key file contributes to a file's key the way it did when this package
/// used `tom_kdbx`, so every file a key file protected still opens: the
/// composite key of each case below, with a password and without, is the hash
/// `tom_kdbx` 2.4.2+tom.4 computed for it (`Credentials.composite`).
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Key file (base64), composite hash with password `pw`, without password.
const cases = {
  'not_a_key_file_xml': (
    'PEtleUZpbGU+PERhdGE+d29uZXFyNTQta2V5ZmlsZS1iN2QyPC9EYXRhPjwvS2V5RmlsZT4=',
    '3af0bd1ab45f9671811793615e663a1dfa863dd2090320c281db5a4ed24d547b',
    '5cb2fb09f4d6d953d0e0206d4a2406cc6548a42a59120271331da24d1b296b9b',
  ),
  'v1_xml': (
    'PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48S2V5RmlsZT48TWV0YT48VmVyc2lvbj4xLjAwPC9WZXJzaW9uPjwvTWV0YT48S2V5PjxEYXRhPkFBRUNBd1FGQmdjSUNRb0xEQTBPRHhBUkVoTVVGUllYR0JrYUd4d2RIaDg9PC9EYXRhPjwvS2V5PjwvS2V5RmlsZT4=',
    '2af62f4428e2cc1d4833e5cb9a708ce8fa83258b35d80a8b089f63b95fe6d106',
    '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd',
  ),
  'v1_xml_no_meta': (
    'PEtleUZpbGU+PEtleT48RGF0YT4vLzc5L1B2NitmajM5dlgwOC9MeDhPL3U3ZXpyNnVubzUrYmw1T1BpNGVBPTwvRGF0YT48L0tleT48L0tleUZpbGU+',
    '7f0bfc807d301785a4aef882c04ba6d6c2b8be731935f95e79f98235f06b519f',
    '1865c00831e73f7ee23fc13cb2d0f588b9c341835ca7472f8ec035aba4b789d6',
  ),
  'v2_xml': (
    'PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz48S2V5RmlsZT48TWV0YT48VmVyc2lvbj4yLjA8L1ZlcnNpb24+PC9NZXRhPjxLZXk+PERhdGEgSGFzaD0iMDAwMDAwMDAiPjAwMDcwZTE1MWMyMzJhMzEzODNmNDY0ZDU0NWI2MjY5NzA3NzdlODU4YzkzOWFhMWE4YWZiNmJkYzRjYmQyZDk8L0RhdGE+PC9LZXk+PC9LZXlGaWxlPg==',
    '869abd2daedb84f2d031346da29ecac0e90b836c4735ce20522271ce14789e66',
    '2dfd602a7a260b7a12905fd2ebd4b9acf49eed561758b9cb89cbccee389ae02d',
  ),
  'hex64': (
    'MDAwMzA2MDkwYzBmMTIxNTE4MWIxZTIxMjQyNzJhMmQzMDMzMzYzOTNjM2Y0MjQ1NDg0YjRlNTE1NDU3NWE1ZA==',
    '27c33721254200f0de04154b7b04d1d3baa519a8b1310c5903a8f9812e2b06b3',
    'b8a0f684999e90aeb22205d81424d7546c2fd71197b355a7dfca9fba6d4d1a06',
  ),
  'hex64_newline': (
    'MDAwNTBhMGYxNDE5MWUyMzI4MmQzMjM3M2M0MTQ2NGI1MDU1NWE1ZjY0Njk2ZTczNzg3ZDgyODc4YzkxOTY5Ygo=',
    '84d978b59a137bdec0c2d63a74e1ca3733a3cb4e89d6cdd76794295180fbf356',
    '915d253fd2f1226e33a53cc8b3a96e11c24bb978cbba9fd1884c9dd035682f7a',
  ),
  'raw32': (
    'Aw4ZJC86RVBbZnF8h5KdqLO+ydTf6vUACxYhLDdCTVg=',
    '9e0461466a3e857d66db6115075b4a8080910a5246aaee9e255c9251aeabd9b0',
    '24266fc3d987e285426e614a7463fe669b72df9e5a3dbf04fa9aa08a2602f892',
  ),
  'text': (
    'YW55IGZpbGUgY2FuIGJlIGEga2V5IGZpbGU=',
    'c8b941df3b905183b18e1998224803531abd1225e82122b3d81b6e89a69dcef4',
    'faa311ed07f4b459db12a5ef512df68ab69d1ca8edb30f19822cf0850cc68e55',
  ),
};

void main() {
  for (final MapEntry(key: name, value: (file, withPassword, without))
      in cases.entries) {
    test('KDBX-KEYFILE-1: $name gives tom_kdbx\'s composite key', () {
      final bytes = base64.decode(file);
      expect(
        _hex(
          Credentials.composite(
            ProtectedValue.fromString('pw'),
            bytes,
          ).getHash(),
        ),
        withPassword,
      );
      expect(_hex(Credentials.composite(null, bytes).getHash()), without);
    });
  }

  test('KDBX-KEYFILE-2: a file keyed with a key file that is no KeePass key '
      'file opens with it again', () async {
    final keyFile = utf8.encode('<KeyFile><Data>not a key</Data></KeyFile>');
    final credentials = Credentials.composite(null, keyFile);
    final file = KdbxFormat().create(credentials, 'k');
    final back = await KdbxFormat().read(await file.save(), credentials);
    expect(back.body.meta.databaseName.get(), 'k');
  });
}
