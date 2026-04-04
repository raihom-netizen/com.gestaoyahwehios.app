import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Contexto do painel: apenas igrejas (licenças/usuários controlados pelo Gestão Frotas à parte).
enum AdminContext {
  igrejas,
}

/// Identificadores das telas do painel admin. Apenas Igrejas + Sistema.
enum AdminMenuItem {
  igrejasDashboard,
  igrejasLista,
  igrejasPlanos,
  igrejasUsuarios,
  igrejasMercadoPago,
  igrejasRecebimentos,
  igrejasGestores,
  igrejasTorreComando,
  // —— SISTEMA ——
  sistemaDashboard,
  sistemaAlertas,
  sistemaAuditoria,
  sistemaCustomizacao,
  sistemaSuporte,
  sistemaMultiAdmin,
  sistemaPrecos,
  sistemaNiveisAcesso,
  sistemaSugestoes,
  sistemaDivulgacao,
  sistemaAcessos,
  sistemaArmazenamento,
  sistemaAvisoGlobal,
  sistemaVersaoMinima,
  sistemaMigrarMembros,
  sistemaHome,
}

/// Menu lateral azul padrão do painel admin. Exibe menu Igrejas + SISTEMA.
class AdminMenuLateral extends StatelessWidget {
  final AdminMenuItem selectedItem;
  final ValueChanged<AdminMenuItem> onItemSelected;
  final bool isCollapsed;
  final AdminContext context;
  final ValueChanged<AdminContext> onContextChanged;
  final bool Function(AdminMenuItem item)? itemVisible;

  const AdminMenuLateral({
    super.key,
    required this.selectedItem,
    required this.onItemSelected,
    required this.context,
    required this.onContextChanged,
    this.itemVisible,
    this.isCollapsed = false,
  });

  static AdminMenuItem firstItemFor(AdminContext ctx) {
    return AdminMenuItem.igrejasDashboard;
  }

  @override
  Widget build(BuildContext context) {
    final width = isCollapsed ? 64.0 : 280.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: BoxDecoration(
        color: ThemeCleanPremium.navSidebar,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(4, 0),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          SizedBox(
            height: isCollapsed ? 28 : 40,
            child: Image.asset(
              'assets/LOGO_GESTAO_YAHWEH.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: isCollapsed ? 28 : 36),
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 6),
            const Text(
              'Gestão YAHWEH',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Painel Admin',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11),
            ),
            const SizedBox(height: 14),
            _buildContextSelector(),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 6 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._menuItemsForContext(),
                  const SizedBox(height: 12),
                  _sectionTitle('SISTEMA', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaDashboard) ?? true) _tile(AdminMenuItem.sistemaDashboard, Icons.analytics, 'Dashboard Geral', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaAlertas) ?? true) _tile(AdminMenuItem.sistemaAlertas, Icons.notifications, 'Alertas', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaAuditoria) ?? true) _tile(AdminMenuItem.sistemaAuditoria, Icons.history, 'Auditoria', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaCustomizacao) ?? true) _tile(AdminMenuItem.sistemaCustomizacao, Icons.settings, 'Customização', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaSuporte) ?? true) _tile(AdminMenuItem.sistemaSuporte, Icons.support_agent, 'Suporte', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaMultiAdmin) ?? true) _tile(AdminMenuItem.sistemaMultiAdmin, Icons.admin_panel_settings, 'Multi-Admin', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaPrecos) ?? true) _tile(AdminMenuItem.sistemaPrecos, Icons.edit_note, 'Editar Preços', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaNiveisAcesso) ?? true) _tile(AdminMenuItem.sistemaNiveisAcesso, Icons.security, 'Níveis de Acesso', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaSugestoes) ?? true) _tile(AdminMenuItem.sistemaSugestoes, Icons.feedback, 'Sugestões / Críticas', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaDivulgacao) ?? true) _tile(AdminMenuItem.sistemaDivulgacao, Icons.perm_media_rounded, 'Mídias Divulgação', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaAcessos) ?? true) _tile(AdminMenuItem.sistemaAcessos, Icons.show_chart_rounded, 'Acessos ao domínio', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaArmazenamento) ?? true) _tile(AdminMenuItem.sistemaArmazenamento, Icons.storage_rounded, 'Armazenamento', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaAvisoGlobal) ?? true) _tile(AdminMenuItem.sistemaAvisoGlobal, Icons.campaign_rounded, 'Aviso global / Manutenção', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaVersaoMinima) ?? true) _tile(AdminMenuItem.sistemaVersaoMinima, Icons.system_update_rounded, 'Forçar atualização', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaMigrarMembros) ?? true) _tile(AdminMenuItem.sistemaMigrarMembros, Icons.people_alt_rounded, 'Migrar membros', isCollapsed),
                  if (itemVisible?.call(AdminMenuItem.sistemaHome) ?? true) _tile(AdminMenuItem.sistemaHome, Icons.home, 'Voltar ao Início', isCollapsed),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSelector() {
    if (isCollapsed) {
      return Icon(Icons.church_rounded, color: ThemeCleanPremium.navSidebarAccent, size: 26);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.church_rounded, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Text('Igrejas', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _menuItemsForContext() {
    return [
      _sectionTitle('IGREJAS', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasDashboard) ?? true) _tile(AdminMenuItem.igrejasDashboard, Icons.dashboard_rounded, 'Painel Igrejas', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasLista) ?? true) _tile(AdminMenuItem.igrejasLista, Icons.church_rounded, 'Lista Igrejas', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasPlanos) ?? true) _tile(AdminMenuItem.igrejasPlanos, Icons.credit_card_rounded, 'Planos & Cobranças', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasUsuarios) ?? true) _tile(AdminMenuItem.igrejasUsuarios, Icons.people_rounded, 'Usuários', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasMercadoPago) ?? true) _tile(AdminMenuItem.igrejasMercadoPago, Icons.payment_rounded, 'Mercado Pago', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasRecebimentos) ?? true) _tile(AdminMenuItem.igrejasRecebimentos, Icons.receipt_long_rounded, 'Recebimentos Licenças', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasGestores) ?? true) _tile(AdminMenuItem.igrejasGestores, Icons.person_add_rounded, 'Ativar mais gestores', isCollapsed),
      if (itemVisible?.call(AdminMenuItem.igrejasTorreComando) ?? true)
        _tile(AdminMenuItem.igrejasTorreComando, Icons.hub_rounded, 'Torre SaaS', isCollapsed),
    ];
  }

  Widget _sectionTitle(String label, bool collapsed) {
    if (collapsed) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _tile(AdminMenuItem item, IconData icon, String label, bool collapsed) {
    final selected = selectedItem == item;
    return Material(
      color: selected ? ThemeCleanPremium.navSidebarHover : Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: InkWell(
        onTap: () => onItemSelected(item),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 8 : ThemeCleanPremium.spaceSm,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? ThemeCleanPremium.navSidebarAccent : Colors.white70,
              ),
              if (!collapsed) ...[
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? ThemeCleanPremium.navSidebarAccent : Colors.white,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
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
