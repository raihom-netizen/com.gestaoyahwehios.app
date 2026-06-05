import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contato por chat da igreja ou WhatsApp — web, iOS e Android.
abstract final class ChurchMemberContactChat {
  ChurchMemberContactChat._();

  static const String faleComigoDraft = 'Olá! Gostaria de falar com você.';

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

  /// Resolve `authUid` do destinatário — mapa leve do painel, doc `membros` ou e-mail.
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

    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return (data: data, memberDocId: docId, peerUid: null);
    }

    try {
      await ChurchTenantResilientReads.preparePanelRead();
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros');

      Future<void> mergeSnap(DocumentSnapshot<Map<String, dynamic>> snap) async {
        if (!snap.exists) return;
        docId = snap.id;
        final fresh = snap.data();
        if (fresh != null && fresh.isNotEmpty) {
          data = {...data, ...fresh};
        }
      }

      if (docId.isNotEmpty) {
        try {
          final snap = await FirestoreReadResilience.getDocument(
            col.doc(docId),
            cacheKey: 'chat_open_peer_${tid}_$docId',
          );
          await mergeSnap(snap);
          peer = peerFromData();
          if (peer != null && peer.isNotEmpty) {
            return (data: data, memberDocId: docId, peerUid: peer);
          }
        } catch (_) {}
      }

      if (cpf.length == 11 && cpf != docId) {
        try {
          final snap = await FirestoreReadResilience.getDocument(
            col.doc(cpf),
            cacheKey: 'chat_open_peer_cpf_${tid}_$cpf',
          );
          await mergeSnap(snap);
          peer = peerFromData();
          if (peer != null && peer.isNotEmpty) {
            return (data: data, memberDocId: docId, peerUid: peer);
          }
        } catch (_) {}
      }

      final email = (data['EMAIL'] ?? data['email'] ?? '').toString().trim();
      if (email.isNotEmpty) {
        for (final field in ['EMAIL', 'email']) {
          try {
            final q = await FirestoreReadResilience.getQuery(
              col.where(field, isEqualTo: email).limit(1),
              cacheKey: 'chat_open_peer_mail_${tid}_${field}_$email',
            );
            if (q.docs.isNotEmpty) {
              await mergeSnap(q.docs.first);
              peer = peerFromData();
              if (peer != null && peer.isNotEmpty) {
                return (data: data, memberDocId: docId, peerUid: peer);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return (data: data, memberDocId: docId, peerUid: peerFromData());
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
    String draftText = faleComigoDraft,
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
        draftText: draftText,
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
    final tid = tenantId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || mid.isEmpty) return memberData;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .doc(mid)
          .get();
      if (!snap.exists) return memberData;
      final fresh = snap.data();
      if (fresh == null || fresh.isEmpty) return memberData;
      return {...memberData, ...fresh};
    } catch (_) {
      return memberData;
    }
  }

  static Future<void> openChatIgreja({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String viewerCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    String? memberDocId,
    String draftText = faleComigoDraft,
    bool popSheetBeforeNavigate = false,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid?.trim();
    if (myUid == null || myUid.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Entre na sua conta para usar o chat da igreja.',
        ),
      );
      return;
    }

    var operationalTenant = tenantId.trim();
    try {
      operationalTenant = await TenantResolverService.resolveOperationalChurchDocId(
        tenantId,
        userUid: myUid,
      );
    } catch (_) {}

    final resolved = await resolvePeerForChat(
      tenantId: operationalTenant,
      memberData: memberData,
      memberDocId: memberDocId,
    );
    final peerUid = resolved.peerUid?.trim();
    if (peerUid == null || peerUid.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Este membro ainda não tem conta no app (login). '
          'Ative o acesso em Membros ou use o WhatsApp.',
        ),
      );
      return;
    }
    if (peerUid == myUid) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Você não pode abrir chat consigo mesmo.',
        ),
      );
      return;
    }

    final titulo =
        displayName.trim().isEmpty ? 'Membro' : displayName.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (popSheetBeforeNavigate && context.mounted) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      }
    }

    final titleA = FirebaseAuth.instance.currentUser?.displayName ?? 'Eu';
    final ensured = await ChurchChatService.ensureDmThreadResilient(
      tenantId: operationalTenant,
      uidA: myUid,
      uidB: peerUid,
      titleA: titleA,
      titleB: titulo,
    );
    if (!ensured && context.mounted) {
      messenger?.showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'A sincronizar o chat — a conversa abre na mesma.',
        ),
      );
    }

    final threadId = ChurchChatService.dmThreadId(myUid, peerUid);
    final draft = draftText.trim();

    ChurchPanelNavigationBridge.instance.requestNavigateToChatThread(
      threadId: threadId,
      tenantId: operationalTenant,
      peerUid: peerUid,
      displayName: titulo,
      initialDraftText: draft.isEmpty ? null : draft,
    );

    unawaited(
      _openChatThreadFallback(
        operationalTenant: operationalTenant,
        threadId: threadId,
        peerUid: peerUid,
        displayName: titulo,
        memberRole: memberRole,
        viewerCpfDigits: viewerCpfDigits,
        initialDraftText: draft.isEmpty ? null : draft,
      ),
    );
  }

  /// Se o hub embutido não consumir o pending a tempo, abre a thread directamente.
  static Future<void> _openChatThreadFallback({
    required String operationalTenant,
    required String threadId,
    required String peerUid,
    required String displayName,
    required String memberRole,
    required String viewerCpfDigits,
    String? initialDraftText,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final pending =
        ChurchPanelNavigationBridge.instance.peekPendingChatThreadOpen();
    if (pending == null || pending.threadId != threadId) return;

    final nav = appRootNavigatorKey.currentState;
    if (nav == null) return;

    ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
    await nav.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: operationalTenant,
          threadId: threadId,
          title: displayName,
          isDepartment: false,
          peerUid: peerUid,
          memberRole: memberRole,
          memberCpfDigits: viewerCpfDigits.replaceAll(RegExp(r'\D'), ''),
          initialDraftText: initialDraftText,
        ),
      ),
    );
  }

  static Future<void> openWhatsAppFaleComigo(
    BuildContext context,
    Map<String, dynamic> memberData, {
    String message = 'Fale comigo',
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
    final phone = digits.startsWith('55') ? digits : '55$digits';
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(message)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível abrir o WhatsApp.',
          ),
        );
      }
    }
  }
}
