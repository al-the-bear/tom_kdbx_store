/// The `identity` group: who this user is when they author something.
///
/// A one-entry group, but **not** a fragment group — the two fields map onto
/// the KDBX fields that already mean them (`Title` = display name, `UserName` =
/// author id), so the entry reads sensibly in a password manager instead of
/// carrying a YAML blob nothing else can interpret.
///
/// Nothing here is a secret: an author id is written into content other people
/// read. There is deliberately no `Password` field.
library;

import 'package:tom_kdbx/tom_kdbx.dart';

import 'package:tom_core_settings/tom_core_settings.dart';
import 'settings_store.dart';

/// Reads and writes the `identity` group of a settings container.
class TomKdbxIdentityStore {
  final TomKdbxSettingsStore settings;

  TomKdbxIdentityStore(this.settings);

  /// The stated identity, or [TomIdentity.unknown] when the group states
  /// nothing.
  ///
  /// Reads *the first* entry rather than requiring the only one, exactly as
  /// `readFragment` does: a container written by a build with a different idea
  /// of the group still yields a value. Settings are advisory, and an identity
  /// that cannot be read at all would stamp everything the user writes
  /// `unknown` — the worse of the two failures.
  TomIdentity read() {
    final entries = settings.entries(TomIdentity.groupName);
    if (entries.isEmpty) return TomIdentity.unknown;
    final entry = entries.first;
    final authorId = entry.getString(KdbxKeyCommon.USER_NAME)?.getText();
    return TomIdentity(
      displayName: entry.getString(KdbxKeyCommon.TITLE)?.getText() ?? '',
      authorId: authorId == null || authorId.isEmpty
          ? TomIdentity.unknownAuthorId
          : authorId,
    );
  }

  /// Replaces the stated identity.
  ///
  /// Writing [TomIdentity.unknown] **removes** the entry, so "the user has
  /// not said who they are" has one on-disk representation rather than two —
  /// the same rule `writeFragment` applies to a blank fragment.
  void write(TomIdentity identity) {
    final group = settings.group(TomIdentity.groupName);
    final existing = group.entries.isEmpty ? null : group.entries.first;
    if (identity.isUnknown) {
      if (existing != null) settings.file.deleteEntry(existing);
      return;
    }
    final entry = existing ?? _create(group);
    entry.setString(KdbxKeyCommon.TITLE, PlainValue(identity.displayName));
    entry.setString(KdbxKeyCommon.USER_NAME, PlainValue(identity.authorId));
  }

  KdbxEntry _create(KdbxGroup group) {
    final entry = KdbxEntry.create(settings.file, group);
    group.addEntry(entry);
    return entry;
  }
}
