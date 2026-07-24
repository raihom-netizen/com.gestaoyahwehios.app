import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/yahweh_contact_greeting.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
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

  /// Igual à ficha em [MembersPage] — `authUid` ou doc id em formato Firebase UID.
  static String? peerAuthUidFromMember(
    Map<String, dynamic> data, {
    String? memberDocId,
  }) {
    final fromFields = authUidFromMember(data);
    if (fromFields != null && fromFields.isNotEmpty) return fromFields;
    final id = (memberDocId ?? '').trim();
    if (id.length >= 20 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(id)) {
      return id;
    }
    return null;
  }

  static String _cpfDigitsFromMemberData(Map<String, dynamic> data) {
    return (data['CPF'] ?? data['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
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

  /// Resolve `authUid` do destinatário — doc directo `igrejas/{churchId}/membros`.
  static Future<
      ({
        Map<String, dynamic> data,
        String memberDocId,
        String? peerUid,
      })> resolvePeerForChat({
    required String tenantId,
    required Map<String, dynamic> memberData,
    String? memberDocId,
  }) async {
    var data = Map<String, dynamic>.from(memberData);
    var docId = (memberDocId ?? '').trim();
    final cpf = _cpfDigitsFromMemberData(data);
    if (docId.isEmpty && cpf.length == 11) docId = cpf;

    String? peerFromData([String? mid]) => peerAuthUidFromMember(
          data,
          memberDocId: (mid ?? docId).trim().isEmpty ? null : (mid ?? docId),
        );

    var peer = peerFromData();
    if (peer != null && peer.isNotEmpty) {
      return (data: data, memberDocId: docId, peerUid: peer);
    }

    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty) {
      return (data: data, memberDocId: docId, peerUid: peerFromData());
    }

    Future<void> mergeSnap(DocumentSnapshot<Map<String, dynamic>> snap) async {
      if (!snap.exists) return;
      docId = snap.id;
      final fresh = snap.data();
      if (fresh != null && fresh.isNotEmpty) {
        data = {...data, ...fresh};
      }
    }

    try {
      await ChurchTenantResilientReads.preparePanelRead();
      if (docId.isNotEmpty) {
        final snap = await _readMemberDoc(churchId, docId);
        if (snap != null) {
          await mergeSnap(snap);
          peer = peerFromData();
          if (peer != null && peer.isNotEmpty) {
            return (data: data, memberDocId: docId, peerUid: peer);
          }
        }
      }
      if (cpf.length == 11 && cpf != docId) {
        final snap = await _readMemberDoc(churchId, cpf);
        if (snap != null) {
          await mergeSnap(snap);
          peer = peerFromData();
          if (peer != null && peer.isNotEmpty) {
            return (data: data, memberDocId: docId, peerUid: peer);
          }
        }
      }
      final auth = authUidFromMember(data);
      if (auth != null && auth.isNotEmpty) {
        Future<QuerySnapshot<Map<String, dynamic>>> query() =>
            ChurchUiCollections.membros(churchId)
                .where('authUid', isEqualTo: auth)
                .limit(1)
                .get();
        final q = await query();
        if (q.docs.isNotEmpty) {
          await mergeSnap(q.docs.first);
          peer = auth;
          return (data: data, memberDocId: docId, peerUid: peer);
        }
      }
    } catch (_) {}

    return (data: data, memberDocId: docId, peerUid: peerFromData());
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
    final myUid = firebaseDefaultAuth.currentUser?.uid.trim();
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (popSheetBeforeNavigate && context.mounted) {
      _popPanelOverlayIfNeeded(context);
    }

    if (myUid == null || myUid.isEmpty) {
      messenger?.showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre na sua conta para usar o chat da igreja.',
        ),
      );
      return;
    }

    final operationalTenant = ChurchPanelTenant.forFirestore(tenantId);
    if (operationalTenant.isEmpty) {
      messenger?.showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Igreja não identificada para abrir o Yahweh Chat.',
        ),
      );
      return;
    }

    final resolved = await resolvePeerForChat(
      tenantId: operationalTenant,
      memberData: memberData,
      memberDocId: memberDocId,
    );
    final peerUid = resolved.peerUid?.trim();
    if (peerUid == null || peerUid.isEmpty) {
      messenger?.showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Este membro ainda não tem conta no app (login). '
          'Ative o acesso em Membros ou use o WhatsApp.',
        ),
      );
      return;
    }
    if (peerUid == myUid) {
      messenger?.showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Você não pode abrir chat consigo mesmo.',
        ),
      );
      return;
    }

    final titulo =
        displayName.trim().isEmpty ? 'Membro' : displayName.trim();

    final titleA = firebaseDefaultAuth.currentUser?.displayName ?? 'Eu';
    final threadId = ChurchChatService.dmThreadId(myUid, peerUid);
    final draft = (draftText ?? faleComigoDraft()).trim();

    // Navega para o Yahweh Chat nativo (hub consome DM pendente).
    ChurchPanelNavigationBridge.instance.requestNavigateToChatThread(
      threadId: threadId,
      tenantId: operationalTenant,
      peerUid: peerUid,
      displayName: titulo,
      initialDraftText: draft.isEmpty ? null : draft,
    );
    ChurchPanelNavigationBridge.instance.renotifyPendingChatThreadOpen();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      ChurchPanelNavigationBridge.instance.renotifyPendingChatThreadOpen();
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      ChurchPanelNavigationBridge.instance.renotifyPendingChatThreadOpen();
    });

    unawaited(
      ChurchChatService.ensureDmThreadResilient(
        tenantId: operationalTenant,
        uidA: myUid,
        uidB: peerUid,
        titleA: titleA,
        titleB: titulo,
      ),
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

