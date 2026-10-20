# Changelog

## 0.1.0

### Added

- **`TomKdbxRecordStore`** — a KDBX file as a store of records: one root-group
  entry per record, entry UUID = record id; restore-or-create for a returning
  record (moved back from the recycle bin, never minted twice), deletion
  records cleared for every entry written, detached history snapshots, history
  pruning that keeps a protected snapshot and reports where it moved, reserved
  entries at fixed ids, and the file's meta custom data.
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
