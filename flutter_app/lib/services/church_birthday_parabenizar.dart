import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';

/// Parabenizar aniversariante pelo chat da igreja (DM) — web, iOS e Android.
abstract final class ChurchBirthdayParabenizar {
  ChurchBirthdayParabenizar._();

  static String messageFor(String primeiroNome) {
    final nome = primeiroNome.trim();
    return 'Feliz aniversário${nome.isNotEmpty ? ', $nome' : ''}! '
        'Que Deus te abençoe. 🎂';
  }

  static String? authUidFromMember(Map<String, dynamic> data) =>
      ChurchMemberContactChat.authUidFromMember(data);

  /// Abre DM no chat com mensagem pré-preenchida (utilizador envia).
  static Future<void> openChat({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String memberCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    required String primeiroNome,
    String? memberDocId,
    bool popSheetBeforeNavigate = false,
  }) {
    return ChurchMemberContactChat.openChatIgreja(
      context: context,
      tenantId: tenantId,
      memberRole: memberRole,
      viewerCpfDigits: memberCpfDigits,
      memberData: memberData,
      displayName: displayName,
      memberDocId: memberDocId,
      draftText: messageFor(primeiroNome),
      popSheetBeforeNavigate: popSheetBeforeNavigate,
    );
  }

  /// Botões do painel (aniversariantes) — não perder o toque por Future silenciosa.
  static void openChatUnawaited({
    required BuildContext context,
    required String tenantId,
    required String memberRole,
    required String memberCpfDigits,
    required Map<String, dynamic> memberData,
    required String displayName,
    required String primeiroNome,
    String? memberDocId,
    bool popSheetBeforeNavigate = false,
  }) {
    unawaited(
      openChat(
        context: context,
        tenantId: tenantId,
        memberRole: memberRole,
        memberCpfDigits: memberCpfDigits,
        memberData: memberData,
        displayName: displayName,
        primeiroNome: primeiroNome,
        memberDocId: memberDocId,
        popSheetBeforeNavigate: popSheetBeforeNavigate,
      ),
    );
  }
}
