# tom_kdbx_store

Published on pub.dev as [`tom_kdbx_store` 0.2.2](https://pub.dev/packages/tom_kdbx_store).

KDBX storage for Tom applications: a **record store** over a KDBX file, an
**encrypted settings container** with its groups, and the **KDBX binding** of
`tom_core_storage`'s key port. Licensed BSD-3.

## Overview

A KDBX file is a password manager's database: an encrypted container of
entries, each with string fields, attachments, a history of earlier versions,
and a recycle bin for deleted ones. This package uses that format for two
things.

- **Records.** `TomKdbxRecordStore` treats the file's root group as a store of
  records, one entry per record, the entry's UUID being the record's id. It
  restores a returning record from the recycle bin instead of minting a second
  entry with the same UUID, clears a stale deletion record from an entry being
  written, makes detached history snapshots, prunes history while protecting a
  snapshot a caller still names (and reports where it moved), and mints
  reserved entries at fixed ids, and says whether a record is recorded as
  permanently deleted. What a record *contains* is the caller's; the store
  never reads a field. Webwork's `.webwork.kdbx` document layout and its
  encrypted collaboration file are consumers of it.
- **Assets.** `TomKdbxAssetEntry` keeps a `tom_core_storage` `TomAssetStore`
  in the file: every asset's bytes are a binary of one reserved entry, keyed by
  its id, with the metadata map as a fragment on that entry. A write that
  changes the asset set is one `modify`, so the entry's history gains one
  snapshot holding every asset the write retired — the append-only history
  area a retired asset resolves from.
- **History.** `TomKdbxHistoryStore` is `tom_core_sync`'s history port over
  entry history: a retained version is a detached snapshot appended to the
  record's entry and addressed by its position, and pruning walks every record
  entry — the recycle bin included — keeping the newest versions, any version
  a conflict record still names, and the whole history of an append-only
  record, and answers where a protected version moved to.
- **Settings.** `TomKdbxSettingsStore` is a settings container's layout:
  groups of entries, and single-entry groups that park a YAML fragment on one
  entry. It knows no group names; every group is a consumer —
  `TomKdbxKeyStore` (`keys`), `TomKdbxTokenStore` (`tokens`),
  `TomKdbxLocationStore` (`locations`), `TomKdbxIdentityStore` (`identity`),
  and whatever groups an application adds. `TomKdbxSettingsContainer` opens and
  commits the container through a `TomStorage`, and
  `TomKdbxSettingsBootstrap` opens it with the one key a device holds, minted by
  `tom_core_storage`'s `TomSettingsKeyBootstrap`.

The marker and field names a settings container stores are formed from the
**namespace** the application passes (`<namespace>.settings`,
`<namespace>.content`, `<namespace>.keyFile`), so an application's existing
containers keep reading and two applications' containers are told apart.

Keys are stated as `tom_core_storage`'s `TomKeyMaterial`;
`TomKdbxKeyProvider` is the `TomKeyRegistry` that turns material into KDBX
`Credentials` (a passphrase, a key file, or both) and opens containers, with a
default key and an override per file.

The KDBX types the API names are the package's own (`KdbxFile`, `KdbxEntry`,
`KdbxGroup`, `Credentials`, `KdbxFormat`, `PlainValue` / `ProtectedValue`,
`KdbxKey`, `KdbxUuid`, ...), implemented over
[`tom_kpasslib`](https://pub.dev/packages/tom_kpasslib). This is the one
package that declares the KDBX library: a consumer names only these types, so
the library underneath is chosen in one place and can change without the
consumer noticing. For a
consumer's tests, `package:tom_kdbx_store/testing.dart` has
`TomKdbxForeignClient`: what another KeePass client does to a file and this
package never does — filing an entry under a folder of its own, emptying the
recycle bin.

## Installation

Consumed by path inside this workspace:

```yaml
dependencies:
  tom_kdbx_store:
    path: ../../tom_ai/kdbx_store
```

It depends on [`tom_kpasslib`](https://pub.dev/packages/tom_kpasslib) by
version — the workspace's fork of `kpasslib` 1.1.2 (MIT), published on pub.dev
from `al-the-bear/tom_kpasslib`, branch `tom/1.1.2-patches` — never by a path to
the fork's working copy. Dart SDK `^3.10.0`; no Flutter dependency. It runs on
the VM and in the browser.

## Example

```dart
import 'package:tom_core_storage/settings.dart';
import 'package:tom_core_storage/io.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';

Future<void> main() async {
  const storage = TomLocalFileSystemStorage();
  final keys = TomKdbxKeyProvider();
  final container = await TomKdbxSettingsBootstrap(
    device: TomDeviceSettings(locator: 'device.yaml', storage: storage),
    secrets: TomInMemorySecretStore(),
    keys: keys,
    storage: storage,
    locator: 'settings.kdbx',
    namespace: 'myapp',
  ).ensure();

  final settings = await container.load();
  TomKdbxTokenStore(
    settings,
  ).put(const TomToken(host: 'github.com', secret: 'ghp_…', account: 'me'));
  settings.writeFragment('preferences', 'theme: dark\n');
  await container.save();
}
```

## Limits

- **No container-level merge.** The package merges no two copies of a file.
  A consumer that syncs merges its own model and writes the result; entries
  supply history, not merge semantics.
- **When history is pushed.** An entry's first change after the file was read
  or saved pushes one snapshot of its previous state; a new entry pushes none,
  and further changes before the next save push none. A version that must be
  kept without becoming current is added explicitly with `historySnapshot`.
- **Key files** are read the way the earlier KDBX library `tom_kdbx` read
  them, so files it keyed still open: a file of exactly 32 raw bytes is hashed,
  where KeePass takes it as the key itself.
- **The key derivation of a new file** is chosen at creation:
  `KdbxFormat().create(credentials, name, argon2: KdbxArgon2(...))` takes the
  Argon2 variant (`argon2d` or `argon2id`), memory, iterations and lanes;
  without a choice a file gets `KdbxArgon2.defaults` (Argon2d, 1 MiB,
  2 iterations, 1 lane). `KdbxFile.argon2` reads an open file's Argon2 (null
  for AES-KDF and KDBX 3), and a save keeps it.
- **What reading refuses** is told by the package's own exceptions:
  `KdbxFormat().read` throws `KdbxInvalidKeyException` when the credentials do
  not open the file, and `KdbxFormatException` (a `FormatException`) for bytes
  that are no KDBX file it reads: no signature, damaged, cut short, or an
  unsupported version or algorithm. No type of the library underneath
  reaches a caller.
- **Argon2 in the browser** is pointycastle's, slower than on the VM: a file
  with a high memory cost takes seconds to open there.

## Licence

BSD-3 (see [LICENSE](LICENSE)). The KDBX library underneath, `tom_kpasslib`,
is MIT. Version 0.1.0, built on the GPL-3 `tom_kdbx`, was published under
GPL-3.0 and stays so.

## Tests

`dart test` runs the record store, the asset entry, the history store, the settings groups and the store's own
guard that it names no group, the settings version refusal, the discard of an
unopenable container, the bootstrap, the foreign client's moves, the KDBX
types (when history is pushed, times, tags, binaries, protected values, a
rejected key, a file written by the earlier KDBX library `tom_kdbx`, key
files giving the composite keys `tom_kdbx` computed), the KDBX compatibility
corpus (files written by KeePassXC, `tom_kdbx`, 0.1.0 and `tom_kpasslib`, each
read as KeePassXC reads it, before and after a write-back; `test/corpus/`), and a
check that `tom_kpasslib` is taken by version from pub.dev, with no other KDBX
library beside it. The suites that read no file from disk also run in the
browser: `dart test -p chrome` with `CHROME_EXECUTABLE` set, naming those test
files.

## Disclaimer

This software is provided "as is", without warranty of any kind, express or
implied, including but not limited to the warranties of merchantability and
fitness for a particular purpose. In no event shall the authors, copyright
holders or contributors be liable for any claim, damages or other liability
arising from, out of or in connection with the software or its use. This
section summarises the warranty and liability disclaimer of the licence;
the licence text in [LICENSE](LICENSE) governs.
