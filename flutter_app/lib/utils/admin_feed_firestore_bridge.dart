import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/church_functions_service.dart';

/// Serializa payloads Firestore para Cloud Functions (Admin SDK).
/// Web: evita assert Firestore quando há listeners concorrentes na mesma coleção.
abstract final class AdminFeedFirestoreBridge {
  AdminFeedFirestoreBridge._();

  static const cfDelete = '__DELETE__';

  static Map<String, dynamic> encodeMap(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final encoded = encodeValue(e.value);
      if (encoded == _skip) continue;
      out[e.key] = encoded;
    }
    return out;
  }

  static const Object _skip = Object();

  static dynamic encodeValue(dynamic value) {
    if (identical(value, FieldValue.serverTimestamp())) return _skip;
    if (identical(value, FieldValue.delete())) return cfDelete;
    if (value is Timestamp) return {'_tsMs': value.millisecondsSinceEpoch};
    if (value is Map) {
      return encodeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(encodeValue).where((v) => v != _skip).toList();
    }
    return value;
  }

  /// Grava via CF na Web; mobile mantém Firestore directo.
  static Future<void> upsertTenantDoc({
    required String churchId,
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    required bool isNewDoc,
    required Future<void> Function() directWrite,
  }) async {
    if (kIsWeb) {
      await ChurchFunctionsService.adminUpsertFeedPost(
        churchId: churchId,
        collection: collection,
        docId: docId,
        data: encodeMap(data),
        create: isNewDoc,
        merge: !isNewDoc,
      );
      return;
    }
    await directWrite();
  }

  static Future<void> deleteFeedPosts({
    required String churchId,
    required String collection,
    required List<String> docIds,
    required Future<void> Function() directDelete,
  }) async {
    if (kIsWeb && docIds.isNotEmpty) {
      await ChurchFunctionsService.adminDeleteFeedPosts(
        churchId: churchId,
        collection: collection,
        docIds: docIds,
      );
      return;
    }
    await directDelete();
  }
}
