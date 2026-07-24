import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatUploadErrorForUser, kFeedPublishQueuedUserMessage;
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/fornecedor_compromisso_publish_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';

/// Fluxo único de anexo de comprovante — **igual Controle Total**.
///
/// Pick → Storage → Firestore → SnackBar.
/// **Sem** faixa global «A trocar comprovante… — N%» (upload silencioso).
/// Falha de rede (mobile): fila local + sync em background.
abstract final class FinanceComprovanteAttachFlow {
  FinanceComprovanteAttachFlow._();

  static Future<bool> attachToLancamento({
    required BuildContext context,
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic>? docData,
    FinanceComprovanteAttachment? prePicked,
    bool showPickSheet = true,
    bool suppressSuccessSnackBar = false,
  }) async {
    final data = docData ?? {};
    final jaTem = FinanceComprovanteAttachService.hasComprovanteInDoc(data);

    final picked = prePicked ??
        (showPickSheet
            ? await FinanceComprovanteAttachService.showPickSheet(
                context,
                title: jaTem ? 'Trocar comprovante' : 'Anexar comprovante',
              )
            : null);
    if (picked == null) return false;
    if (!context.mounted) return false;

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    try {
      final refDate =
          FinanceComprovantePublishService.referenceDateFromMap(data);
      final mime = picked.isPdf ? 'application/pdf' : picked.mimeType;

      await FinanceComprovantePublishService.uploadComprovanteControleTotal(
        tenantId: tenantId,
        docRef: docRef,
        rawBytes: picked.bytes,
        mimeType: mime,
        fileName: picked.fileName,
        referenceDate: refDate,
        previousStoragePath: (data['comprovanteStoragePath'] ?? '').toString(),
        previousDownloadUrl:
            (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
                .toString(),
        alreadyCompressed: picked.alreadyOptimized,
      );

      if (context.mounted && !suppressSuccessSnackBar) {
        ImmediateMediaAttachFeedback.showEnviadoEVinculado(context);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            jaTem ? 'Comprovante actualizado.' : 'Comprovante anexado.',
          ),
        );
      }
      unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
      return true;
    } on FinanceComprovanteQueuedLocally {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(kFeedPublishQueuedUserMessage),
        );
      }
      unawaited(ChurchFinanceRealtimeService.onFinanceMutation(tenantId));
      return true;
    } catch (e) {
      await FinanceComprovantePublishService.markComprovanteUploadFailed(
        docRef: docRef,
        error: e,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            formatUploadErrorForUser(e),
            onRetry: () => unawaited(
              attachToLancamento(
                context: context,
                tenantId: tenantId,
                docRef: docRef,
                docData: docData,
                prePicked: picked,
                showPickSheet: false,
              ),
            ),
          ),
        );
      }
      return false;
    }
  }

  /// Compromisso de fornecedor — mesmo fluxo CT (silencioso, sem faixa %).
  static Future<bool> attachToCompromisso({
    required BuildContext context,
    required String tenantId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String fornecedorId,
    Map<String, dynamic>? docData,
    FinanceComprovanteAttachment? prePicked,
    bool showPickSheet = true,
    bool suppressSuccessSnackBar = false,
  }) async {
    final data = docData ?? {};
    final jaTem = FinanceComprovanteAttachService.hasComprovanteInDoc(data);

    final picked = prePicked ??
        (showPickSheet
            ? await FinanceComprovanteAttachService.showPickSheet(
                context,
                title: jaTem ? 'Trocar comprovante' : 'Anexar comprovante',
              )
            : null);
    if (picked == null) return false;
    if (!context.mounted) return false;

    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    try {
      final mime = picked.isPdf ? 'application/pdf' : picked.mimeType;

      await FornecedorCompromissoPublishService.attachComprovanteControleTotal(
        docRef: docRef,
        churchId: tenantId,
        fornecedorId: fornecedorId,
        compromissoId: docRef.id,
        bytes: picked.bytes,
        mimeType: mime,
        fileName: picked.fileName,
        alreadyCompressed: picked.alreadyOptimized,
      );

      if (context.mounted && !suppressSuccessSnackBar) {
        ImmediateMediaAttachFeedback.showEnviadoEVinculado(context);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            jaTem ? 'Comprovante actualizado.' : 'Comprovante anexado.',
          ),
        );
      }
      return true;
    } on FinanceComprovanteQueuedLocally {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(kFeedPublishQueuedUserMessage),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            formatUploadErrorForUser(e),
            onRetry: () => unawaited(
              attachToCompromisso(
                context: context,
                tenantId: tenantId,
                docRef: docRef,
                fornecedorId: fornecedorId,
                docData: docData,
                prePicked: picked,
                showPickSheet: false,
              ),
            ),
          ),
        );
      }
      return false;
    }
  }
}
