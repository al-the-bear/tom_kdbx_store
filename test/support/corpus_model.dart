/// The model the corpus test compares: what a KDBX file holds, as KeePassXC's
/// XML export states it and as this package reads it, in one canonical form.
///
/// Groups by path below the root; the recycle bin by path; entries by UUID with
/// their group, string fields (empty ones left out, each with whether it is
/// protected), attachment names, custom icon and history; the deleted objects;
/// meta custom data (KeePassXC's own `KPXC_*` and `_LAST_MODIFIED` left out);
/// custom icons by UUID with the SHA-256 of their image. Times are left out:
/// every writer stamps its own.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tom_kdbx_store/tom_kdbx_store.dart';
import 'package:xml/xml.dart';

/// Custom-data keys KeePassXC writes for itself, on every export.
bool _isKeePassXcOwn(String key) =>
    key.startsWith('KPXC_') || key == '_LAST_MODIFIED';

Map<String, Object?> _fieldsOf(Iterable<(String, String, bool)> fields) => {
  for (final (key, value, protected) in fields)
    if (value.isNotEmpty) key: [value, protected],
};

/// The model of a KeePassXC XML export.
Map<String, Object?> modelFromKeePassXcXml(String xml) {
  final file = XmlDocument.parse(xml).rootElement;
  final meta = file.getElement('Meta')!;
  final root = file.getElement('Root')!;
  final groupPaths = <String, String>{}; // uuid -> path
  final groups = <String>[];
  final entries = <String, Object?>{};

  Map<String, Object?> entryModel(XmlElement entry, String path) {
    final fields = _fieldsOf([
      for (final string in entry.findElements('String'))
        (
          string.getElement('Key')!.innerText,
          string.getElement('Value')!.innerText,
          string.getElement('Value')!.getAttribute('ProtectInMemory') ==
                  'True' ||
              string.getElement('Value')!.getAttribute('Protected') == 'True',
        ),
    ]);
    final binaries = [
      for (final binary in entry.findElements('Binary'))
        binary.getElement('Key')!.innerText,
    ]..sort();
    final icon = entry.getElement('CustomIconUUID')?.innerText;
    return {
      'group': path,
      'fields': fields,
      'binaries': binaries,
      'icon': icon == null || icon == _zeroUuid ? null : icon,
    };
  }

  void walk(XmlElement group, String path, {required bool isRoot}) {
    groupPaths[group.getElement('UUID')!.innerText] = path;
    if (!isRoot) groups.add(path);
    for (final child in group.childElements) {
      if (child.name.local == 'Group') {
        final name = child.getElement('Name')!.innerText;
        walk(child, path.isEmpty ? name : '$path/$name', isRoot: false);
      } else if (child.name.local == 'Entry') {
        final model = entryModel(child, path);
        model['history'] = [
          for (final old
              in child.getElement('History')?.findElements('Entry') ??
                  const <XmlElement>[])
            {
              'fields': (entryModel(old, path))['fields'],
              'binaries': (entryModel(old, path))['binaries'],
            },
        ];
        entries[child.getElement('UUID')!.innerText] = model;
      }
    }
  }

  walk(root.getElement('Group')!, '', isRoot: true);
  final bin = meta.getElement('RecycleBinUUID')?.innerText;
  return {
    'groups': groups..sort(),
    'recycleBin': bin == null ? null : groupPaths[bin],
    'entries': entries,
    'deleted': [
      for (final deleted
          in root.getElement('DeletedObjects')?.findElements('DeletedObject') ??
              const <XmlElement>[])
        deleted.getElement('UUID')!.innerText,
    ]..sort(),
    'customData': {
      for (final item
          in meta.getElement('CustomData')?.findElements('Item') ??
              const <XmlElement>[])
        if (!_isKeePassXcOwn(item.getElement('Key')!.innerText))
          item.getElement('Key')!.innerText: item
              .getElement('Value')!
              .innerText,
    },
    'customIcons': {
      for (final icon
          in meta.getElement('CustomIcons')?.findElements('Icon') ??
              const <XmlElement>[])
        icon.getElement('UUID')!.innerText: sha256
            .convert(base64.decode(icon.getElement('Data')!.innerText.trim()))
            .toString(),
    },
  };
}

const _zeroUuid = 'AAAAAAAAAAAAAAAAAAAAAA==';

/// The model of [file] as this package reads it.
Map<String, Object?> modelFromStore(KdbxFile file) {
  final groupPaths = <KdbxGroup, String>{};
  final groups = <String>[];
  final entries = <String, Object?>{};

  Map<String, Object?> entryModel(KdbxEntry entry, String path) => {
    'group': path,
    'fields': _fieldsOf([
      for (final field in entry.stringEntries)
        (
          field.key.key,
          field.value?.getText() ?? '',
          field.value is ProtectedValue,
        ),
    ]),
    'binaries': [for (final binary in entry.binaryEntries) binary.key.key]
      ..sort(),
    'icon': entry.customIconUuid?.uuid,
  };

  void walk(KdbxGroup group, String path, {required bool isRoot}) {
    groupPaths[group] = path;
    if (!isRoot) groups.add(path);
    for (final entry in group.entries) {
      entries[entry.uuid.uuid] = entryModel(entry, path)
        ..['history'] = [
          for (final old in entry.history)
            {
              'fields': entryModel(old, path)['fields'],
              'binaries': entryModel(old, path)['binaries'],
            },
        ];
    }
    for (final child in group.groups) {
      final name = child.name.get() ?? '';
      walk(child, path.isEmpty ? name : '$path/$name', isRoot: false);
    }
  }

  walk(file.body.rootGroup, '', isRoot: true);
  final bin = file.recycleBin;
  return {
    'groups': groups..sort(),
    'recycleBin': bin == null ? null : groupPaths[bin],
    'entries': entries,
    'deleted': [for (final uuid in file.deletedObjects) uuid.uuid]..sort(),
    'customData': {
      for (final item in file.body.meta.customData.entries)
        if (!_isKeePassXcOwn(item.key)) item.key: item.value,
    },
    'customIcons': {
      for (final icon in file.body.meta.customIcons.entries)
        icon.key.uuid: sha256.convert(icon.value).toString(),
    },
  };
}

/// The SHA-256 of every attachment of [file]'s entries, by entry path (group
/// path / title), as `keepassxc-cli attachment-export` names them.
Map<String, Map<String, String>> attachmentsFromStore(KdbxFile file) {
  final out = <String, Map<String, String>>{};
  void walk(KdbxGroup group, String path) {
    for (final entry in group.entries) {
      final binaries = entry.binaryEntries.toList();
      if (binaries.isEmpty || entry.label == null) continue;
      out[path.isEmpty ? entry.label! : '$path/${entry.label}'] = {
        for (final binary in binaries)
          binary.key.key: sha256.convert(binary.value.value).toString(),
      };
    }
    for (final child in group.groups) {
      final name = child.name.get() ?? '';
      walk(child, path.isEmpty ? name : '$path/$name');
    }
  }

  walk(file.body.rootGroup, '');
  return out;
}
