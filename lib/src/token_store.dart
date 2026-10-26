/// The `tokens` group: remote credentials by host.
library;

import 'package:tom_kdbx/tom_kdbx.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'settings_store.dart';

/// Remote credentials kept in an encrypted settings container (group
/// `tokens`).
///
/// A token is a secret, so it lives where secrets live: a KDBX entry with the
/// value in the `Password` field, which `package:tom_kdbx` holds as a
/// [ProtectedValue] — encrypted in memory and encrypted at rest.
///
/// One entry per host, `Title` = the host. That is deliberately the shape a
/// password manager shows, so a user who opens the settings container in one
/// sees their token as an ordinary entry rather than as opaque custom data.
///
/// Structurally this class is **just a consumer** of [TomKdbxSettingsStore]:
/// `tokens` is one group among others and gets no privileged access.
class TomKdbxTokenStore extends TomTokenSource {
  /// The group tokens live in, created on first write.
  static const groupName = 'tokens';

  final TomKdbxSettingsStore settings;

  TomKdbxTokenStore(this.settings);

  @override
  Future<TomToken?> tokenFor(String host) async {
    final entry = settings.entryByTitle(groupName, host);
    final secret = entry?.getString(KdbxKeyCommon.PASSWORD)?.getText();
    if (entry == null || secret == null || secret.isEmpty) return null;
    return TomToken(
      host: host,
      secret: secret,
      account: entry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
    );
  }

  /// Stores [token], replacing any credential already held for its host.
  ///
  /// The caller still has to save the container — this only mutates the
  /// in-memory file, so a token obtained during a failed sign-in flow can be
  /// discarded by simply not saving.
  void put(TomToken token) {
    final entry = settings.requireEntryByTitle(groupName, token.host);
    entry.setString(
      KdbxKeyCommon.USER_NAME,
      token.account == null ? null : PlainValue(token.account!),
    );
    entry.setString(
      KdbxKeyCommon.PASSWORD,
      ProtectedValue.fromString(token.secret),
    );
  }

  /// Forgets the credential for [host], if any. Sign-out.
  void remove(String host) => settings.removeEntryByTitle(groupName, host);

  /// The credentials held, by host and account. Secrets are never returned —
  /// this is for a settings screen that lists connected accounts.
  List<TomTokenListing> get listings => [
    for (final entry in settings.entries(groupName))
      if (entry.getString(KdbxKeyCommon.TITLE)?.getText() case final host?
          when host.isNotEmpty)
        TomTokenListing(
          host: host,
          account: entry.getString(KdbxKeyCommon.USER_NAME)?.getText(),
        ),
  ];
}
