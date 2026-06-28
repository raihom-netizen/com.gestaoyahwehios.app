import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/church_functions_service.dart';

/// Serializa payloads Firestore para Cloud Functions (Admin SDK).
/// Web: evita assert Firestore quando há listeners concorrentes na mesma coleção.
abstract final class AdminFeedFirestoreBridge {
  AdminFeedFirestoreBridge._();

  static const cfDelete = '__DELETE__';
  static const Duration kWebCfTimeout = Duration(seconds: 45);

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

  /// Parse `igrejas/{churchId}/col/doc` ou `…/col/doc/subCol/subDoc`.
  static ({
    String churchId,
    String collection,
    String docId,
    String? subCollection,
    String? subDocId,
  })? parseTenantDocPath(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 4 || parts[0] != 'igrejas') return null;
    final churchId = parts[1].trim();
    final collection = parts[2].trim();
    final docId = parts[3].trim();
    if (churchId.isEmpty || collection.isEmpty || docId.isEmpty) return null;
    if (parts.length >= 6) {
      return (
        churchId: churchId,
        collection: collection,
        docId: docId,
        subCollection: parts[4].trim(),
        subDocId: parts[5].trim(),
      );
    }
    return (
      churchId: churchId,
      collection: collection,
      docId: docId,
      subCollection: null,
      subDocId: null,
    );
  }

  /// Grava via CF na Web; mobile mantém Firestore directo.
  static Future<void> upsertTenantDoc({
    required String churchId,
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    required bool isNewDoc,
    required Future<void> Function() directWrite,
    String? subCollection,
    String? subDocId,
    bool useUpdate = false,
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb) {
      onProgress?.call(0.80);
      await ChurchFunctionsService.adminUpsertFeedPost(
        churchId: churchId,
        collection: collection,
        docId: docId,
        subCollection: subCollection,
        subDocId: subDocId,
        data: encodeMap(data),
        create: isNewDoc,
        merge: !isNewDoc,
        useUpdate: useUpdate,
      ).timeout(
        kWebCfTimeout,
        onTimeout: () => throw TimeoutException(
          'Gravação demorou demais (servidor). Tente novamente.',
          kWebCfTimeout,
        ),
      );
      onProgress?.call(0.86);
      return;
    }
    await directWrite();
  }

  /// Resolve path a partir de [docRef] — avisos, membros, chat/messages, etc.
  static Future<void> upsertDocRef({
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> data,
    required bool isNewDoc,
    required Future<void> Function() directWrite,
    bool useUpdate = false,
    void Function(double progress)? onProgress,
  }) async {
    final parsed = parseTenantDocPath(docRef.path);
    if (parsed == null) {
      await directWrite();
      return;
    }
    await upsertTenantDoc(
      churchId: parsed.churchId,
      collection: parsed.collection,
      docId: parsed.docId,
      subCollection: parsed.subCollection,
      subDocId: parsed.subDocId,
      data: data,
      isNewDoc: isNewDoc,
      useUpdate: useUpdate,
      onProgress: onProgress,
      directWrite: directWrite,
    );
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
