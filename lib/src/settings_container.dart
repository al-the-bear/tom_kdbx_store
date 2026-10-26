/// An encrypted settings container as a *stored artifact*: where it lives,
/// how it is opened, how it is committed.
///
/// [TomKdbxSettingsStore] models the container's **layout** and knows nothing
/// about storage; this models its **lifecycle** and knows nothing about groups.
/// Keeping them apart lets a settings file sit on any storage backend next to
/// the documents without the layout learning a transport, and lets the layout
/// be tested against an in-memory file with no backend at all.
///
/// The key rules are the ordinary ones: the container is a KDBX file, so
/// [TomKdbxKeyProvider] supplies its key and a missing or rejected key raises
/// [TomKeyRequiredException] for the caller's prompt. There is deliberately
/// **no plaintext fallback** — the container holds tokens and keys, and an
/// unencrypted copy of it is exactly what it exists to avoid.
library;

import 'dart:typed_data';

import 'package:tom_kdbx/tom_kdbx.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'settings_store.dart';
import 'key_provider.dart';

/// Opens, holds and commits an encrypted settings container at one locator.
///
/// A single instance per application: the container is read once, edited in
/// memory by whichever group the user touched, and committed under
/// compare-and-swap like any other container.
class TomKdbxSettingsContainer {
  /// The KDBX database name written into a freshly created container.
  static const databaseName = 'settings';

  final String locator;
  final TomStorage storage;
  final TomKdbxKeyProvider keys;
  final KdbxFormat format;

  /// The application's prefix for the names the container stores; see
  /// [TomKdbxSettingsStore.namespace].
  final String namespace;

  TomKdbxSettingsStore? _store;
  String? _head;

  TomKdbxSettingsContainer({
    required this.locator,
    required this.storage,
    required this.keys,
    required this.namespace,
    KdbxFormat? format,
  }) : format = format ?? KdbxFormat();

  /// The loaded container, or null before [load] has succeeded.
  ///
  /// Exposed as a nullable rather than behind an `isLoaded` guard so a caller
  /// that can carry on without settings — which is every caller, settings
  /// being the middle layer of a ladder whose bottom is the built-in defaults —
  /// can simply fall through on null.
  TomKdbxSettingsStore? get store => _store;

  bool get isLoaded => _store != null;

  /// Whether a key is configured that could open (or create) the container.
  ///
  /// Checked before [load] by callers that must not raise: at start-up nothing
  /// has prompted for a key yet, and a start-up that pops a key dialog before
  /// the user has opened anything is asking them to unlock a file they do not
  /// know exists.
  bool get hasKey => keys.keyFor(locator) != null;

  /// Reads the container, creating an empty one in memory when the locator
  /// holds nothing yet.
  ///
  /// A container that does not exist is **not** an error: the first run of the
  /// application has no settings file, and the difference between "no file"
  /// and "a file that states nothing" is invisible to every group, all of which
  /// read an absent fragment as the defaults.
  ///
  /// Throws [TomKeyRequiredException] when no configured key opens it,
  /// and [TomKdbxSettingsVersionException] when it was written by a newer
  /// major layout — refused before this build stamps its own version on it.
  Future<TomKdbxSettingsStore> load() async {
    final credentials = keys.keyFor(locator);
    if (credentials == null) {
      throw TomKeyRequiredException(locator, 'no key configured');
    }

    Uint8List? bytes;
    try {
      bytes = await storage.readBytes(locator);
      _head = await storage.headOf(locator);
    } on TomContainerNotFoundException {
      bytes = null;
      _head = null;
    }

    final store =
        bytes == null
              ? TomKdbxSettingsStore.create(
                  format,
                  credentials,
                  namespace: namespace,
                  name: databaseName,
                )
              : (TomKdbxSettingsStore(
                  await keys.open(format, locator, bytes),
                  namespace: namespace,
                )..refuseNewerLayout(locator))
          ..markAsSettings();

    _store = store;
    return store;
  }

  /// Replaces a container that the configured key no longer opens with a
  /// fresh, empty one — **the only operation that removes a settings
  /// container**.
  ///
  /// A wiped or migrated keychain leaves the bootstrap a new key under the old
  /// handle, after which the file on disk is intact and unopenable. It comes
  /// back if the keychain does, so discarding it is the user's call and never
  /// an automatic one; a settings interface runs it on a confirmed "start
  /// fresh". With [keepBackup] the old bytes are first written beside it
  /// as `<locator>.locked-<UTC stamp>` — the same file under another name, so a
  /// later keychain restore can still open it by hand — and the name is
  /// returned; without it nothing of the old file remains.
  ///
  /// **It re-proves its own precondition** rather than trusting the caller: a
  /// key must be configured (otherwise the file is not locked, merely not yet
  /// keyed) and that key must fail to open the file. A container that opens is
  /// refused with a [StateError] and left untouched, so no path through this
  /// can discard settings that could still be read.
  ///
  /// Leaves the new container loaded and committed, so the next write lands.
  Future<String?> discardUnopenable({
    required bool keepBackup,
    DateTime? now,
  }) async {
    if (!hasKey) {
      throw StateError(
        'No settings key is configured, so $locator is not '
        'locked; there is nothing to discard.',
      );
    }
    try {
      await load();
      throw StateError(
        '$locator opens with the configured key; it is not '
        'locked and will not be discarded.',
      );
    } on TomKeyRequiredException {
      // The precondition: a key exists and the file refuses it.
    }
    final bytes = await storage.readBytes(locator);
    String? backup;
    if (keepBackup) {
      final at = (now ?? DateTime.now()).toUtc();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${at.year}${two(at.month)}${two(at.day)}-'
          '${two(at.hour)}${two(at.minute)}${two(at.second)}';
      backup = '$locator.locked-$stamp';
      await storage.commit(
        backup,
        TomChangeset.singleFile(bytes),
        message: 'Keep the settings this device could not open',
      );
    }
    await storage.delete(locator);
    _store = null;
    _head = null;
    await load();
    await save(message: 'Start fresh settings');
    return backup;
  }

  /// Commits the in-memory container, refusing the write if it moved.
  ///
  /// Returns the new head. Does nothing and returns null when nothing has been
  /// loaded — persisting a container you never read would replace whatever is
  /// there with an empty one.
  Future<String?> save({String? message}) async {
    final store = _store;
    if (store == null) return null;
    final bytes = await store.file.save();
    final head = await storage.commit(
      locator,
      TomChangeset.singleFile(bytes),
      expectedHead: _head,
      message: message ?? 'Update settings',
    );
    _head = head;
    return head;
  }
}
