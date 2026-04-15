import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Converte valores vindos do Firestore para estruturas 100% compatíveis com [jsonEncode].
///
/// Usado em exportação JSON (Configurações) e cache local — evita
/// `JsonCodec.encode` / "Converting object to an encodable object failed" com
/// [Timestamp], [GeoPoint], [DocumentReference], [Blob], [VectorValue], etc.
dynamic firestoreToJsonSafe(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is GeoPoint) {
    return <String, dynamic>{
      '_firestore_geo': true,
      'latitude': v.latitude,
      'longitude': v.longitude,
    };
  }
  if (v is DocumentReference) {
    return <String, dynamic>{
      '_firestore_ref': true,
      'path': v.path,
    };
  }
  if (v is VectorValue) {
    return <String, dynamic>{
      '_firestore_vector': true,
      'repr': v.toString(),
    };
  }
  if (v is Blob) {
    final bytes = v.bytes;
    const max = 65536;
    if (bytes.length > max) {
      return <String, dynamic>{
        '_blob_omitted': true,
        'length': bytes.length,
      };
    }
    return <String, dynamic>{
      '_firestore_blob_b64': true,
      'data': base64Encode(bytes),
    };
  }
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), firestoreToJsonSafe(val)));
  }
  if (v is Iterable && v is! String) {
    return v.map(firestoreToJsonSafe).toList();
  }
  if (v is num || v is String || v is bool) return v;
  return v.toString();
}
