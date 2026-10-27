# tom_kdbx_store

KDBX storage for Tom applications: a **record store** over a KDBX file, an
**encrypted settings container** with its groups, and the **KDBX binding** of
`tom_core_storage`'s key port. Licensed GPL-3.0, because it imports `tom_kdbx`.

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

This is the one package that declares `tom_kdbx`. A consumer reaches the
format through the types this package re-exports and the operations it names,
and never depends on `tom_kdbx` itself, so the fork's version is chosen in one
place. For a
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

It depends on [`tom_kdbx`](https://pub.dev/packages/tom_kdbx) by version — the
workspace's fork of `kdbx` 2.4.2, published on pub.dev from
`al-the-bear/tom_kdbx`, branch `tom/2.4.2-patches` — never by a path to the
fork's working copy. Dart SDK `^3.10.0`; no Flutter dependency.

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

- **No browser.** `package:tom_kdbx` compiles under dart2js and then throws
  `Uint64 accessor not supported by dart2js` on the first container it reads or
  writes: the KDBX 4 header's variant dictionary is written with
  `ByteData.setUint64` and read with `getUint64`, which dart2js does not
  implement. A web build therefore cannot use this package; a browser
  application holds key material with `tom_core_storage`'s
  `TomMemoryKeyRegistry` and persists no encrypted settings.
- **No container-level merge.** `KdbxFile.merge` is two-way and entry-scoped:
  it cannot tell a deletion from an absence, settles disagreements silently,
  and does not merge meta custom data. A consumer that syncs merges its own
  model and writes the result; entries supply history, not merge semantics.
- **The history a library pushes is its own.** `tom_kdbx` decides when a field
  write pushes a history snapshot; a version that must be kept without becoming
  current is added explicitly with `historySnapshot`.

## Licence

GPL-3.0 (see [LICENSE](LICENSE)), inherited from `tom_kdbx` (upstream `kdbx`). A BSD-3 package never
depends on this one; the Webwork seam audit checks the workspace's shared BSD
packages for it.

## Tests

`dart test` runs the record store, the asset entry, the history store, the settings groups and the store's own
guard that it names no group, the settings version refusal, the discard of an
unopenable container, the bootstrap, the foreign client's moves, and a check
that `tom_kdbx` is taken by version from pub.dev, with no second KDBX
implementation beside it.
