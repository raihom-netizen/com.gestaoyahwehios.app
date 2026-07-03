import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/dashboard/church_ministry_intel.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, isValidImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';

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
    final prefill =
        whatsappPrefill ?? ChurchMemberContactChat.faleComigoDraft();
    final hasPhone = alert.phoneDigits.trim().length >= 10;
    final foto = MemberProfilePhotoResolver.displayRef(memberData, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(memberData, preferThumb: true);
    final avatarColor =
        avatarColorForMember(memberData, hasPhoto: hasFoto);
    final cpf = alert.cpfDigits.length == 11 ? alert.cpfDigits : null;
    final nomeCompleto = (memberData['NOME_COMPLETO'] ?? memberData['nome'] ?? alert.name)
      .toString()
      .trim();
    final initial = nomeCompleto.isNotEmpty ? nomeCompleto[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FotoMembroWidget(
                  imageUrl: foto,
                  memberData: memberData,
                  tenantId: tenantId,
                  memberId: alert.memberId,
                  cpfDigits: cpf,
                  authUid: alert.authUid,
                  size: 52,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
                  preferListThumbnail: true,
                  backgroundColor:
                      avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  fallbackChild: CircleAvatar(
                    radius: 26,
                    backgroundColor: avatarColor ??
                        ThemeCleanPremium.primary.withValues(alpha: 0.15),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeCompleto,
                        maxLines: 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.25,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        alert.summary,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!hasPhone)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Sem telefone na ficha — use o chat se tiver conta no app.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: YahwehSuperPremiumActionButton.chat(
                    compact: true,
                    onPressed: () => ChurchMemberContactChat.tapYahwehChat(
                      context: context,
                      tenantId: tenantId,
                      memberRole: memberRole,
                      viewerCpfDigits: viewerCpfDigits,
                      memberData: memberData,
                      displayName: nomeCompleto,
                      memberDocId: alert.memberId,
                      draftText: prefill,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: YahwehSuperPremiumActionButton.whatsapp(
                    compact: true,
                    onPressed: hasPhone
                        ? () => ChurchMemberContactChat.tapWhatsApp(
                              context: context,
                              memberData: memberData,
                              message: prefill,
                              tenantId: tenantId,
                              memberDocId: alert.memberId,
                            )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
