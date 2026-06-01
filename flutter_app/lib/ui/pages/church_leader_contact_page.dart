import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_role_badge.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, isValidImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';

String? leaderContactAuthUid(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final k in ['authUid', 'uid', 'userId', 'firebaseUid', 'USER_ID']) {
    final v = (data[k] ?? '').toString().trim();
    if (v.length >= 8) return v;
  }
  return null;
}

/// Contato full-screen: líderes, corpo administrativo e departamentos.
class ChurchLeaderContactPage extends StatelessWidget {
  final Map<String, dynamic> memberData;
  final List<String> departmentNames;
  final List<String> funcoes;
  final String tenantId;
  final String memberDocId;
  final String memberRole;
  final String viewerCpfDigits;

  const ChurchLeaderContactPage({
    super.key,
    required this.memberData,
    required this.departmentNames,
    this.funcoes = const [],
    required this.tenantId,
    required this.memberDocId,
    required this.memberRole,
    this.viewerCpfDigits = '',
  });

  @override
  Widget build(BuildContext context) {
    final nome = (memberData['NOME_COMPLETO'] ??
            memberData['nome'] ??
            memberData['name'] ??
            '')
        .toString()
        .trim();
    final titulo = nome.isEmpty ? 'Contato' : nome;
    final foto = imageUrlFromMap(memberData);
    final hasFoto = isValidImageUrl(foto);
    final avatarColor =
        avatarColorForMember(memberData, hasPhoto: hasFoto);
    final cpfRaw = (memberData['CPF'] ?? memberData['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[^0-9]'), '');
    final phone = ChurchMemberContactChat.phoneDigitsFromMember(memberData);
    final phoneDisplay = (memberData['TELEFONES'] ??
            memberData['telefone'] ??
            memberData['phone'] ??
            memberData['telefones'] ??
            '')
        .toString()
        .trim();

    final initialLetter =
        (nome.isNotEmpty ? nome[0] : '?').toUpperCase();
    final letterAvatar = CircleAvatar(
      radius: 64,
      backgroundColor:
          avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.2),
      child: Text(
        initialLetter,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Contato'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: Column(
            children: [
              const SizedBox(height: 16),
              FotoMembroWidget(
                imageUrl: hasFoto ? foto : null,
                memberData: memberData,
                tenantId: tenantId,
                memberId: memberDocId,
                cpfDigits: cpfRaw.length == 11 ? cpfRaw : null,
                authUid: leaderContactAuthUid(memberData),
                size: 128,
                memCacheWidth: 280,
                memCacheHeight: 280,
                backgroundColor:
                    avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 20),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              if (funcoes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: funcoes
                      .map(
                        (f) => ChurchRoleBadge(
                          label: churchRoleDisplayLabel(f),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (departmentNames.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Text(
                    'Líder dos departamentos: ${departmentNames.join(', ')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (phoneDisplay.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEEF2F6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_iphone_rounded,
                        size: 22,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          phoneDisplay,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              YahwehSuperPremiumActionButton.chat(
                label: 'Chat Igreja — Fale comigo',
                onPressed: () => ChurchMemberContactChat.openChatIgrejaUnawaited(
                  context: context,
                  tenantId: tenantId,
                  memberRole: memberRole,
                  viewerCpfDigits: viewerCpfDigits,
                  memberData: memberData,
                  displayName: titulo,
                  memberDocId: memberDocId,
                ),
              ),
              const SizedBox(height: 10),
              YahwehSuperPremiumActionButton.whatsapp(
                label: 'WhatsApp — Fale comigo',
                onPressed: () => ChurchMemberContactChat.openWhatsAppFaleComigo(
                  context,
                  memberData,
                  tenantId: tenantId,
                  memberDocId: memberDocId,
                ),
              ),
              if (phone.length < 10) ...[
                const SizedBox(height: 8),
                Text(
                  'Sem telefone cadastrado — cadastre em Membros > Editar para usar o WhatsApp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void openChurchLeaderContactPage(
  BuildContext context, {
  required Map<String, dynamic> memberData,
  required List<String> departmentNames,
  List<String> funcoes = const [],
  required String tenantId,
  required String memberDocId,
  required String memberRole,
  String viewerCpfDigits = '',
}) {
  Navigator.of(context).push(
    ThemeCleanPremium.fadeSlideRoute(
      ChurchLeaderContactPage(
        memberData: memberData,
        departmentNames: departmentNames,
        funcoes: funcoes,
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberRole: memberRole,
        viewerCpfDigits: viewerCpfDigits,
      ),
    ),
  );
}
