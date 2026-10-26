/// The layout of an encrypted settings container.
library;

import 'package:tom_kdbx/tom_kdbx.dart';
import 'package:meta/meta.dart';
import 'package:tom_core_storage/tom_core_storage.dart';

/// An encrypted settings container's **layout**: groups of entries, and
/// single-entry groups that park a YAML fragment on one entry.
///
/// **This class knows no group names.** It offers group access, entry access
/// and the fragment accessors single-entry groups are built from — nothing
/// else. Every actual group (`tokens`, `keys`, `identity`, `locations`, an
/// application's own) is a **caller**, so the set of groups is an open registry
/// in fact and not merely in prose: adding a group is adding a consumer, never
/// an edit here. This class must not grow a `switch` on a group name, a group
/// enum or a validation table.
///
/// The marker and field names are formed from [namespace], the application's
/// own prefix — `<namespace>.settings`, `<namespace>.settingsVersion`,
/// `<namespace>.content` — so containers an application has already written
/// keep reading, and two applications' containers are told apart.
class TomKdbxSettingsStore {
  /// The version of the settings layout this build writes.
  static const _currentVersion = '1.0';

  /// The application's prefix for the names this container stores.
  final String namespace;

  final KdbxFile file;

  /// The one string field a single-entry group carries: a deterministic YAML
  /// fragment parked on a KDBX entry.
  final KdbxKey keyContent;

  TomKdbxSettingsStore(this.file, {required this.namespace})
    : keyContent = KdbxKey('$namespace.content');

  /// Creates a fresh settings container.
  static TomKdbxSettingsStore create(
    KdbxFormat format,
    Credentials credentials, {
    required String namespace,
    String name = 'settings',
  }) => TomKdbxSettingsStore(
    format.create(credentials, name),
    namespace: namespace,
  )..markAsSettings();

  String get _metaMarker => '$namespace.settings';
  String get _metaVersion => '$namespace.settingsVersion';

  /// Whether [file] carries the settings markers.
  @visibleForTesting
  bool get isSettingsContainer =>
      file.body.meta.customData[_metaMarker] == 'true';

  /// The layout version the container records, or null when it carries no
  /// marker yet.
  String? get _settingsVersion => file.body.meta.customData[_metaVersion];

  /// Refuses a container whose layout has a newer **major** version than this
  /// build writes, naming both versions.
  ///
  /// Checked before [markAsSettings], which stamps this build's version: run
  /// the other way round, the first load of a newer container would quietly
  /// relabel it as this build's layout, and every later write would be made in
  /// a format the file no longer admits to. An older or equal major is
  /// accepted, and so is a version this build cannot parse: refusing on a
  /// malformed marker would lock the user out of settings over the one field
  /// that says nothing about the content.
  void refuseNewerLayout(String locator) {
    final found = _settingsVersion;
    final major = found == null ? null : int.tryParse(found.split('.').first);
    if (major != null && major > _majorOf(_currentVersion)) {
      throw TomKdbxSettingsVersionException(
        locator,
        found: found!,
        supported: _currentVersion,
      );
    }
  }

  static int _majorOf(String version) => int.parse(version.split('.').first);

  /// Writes the settings markers. Idempotent.
  void markAsSettings() {
    file.body.meta.customData[_metaMarker] = 'true';
    file.body.meta.customData[_metaVersion] = _currentVersion;
  }

  // ── Groups & entries ────────────────────────────────────────────────────

  /// Group names present in the container. Not a registry — just what is
  /// there, which is how a settings interface can show a group this build
  /// predates.
  List<String> get groupNames => [
    for (final group in file.body.rootGroup.groups) group.name.get() ?? '',
  ];

  /// The group named [name], created on demand.
  KdbxGroup group(String name) {
    final root = file.body.rootGroup;
    for (final existing in root.groups) {
      if (existing.name.get() == name) return existing;
    }
    return file.createGroup(parent: root, name: name);
  }

  /// Entries of [groupName], in file order.
  List<KdbxEntry> entries(String groupName) =>
      group(groupName).entries.toList();

  /// The entry of [groupName] whose Title is [title], or null.
  KdbxEntry? entryByTitle(String groupName, String title) {
    for (final entry in group(groupName).entries) {
      if (entry.getString(KdbxKeyCommon.TITLE)?.getText() == title) {
        return entry;
      }
    }
    return null;
  }

  /// The entry of [groupName] titled [title], created (and titled) on demand.
  KdbxEntry requireEntryByTitle(String groupName, String title) {
    final existing = entryByTitle(groupName, title);
    if (existing != null) return existing;
    final entry = createEntry(groupName);
    entry.setString(KdbxKeyCommon.TITLE, PlainValue(title));
    return entry;
  }

  /// A new, empty entry in [groupName].
  KdbxEntry createEntry(String groupName) {
    final target = group(groupName);
    final entry = KdbxEntry.create(file, target);
    target.addEntry(entry);
    return entry;
  }

  /// Removes the entry of [groupName] titled [title], if present.
  void removeEntryByTitle(String groupName, String title) {
    final entry = entryByTitle(groupName, title);
    if (entry != null) file.deleteEntry(entry);
  }

  // ── Single-entry (fragment) groups ──────────────────────────────────────

  /// The fragment of a **single-entry** group, or null when the group states
  /// nothing.
  ///
  /// "The sole entry" is read as *the first* rather than *the only* one, so a
  /// container written by a build with a different idea of the group still
  /// yields a value instead of an error — settings are advisory, and a
  /// settings file that cannot be read at all is worse than one read
  /// conservatively.
  String? readFragment(String groupName) {
    final entries = group(groupName).entries;
    if (entries.isEmpty) return null;
    return entries.first.getString(keyContent)?.getText();
  }

  /// Replaces the fragment of a single-entry group. A null or blank
  /// [fragment] removes the entry, so "states nothing" has exactly one
  /// on-disk representation.
  void writeFragment(String groupName, String? fragment) {
    final target = group(groupName);
    final existing = target.entries.isEmpty ? null : target.entries.first;
    if (fragment == null || fragment.trim().isEmpty) {
      if (existing != null) file.deleteEntry(existing);
      return;
    }
    final entry = existing ?? requireEntryByTitle(groupName, groupName);
    if (entry.getString(keyContent)?.getText() == fragment) return;
    entry.setString(keyContent, PlainValue(fragment));
  }

  Future<List<int>> saveBytes() => file.save();
}

/// A settings container written by a newer major layout than this build reads:
/// refused rather than opened, so nothing this build writes can damage it.
/// [found] and [supported] are the two versions the refusal names.
class TomKdbxSettingsVersionException extends TomStorageException {
  /// The settings version the container records.
  final String found;

  /// The newest layout this build writes.
  final String supported;

  TomKdbxSettingsVersionException(
    String locator, {
    required this.found,
    required this.supported,
  }) : super(
         locator,
         'These settings were written by a newer version of this application '
         '(settings version $found); this build reads settings version '
         '$supported and older.',
       );
}
