/// Test support: what another KeePass client does to a file.
///
/// A record store never files an entry under a folder of its own or empties
/// the recycle bin, but other clients do both, and a consumer's tests have to
/// reproduce that to check how its store reads the result. These are KDBX
/// operations; this entry point is how a consumer reaches them without
/// depending on the KDBX library itself. Not for shipped code.
library;

import 'src/kdbx_model.dart';

/// Another KeePass client, acting on [file].
final class TomKdbxForeignClient {
  /// The file the client acts on.
  final KdbxFile file;

  /// A client acting on [file].
  TomKdbxForeignClient(this.file);

  /// Files [entry] under a new folder [name] of the root group, as a client
  /// that sorts entries into folders does, and returns the folder.
  KdbxGroup fileUnder(KdbxEntry entry, String name) {
    final folder = file.createGroup(parent: file.body.rootGroup, name: name);
    file.move(entry, folder);
    return folder;
  }

  /// Empties [entry] out of the recycle bin: removes it and records its UUID
  /// as permanently deleted, as emptying the bin does.
  void purge(KdbxEntry entry) => file.deletePermanently(entry);
}
