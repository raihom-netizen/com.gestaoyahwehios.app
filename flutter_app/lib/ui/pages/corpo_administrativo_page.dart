import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_corpo_admin_roles.dart';
import 'package:gestao_yahweh/services/church_panel_leadership_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_leadership_cards.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// «Corpo administrativo» — página completa no mesmo padrão de abertura do
/// Organograma ministerial (cache-first do painel, linhas estreitas modernas).
class CorpoAdministrativoPage extends StatelessWidget {
  const CorpoAdministrativoPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.viewerCpfDigits = '',
    this.panelCache,
    this.membersDirectory,
    this.corpoAdminRoles,
  });

  final String tenantId;
  final String role;
  final String viewerCpfDigits;
  final PanelDashboardSnapshot? panelCache;
  final MembersDirectorySnapshot? membersDirectory;
  final List<String>? corpoAdminRoles;

  static const Color _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leadingWidth: 64,
        leading: YahwehSuperPremiumBackButton.appBarLeading(context),
        automaticallyImplyLeading: false,
        title: Text(
          'Corpo administrativo',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _accent,
                Color.lerp(_accent, Colors.white, 0.22)!,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: churchModuleBodyGradient(_accent),
        child: SafeArea(
          top: false,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              padding.left,
              16,
              padding.right,
              padding.bottom + 24,
            ),
            children: [
              YahwehWisdomSectionCard(
                borderTint: _accent,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    churchWisdomModuleIconLeading(
                      icon: Icons.groups_rounded,
                      accent: _accent,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Equipe administrativa',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pastores, gestores, secretaria e tesouraria — toque para contato via Chat ou WhatsApp.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ChurchPanelLeadershipCardSection(
                tenantId: tenantId,
                role: role,
                viewerCpfDigits: viewerCpfDigits,
                section: ChurchPanelLeadershipSection.corpoAdmin,
                panelCache: panelCache,
                membersDirectory: membersDirectory,
                corpoAdminRoles:
                    corpoAdminRoles ?? ChurchCorpoAdminRoles.defaultRoleKeys,
                onRetry: () async {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
