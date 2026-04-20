import 'package:flutter/material.dart';

/// Ícone do módulo **Fornecedores** (menu + telas).
/// `storefront_rounded` pode renderizar vazio na web/PWA (subset Material / tree-shake).
const IconData kFornecedoresModuleIcon = Icons.local_shipping_rounded;

/// Entrada do menu lateral do painel da igreja ([IgrejaCleanShell]).
/// A ordem define os **índices** (`_selectedIndex`, cache de páginas, etc.).
/// [accent] — cor do módulo (chips do menu, rodapé, identidade visual moderna).
class ChurchShellNavEntry {
  final IconData icon;
  final String label;
  final Color accent;
  const ChurchShellNavEntry(this.icon, this.label, this.accent);
}

/// Menu completo — única fonte para labels + ícones + cores + warmup de fonte Material na web.
const List<ChurchShellNavEntry> kChurchShellNavEntries = [
  ChurchShellNavEntry(
      Icons.dashboard_rounded, 'Painel', Color(0xFF3B82F6)),
  ChurchShellNavEntry(
      Icons.business_rounded, 'Cadastro da Igreja', Color(0xFF6366F1)),
  ChurchShellNavEntry(Icons.people_rounded, 'Membros', Color(0xFF0D9488)),
  ChurchShellNavEntry(
      Icons.groups_rounded, 'Departamentos', Color(0xFF8B5CF6)),
  ChurchShellNavEntry(
      Icons.person_add_rounded, 'Visitantes', Color(0xFFF59E0B)),
  ChurchShellNavEntry(Icons.work_rounded, 'Cargos', Color(0xFFF43F5E)),
  ChurchShellNavEntry(
      Icons.article_rounded, 'Mural de Avisos', Color(0xFF0EA5E9)),
  ChurchShellNavEntry(
      Icons.event_rounded, 'Mural de Eventos', Color(0xFFF97316)),
  ChurchShellNavEntry(
      Icons.favorite_rounded, 'Pedidos de Oração', Color(0xFFEC4899)),
  ChurchShellNavEntry(
      Icons.calendar_today_rounded, 'Agenda', Color(0xFF2563EB)),
  ChurchShellNavEntry(
      Icons.edit_calendar_rounded, 'Minha Escala', Color(0xFF06B6D4)),
  ChurchShellNavEntry(
      Icons.schedule_rounded, 'Escala Geral', Color(0xFF14B8A6)),
  ChurchShellNavEntry(
      Icons.badge_rounded, 'Cartão do membro', Color(0xFF10B981)),
  ChurchShellNavEntry(
      Icons.verified_rounded, 'Certificados', Color(0xFF7C3AED)),
  ChurchShellNavEntry(Icons.article_rounded, 'Cartas e transferências',
      Color(0xFFA78BFA)),
  ChurchShellNavEntry(
      Icons.bar_chart_rounded, 'Relatórios', Color(0xFFCA8A04)),
  ChurchShellNavEntry(
      Icons.tune_rounded, 'Configurações', Color(0xFF64748B)),
  /// `info_rounded` pode sair vazio na web (subset Material tree-shake); `feedback_rounded` cobre bem “informações / sugestões”.
  ChurchShellNavEntry(
      Icons.feedback_rounded, 'Informações', Color(0xFF38BDF8)),
  ChurchShellNavEntry(
      Icons.fact_check_rounded, 'Aprovações rápidas', Color(0xFF22C55E)),
  /// Mesmo glifo usado no preset “Pastoral” em Departamentos — evita glifo ausente na web.
  ChurchShellNavEntry(
      Icons.church_rounded, 'Pastoral & comunicação', Color(0xFFEAB308)),
  ChurchShellNavEntry(
      Icons.payment_rounded, 'Financeiro', Color(0xFF16A34A)),
  ChurchShellNavEntry(
      Icons.inventory_2_rounded, 'Patrimônio', Color(0xFFD97706)),
  ChurchShellNavEntry(
      kFornecedoresModuleIcon, 'Fornecedores', Color(0xFF475569)),
  ChurchShellNavEntry(
      Icons.card_giftcard_rounded, 'Doação', Color(0xFFDC2626)),
];

/// Acentos derivados de [kChurchShellNavEntries] — login, marketing e Torre Master SaaS
/// (uma única fonte visual com o painel da igreja).
abstract final class ChurchShellAccentTokens {
  ChurchShellAccentTokens._();

  /// **Membros** — fluxo “Sou membro”.
  static Color get loginMembro => kChurchShellNavEntries[2].accent;

  /// **Cadastro da Igreja** — gestor, nova igreja, callouts de cadastro.
  static Color get loginGestor => kChurchShellNavEntries[1].accent;

  /// **Financeiro** — resumo de planos / mensalidades.
  static Color get loginPlanos => kChurchShellNavEntries[20].accent;

  /// **Painel** — tab Clientes na Torre Master.
  static Color get masterSaasClientes => kChurchShellNavEntries[0].accent;

  /// **Relatórios** — tab Negócio (métricas e visão executiva).
  static Color get masterSaasNegocio => kChurchShellNavEntries[15].accent;
}

/// Glifos extras usados em módulos (toolbar/banners) além do menu — manter na web.
/// Inclui ícones dos cards de [DepartmentsPage] (`_iconOptions`) e telas embutidas,
/// para builds **sem** `--no-tree-shake-icons` não exibirem quadrados vazios.
const List<IconData> kChurchShellNavMaterialIconExtras = [
  Icons.article_rounded,
  Icons.mail_rounded,
  Icons.account_tree_rounded,
  Icons.description_rounded,
  Icons.refresh_rounded,
  Icons.add_circle_outline_rounded,
  Icons.open_in_new_rounded,
  Icons.copy_all_rounded,
  Icons.label_off_rounded,
  Icons.chat_bubble_rounded,
  Icons.photo_library_rounded,
  Icons.auto_awesome_mosaic_rounded,
  Icons.dashboard_customize_rounded,
  Icons.child_care_rounded,
  Icons.volunteer_activism_rounded,
  Icons.record_voice_over_rounded,
  Icons.account_balance_wallet_rounded,
  Icons.menu_book_rounded,
  Icons.bolt_rounded,
  Icons.music_note_rounded,
  Icons.videocam_rounded,
  Icons.public_rounded,
  Icons.construction_rounded,
  Icons.auto_awesome_rounded,
  Icons.church_rounded,
  Icons.gavel_rounded,
  Icons.waving_hand_rounded,
  Icons.savings_rounded,
  Icons.warning_amber_rounded,
  Icons.feedback_rounded,
  Icons.view_list_rounded,
];
