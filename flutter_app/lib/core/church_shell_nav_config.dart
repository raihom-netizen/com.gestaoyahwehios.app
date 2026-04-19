import 'package:flutter/material.dart';

/// Ícone do módulo **Fornecedores** (menu + telas).
/// `storefront_rounded` pode renderizar vazio na web/PWA (subset Material / tree-shake).
const IconData kFornecedoresModuleIcon = Icons.local_shipping_rounded;

/// Entrada do menu lateral do painel da igreja ([IgrejaCleanShell]).
/// A ordem define os **índices** (`_selectedIndex`, cache de páginas, etc.).
class ChurchShellNavEntry {
  final IconData icon;
  final String label;
  const ChurchShellNavEntry(this.icon, this.label);
}

/// Menu completo — única fonte para labels + ícones + warmup de fonte Material na web.
const List<ChurchShellNavEntry> kChurchShellNavEntries = [
  ChurchShellNavEntry(Icons.dashboard_rounded, 'Painel'),
  ChurchShellNavEntry(Icons.business_rounded, 'Cadastro da Igreja'),
  ChurchShellNavEntry(Icons.people_rounded, 'Membros'),
  ChurchShellNavEntry(Icons.groups_rounded, 'Departamentos'),
  ChurchShellNavEntry(Icons.person_add_rounded, 'Visitantes'),
  ChurchShellNavEntry(Icons.work_rounded, 'Cargos'),
  ChurchShellNavEntry(Icons.article_rounded, 'Mural de Avisos'),
  ChurchShellNavEntry(Icons.event_rounded, 'Mural de Eventos'),
  ChurchShellNavEntry(Icons.favorite_rounded, 'Pedidos de Oração'),
  ChurchShellNavEntry(Icons.calendar_today_rounded, 'Agenda'),
  ChurchShellNavEntry(Icons.edit_calendar_rounded, 'Minha Escala'),
  ChurchShellNavEntry(Icons.schedule_rounded, 'Escala Geral'),
  ChurchShellNavEntry(Icons.badge_rounded, 'Cartão do membro'),
  ChurchShellNavEntry(Icons.verified_rounded, 'Certificados'),
  ChurchShellNavEntry(Icons.article_rounded, 'Cartas e transferências'),
  ChurchShellNavEntry(Icons.bar_chart_rounded, 'Relatórios'),
  ChurchShellNavEntry(Icons.tune_rounded, 'Configurações'),
  /// `info_rounded` pode sair vazio na web (subset Material tree-shake); `feedback_rounded` cobre bem “informações / sugestões”.
  ChurchShellNavEntry(Icons.feedback_rounded, 'Informações'),
  ChurchShellNavEntry(Icons.fact_check_rounded, 'Aprovações rápidas'),
  /// Mesmo glifo usado no preset “Pastoral” em Departamentos — evita glifo ausente na web.
  ChurchShellNavEntry(Icons.church_rounded, 'Pastoral & comunicação'),
  ChurchShellNavEntry(Icons.payment_rounded, 'Financeiro'),
  ChurchShellNavEntry(Icons.inventory_2_rounded, 'Patrimônio'),
  ChurchShellNavEntry(kFornecedoresModuleIcon, 'Fornecedores'),
  ChurchShellNavEntry(Icons.card_giftcard_rounded, 'Doação'),
];

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
