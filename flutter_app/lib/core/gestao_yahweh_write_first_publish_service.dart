import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Alias fino → [EcoFireResilientPublish.queueFinanceComprovante].
/// Preferir a API EcoFire / [YahwehCentralEngineService.queueFinanceComprovante] directamente.
abstract final class GestaoYahwehWriteFirstPublishService {
  GestaoYahwehWriteFirstPublishService._();

  static String resolveChurchId(String hint) => ChurchRepository.churchId(hint);

  static Future<void> queueFinanceComprovanteAfterSave({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    bool alreadyCompressed = true,
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
      alreadyCompressed: alreadyCompressed,
    );
    EcoFireResilientPublish.scheduleSync(reason: 'finance_comprovante_write_first');
  }
}
