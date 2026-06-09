import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';

/// Verificações dos módulos restantes — mesmo padrão Avisos/Eventos.
abstract final class FinanceiroPublishVerificationService {
  FinanceiroPublishVerificationService._();

  static const kFailed = 'Falha ao salvar lançamento financeiro.';
  static const kStorageFailed = 'Comprovante não confirmado no Storage.';
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'financeiro');

  static DocumentReference<Map<String, dynamic>> financeDocRef({
    required String igrejaId,
    required String docId,
  }) =>
      ChurchOperationalPaths.churchDoc(igrejaId.trim())
          .collection('finance')
          .doc(docId.trim());

  static String comprovantePath({
    required String igrejaId,
    required String lancamentoId,
  }) =>
      ChurchStorageLayout.financeComprovantePath(
        tenantId: igrejaId,
        lancamentoId: lancamentoId,
      );

  static Future<void> verifyStorage(String path) async {
    try {
      await ChurchStorageMetadataVerify.assertExists(path);
    } catch (e) {
      _lastError = kStorageFailed;
      rethrow;
    }
  }

  static Future<void> verifyDoc(DocumentReference<Map<String, dynamic>> ref) async {
    final s = await ref.get(const GetOptions(source: Source.serverAndCache));
    if (!s.exists) {
      _lastError = kFailed;
      throw StateError(kFailed);
    }
  }

  static void clearError() => _lastError = null;
}

abstract final class CertificadosPublishVerificationService {
  CertificadosPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'certificados');

  static String storagePrefix(String igrejaId) =>
      '${ChurchStorageLayout.churchRoot(igrejaId)}/certificados/';

  static void clearError() => _lastError = null;
}

abstract final class CarteirinhaPublishVerificationService {
  CarteirinhaPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'carteirinha');

  static String storagePrefix(String igrejaId) =>
      '${ChurchStorageLayout.churchRoot(igrejaId)}/${ChurchStorageLayout.kSegCartaoMembro}/';

  static void clearError() => _lastError = null;
}

abstract final class OracaoPublishVerificationService {
  OracaoPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'oracao');

  static String collectionPath(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/pedidosOracao';

  static void clearError() => _lastError = null;
}

abstract final class TransferenciaPublishVerificationService {
  TransferenciaPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'transferencia');

  static String collectionPath(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/cartas_historico';

  static void clearError() => _lastError = null;
}

abstract final class FornecedorPublishVerificationService {
  FornecedorPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'fornecedor');

  static String collectionPath(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/fornecedores';

  static void clearError() => _lastError = null;
}

abstract final class AprovacoesPublishVerificationService {
  AprovacoesPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'aprovacoes');

  static void clearError() => _lastError = null;
}

abstract final class DashboardPublishVerificationService {
  DashboardPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'dashboard');

  static void clearError() => _lastError = null;
}

abstract final class SitePublicoPublishVerificationService {
  SitePublicoPublishVerificationService._();
  static String? _lastError;
  static String? get lastError => _lastError;

  static Future<String> resolveTenant({
    required String seed,
    String? userUid,
  }) =>
      _resolve(seed, userUid, 'site_publico');

  static void clearError() => _lastError = null;
}

Future<String> _resolve(String seed, String? userUid, String module) async {
  final resolved = ChurchPublishContext.churchIdForPublish(seed);
  debugPrint('CHURCH_ID ($module): $resolved');
  return resolved;
}
