/// Assets in a KDBX file: binaries on one reserved entry, keyed by id, with
/// the metadata map as a fragment on the same entry.
library;

import 'package:kdbx/kdbx.dart';
import 'package:tom_basics/utilities.dart';
import 'package:tom_core_storage/tom_core_storage.dart';
import 'package:yaml/yaml.dart' as yaml;

import 'record_store.dart';

/// How a [TomAssetStore] is laid out in a KDBX file.
///
/// Every asset's bytes are a binary attachment of one reserved entry at
/// [entryId], keyed by the asset id (64 hex characters, which the library's
/// file-name uniquifier leaves as given), and the metadata map — per id, the
/// asset's [TomAsset.metadata] — is a canonical YAML fragment in the entry's
/// [contentKey] field.
///
/// All binary changes of one write are made inside **one** `modify`, so the
/// entry gains exactly one history snapshot per write that changed its asset
/// set — the state before it, which holds every asset the write retires. That
/// history is the KDBX counterpart of a bundle's history folder, and is
/// **append-only** for the same reason: a pruning policy must skip this entry.
/// A write that changes nothing touches nothing.
class TomKdbxAssetEntry {
  /// The types the assets are filed as.
  final TomAssetTypes types;

  /// The canonical UUID of the reserved entry.
  final String entryId;

  /// The field holding the metadata fragment.
  final KdbxKey contentKey;

  /// The entry's Title — informational, for a KDBX browser.
  final String title;

  /// Further string fields that mark the entry for its application (a type
  /// field, say), written with every change.
  final Map<KdbxKey, String> markers;

  const TomKdbxAssetEntry({
    required this.types,
    required this.entryId,
    required this.contentKey,
    this.title = 'Assets',
    this.markers = const {},
  });

  /// Writes the entry from [store] and the [live] ids — the assets content
  /// still references — and retires from [store] what [live] no longer names.
  ///
  /// Every live asset [store] holds must already be loaded
  /// ([TomAssetStore.materialize]): this writer is synchronous, as the KDBX
  /// library is. A live id [store] does not hold but the entry carries as a
  /// binary is kept, with the metadata it already has. Sets [store]'s history
  /// to the entry's.
  void write(
    TomKdbxRecordStore records,
    TomAssetStore store,
    Set<String> live,
  ) {
    final existing = records.rootEntry(entryId);
    final held = <String, TomAsset>{
      for (final id in live) id: ?store.assets[id],
    };
    final current = <String>{
      ...?existing?.binaryEntries.map((binary) => binary.key.key),
    };
    final keep = {...held.keys, ...live.intersection(current)};
    final metadata = <String, Object?>{
      for (final id in keep.toList()..sort())
        id: held[id]?.metadata() ?? _storedMetadata(existing, id),
    }..removeWhere((_, value) => value == null);
    final fragment = metadata.isEmpty ? '' : tomEmitCanonicalFragment(metadata);

    if (keep.isEmpty && existing == null) {
      _retireUnheld(store, live);
      return;
    }
    final unchanged =
        existing != null &&
        current.length == keep.length &&
        current.containsAll(keep) &&
        (existing.getString(contentKey)?.getText() ?? '') == fragment;
    if (unchanged) {
      _retireUnheld(store, live);
      store.history = historyOf(existing);
      return;
    }

    final target = existing ?? records.createWithId(entryId);
    target.modify(() {
      target.setString(KdbxKeyCommon.TITLE, PlainValue(title));
      for (final marker in markers.entries) {
        target.setString(marker.key, PlainValue(marker.value));
      }
      target.setString(contentKey, PlainValue(fragment));
      for (final id in current.difference(keep)) {
        target.removeBinary(KdbxKey(id));
      }
      for (final id in keep.difference(current)) {
        target.createBinary(
          isProtected: false,
          name: id,
          bytes: held[id]!.loadedBytes,
        );
      }
    });
    _retireUnheld(store, live);
    store.history = historyOf(target);
  }

  /// Adopts into [store] every asset [entry] holds, verifying each binary
  /// against its id **now** — a decrypted file already holds the bytes, so
  /// the check costs a hash. A binary the metadata names but the entry lacks
  /// is skipped: it resolves as missing, never a load failure. Sets [store]'s
  /// history to the entry's.
  ///
  /// Throws [FormatException] for metadata naming a MIME type or a kind
  /// [types] does not file, and [TomAssetCorruptException] for bytes that do
  /// not hash to their id.
  void read(KdbxEntry entry, TomAssetStore store, {String? where}) {
    final at = where ?? 'KDBX entry $entryId';
    final fragment = entry.getString(contentKey)?.getText() ?? '';
    final map = fragment.trim().isEmpty
        ? const <String, Object?>{}
        : (tomYamlToPlain(yaml.loadYaml(fragment)) as Map)
              .cast<String, Object?>();
    for (final item in map.entries) {
      final binary = entry.getBinary(KdbxKey(item.key));
      if (binary == null) continue;
      final meta = (item.value as Map).cast<String, Object?>();
      final mime = meta['mime'];
      if (mime is! String || types[mime] == null) {
        throw FormatException(
          'asset ${item.key} in $at has MIME type "$mime", which is not an '
          'asset type',
        );
      }
      if (!types.hasKind(meta['kind'])) {
        throw FormatException(
          'asset ${item.key} in $at has kind "${meta['kind']}", which is not a '
          'kind this container files',
        );
      }
      store.adopt(
        TomAsset.verified(
          id: item.key,
          mime: mime,
          bytes: binary.value,
          types: types,
          where: at,
        ),
      );
    }
    store.history = historyOf(entry);
  }

  /// The entry's history as the store's history area: the newest snapshot
  /// that still held the asset.
  TomAssetHistory historyOf(KdbxEntry entry) {
    final where = 'KDBX entry $entryId history';
    return (id) async {
      for (final old in entry.history.reversed) {
        final binary = old.getBinary(KdbxKey(id));
        if (binary == null) continue;
        // A snapshot whose metadata names no type this store files cannot
        // say what the bytes are; an older snapshot may.
        final mime = _storedMetadata(old, id)?['mime'];
        if (mime is! String || types[mime] == null) continue;
        return TomAsset.verified(
          id: id,
          mime: mime,
          bytes: binary.value,
          types: types,
          where: where,
        );
      }
      return null;
    };
  }

  /// Drops from [store] what [live] no longer names — the entry's history now
  /// holds it.
  static void _retireUnheld(TomAssetStore store, Set<String> live) {
    for (final id in store.assets.keys.toList()) {
      if (!live.contains(id)) store.retire(id);
    }
  }

  /// The metadata [entry] already records for [id], if any.
  Map<String, Object?>? _storedMetadata(KdbxEntry? entry, String id) {
    final fragment = entry?.getString(contentKey)?.getText();
    if (fragment == null || fragment.trim().isEmpty) return null;
    final map = tomYamlToPlain(yaml.loadYaml(fragment));
    if (map is! Map) return null;
    final meta = map[id];
    return meta is Map ? meta.cast<String, Object?>() : null;
  }
}
