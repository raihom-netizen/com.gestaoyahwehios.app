import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_birthday_parabenizar.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contato por chat da igreja ou WhatsApp — web, iOS e Android.
abstract final class ChurchMemberContactChat {
  ChurchMemberContactChat._();

  static const String faleComigoDraft = 'Olá! Gostaria de falar com você.';

  static String? authUidFromMember(Map<String, dynamic> data) =>
      ChurchBirthdayParabenizar.authUidFromMember(data);

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

    final peerUid = authUidFromMember(memberData)?.trim();
    if (peerUid == null || peerUid.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Este membro ainda não tem login no app. '
          'Peça para ativar a conta ou use o WhatsApp.',
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

    if (popSheetBeforeNavigate && context.mounted) {
      Navigator.pop(context);
    }

    await ChurchChatService.ensureDmThread(
      tenantId: tenantId,
      uidA: myUid,
      uidB: peerUid,
      titleA: FirebaseAuth.instance.currentUser?.displayName ?? 'Eu',
      titleB: titulo,
    );

    final threadId = ChurchChatService.dmThreadId(myUid, peerUid);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: tenantId,
          threadId: threadId,
          title: titulo,
          isDepartment: false,
          peerUid: peerUid,
          memberRole: memberRole,
          memberCpfDigits: viewerCpfDigits,
          initialDraftText: draftText.trim(),
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
