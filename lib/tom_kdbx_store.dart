/// KDBX storage for Tom applications: a record store over a KDBX file, assets
/// as binaries on a reserved entry, an
/// encrypted settings container with its groups (keys, tokens, locations,
/// identity), the KDBX binding of `tom_core_settings`' key port, and the
/// settings bootstrap's container half.
///
/// GPL-3.0, because it imports `package:kdbx`; a BSD package never imports
/// this one.
library;

// The kdbx types this package's API names. A consumer that holds an entry, a
// file or credentials has to be able to name them, and doing so through this
// list keeps every consumer on the one pinned fork rather than each depending
// on `kdbx` directly. `KdbxCustomData` is what [TomKdbxRecordStore.meta]
// returns; `PlainValue` and `ProtectedValue` are the two kinds of field value a
// group distinguishes — a token or a key is protected, a locator is not.
export 'package:kdbx/kdbx.dart'
    show
        Credentials,
        KdbxCustomData,
        KdbxEntry,
        KdbxFile,
        KdbxFormat,
        KdbxGroup,
        KdbxInvalidKeyException,
        KdbxKey,
        KdbxKeyCommon,
        KdbxUuid,
        PlainValue,
        ProtectedValue;

export 'src/asset_entry.dart';
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
