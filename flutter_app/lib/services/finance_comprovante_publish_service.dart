import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';

/// Financeiro — lançamento gravado primeiro; comprovante em background.
abstract final class FinanceComprovantePublishService {
  FinanceComprovantePublishService._();

  static const String comprovanteUploadStateField = 'comprovanteUploadState';

  /// Grava lançamento **sem** esperar comprovante (UI pode fechar).
  static Future<DocumentReference<Map<String, dynamic>>> saveLancamentoFirst({
    required CollectionReference<Map<String, dynamic>> financeCol,
    required Map<String, dynamic> payload,
    required bool isEdit,
    DocumentReference<Map<String, dynamic>>? existingRef,
    bool hasNewComprovante = false,
  }) async {
    YahwehFlowLog.start('FINANCEIRO');
    final patch = Map<String, dynamic>.from(payload);
    if (hasNewComprovante) {
      patch[comprovanteUploadStateField] = EntityPublishStatus.uploading;
      patch.remove('comprovanteUrl');
    }
    if (isEdit && existingRef != null) {
      await existingRef.update(patch);
      YahwehFlowLog.success('FINANCEIRO');
      return existingRef;
    }
    final ref = await financeCol.add(patch);
    YahwehFlowLog.success('FINANCEIRO');
    return ref;
  }

  static void scheduleComprovanteUpload({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    void Function(String url)? onSuccess,
    void Function(Object error)? onError,
  }) {
    unawaited(
      runFirebaseBackgroundTask<void>(
        () => _uploadComprovante(
          tenantId: tenantId,
          docRef: docRef,
          rawBytes: rawBytes,
          onSuccess: onSuccess,
        ),
        debugLabel: 'finance_comprovante_bg',
      ).catchError((Object e, StackTrace st) {
        YahwehFlowLog.error('FINANCEIRO', e, st);
        unawaited(_markError(docRef, e));
        onError?.call(e);
      }),
    );
  }

  static Future<void> _uploadComprovante({
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List rawBytes,
    void Function(String url)? onSuccess,
  }) async {
    YahwehFlowLog.uploadStart('comprovante');
    final compressed = await ImageHelper.compressImage(
      rawBytes,
      minWidth: 800,
      minHeight: 600,
      quality: 80,
    );
    final path = 'igrejas/$tenantId/comprovantes/${docRef.id}.jpg';
    final url = await UnifiedUploadService.uploadJpegBytes(
      storagePath: path,
      bytes: compressed,
    );
    await docRef.set(
      {
        'comprovanteUrl': url,
        comprovanteUploadStateField: EntityPublishStatus.published,
        'comprovanteUploadError': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    YahwehFlowLog.uploadSuccess('comprovante');
    onSuccess?.call(url);
  }

  static Future<void> _markError(
    DocumentReference<Map<String, dynamic>> docRef,
    Object error,
  ) async {
    try {
      await docRef.set(
        {
          comprovanteUploadStateField: EntityPublishStatus.error,
          'comprovanteUploadError': error.toString(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
