/// Key material as KDBX credentials.
library;

import 'kdbx_model.dart';
import 'package:tom_core_storage/settings.dart';

/// The KDBX binding of [TomKeyMaterial]: material → KDBX [Credentials].
///
/// An extension rather than a method, so the material itself stays in
/// `tom_core_storage`'s `settings.dart` with no KDBX import, and only code
/// that already links this package can ask for credentials.
extension TomKdbxKeyMaterialCredentials on TomKeyMaterial {
  /// Builds KDBX [Credentials] from this material.
  ///
  /// Throws [StateError] when the material is not resolvable — see
  /// [TomKeyMaterial.requireResolvable].
  Credentials toCredentials() {
    requireResolvable();
    final passwordPart = (passphrase != null && passphrase!.isNotEmpty)
        ? ProtectedValue.fromString(passphrase!)
        : null;
    if (keyFileBytes != null && keyFileBytes!.isNotEmpty) {
      return Credentials.composite(passwordPart, keyFileBytes);
    }
    return Credentials(passwordPart!);
  }
}
