/// The KDBX types of this package's API, implemented over `tom_kpasslib`.
///
/// They carry the names and the behaviour a consumer of this package has
/// always used — a file with a root group and meta custom data, entries with
/// string fields, binaries, history and times, credentials, a format that
/// creates and reads files — so a consumer names only this package, and a
/// change of the KDBX library underneath is invisible above it.
///
/// What the behaviour is, where a KDBX library leaves a choice:
///
/// - **History.** An entry's first change after it was read or saved pushes
///   one snapshot of its previous state to [KdbxEntry.history]; a new entry
///   pushes none, and further changes before the next save push none. A
///   change to the same value is no change. [KdbxEntry.modify] groups several
///   changes into one.
/// - **Times.** Every change sets the entry's last-modification time to now;
///   setting a time through [KdbxEntry.times] is not a change.
/// - **Deletion.** [KdbxFile.deleteEntry] moves an entry into the recycle bin,
///   created on first use; [KdbxFile.deletePermanently] removes it and records
///   its UUID as deleted, which [KdbxFile.clearDeletion] forgets.
/// - **New entries** carry no fields until one is set.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:tom_kpasslib/tom_kpasslib.dart' as kp;
import 'package:xml/xml.dart';

// ── Identity ────────────────────────────────────────────────────────────────

/// The UUID of a KDBX entry or group: 16 bytes, written as base64.
final class KdbxUuid {
  /// The base64 form of the 16 bytes.
  final String uuid;

  /// The UUID whose base64 form is [uuid].
  const KdbxUuid(this.uuid);

  /// The UUID of these 16 [bytes].
  KdbxUuid.fromBytes(Uint8List bytes) : uuid = base64.encode(bytes);

  /// A random UUID.
  factory KdbxUuid.random() => KdbxUuid(kp.KdbxUuid.random().string);

  /// The 16 bytes.
  Uint8List toBytes() => base64.decode(uuid);

  kp.KdbxUuid get _native => kp.KdbxUuid.fromString(uuid);

  @override
  bool operator ==(Object other) => other is KdbxUuid && other.uuid == uuid;

  @override
  int get hashCode => uuid.hashCode;

  @override
  String toString() => uuid;
}

/// The name of an entry's string field or binary.
final class KdbxKey {
  /// The name.
  final String key;

  /// The field or binary named [key].
  const KdbxKey(this.key);

  @override
  bool operator ==(Object other) => other is KdbxKey && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'KdbxKey{$key}';
}

/// The string fields every KeePass client knows.
abstract final class KdbxKeyCommon {
  // The KeePass field names, under the constant names consumers already use.
  // ignore_for_file: constant_identifier_names

  /// `Title`.
  static const TITLE = KdbxKey('Title');

  /// `URL`.
  static const URL = KdbxKey('URL');

  /// `UserName`.
  static const USER_NAME = KdbxKey('UserName');

  /// `Password`.
  static const PASSWORD = KdbxKey('Password');

  /// `Notes`.
  static const NOTES = KdbxKey('Notes');

  /// `otp`, the one-time-password field KeePass clients share.
  static const OTP = KdbxKey('otp');
}

// ── Values ──────────────────────────────────────────────────────────────────

/// The value of a string field: [PlainValue] or [ProtectedValue].
abstract interface class StringValue {
  /// The text.
  String? getText();
}

/// A string field stored as plain text.
final class PlainValue implements StringValue {
  /// The text.
  final String? text;

  /// A plain value holding [text].
  PlainValue(this.text);

  @override
  String? getText() => text;

  @override
  bool operator ==(Object other) => other is PlainValue && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'PlainValue{$text}';
}

/// A string field kept protected: encrypted in the file, and masked in memory.
final class ProtectedValue implements StringValue {
  final kp.ProtectedData _data;

  ProtectedValue._(this._data);

  /// A protected value holding [text].
  factory ProtectedValue.fromString(String text) =>
      ProtectedValue._(kp.ProtectedData.fromString(text));

  /// A protected value holding these UTF-8 [bytes].
  factory ProtectedValue.fromBinary(Uint8List bytes) =>
      ProtectedValue._(kp.ProtectedData.fromBytes(bytes));

