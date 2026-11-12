/// KDBX storage for Tom applications: a record store over a KDBX file, assets
/// as binaries on a reserved entry, an
/// encrypted settings container with its groups (keys, tokens, locations,
/// identity), the KDBX binding of `tom_core_storage`'s key port, and the
/// settings bootstrap's container half.
///
/// The KDBX types its API names — files, groups, entries, fields, credentials,
/// the format — are its own (`src/kdbx_model.dart`), implemented over
/// `tom_kpasslib`: a consumer names only this package, and the KDBX library
/// underneath can change without the consumer noticing.
library;

export 'src/kdbx_model.dart';
export 'src/asset_entry.dart';
export 'src/history_store.dart';
export 'src/identity_store.dart';
export 'src/key_credentials.dart';
export 'src/key_provider.dart';
export 'src/key_store.dart';
export 'src/location_store.dart';
export 'src/record_store.dart';
export 'src/settings_bootstrap.dart';
export 'src/settings_container.dart';
export 'src/settings_store.dart';
export 'src/token_store.dart';
export 'src/uuid_convert.dart';
