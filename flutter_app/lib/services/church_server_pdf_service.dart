import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
/// PDF gerado no servidor (certificado / carteirinha) — evita trabalho pesado no cliente.
abstract final class ChurchServerPdfService {
  ChurchServerPdfService._();

  static final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: '');

  static Future<ChurchServerPdfResult> gerarCertificado({
    required String tenantId,
    required String memberId,
    String templateId = 'batismo',
    String? certificadoId,
  }) async {
    final res = await _fn.httpsCallable('gerarCertificadoPdf').call({
      'tenantId': tenantId.trim(),
      'memberId': memberId.trim(),
      'templateId': templateId.trim(),
      if (certificadoId != null && certificadoId.trim().isNotEmpty)
        'certificadoId': certificadoId.trim(),
    });
    return ChurchServerPdfResult.fromMap(
      Map<String, dynamic>.from(res.data as Map),
    );
  }

  static Future<ChurchServerPdfResult> gerarCarteirinha({
    required String tenantId,
    required String memberId,
  }) async {
    final res = await _fn.httpsCallable('gerarCarteirinhaPdf').call({
      'tenantId': tenantId.trim(),
      'memberId': memberId.trim(),
    });
    return ChurchServerPdfResult.fromMap(
      Map<String, dynamic>.from(res.data as Map),
    );
  }
}

class ChurchServerPdfResult {
  const ChurchServerPdfResult({
    required this.ok,
    this.storagePath = '',
    this.downloadUrl = '',
    this.qrValidationUrl = '',
    this.certificadoId = '',
    this.memberId = '',
  });

  final bool ok;
  final String storagePath;
  final String downloadUrl;
  final String qrValidationUrl;
  final String certificadoId;
  final String memberId;

  factory ChurchServerPdfResult.fromMap(Map<String, dynamic> raw) {
    return ChurchServerPdfResult(
      ok: raw['ok'] == true,
      storagePath: (raw['storagePath'] ?? '').toString(),
      downloadUrl: (raw['downloadUrl'] ?? '').toString(),
      qrValidationUrl: (raw['qrValidationUrl'] ?? '').toString(),
      certificadoId: (raw['certificadoId'] ?? '').toString(),
      memberId: (raw['memberId'] ?? '').toString(),
    );
  }
}

