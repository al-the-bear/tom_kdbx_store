/// Converting between canonical UUID strings and KDBX UUIDs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_kdbx/tom_kdbx.dart';

/// Converts a canonical `8-4-4-4-12` UUID string to a [KdbxUuid] (base64 of
/// the same 16 bytes), so a record's id can *be* its entry's UUID.
///
/// Throws [FormatException] for a string that is not 32 hex digits once the
/// dashes are removed.
KdbxUuid tomKdbxUuidFromCanonical(String uuid) {
  final hex = uuid.replaceAll('-', '');
  if (hex.length != 32) {
    throw FormatException('Not a canonical UUID: "$uuid"');
  }
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return KdbxUuid.fromBytes(bytes);
}

/// Converts a [KdbxUuid] back to the canonical lower-case UUID string.
String tomCanonicalFromKdbxUuid(KdbxUuid uuid) {
  final bytes = base64.decode(uuid.uuid);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
