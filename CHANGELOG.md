# Changelog

## 0.2.1

### Added

- `KdbxTimes.expires`: KDBX's `Expires` flag beside `expiryTime` (an entry
  expires only when the flag is set).

## 0.2.0

### Changed

- **Licensed BSD-3.** The package no longer contains or links GPL code: the
  KDBX library is `tom_kpasslib` (MIT) instead of `tom_kdbx` (GPL-3), so the
  package and every program built on it can be BSD-3. 0.1.0 stays GPL-3.0 on
  pub.dev as it was published.

- **The KDBX library is `tom_kpasslib`** (the workspace's fork of `kpasslib`,
  MIT) instead of `tom_kdbx` (AuthPass's `kdbx.dart`, GPL-3). The KDBX types the
  API names are the package's own (`lib/src/kdbx_model.dart`), with the names
  and behaviour consumers used: `KdbxFile`, `KdbxEntry`, `KdbxGroup`,
  `KdbxFormat`, `Credentials`, `PlainValue`, `ProtectedValue`, `KdbxKey`,
  `KdbxKeyCommon`, `KdbxUuid`, `KdbxCustomData`, `KdbxInvalidKeyException`,
  and beside them `StringValue`, `KdbxBinary`, `KdbxBody`, `KdbxMeta`,
  `KdbxTimes` and `KdbxNode`. Members of `tom_kdbx`'s types the package never
  used are gone (merge, change streams, dirty tracking, icons, ...).
- **It runs in the browser**: `tom_kpasslib` compiles with dart2js.
- **Key files read as before.** `Credentials.composite` takes the key-file
  part the way `tom_kdbx` did (`Credentials.keyFileKey`): 64 hex digits, an XML
  key file (hex for 2.x, base64 otherwise), else the SHA-256 of the file — so
  every file a key file protected still opens. `tom_kpasslib` alone refuses
  XML that is no key file and takes 32 raw bytes as the key itself.
- `tom_kpasslib` ^1.1.2+tom.3: it reads a binary's protected flag the right way
  round (tom.2), and keeps a KDBX 3 file's protected values beside a protected
  binary (tom.3).
- Read-only on the types: `KdbxFile.deletedObjects`, `KdbxMeta.customIcons`,
  `KdbxEntry.customIconUuid`.
- A KDBX compatibility corpus (`test/corpus/`, README there): files written by
  KeePassXC, `tom_kdbx`, this package's 0.1.0 and `tom_kpasslib` over KDBX
  3.1 / 4.0 / 4.1, Argon2d / Argon2id / AES-KDF, AES / ChaCha20 and password /
  key file / both. Each reads as KeePassXC reads it, before and after this
  package writes it back (`test/corpus_test.dart`).
- New on the types: `KdbxEntry.label`, `KdbxFile.recycleBin`,
  `KdbxFile.credentials` (re-keying), `KdbxMeta.databaseName`,
  `Credentials.getHash`.
- A new file has no recycle bin until something is deleted, as before; a file
  whose recycle bin is switched off gets it switched on by a delete.

## 0.1.0

### Added

- **`package:tom_kdbx_store/testing.dart`** — `TomKdbxForeignClient`, what
  another KeePass client does to a file and this package never does (file an
  entry under a folder, empty it out of the recycle bin), for a consumer's
  tests; and **`TomKdbxRecordStore.isRecordedDeleted`**, whether a record is
  recorded as permanently deleted. With them a consumer needs no dependency on
  `tom_kdbx` of its own: this is the one package that names the fork.
- **`tom_kdbx` by version.** The KDBX format is `tom_kdbx` ^2.4.2+tom.4 from
  pub.dev (the workspace's fork of `kdbx`, published under its own name),
  replacing the git dependency on the fork; imports are
  `package:tom_kdbx/tom_kdbx.dart`.
- **`TomKdbxRecordStore`** — a KDBX file as a store of records: one root-group
  entry per record, entry UUID = record id; restore-or-create for a returning
  record (moved back from the recycle bin, never minted twice), deletion
  records cleared for every entry written, detached history snapshots, history
  pruning that keeps a protected snapshot and reports where it moved, reserved
  entries at fixed ids, and the file's meta custom data.
- **`TomKdbxAssetEntry`** — a `TomAssetStore` in a KDBX file: binaries on one
  reserved entry keyed by asset id, the metadata map as a fragment on it, one
  history snapshot per write that changes the set (the append-only history
  area), verification on read, a missing binary skipped. Adds `tom_basics` and
  `yaml` as dependencies.
- **`TomKdbxHistoryStore`** — `tom_core_sync`'s history port over KDBX entry
  history: positional locators, retention by depth with a protected version
  that is re-pointed when it moves, append-only records left whole. Adds
  `tom_core_sync` as a dependency.
- **The settings container.** `TomKdbxSettingsStore` (groups, entries,
  single-entry fragment groups; no group names; marker and field names under
  the application's namespace), `TomKdbxSettingsVersionException` for a newer
  major layout, `TomKdbxSettingsContainer` (load, commit under compare-and-swap,
  discard an unopenable container with an optional backup), and
  `TomKdbxSettingsBootstrap`, which opens it with the device key
  `tom_core_settings` mints.
- **Groups.** `TomKdbxKeyStore` (`keys`: two default scopes by Title,
  per-file overrides by URL, key files by locator only), `TomKdbxTokenStore`
  (`tokens`, a `TomTokenSource`), `TomKdbxLocationStore` (`locations`),
  `TomKdbxIdentityStore` (`identity`).
- **The KDBX key binding.** `TomKdbxKeyProvider` (a `TomKeyRegistry` with a
  default key and per-file overrides that opens containers),
  `TomKeyMaterial.toCredentials()`, and the UUID helpers
  `tomKdbxUuidFromCanonical` / `tomCanonicalFromKdbxUuid`.

These came from the Webwork app, where they carried the `Webwork` prefix; the
record store was generalised from its `.webwork.kdbx` document store, which is
now one of its consumers.
