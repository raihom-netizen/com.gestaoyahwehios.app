import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/pages/member_card_cnh_fullscreen_page.dart';

/// Abre o cartão membro CNH em tela cheia (evita import circular).
void openMemberCardCnhFullscreen(
  BuildContext context, {
  required String tenantId,
  required String role,
  String? memberId,
  String? cpf,
  Map<String, dynamic>? memberSeedData,
}) {
  MemberCardCnhFullscreenPage.open(
    context,
    tenantId: tenantId,
    role: role,
    memberId: memberId,
    cpf: cpf,
    memberSeedData: memberSeedData,
  );
}
