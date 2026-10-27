/// Per-file KDBX keys: a default, and an override per container.
library;

import 'dart:typed_data';

import 'package:tom_kdbx/tom_kdbx.dart';
import 'package:tom_core_storage/settings.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'key_credentials.dart';

/// Per-file KDBX key management.
///
/// Every KDBX file may use a different key. A configurable [defaultKey]
/// covers ordinary files; if it fails to open a specific file, the
/// application prompts for that file's key and registers it here as a
/// per-file override.
///
/// The KDBX binding of [TomKeyRegistry]: a user interface registers key
/// *material* through the port, and this turns it into the credentials
/// containers are opened with.
class TomKdbxKeyProvider implements TomKeyRegistry {
  Credentials? defaultKey;
  final Map<String, Credentials> _overrides = {};

  TomKdbxKeyProvider({this.defaultKey});

  @override
  bool get hasDefault => defaultKey != null;

  @override
  void registerDefault(TomKeyMaterial? material) =>
      defaultKey = material?.toCredentials();

  @override
  void registerKeyFor(String locator, TomKeyMaterial material) =>
      setKeyFor(locator, material.toCredentials());

  @override
  TomKdbxKeyProvider newScope() => TomKdbxKeyProvider();

  /// Registers a per-file key override for [locator].
  void setKeyFor(String locator, Credentials credentials) =>
      _overrides[locator] = credentials;

  /// Drops the per-file override for [locator], falling back to [defaultKey].
  ///
  /// The in-memory half of "forget this file's key": without it, a forget that
  /// removed only the persisted copy would keep opening the file for the rest
  /// of the session and appear to have done nothing until the next launch.
  @override
  void removeKeyFor(String locator) => _overrides.remove(locator);

  /// The key that would be tried for [locator]: per-file override first,
  /// then the default key.
  Credentials? keyFor(String locator) => _overrides[locator] ?? defaultKey;

  @override
  bool hasOverrideFor(String locator) => _overrides.containsKey(locator);

  @override
  Iterable<String> get overriddenLocators => List.unmodifiable(_overrides.keys);

  /// Opens the KDBX file at [locator] from [bytes].
  ///
  /// Tries the per-file override, then the default key. A missing or
  /// rejected key surfaces as [TomKeyRequiredException] so the caller can
  /// prompt for the file-specific key.
  Future<KdbxFile> open(
    KdbxFormat format,
    String locator,
    Uint8List bytes,
  ) async {
    final credentials = keyFor(locator);
    if (credentials == null) {
      throw TomKeyRequiredException(locator, 'no key configured');
    }
    try {
      return await format.read(bytes, credentials);
    } on KdbxInvalidKeyException {
      throw TomKeyRequiredException(
        locator,
        hasOverrideFor(locator)
            ? 'the per-file key was rejected'
            : 'the default key was rejected',
      );
    }
  }
}
