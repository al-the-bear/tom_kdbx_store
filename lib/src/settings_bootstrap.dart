/// Opening the encrypted settings container with the one key a device holds.
library;

import 'package:kdbx/kdbx.dart';
import 'package:tom_core_settings/tom_core_settings.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

import 'key_provider.dart';
import 'settings_container.dart';

/// Ensures this device has a usable key for its settings container, and
/// returns the container.
///
/// Minting the key, keeping it in the platform secret store and recording its
/// handle in device settings is `tom_core_settings`' [TomSettingsKeyBootstrap],
/// which knows no container format. This adds the KDBX half: the key is
/// registered with the key provider for [locator], and the container it opens
/// is handed back.
class TomKdbxSettingsBootstrap {
  final TomDeviceSettings device;
  final TomSecretStore secrets;
  final TomKdbxKeyProvider keys;
  final TomStorage storage;

  /// Where the settings container lives.
  final String locator;

  /// The application's prefix for the names the container stores.
  final String namespace;

  final KdbxFormat format;

  TomKdbxSettingsBootstrap({
    required this.device,
    required this.secrets,
    required this.keys,
    required this.storage,
    required this.locator,
    required this.namespace,
    KdbxFormat? format,
  }) : format = format ?? KdbxFormat();

  /// Registers this device's settings key with [keys] and returns the
  /// container it opens.
  ///
  /// The key comes from [TomSettingsKeyBootstrap.ensure]: idempotent, and a
  /// secret store that fails raises [TomSecretStoreException].
  ///
  /// The container is returned unloaded. Whether it opens is a separate
  /// question from whether a key exists, and conflating them here would hide
  /// the case that matters — a key that no longer matches the file.
  Future<TomKdbxSettingsContainer> ensure({String? message}) async {
    final key = await TomSettingsKeyBootstrap(
      device: device,
      secrets: secrets,
    ).ensure(message: message);

    keys.setKeyFor(locator, Credentials(ProtectedValue.fromString(key.secret)));

    return TomKdbxSettingsContainer(
      locator: locator,
      storage: storage,
      keys: keys,
      namespace: namespace,
      format: format,
    );
  }
}
