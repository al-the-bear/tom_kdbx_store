/// The `keys` group: where per-file container keys are kept.
///
/// A key is a secret, so it lives where secrets live — a `Password` field on a
/// KDBX entry, which `package:tom_kdbx` holds as a [ProtectedValue], encrypted in
/// memory and at rest. One entry per key, which is deliberately what a password
/// manager already shows.
///
/// **Two lookup keys, on purpose.** The two default scopes are found by Title,
/// because there is exactly one of each and the name *is* the scope. A per-file
/// override is found by **URL**, which holds the locator — never by Title, so
/// renaming the entry by hand in a password manager cannot detach the override
/// from the file it belongs to. The Title on an override is therefore a label.
///
/// Structurally this is **just a consumer** of [TomKdbxSettingsStore]: it
/// creates its override entries through the store's generic group access
/// rather than through a URL-keyed creator the store would have to grow for
/// this one group.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:tom_kdbx/tom_kdbx.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'settings_store.dart';
import 'package:tom_core_storage/settings.dart';

/// [TomKeyStore] over the settings container's `keys` group.
class TomKdbxKeyStore implements TomKeyStore {
  /// The group name. Named here rather than in the store.
  static const groupName = 'keys';

  /// Title of the entry holding the default document key.
  @visibleForTesting
  static const documentsDefaultScope = 'documents.default';

  /// Title of the entry holding the default collaboration-file key.
  static const _collaborationDefaultScope = 'collaboration.default';

  /// The unprotected field holding a key file's **locator**, in the store's
  /// namespace.
  ///
  /// Deliberately not a [ProtectedValue]: a path is not the secret, the bytes
  /// are, and the bytes are never stored here at all.
  @visibleForTesting
  KdbxKey get keyFileField => KdbxKey('${settings.namespace}.keyFile');

  final TomKdbxSettingsStore settings;

  /// Where key files are read from, when the caller wants them resolved.
  ///
  /// Optional because most callers only need to *record* a key file. A store
  /// built without it returns material that names a key file it has not read —
  /// `isResolvable == false` — rather than pretending the key is complete.
  final TomStorage? keyFiles;

  TomKdbxKeyStore(this.settings, {this.keyFiles});

  // ── Default scopes (looked up by Title) ─────────────────────────────────

  @override
  Future<TomKeyMaterial?> loadDefaultKey() => _readScope(documentsDefaultScope);

  @override
  Future<void> saveDefaultKey(TomKeyMaterial? material) async =>
      _writeScope(documentsDefaultScope, material);

  @override
  Future<TomKeyMaterial?> loadCollaborationDefaultKey() =>
      _readScope(_collaborationDefaultScope);

  @override
  Future<void> saveCollaborationDefaultKey(TomKeyMaterial? material) async =>
      _writeScope(_collaborationDefaultScope, material);

  Future<TomKeyMaterial?> _readScope(String scope) =>
      _readMaterial(settings.entryByTitle(groupName, scope));

  void _writeScope(String scope, TomKeyMaterial? material) {
    // A null (or contentless) key forgets the scope, so "no default key" has
    // one representation rather than two — an absent entry and a blank one
    // would otherwise both mean it.
    if (material == null || material.isEmpty) {
      settings.removeEntryByTitle(groupName, scope);
      return;
    }
    _writeMaterial(settings.requireEntryByTitle(groupName, scope), material);
  }

  // ── Per-file overrides (looked up by URL) ───────────────────────────────

  @override
  Future<Map<String, TomKeyMaterial>> loadOverrides() async {
    final overrides = <String, TomKeyMaterial>{};
    for (final entry in settings.entries(groupName)) {
      final locator = entry.getString(KdbxKeyCommon.URL)?.getText();
      if (locator == null || locator.isEmpty) continue;
      final material = await _readMaterial(entry);
      if (material != null) overrides[locator] = material;
    }
    return overrides;
  }

  @override
  Future<void> saveOverride(String locator, TomKeyMaterial material) async {
    final entry = _entryForLocator(locator) ?? _createEntry();
    entry.setString(KdbxKeyCommon.URL, PlainValue(locator));
    // A label, not a key: the lookup above is by URL, so a user renaming this
    // in a password manager changes what they see and nothing else.
    entry.setString(KdbxKeyCommon.TITLE, PlainValue('file:$locator'));
    _writeMaterial(entry, material);
  }

  @override
  Future<void> removeOverride(String locator) async {
    final entry = _entryForLocator(locator);
    if (entry != null) settings.file.deleteEntry(entry);
  }

  /// Locators an override is held for. Values are never returned — this is for
  /// a settings screen listing the files with their own key.
  List<String> get overriddenLocators => [
    for (final entry in settings.entries(groupName))
      if (entry.getString(KdbxKeyCommon.URL)?.getText() case final locator?
          when locator.isNotEmpty)
        locator,
  ];

  KdbxEntry? _entryForLocator(String locator) {
    for (final entry in settings.entries(groupName)) {
      if (entry.getString(KdbxKeyCommon.URL)?.getText() == locator) {
        return entry;
      }
    }
    return null;
  }

  /// Creates an entry using only the store's generic group access.
  KdbxEntry _createEntry() => settings.createEntry(groupName);

  // ── Field mapping ───────────────────────────────────────────────────────

  void _writeMaterial(KdbxEntry entry, TomKeyMaterial material) {
    final passphrase = material.passphrase;
    entry.setString(
      KdbxKeyCommon.PASSWORD,
      passphrase == null || passphrase.isEmpty
          ? null
          : ProtectedValue.fromString(passphrase),
    );
    final keyFile = material.keyFileLocator;
    entry.setString(
      keyFileField,
      keyFile == null || keyFile.isEmpty ? null : PlainValue(keyFile),
    );
  }

  Future<TomKeyMaterial?> _readMaterial(KdbxEntry? entry) async {
    if (entry == null) return null;
    final passphrase = entry.getString(KdbxKeyCommon.PASSWORD)?.getText();
    final keyFileLocator = entry.getString(keyFileField)?.getText();
    return TomKeyMaterial(
      passphrase: passphrase == null || passphrase.isEmpty ? null : passphrase,
      keyFileLocator: keyFileLocator == null || keyFileLocator.isEmpty
          ? null
          : keyFileLocator,
      keyFileBytes: await _readKeyFile(keyFileLocator),
    );
  }

  /// Resolves a key-file locator to bytes, or gives up quietly.
  ///
  /// An unreadable key file **degrades** rather than throwing: the material
  /// comes back unresolvable, and the caller prompts for that one file. The
  /// alternative — raising here — would make a single detached USB stick fail
  /// the whole start-up hydration, taking every other key with it.
  Future<Uint8List?> _readKeyFile(String? locator) async {
    final storage = keyFiles;
    if (storage == null || locator == null || locator.isEmpty) return null;
    try {
      return await storage.readBytes(locator);
    } on TomStorageException {
      return null;
    }
  }
}
