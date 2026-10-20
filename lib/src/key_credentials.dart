/// Key material as KDBX credentials.
library;

import 'package:kdbx/kdbx.dart';
import 'package:tom_core_settings/tom_core_settings.dart';

/// The KDBX binding of [TomKeyMaterial]: material → `kdbx` credentials.
///
/// An extension rather than a method, so the material itself stays in
/// `tom_core_settings` with no `kdbx` import, and only code that already links
/// `package:kdbx` can ask for credentials.
extension TomKdbxKeyMaterialCredentials on TomKeyMaterial {
  /// Builds kdbx [Credentials] from this material.
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
