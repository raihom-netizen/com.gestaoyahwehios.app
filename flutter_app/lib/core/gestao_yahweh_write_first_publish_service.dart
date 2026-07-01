import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Fila offline de comprovante financeiro — Storage em background após lançamento gravado.
abstract final class GestaoYahwehWriteFirstPublishService {
  GestaoYahwehWriteFirstPublishService._();

  static String resolveChurchId(String hint) => ChurchRepository.churchId(hint);

  /// Financeiro — lançamento **já** gravado; comprovante só em fila Storage.
  static Future<void> queueFinanceComprovanteAfterSave({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
  }) async {
    await EcoFireResilientPublish.queueFinanceComprovante(
      churchId: churchId,
      docRef: docRef,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      referenceDate: referenceDate,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
    );
    EcoFireResilientPublish.scheduleSync(reason: 'finance_comprovante_write_first');
  }
}
