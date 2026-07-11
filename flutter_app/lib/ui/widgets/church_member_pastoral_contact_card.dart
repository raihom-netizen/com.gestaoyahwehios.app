import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';

/// Card padrão **Atenção pastoral** — avatar, nome, subtítulo e Chat + WhatsApp.
class ChurchMemberPastoralContactCard extends StatelessWidget {
  const ChurchMemberPastoralContactCard({
    super.key,
    required this.displayName,
    required this.subtitle,
    required this.memberData,
    required this.tenantId,
    required this.memberDocId,
    required this.memberRole,
    this.viewerCpfDigits = '',
    this.accent,
    this.whatsappMessage,
    this.phoneHint,
    this.avatarSize = 52,
    this.compact = false,
  });

  final String displayName;
  final String subtitle;
  final Map<String, dynamic> memberData;
  final String tenantId;
  final String memberDocId;
  final String memberRole;
  final String viewerCpfDigits;
  final Color? accent;
  final String? whatsappMessage;
  final String? phoneHint;
  final double avatarSize;
  final bool compact;

  bool _hasPhone(Map<String, dynamic> data) {
    for (final k in const [
      'TELEFONES',
      'telefone',
      'phone',
      'celular',
      'whatsapp',
    ]) {
      final v = (data[k] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (v.length >= 10) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? ThemeCleanPremium.primary;
    final nome = displayName.trim().isEmpty ? 'Membro' : displayName.trim();
    final sub = subtitle.trim();
    final foto = MemberProfilePhotoResolver.displayRef(memberData, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(memberData, preferThumb: true);
    final avatarColor = avatarColorForMember(memberData, hasPhoto: hasFoto);
    final cpf = (memberData['CPF'] ?? memberData['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final initial = nome.isNotEmpty ? nome[0].toUpperCase() : '?';
    final hasPhone = _hasPhone(memberData);
    final waMsg = whatsappMessage ?? ChurchMemberContactChat.faleComigoDraft();
    final effectiveAvatar = compact ? 44.0 : avatarSize;
    final outerPad = compact ? 12.0 : 14.0;
    final titleSize = compact ? 14.0 : 16.0;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
            tint.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
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
        padding: EdgeInsets.fromLTRB(outerPad, outerPad, outerPad, outerPad),
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
                  memberId: memberDocId,
                  cpfDigits: cpf.length == 11 ? cpf : null,
                  authUid: MemberProfilePhotoResolver.authUidFromData(
                    memberData,
                    memberDocId: memberDocId,
                  ),
                  size: effectiveAvatar,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
                  preferListThumbnail: true,
                  backgroundColor:
                      avatarColor ?? tint.withValues(alpha: 0.12),
                  fallbackChild: CircleAvatar(
                    radius: effectiveAvatar / 2,
                    backgroundColor:
                        avatarColor ?? tint.withValues(alpha: 0.15),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: effectiveAvatar * 0.38,
                        color: tint,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: compact ? 2 : 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: titleSize,
                          letterSpacing: -0.25,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (!hasPhone && phoneHint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            phoneHint!,
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
            SizedBox(height: compact ? 10 : 14),
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
                      displayName: nome,
                      memberDocId: memberDocId,
                      draftText: waMsg,
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
                              message: waMsg,
                              tenantId: tenantId,
                              memberDocId: memberDocId,
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
