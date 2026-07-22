import 'dart:async' show TimeoutException;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/church_functions_service.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Serializa payloads Firestore para Cloud Functions (Admin SDK).
/// Web: evita assert Firestore quando há listeners concorrentes na mesma coleção.
abstract final class AdminFeedFirestoreBridge {
  AdminFeedFirestoreBridge._();

  static const cfDelete = '__DELETE__';
  static const Duration kWebCfTimeout = Duration(seconds: 18);
  static const Duration kWebDirectWriteTimeout = Duration(seconds: 22);

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

  /// SDK Web irrecuperável no processo (assert interno, cliente terminado)
  /// ou pendurado (timeout) — a CF via HTTP é independente do cliente Firestore.
  static bool _shouldFallbackToCf(Object e) {
    if (FirestoreWebGuard.isInternalAssertionError(e) ||
        FirestoreWebGuard.isClientTerminated(e)) {
      return true;
    }
    if (e is TimeoutException) return true;
    final msg = e.toString();
    return msg.contains('INTERNAL ASSERTION') ||
        msg.contains('WatchChangeAggregator') ||
        msg.contains('PersistentListenStream');
  }

  static dynamic encodeValue(dynamic value) {
    if (value is FieldValue) {
      // cloud_firestore 6.x: serverTimestamp()/delete() criam instância nova —
      // `identical` falhava e o FieldValue cru quebrava a serialização da CF
      // (ex.: CRIADO_EM no cadastro público de membro). Comparar por igualdade
      // e, em último caso, descartar o sentinel (a CF define os timestamps).
      if (value == FieldValue.delete()) return cfDelete;
      if (value == FieldValue.serverTimestamp()) return _skip;
      final s = value.toString().toLowerCase();
      if (s.contains('delete')) return cfDelete;
      return _skip;
    }
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

  /// Doc raiz `igrejas/{churchId}` — Cadastro da Igreja (Web: direct-first + CF fallback).
  static Future<void> upsertChurchRoot({
    required String churchId,
    required Map<String, dynamic> data,
    required Future<void> Function() directWrite,
    bool merge = true,
  }) async {
    if (kIsWeb) {
      try {
        await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
        await runFirestorePublishWithRecovery(
          directWrite,
          maxAttempts: 3,
          criticalWrite: true,
        ).timeout(
          kWebDirectWriteTimeout,
          onTimeout: () => throw TimeoutException(
            'Gravação do cadastro demorou demais. Verifique a rede.',
            kWebDirectWriteTimeout,
          ),
        );
        return;
      } catch (directError) {
        if (!_shouldFallbackToCf(directError)) {
          debugPrint(
            'AdminFeedFirestoreBridge: direct church root falhou: $directError',
          );
          rethrow;
        }
        debugPrint(
          'AdminFeedFirestoreBridge: assert Firestore — CF church root fallback',
        );
        await ChurchFunctionsService.adminUpsertChurchRoot(
          churchId: churchId,
          data: encodeMap(data),
          merge: merge,
        ).timeout(
          kWebCfTimeout,
          onTimeout: () => throw TimeoutException(
            'Gravação do cadastro demorou demais (servidor). Tente novamente.',
            kWebCfTimeout,
          ),
        );
        return;
      }
    }
    await directWrite();
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
      // Não reiniciar a barra em 0.80 (rewind visual + hang «A gravar… 82%»).
      onProgress?.call(0.90);
      try {
        await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
        await runFirestorePublishWithRecovery(
          directWrite,
          maxAttempts: 3,
          criticalWrite: true,
        ).timeout(
          kWebDirectWriteTimeout,
          onTimeout: () => throw TimeoutException(
            'Gravação demorou demais. Verifique a rede e tente novamente.',
            kWebDirectWriteTimeout,
          ),
        );
        onProgress?.call(0.94);
        return;
      } catch (directError) {
        if (!_shouldFallbackToCf(directError)) {
          debugPrint(
            'AdminFeedFirestoreBridge: direct falhou ($collection/$docId): $directError',
          );
          rethrow;
        }
        debugPrint(
          'AdminFeedFirestoreBridge: assert Firestore — CF fallback ($collection/$docId)',
        );
        try {
          await ChurchFunctionsService.adminUpsertFeedPost(
            churchId: churchId,
            collection: collection,
            docId: docId,
            subCollection: subCollection,
            subDocId: subDocId,
            data: encodeMap(data),
            create: isNewDoc,
            merge: FirestoreWriteGuard.effectiveSetMerge(
              merge: !isNewDoc,
              data: data,
            ),
            useUpdate: useUpdate,
          ).timeout(
            kWebCfTimeout,
            onTimeout: () => throw TimeoutException(
              'Gravação demorou demais (servidor). Tente novamente.',
              kWebCfTimeout,
            ),
          );
          onProgress?.call(0.94);
          return;
        } catch (cfError) {
          debugPrint(
            'AdminFeedFirestoreBridge: CF falhou ($collection/$docId): $cfError',
          );
          rethrow;
        }
      }
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

  /// Web: Firestore directo primeiro; CF só em INTERNAL ASSERTION.
  static Future<void> deleteFeedPosts({
    required String churchId,
    required String collection,
    required List<String> docIds,
    required Future<void> Function() directDelete,
  }) async {
    if (kIsWeb && docIds.isNotEmpty) {
      try {
        await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
        await runFirestorePublishWithRecovery(
          directDelete,
          maxAttempts: 3,
          criticalWrite: true,
        ).timeout(
          kWebDirectWriteTimeout,
          onTimeout: () => throw TimeoutException(
            'Exclusão demorou demais. Verifique a rede.',
            kWebDirectWriteTimeout,
          ),
        );
        return;
      } catch (directError) {
        if (!_shouldFallbackToCf(directError)) {
          debugPrint(
            'AdminFeedFirestoreBridge: direct delete falhou ($collection): $directError',
          );
          rethrow;
        }
        debugPrint(
          'AdminFeedFirestoreBridge: assert Firestore — CF delete fallback ($collection)',
        );
        await ChurchFunctionsService.adminDeleteFeedPosts(
          churchId: churchId,
          collection: collection,
          docIds: docIds,
        ).timeout(
          kWebCfTimeout,
          onTimeout: () => throw TimeoutException(
            'Exclusão demorou demais (servidor).',
            kWebCfTimeout,
          ),
        );
        return;
      }
    }
    await directDelete();
  }
}