  @override
  String getText() => _data.text;

  /// The value's bytes.
  Uint8List get binaryValue => Uint8List.fromList(_data.bytes);

  @override
  bool operator ==(Object other) =>
      other is ProtectedValue && other.getText() == getText();

  @override
  int get hashCode => getText().hashCode;

  @override
  String toString() => 'ProtectedValue{***}';
}

/// The key a file is opened with: a password, a key file, or both.
final class Credentials {
  final ProtectedValue? _password;
  final Uint8List? _keyFile;

  /// Credentials of a [password] alone.
  Credentials(ProtectedValue password) : this.composite(password, null);

  /// Credentials of a [password] and the bytes of a [keyFile] (KeePass key
  /// file formats 1.0 and 2.0, 32 raw or 64 hex bytes, or any other file's
  /// SHA-256), either of them optional.
  Credentials.composite(ProtectedValue? password, Uint8List? keyFile)
    : _password = password,
      _keyFile = keyFile;

  kp.KdbxCredentials get _native => kp.KdbxCredentials(
    password: _password?._data,
    keyData: _keyFile == null ? null : keyFileKey(_keyFile),
  );

  /// The 32 bytes a key file contributes to the composite key, read the way
  /// files this package wrote have always been keyed: a string beginning with
  /// 64 hex digits is hex; an XML `<KeyFile>` with one `<Key><Data>` is hex
  /// for version 2.x and base64 otherwise; anything else — including XML that
  /// is no key file, and 32 raw bytes — is the SHA-256 of the whole file.
  ///
  /// KeePass reads XML key files (1.0 and 2.0), 64 hex digits and any other
  /// file the same way; it takes a file of exactly 32 raw bytes as the key
  /// itself, where this package hashes it.
  static Uint8List keyFileKey(Uint8List contents) {
    try {
      final text = utf8.decode(contents);
      if (RegExp(r'^[a-f\d]{64}', caseSensitive: false).hasMatch(text)) {
        return _hexDecode(text);
      }
      final document = XmlDocument.parse(text);
      final versions = document.findAllElements('Version');
      final version = versions.length == 1 ? versions.single.innerText : null;
      final data = document.findAllElements('Key').single.findElements('Data');
      final encoded = data.single.innerText.replaceAll(RegExp(r'\s'), '');
      return version != null && version.startsWith('2.')
          ? _hexDecode(encoded)
          : base64.decode(encoded);
    } catch (_) {
      return Uint8List.fromList(sha256.convert(contents).bytes);
    }
  }

  static Uint8List _hexDecode(String hex) {
    if (hex.length.isOdd) throw const FormatException('odd hex length');
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  /// The composite key these credentials make, as a hash: equal for two
  /// credentials that open the same files.
  Uint8List getHash() => Uint8List.fromList(_native.getHash());
}

/// A file's bytes do not open with the credentials given.
final class KdbxInvalidKeyException implements Exception {
  /// What the library reported.
  final String message;

  /// A refusal reporting [message].
  KdbxInvalidKeyException([this.message = 'invalid credentials']);

  @override
  String toString() => 'KdbxInvalidKeyException: $message';
}

// ── Format and file ─────────────────────────────────────────────────────────

/// Creates and reads KDBX files: KDBX 4.1 with Argon2d and AES-256 for a new
/// file; every KDBX 3 and 4 file KeePass and KeePassXC write for a read.
class KdbxFormat {
  /// The format.
  KdbxFormat();

  /// A new, empty file named [name], opened with [credentials].
  KdbxFile create(Credentials credentials, String name) {
    final db = kp.KdbxDatabase.create(
      credentials: credentials._native,
      name: name,
    );
    // A new file has no recycle bin until something is deleted.
    final bin = db.meta.recycleBinUuid;
    db.root.groups.removeWhere((group) => group.uuid == bin);
    db.meta.recycleBinUuid = null;
    return KdbxFile._(db, credentials);
  }

