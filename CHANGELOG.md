# Changelog

## 0.1.0

### Added

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
