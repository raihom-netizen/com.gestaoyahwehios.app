import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/dashboard/church_ministry_intel.dart';
import 'package:gestao_yahweh/ui/widgets/church_member_pastoral_contact_card.dart';

/// Faixa/card moderno — Atenção pastoral: Chat Igreja + WhatsApp (web, iOS, Android).
class PastoralAttentionMemberCard extends StatelessWidget {
  final MemberPastoralAlert alert;
  final Map<String, dynamic> memberData;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;
  final String? whatsappPrefill;

  const PastoralAttentionMemberCard({
    super.key,
    required this.alert,
    required this.memberData,
    required this.tenantId,
    required this.memberRole,
    this.viewerCpfDigits = '',
    this.whatsappPrefill,
  });

  @override
  Widget build(BuildContext context) {
    final nomeCompleto = (memberData['NOME_COMPLETO'] ?? memberData['nome'] ?? alert.name)
        .toString()
        .trim();
    final hasPhone = alert.phoneDigits.trim().length >= 10;

    return ChurchMemberPastoralContactCard(
      displayName: nomeCompleto,
      subtitle: alert.summary,
      memberData: memberData,
      tenantId: tenantId,
      memberDocId: alert.memberId,
      memberRole: memberRole,
      viewerCpfDigits: viewerCpfDigits,
      whatsappMessage: whatsappPrefill,
      phoneHint: hasPhone
          ? null
          : 'Sem telefone na ficha — use o chat se tiver conta no app.',
    );
  }
}