  /// The file [input] holds, opened with [credentials].
  ///
  /// Throws [KdbxInvalidKeyException] when the credentials do not open it.
  Future<KdbxFile> read(Uint8List input, Credentials credentials) async {
    try {
      final db = await kp.KdbxDatabase.fromBytes(
        data: input,
        credentials: credentials._native,
      );
      return KdbxFile._(db, credentials);
    } on kp.InvalidCredentialsError catch (e) {
      throw KdbxInvalidKeyException('$e');
    }
  }
}

/// An open KDBX file.
class KdbxFile {
  final kp.KdbxDatabase _db;

  /// The wrapper of each native entry and group, so one entry is always one
  /// object.
  final _entries = Expando<KdbxEntry>();
  final _groups = Expando<KdbxGroup>();

  /// Entries changed since the file was read or last saved.
  final _dirty = HashSet<kp.KdbxEntry>.identity();

  KdbxFile._(this._db, this._credentials);

  Credentials _credentials;

  /// The credentials the file is opened with.
  Credentials get credentials => _credentials;

  /// Re-keys the file: the next [save] encrypts it with [credentials].
  set credentials(Credentials credentials) {
    _credentials = credentials;
    _db.header.credentials = credentials._native;
  }

  /// The recycle bin, or null while the file has none.
  KdbxGroup? get recycleBin {
    final id = _db.meta.recycleBinUuid;
    final bin = id == null ? null : _db.getGroup(uuid: id);
    return bin == null ? null : _group(bin);
  }

  /// The file's content: its root group and meta data.
  late final KdbxBody body = KdbxBody._(this);

  /// The file's bytes as they are now. Every entry counts as unchanged
  /// afterwards, so its next change pushes a history snapshot.
  Future<Uint8List> save() async {
    final bytes = await _db.save();
    _dirty.clear();
    return Uint8List.fromList(bytes);
  }

  /// A new group [name] under [parent].
  KdbxGroup createGroup({required KdbxGroup parent, required String name}) =>
      _group(_db.createGroup(parent: parent._native, name: name));

  /// Moves [entry] into the group [toGroup].
  void move(KdbxEntry entry, KdbxGroup toGroup) =>
      _db.move(item: entry._native, target: toGroup._native);

  /// Moves [entry] into the recycle bin, creating the bin when the file has
  /// none.
  void deleteEntry(KdbxEntry entry) {
    final bin = _db.recycleBin ?? _enableRecycleBin();
    _db.move(item: entry._native, target: bin);
  }

  kp.KdbxGroup _enableRecycleBin() {
    _db.meta.recycleBinEnabled = true;
    return _db.recycleBin!;
  }

  /// Removes [entry] from the file and records its UUID as deleted, as
  /// emptying the recycle bin does.
  ///
  /// Throws [StateError] for an entry in no group.
  void deletePermanently(KdbxEntry entry) {
    if (entry._native.parent == null) {
      throw StateError(
        'Unable to delete object. Object has no parent, already deleted?',
      );
    }
    _db.move(item: entry._native, target: null);
  }

  /// Whether the file records [uuid] as permanently deleted.
  bool isDeleted(KdbxUuid uuid) => _db.deletedObjects.containsKey(uuid._native);

  /// The UUIDs the file records as permanently deleted.
  Iterable<KdbxUuid> get deletedObjects =>
      _db.deletedObjects.keys.map((uuid) => KdbxUuid(uuid.string));

  /// Forgets that [uuid] was permanently deleted, and says whether the file
  /// had recorded it. Changes nothing else.
  bool clearDeletion(KdbxUuid uuid) =>
      _db.deletedObjects.remove(uuid._native) != null;

  KdbxEntry _entry(kp.KdbxEntry native, {bool isHistoryEntry = false}) =>
      _entries[native] ??= KdbxEntry._(this, native, isHistoryEntry);

  KdbxGroup _group(kp.KdbxGroup native) =>
      _groups[native] ??= KdbxGroup._(this, native);
}

/// A file's content.
final class KdbxBody {
  final KdbxFile _file;

  KdbxBody._(this._file);

  /// The root group.
  KdbxGroup get rootGroup => _file._group(_file._db.root);

  /// The file's meta data.
  late final KdbxMeta meta = KdbxMeta._(_file);
}

/// A file's meta data.
final class KdbxMeta {
  final KdbxFile _file;

  KdbxMeta._(this._file);

  /// The database name.
  late final KdbxNode<String> databaseName = KdbxNode._(
    () => _file._db.meta.name,
    (value) => _file._db.meta.name = value ?? '',
  );

