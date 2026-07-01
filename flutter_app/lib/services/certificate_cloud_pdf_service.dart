import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:http/http.dart' as http;

/// PDF de certificado no servidor — `gerarCertificadoPdf` / `processarCertificadosLote`.
///
/// Evita pipeline local pesado (logo/assinaturas na Web) quando a CF está disponível.
abstract final class CertificateCloudPdfService {
  CertificateCloudPdfService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  /// Um membro — bytes do PDF já no Storage (URL assinada).
  static Future<Uint8List?> generateSingleMemberPdf({
    required String tenantId,
    required String memberId,
    required String templateId,
    String? certificadoId,
  }) async {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    final mid = memberId.trim();
    if (churchId.isEmpty || mid.isEmpty) return null;
    try {
      final callable = _functions.httpsCallable(
        'gerarCertificadoPdf',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );
      final res = await callable.call<Map<dynamic, dynamic>>({
        'tenantId': churchId,
        'memberId': mid,
        'templateId': templateId.trim().isEmpty ? 'membro' : templateId.trim(),
        if (certificadoId != null && certificadoId.trim().isNotEmpty)
          'certificadoId': certificadoId.trim(),
      });
      return _downloadPdfBytes((res.data['downloadUrl'] ?? '').toString());
    } catch (e, st) {
      debugPrint('CertificateCloudPdfService.generateSingle: $e\n$st');
      return null;
    }
  }

  /// Lote na nuvem — link ZIP/PDF único (até 200 no servidor).
  static Future<String?> startBatchZipUrl({
    required String tenantId,
    required List<String> memberIds,
    required String templateId,
  }) async {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty || memberIds.isEmpty) return null;
    try {
      final callable = _functions.httpsCallable(
        'processarCertificadosLote',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final res = await callable.call<Map<dynamic, dynamic>>({
        'igrejaId': churchId,
        'tenantId': churchId,
        'listaMembrosId': memberIds,
        'idAssinatura': templateId,
        'templateId': templateId,
      });
      final url = (res.data['downloadUrl'] ?? '').toString().trim();
      return url.isEmpty ? null : url;
    } catch (e, st) {
      debugPrint('CertificateCloudPdfService.startBatch: $e\n$st');
      return null;
    }
  }

  static Future<Uint8List?> _downloadPdfBytes(String url) async {
    final u = url.trim();
    if (u.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse(u))
          .timeout(const Duration(seconds: 45));
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (e, st) {
      debugPrint('CertificateCloudPdfService.download: $e\n$st');
    }
    return null;
  }
}
