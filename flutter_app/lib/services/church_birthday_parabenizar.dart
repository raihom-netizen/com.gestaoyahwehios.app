import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Parabenizar aniversariante pelo chat da igreja (DM) — web, iOS e Android.
abstract final class ChurchBirthdayParabenizar {
  ChurchBirthdayParabenizar._();

  static String messageFor(String primeiroNome) {
    final nome = primeiroNome.trim();
    return 'Feliz aniversário${nome.isNotEmpty ? ', $nome' : ''}! '
        'Que Deus te abençoe. 🎂';
  }

  static String? authUidFromMember(Map<String, dynamic> data) {
    for (final k in [
      'authUid',
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

  /// Abre DM no chat com mensagem pré-preenchida (utilizador envia).
  static Future<void> openChat({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String memberCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    required String primeiroNome,
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
          'Você não pode enviar parabéns para si mesmo no chat.',
        ),
      );
      return;
    }

    final titulo = displayName.trim().isEmpty ? 'Membro' : displayName.trim();
    final draft = messageFor(primeiroNome);

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
          memberCpfDigits: memberCpfDigits,
          initialDraftText: draft,
        ),
      ),
    );
  }
}
