/// The `locations` group: the storage locations the user has registered.
///
/// One entry per location, keyed by **URL** (the locator) and never by Title,
/// because a display name is not an identity — a `notes` repository and a
/// `notes` folder are not a mistake, and renaming either in a password manager
/// may not merge them.
///
/// A location entry carries **no `Password`**. The credential for a location is
/// a `tokens` entry keyed by host, and a copy here would give a secret a second
/// home to defend.
library;

import 'package:tom_kdbx/tom_kdbx.dart';

import 'package:tom_core_storage/settings.dart';
import 'settings_store.dart';

/// Reads and writes the `locations` group of a settings container.
class TomKdbxLocationStore {
  final TomKdbxSettingsStore settings;

  TomKdbxLocationStore(this.settings);

  /// Every registered location, in file order.
  ///
  /// Entries with no locator are skipped rather than reported: this group is a
  /// convenience registry, and an entry a user created by hand in a password
  /// manager should cost them a missing row, not an error dialog.
  List<TomStorageLocation> get locations => [
    for (final entry in settings.entries(TomStorageLocation.groupName))
      if (entry.getString(KdbxKeyCommon.URL)?.getText() case final locator?
          when locator.isNotEmpty)
        TomStorageLocation(
          displayName: entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
          locator: locator,
        ),
  ];

  /// Registers [location], replacing whatever was held for its locator.
  void put(TomStorageLocation location) {
    final entry = _entryForLocator(location.locator) ?? _create();
    entry.setString(KdbxKeyCommon.URL, PlainValue(location.locator));
    entry.setString(KdbxKeyCommon.TITLE, PlainValue(location.displayName));
  }

  /// Forgets the location at [locator], if any.
  ///
  /// Forgetting a location does not touch anything stored *at* it — the group
  /// is a list of places the shell offers, not a list of places the user is
  /// allowed to open.
  void remove(String locator) {
    final entry = _entryForLocator(locator);
    if (entry != null) settings.file.deleteEntry(entry);
  }

  KdbxEntry? _entryForLocator(String locator) {
    for (final entry in settings.entries(TomStorageLocation.groupName)) {
      if (entry.getString(KdbxKeyCommon.URL)?.getText() == locator) {
        return entry;
      }
    }
    return null;
  }

  KdbxEntry _create() => settings.createEntry(TomStorageLocation.groupName);
}
