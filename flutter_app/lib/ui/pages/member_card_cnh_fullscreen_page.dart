import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/ui/pages/member_card_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Visualização premium em tela cheia do cartão membro CNH digital.
class MemberCardCnhFullscreenPage extends StatelessWidget {
  const MemberCardCnhFullscreenPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.memberId,
    this.cpf,
    this.memberSeedData,
  });

  final String tenantId;
  final String role;
  final String? memberId;
  final String? cpf;
  final Map<String, dynamic>? memberSeedData;

  static Future<void> open(
    BuildContext context, {
    required String tenantId,
    required String role,
    String? memberId,
    String? cpf,
    Map<String, dynamic>? memberSeedData,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MemberCardCnhFullscreenPage(
          tenantId: tenantId,
          role: role,
          memberId: memberId,
          cpf: cpf,
          memberSeedData: memberSeedData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A2342),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: 'Compartilhar',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Use os botões abaixo do cartão: WhatsApp, PNG, PDF ou salvar no celular.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
              },
            ),
          ],
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestão YAHWEH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                  letterSpacing: 0.4,
                ),
              ),
              const Text(
                'Carteira membro digital',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A2342),
                const Color(0xFF0D2C54),
                ThemeCleanPremium.primary.withValues(alpha: 0.35),
                const Color(0xFF0A2342),
              ],
            ),
          ),
          child: SafeArea(
            child: MemberCardPage(
              tenantId: tenantId,
              role: role,
              memberId: memberId,
              cpf: cpf,
              memberSeedData: memberSeedData,
              cnhFullscreenOnly: true,
            ),
          ),
        ),
      ),
    );
  }
}
