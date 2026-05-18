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

  static String phoneDigitsFromMember(Map<String, dynamic> data) {
    for (final k in [
      'whatsapp',
      'WHATSAPP',
      'whatsappIgreja',
      'TELEFONES',
      'telefones',
      'celular',
      'CELULAR',
      'telefone',
      'TELEFONE',
      'fone',
      'phone',
    ]) {
      final s = (data[k] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
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
      final s = (e.value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (s.length >= 10) return s;
    }
    return '';
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
  }) async {
    final digits = phoneDigitsFromMember(memberData);
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
