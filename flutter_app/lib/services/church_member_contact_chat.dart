import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_contact_greeting.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Contato por Yahweh Chat (hub nativo Conversas/Grupos) ou WhatsApp — web, iOS e Android.
abstract final class ChurchMemberContactChat {
  ChurchMemberContactChat._();

  static String faleComigoDraft([DateTime? at]) =>
      YahwehContactGreeting.faleComigoDraft(at);

  /// Fecha dialog/sheet/ficha empilhada antes de ir ao módulo Chat (web painel).
  static void _popPanelOverlayIfNeeded(BuildContext context) {
    if (!context.mounted) return;
    final route = ModalRoute.of(context);
    if (route is PopupRoute) {
      Navigator.of(context).pop();
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  static String? authUidFromMember(Map<String, dynamic> data) {
    for (final k in [
      'authUid',
      'auth_uid',
      'uid',
      'userId',
      'firebaseUid',
      'USER_ID',
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.length >= 8) return v;
    }
    return null;
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _readMemberDoc(
    String churchId,
    String docId,
  ) async {
    final id = docId.trim();
    if (churchId.trim().isEmpty || id.isEmpty) return null;
    if (kIsWeb) {
      try {
        await FirestoreWebGuard.ensurePanelReadReady()
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    return ChurchUiCollections.membros(churchId).doc(id).get();
  }


  /// Atalho único — Yahweh Chat: abre módulo + conversa individual (web/iOS/Android).
  static void tapYahwehChat({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String viewerCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    String? memberDocId,
    String? draftText,
    bool popSheetBeforeNavigate = true,
  }) {
    openChatIgrejaUnawaited(
      context: context,
      tenantId: tenantId,
      memberRole: memberRole,
      viewerCpfDigits: viewerCpfDigits,
      memberData: memberData,
      displayName: displayName,
      memberDocId: memberDocId,
      draftText: draftText,
      popSheetBeforeNavigate: popSheetBeforeNavigate,
    );
  }

  /// Atalho único — WhatsApp: abre app com conversa do membro.
  static void tapWhatsApp({
    required BuildContext context,
    required Map<String, dynamic> memberData,
    String? tenantId,
    String? memberDocId,
    String? message,
  }) {
    unawaited(
      openWhatsAppFaleComigo(
        context,
        memberData,
        message: message,
        tenantId: tenantId,
        memberDocId: memberDocId,
      ),
    );
  }

  /// Atalhos do painel / membros — não bloqueia o botão (Future em background).
  static void openChatIgrejaUnawaited({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String viewerCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    String? memberDocId,
    String? draftText,
    bool popSheetBeforeNavigate = false,
  }) {
    unawaited(
      openChatIgreja(
        context: context,
        tenantId: tenantId,
        memberRole: memberRole,
        viewerCpfDigits: viewerCpfDigits,
        memberData: memberData,
        displayName: displayName,
        memberDocId: memberDocId,
        draftText: draftText ?? faleComigoDraft(),
        popSheetBeforeNavigate: popSheetBeforeNavigate,
      ),
    );
  }

  static String _stripPhoneDigits(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final s = v.toInt().toString();
      return s.length >= 10 ? s : '';
    }
    if (v is List) {
      for (final e in v) {
        final s = _stripPhoneDigits(e);
        if (s.length >= 10) return s;
      }
      return v
          .map((e) => e.toString())
          .join('')
          .replaceAll(RegExp(r'[^0-9]'), '');
    }
    return v.toString().replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Dígitos do telefone/WhatsApp na ficha do membro (≥10 dígitos).
  static String phoneDigitsFromMember(Map<String, dynamic> data) {
    const keys = [
      'TELEFONES',
      'telefones',
      'whatsapp',
      'WHATSAPP',
      'whatsappIgreja',
      'celular',
      'CELULAR',
      'telefone',
      'TELEFONE',
      'fone',
      'phone',
      'PHONE',
    ];
    for (final k in keys) {
      final s = _stripPhoneDigits(data[k]);
      if (s.length >= 10) return s;
    }
    for (final e in data.entries) {
      final key = e.key.toString().toLowerCase();
      if (!key.contains('tel') &&
          !key.contains('fone') &&
          !key.contains('zap') &&
          !key.contains('whats')) {
        continue;
      }
      final s = _stripPhoneDigits(e.value);
      if (s.length >= 10) return s;
    }
    return '';
  }

  /// Completa [memberData] com a ficha em Firestore quando o mapa leve não traz telefone.
  static Future<Map<String, dynamic>> enrichMemberDataWithPhone({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    if (phoneDigitsFromMember(memberData).length >= 10) return memberData;
    final churchId = ChurchRepository.churchId(tenantId.trim());
    final mid = memberDocId.trim();
    if (churchId.isEmpty || mid.isEmpty) return memberData;
    try {
      final snap = await _readMemberDoc(churchId, mid);
      if (snap == null || !snap.exists) return memberData;
      final fresh = snap.data();
      if (fresh == null || fresh.isEmpty) return memberData;
      return {...memberData, ...fresh};
    } catch (_) {
      return memberData;
    }
  }

  /// Abre WhatsApp (app nativo ou wa.me na web).
  static Future<bool> launchWhatsAppDigits(
    String rawDigits, {
    String? message,
  }) =>
      YahwehWhatsAppService.openWithMessage(
        message: message ?? faleComigoDraft(),
        phoneDigits: rawDigits,
      );

  static Future<void> openChatIgreja({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String viewerCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    String? memberDocId,
    String? draftText,
    bool popSheetBeforeNavigate = false,
  }) async {
    // Chat interno da igreja foi removido — contato de membro passa a abrir
    // diretamente o WhatsApp (fallback único). Mantém a assinatura para os
    // callers (botões "Falar" no painel/membros) seguirem funcionando.
    if (popSheetBeforeNavigate && context.mounted) {
      _popPanelOverlayIfNeeded(context);
    }
    await openWhatsAppFaleComigo(
      context,
      memberData,
      message: draftText,
      tenantId: tenantId,
      memberDocId: memberDocId,
    );
  }

  static Future<void> openWhatsAppFaleComigo(
    BuildContext context,
    Map<String, dynamic> memberData, {
    String? message,
    String? tenantId,
    String? memberDocId,
  }) async {
    var data = memberData;
    if (phoneDigitsFromMember(data).length < 10 &&
        tenantId != null &&
        memberDocId != null) {
      data = await enrichMemberDataWithPhone(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: data,
      );
    }
    final digits = phoneDigitsFromMember(data);
    if (digits.length < 10) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Cadastre o telefone/WhatsApp do membro para enviar mensagem.',
        ),
      );
      return;
    }
    final ok = await launchWhatsAppDigits(
      digits,
      message: message ?? faleComigoDraft(),
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Não foi possível abrir o WhatsApp. Verifique se o app está instalado.',
        ),
      );
    }
  }
}