  /// The file's custom icons: their image bytes by UUID.
  Map<KdbxUuid, Uint8List> get customIcons => {
    for (final icon in _file._db.meta.customIcons.entries)
      KdbxUuid(icon.key.string): Uint8List.fromList(icon.value.data),
  };

  /// The file's custom data: string values by key, belonging to the file.
  late final KdbxCustomData customData = KdbxCustomData._(
    () => _file._db.meta.customData,
  );
}

/// Custom data: string values by key.
final class KdbxCustomData {
  final kp.KdbxCustomData Function() _native;

  KdbxCustomData._(this._native);

  Map<String, kp.KdbxCustomItem> get _map => _native().map;

  /// The value of [key], or null.
  String? operator [](String key) => _map[key]?.value;

  /// Sets [key] to [value].
  void operator []=(String key, String value) => _map[key] = kp.KdbxCustomItem(
    value: value,
    modification: kp.KdbxTime.now(),
  );

  /// Removes [key], answering its value.
  String? remove(String key) => _map.remove(key)?.value;

  /// Whether [key] has a value.
  bool containsKey(String key) => _map.containsKey(key);

  /// The keys.
  Iterable<String> get keys => _map.keys;

  /// The values by key.
  Iterable<MapEntry<String, String>> get entries =>
      _map.entries.map((e) => MapEntry(e.key, e.value.value));

  /// Whether there is no value.
  bool get isEmpty => _map.isEmpty;
}

// ── Groups ──────────────────────────────────────────────────────────────────

/// A group of entries and groups.
class KdbxGroup {
  /// The file the group is in.
  final KdbxFile file;
  final kp.KdbxGroup _native;

  KdbxGroup._(this.file, this._native);

  /// The group's UUID.
  KdbxUuid get uuid => KdbxUuid(_native.uuid.string);

  /// The group's name.
  late final KdbxNode<String> name = KdbxNode._(
    () => _native.name,
    (value) => _native.name = value ?? '',
  );

  /// The group holding this one, or null for the root group.
  KdbxGroup? get parent {
    final parent = _native.parent;
    return parent == null ? null : file._group(parent);
  }

  /// The entries directly in this group, in file order.
  List<KdbxEntry> get entries =>
      List.unmodifiable(_native.entries.map(file._entry));

  /// The groups directly in this group, in file order.
  List<KdbxGroup> get groups =>
      List.unmodifiable(_native.groups.map(file._group));

  /// Adds [entry] to this group, if it is not in it yet.
  void addEntry(KdbxEntry entry) {
    final native = entry._native;
    if (_native.entries.contains(native)) return;
    native.parent = _native;
    _native.entries.add(native);
  }

  /// Every entry in this group and in every group below it, the recycle bin
  /// included.
  Iterable<KdbxEntry> getAllEntries() => _native.allEntries.map(file._entry);

  /// Every group below this one.
  Iterable<KdbxGroup> getAllGroups() => _native.allGroups.map(file._group);
}

// ── Entries ─────────────────────────────────────────────────────────────────

/// A binary attached to an entry.
final class KdbxBinary {
  /// The bytes.
  final Uint8List value;

  /// Whether the file stores the bytes protected.
  final bool isProtected;

  KdbxBinary._(this.value, this.isProtected);
}

/// An entry: string fields, binaries, history and times.
class KdbxEntry {
  /// The file the entry is in.
  final KdbxFile file;

  /// Whether the entry is a version in another entry's history.
  final bool isHistoryEntry;

  final kp.KdbxEntry _native;
  bool _inModify = false;

  KdbxEntry._(this.file, this._native, this.isHistoryEntry);

  /// A new entry of [parent], with no fields. It is not in the group until
  /// [KdbxGroup.addEntry] adds it; a history entry ([isHistoryEntry]) never
  /// is, and goes into another entry's [history] instead.
  factory KdbxEntry.create(
    KdbxFile file,
    KdbxGroup parent, {
    bool isHistoryEntry = false,
  }) {
    final db = file._db;
    final native = kp.KdbxEntry.create(
      parent: parent._native,
      meta: db.meta,
      id: kp.KdbxUuid.random(
        prohibited: db.root.allItems.map((item) => item.uuid).toSet(),
      ),
    )..fields.clear();
    final entry = KdbxEntry._(file, native, isHistoryEntry);
    file._entries[native] = entry;
    file._dirty.add(native);
    return entry;
  }

