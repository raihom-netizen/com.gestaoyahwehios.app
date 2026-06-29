import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Callable Functions — anexos Web-safe (Admin SDK no servidor).
abstract final class ChurchFunctionsService {
  ChurchFunctionsService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );
    final result = await callable.call(data);
    final raw = result.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{'ok': raw == true};
  }

  /// Upload comprovante via CF (Web) — base64 → Storage + Firestore merge.
  static Future<FinanceComprovanteCfResult> uploadFinanceComprovante({
    required String churchId,
    required String lancamentoId,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    String? referenceYearMonth,
  }) async {
    final res = await _call('gyUploadFinanceComprovante', {
      'churchId': churchId.trim(),
      'lancamentoId': lancamentoId.trim(),
      'base64': base64Encode(bytes),
      'mimeType': mimeType,
      if (fileName != null && fileName.trim().isNotEmpty) 'fileName': fileName.trim(),
      if (referenceYearMonth != null && referenceYearMonth.trim().isNotEmpty)
        'referenceYearMonth': referenceYearMonth.trim(),
    });
    return FinanceComprovanteCfResult(
      ok: res['ok'] == true,
      comprovanteUrl: (res['comprovanteUrl'] ?? '').toString(),
      storagePath: (res['storagePath'] ?? '').toString(),
      mimeType: (res['mimeType'] ?? mimeType).toString(),
      fileName: (res['fileName'] ?? fileName ?? 'comprovante').toString(),
    );
  }

  /// Merge doc raiz `igrejas/{churchId}` via Admin SDK (Web — Cadastro da Igreja).
  static Future<void> adminUpsertChurchRoot({
    required String churchId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    await _call('gyAdminUpsertChurchRoot', {
      'churchId': churchId.trim(),
      'data': data,
      'merge': merge,
    });
  }

  /// Upsert documento tenant via Admin SDK (Web — avisos, eventos, patrimônio, finance, chat, membros).
  static Future<String> adminUpsertFeedPost({
    required String churchId,
    required String collection,
    required String docId,
    required Map<String, dynamic> data,
    bool create = false,
    bool merge = true,
    bool useUpdate = false,
    String? subCollection,
    String? subDocId,
  }) async {
    final res = await _call('gyAdminUpsertFeedPost', {
      'churchId': churchId.trim(),
      'collection': collection.trim(),
      'docId': docId.trim(),
      'data': data,
      'create': create,
      'merge': merge,
      'useUpdate': useUpdate,
      if (subCollection != null && subCollection.trim().isNotEmpty)
        'subCollection': subCollection.trim(),
      if (subDocId != null && subDocId.trim().isNotEmpty)
        'subDocId': subDocId.trim(),
    });
    return (res['docId'] ?? subDocId ?? docId).toString();
  }

  /// Cadastro membro público via Admin SDK (Web-safe).
  static Future<String> publicMemberSignup({
    required String churchId,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final res = await _call('gyPublicMemberSignup', {
      'churchId': churchId.trim(),
      'docId': docId.trim(),
      'data': data,
    });
    return (res['docId'] ?? docId).toString();
  }

  /// Acompanhar cadastro público (visitante — sem leitura directa de `membros`).
  static Future<PublicSignupStatusCfResult> publicSignupStatus({
    String? slug,
    String? churchId,
    required String protocolo,
  }) async {
    final res = await _call('gyPublicSignupStatus', {
      'protocolo': protocolo.trim(),
      if (slug != null && slug.trim().isNotEmpty) 'slug': slug.trim(),
      if (churchId != null && churchId.trim().isNotEmpty)
        'churchId': churchId.trim(),
    });
    return PublicSignupStatusCfResult.fromMap(res);
  }

  /// Exclusão em lote avisos/eventos (admin Web).
  static Future<int> adminDeleteFeedPosts({
    required String churchId,
    required String collection,
    required List<String> docIds,
  }) async {
    if (docIds.isEmpty) return 0;
    final res = await _call('gyAdminDeleteFeedPosts', {
      'churchId': churchId.trim(),
      'collection': collection.trim(),
      'docIds': docIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    });
    return (res['deleted'] as num?)?.toInt() ?? docIds.length;
  }
}

class PublicSignupStatusCfResult {
  const PublicSignupStatusCfResult({
    required this.ok,
    required this.found,
    required this.churchName,
    this.churchId,
    this.protocolo,
    this.nome,
    this.status,
    this.error,
  });

  final bool ok;
  final bool found;
  final String churchName;
  final String? churchId;
  final String? protocolo;
  final String? nome;
  final String? status;
  final String? error;

  factory PublicSignupStatusCfResult.fromMap(Map<String, dynamic> m) {
    return PublicSignupStatusCfResult(
      ok: m['ok'] == true,
      found: m['found'] == true,
      churchName: (m['churchName'] ?? 'Igreja').toString(),
      churchId: (m['churchId'] ?? '').toString().trim().isEmpty
          ? null
          : (m['churchId'] ?? '').toString().trim(),
      protocolo: (m['protocolo'] ?? '').toString().trim().isEmpty
          ? null
          : (m['protocolo'] ?? '').toString().trim(),
      nome: (m['nome'] ?? '').toString().trim().isEmpty
          ? null
          : (m['nome'] ?? '').toString().trim(),
      status: (m['status'] ?? '').toString().trim().isEmpty
          ? null
          : (m['status'] ?? '').toString().trim(),
      error: (m['error'] ?? '').toString().trim().isEmpty
          ? null
          : (m['error'] ?? '').toString().trim(),
    );
  }
}

class FinanceComprovanteCfResult {
  const FinanceComprovanteCfResult({
    required this.ok,
    required this.comprovanteUrl,
    required this.storagePath,
    required this.mimeType,
    required this.fileName,
  });

  final bool ok;
  final String comprovanteUrl;
  final String storagePath;
  final String mimeType;
  final String fileName;
}