  /// The entry's UUID.
  KdbxUuid get uuid => KdbxUuid(_native.uuid.string);

  /// Gives the entry [uuid] — for an entry whose UUID is an id the caller
  /// owns.
  void assignUuid(KdbxUuid uuid) => _native.uuid = uuid._native;

  /// The group holding the entry, or null.
  KdbxGroup? get parent {
    final parent = _native.parent;
    return parent == null ? null : file._group(parent);
  }

  /// The entry's earlier versions, oldest first.
  late final List<KdbxEntry> history = _HistoryList(this);

  /// The UUID of the entry's custom icon (see [KdbxMeta.customIcons]), or
  /// null.
  KdbxUuid? get customIconUuid {
    final icon = _native.customIcon;
    return icon == null ? null : KdbxUuid(icon.string);
  }

  /// The entry's Title.
  String? get label => getString(KdbxKeyCommon.TITLE)?.getText();

  /// Sets the entry's Title.
  set label(String? label) => setString(KdbxKeyCommon.TITLE, PlainValue(label));

  /// The entry's times.
  late final KdbxTimes times = KdbxTimes._(_native);

  /// The entry's tags, as one string separated by `;`.
  late final KdbxNode<String> tags = KdbxNode._(
    () {
      final tags = _native.tags;
      return tags == null || tags.isEmpty ? null : tags.join(';');
    },
    (value) => modify(() {
      final tags = (value ?? '')
          .split(';')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      _native.tags = tags.isEmpty ? null : tags;
    }),
  );

  /// The value of the string field [key], or null.
  StringValue? getString(KdbxKey key) => switch (_native.fields[key.key]) {
    final kp.ProtectedTextField field => ProtectedValue._(field.protectedText),
    final kp.KdbxTextField field => PlainValue(field.text),
    null => null,
  };

  /// Sets the string field [key] to [value]; null removes it. Setting the
  /// value it already has is no change.
  void setString(KdbxKey key, StringValue? value) {
    if (getString(key) == value) return;
    modify(() {
      switch (value) {
        case null:
          _native.fields.remove(key.key);
        case final ProtectedValue protected:
          _native.fields[key.key] = kp.ProtectedTextField(protected._data);
        case _:
          _native.fields[key.key] = kp.KdbxTextField.fromText(
            text: value.getText() ?? '',
          );
      }
    });
  }

  /// Removes the string field [key].
  void removeString(KdbxKey key) => setString(key, null);

  /// The string fields, by key.
  Iterable<MapEntry<KdbxKey, StringValue?>> get stringEntries =>
      _native.fields.keys.map((name) {
        final key = KdbxKey(name);
        return MapEntry(key, getString(key));
      });

  /// The binary [key], or null.
  KdbxBinary? getBinary(KdbxKey key) {
    final reference = _native.binaries[key.key];
    return reference == null ? null : _resolve(reference);
  }

  /// The binaries, by key.
  Iterable<MapEntry<KdbxKey, KdbxBinary>> get binaryEntries => [
    for (final binary in _native.binaries.entries)
      if (_resolve(binary.value) case final resolved?)
        MapEntry(KdbxKey(binary.key), resolved),
  ];

  KdbxBinary? _resolve(kp.BinaryReference reference) =>
      switch (file._db.binaries.getByRef(reference)) {
        final kp.PlainBinary binary => KdbxBinary._(
          Uint8List.fromList(binary.data),
          false,
        ),
        final kp.ProtectedBinary binary => KdbxBinary._(
          Uint8List.fromList(binary.protectedData.bytes),
          true,
        ),
        _ => null,
      };

  /// Attaches [bytes] as a binary under the file name of [name] — made unique
  /// among the entry's binaries by a number before the extension when taken.
  KdbxBinary createBinary({
    required bool isProtected,
    required String name,
    required Uint8List bytes,
  }) {
    final key = _uniqueBinaryName(name.split(RegExp(r'[/\\]')).last);
    modify(() {
      _native.binaries[key] = file._db.binaries.add(
        isProtected
            ? kp.ProtectedBinary(
                protectedData: kp.ProtectedData.fromBytes(bytes),
              )
            : kp.PlainBinary(data: bytes, compressed: false),
      );
    });
    return KdbxBinary._(Uint8List.fromList(bytes), isProtected);
  }

  String _uniqueBinaryName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > -1 ? fileName.substring(0, dot) : fileName;
    final extension = dot > -1 ? fileName.substring(dot + 1) : 'ext';
    for (var i = 0; i < 1000; i++) {
      final name = i == 0 ? fileName : '$base$i.$extension';
      if (!_native.binaries.containsKey(name)) return name;
    }
    throw StateError('Unable to find unique name for $fileName');
  }

  /// Removes the binary [key].
  void removeBinary(KdbxKey key) {
    if (!_native.binaries.containsKey(key.key)) return;
    modify(() => _native.binaries.remove(key.key));
  }

  /// Runs [change] as one change of the entry: the first change since the
  /// file was read or saved pushes the entry's previous state to [history]
  /// first; every change sets the last-modification time to now.
  T modify<T>(T Function() change) {
    final dirty = file._dirty.contains(_native);
    if (dirty || _inModify) {
      try {
        return change();
      } finally {
        _native.times.modification = kp.KdbxTime.now();
      }
    }
    _inModify = true;
    if (!isHistoryEntry) _native.pushHistory();
    try {
      return change();
    } finally {
      _inModify = false;
      file._dirty.add(_native);
      _native.times.modification = kp.KdbxTime.now();
    }
  }
}

/// An entry's history as a list of entries, backed by the file's own list.
final class _HistoryList extends ListBase<KdbxEntry> {
  final KdbxEntry _owner;

  _HistoryList(this._owner);

  List<kp.KdbxEntry> get _list => _owner._native.history;

  @override
  int get length => _list.length;

  @override
  set length(int newLength) => _list.length = newLength;

  @override
  KdbxEntry operator [](int index) =>
      _owner.file._entry(_list[index], isHistoryEntry: true);

  @override
  void operator []=(int index, KdbxEntry value) => _list[index] = value._native;

  @override
  void add(KdbxEntry element) => _list.add(element._native);

  @override
  void addAll(Iterable<KdbxEntry> iterable) =>
      _list.addAll(iterable.map((entry) => entry._native));

  @override
  void clear() => _list.clear();
}

/// A value of an entry or group, read with [get] and written with [set].
final class KdbxNode<T> {
  final T? Function() _get;
  final void Function(T? value) _set;

  KdbxNode._(this._get, this._set);

  /// The value, or null.
  T? get() => _get();

  /// Sets the value.
  void set(T? value) => _set(value);
}

/// An entry's times, in UTC. Setting one is not a change of the entry.
final class KdbxTimes {
  final kp.KdbxItem _native;

  KdbxTimes._(this._native);

  KdbxNode<DateTime> _node(
    kp.KdbxTime Function(kp.KdbxTimes times) read,
    void Function(kp.KdbxTimes times, kp.KdbxTime value) write,
  ) => KdbxNode._(
    () => read(_native.times).time?.toUtc(),
    (value) => write(_native.times, kp.KdbxTime(value?.toUtc())),
  );

  /// When the entry was created.
  late final KdbxNode<DateTime> creationTime = _node(
    (times) => times.creation,
    (times, value) => times.creation = value,
  );

  /// When the entry last changed.
  late final KdbxNode<DateTime> lastModificationTime = _node(
    (times) => times.modification,
    (times, value) => times.modification = value,
  );

  /// When the entry was last read.
  late final KdbxNode<DateTime> lastAccessTime = _node(
    (times) => times.access,
    (times, value) => times.access = value,
  );

  /// When the entry expires.
  late final KdbxNode<DateTime> expiryTime = _node(
    (times) => times.expiry,
    (times, value) => times.expiry = value,
  );

  /// When the entry last moved to another group.
  late final KdbxNode<DateTime> locationChanged = _node(
    (times) => times.locationChange,
    (times, value) => times.locationChange = value,
  );
}
