import 'package:flutter/material.dart';

/// Ícone do módulo **Fornecedores** (menu + telas).
/// `storefront_rounded` pode renderizar vazio na web/PWA (subset Material / tree-shake).
const IconData kFornecedoresModuleIcon = Icons.local_shipping_rounded;

/// Ícone do módulo **Utilitários** (menu + cards).
const IconData kUtilitariosModuleIcon = Icons.widgets_rounded;

/// Label canónico — módulo dízimos/ofertas (painel, site público, divulgação).
const String kChurchDonationModuleLabel = 'Dízimos/Ofertas';
const String kChurchDonationModuleSubtitle = 'PIX e cartão Mercado Pago';
const String kChurchDonationPublicCtaCompact = 'Dízimos/Ofertas';
const String kChurchDonationPublicCtaFull = 'Dízimos/Ofertas — PIX/Cartão';

/// Entrada do menu lateral do painel da igreja ([IgrejaCleanShell]).
/// A ordem define os **índices** (`_selectedIndex`, cache de páginas, etc.).
/// [accent] — cor do módulo (chips do menu, rodapé, identidade visual moderna).
/// [subtitle] — descrição curta no cabeçalho mobile e no drawer (padrão WISDOMAPP).
class ChurchShellNavEntry {
  final IconData icon;
  final String label;
  final Color accent;
  final String subtitle;
  const ChurchShellNavEntry(
    this.icon,
    this.label,
    this.accent, {
    this.subtitle = '',
  });
}

/// Menu completo — única fonte para labels + ícones + cores + warmup de fonte Material na web.
const List<ChurchShellNavEntry> kChurchShellNavEntries = [
  ChurchShellNavEntry(
    Icons.insights_rounded,
    'Painel',
    Color(0xFF3B82F6),
    subtitle: 'Visão geral e atalhos da igreja',
  ),
  ChurchShellNavEntry(
    Icons.domain_rounded,
    'Cadastro da Igreja',
    Color(0xFF6366F1),
    subtitle: 'Logo, endereço e dados oficiais',
  ),
  ChurchShellNavEntry(
    Icons.settings_suggest_rounded,
    'Configurações',
    Color(0xFF64748B),
    subtitle: 'Conta, notificações e preferências',
  ),
  ChurchShellNavEntry(
    Icons.people_alt_rounded,
    'Membros',
    Color(0xFF14B8A6),
    subtitle: 'Cadastro, fotos e carteirinha',
  ),
  ChurchShellNavEntry(
    Icons.groups_3_rounded,
    'Departamentos',
    Color(0xFF8B5CF6),
    subtitle: 'Ministérios e equipes de serviço',
  ),
  ChurchShellNavEntry(
    Icons.person_add_alt_1_rounded,
    'Visitantes',
    Color(0xFFF59E0B),
    subtitle: 'Primeira visita e acompanhamento',
  ),
  ChurchShellNavEntry(
    Icons.badge_rounded,
    'Cargos',
    Color(0xFFF43F5E),
    subtitle: 'Funções e liderança ministerial',
  ),
  ChurchShellNavEntry(
    Icons.campaign_rounded,
    'Avisos',
    Color(0xFF0EA5E9),
    subtitle: 'Mural e comunicados oficiais',
  ),
  ChurchShellNavEntry(
    Icons.celebration_rounded,
    'Eventos',
    Color(0xFFF97316),
    subtitle: 'Cultos, programação e feed',
  ),
  ChurchShellNavEntry(
    Icons.volunteer_activism_rounded,
    'Pedidos de Oração',
    Color(0xFFEC4899),
    subtitle: 'Pedidos e acompanhamento pastoral',
  ),
  ChurchShellNavEntry(
    Icons.event_available_rounded,
    'Agenda',
    Color(0xFF2563EB),
    subtitle: 'Calendário e cultos fixos',
  ),
  ChurchShellNavEntry(
    Icons.edit_calendar_rounded,
    'Minha Escala',
    Color(0xFF06B6D4),
    subtitle: 'Seus compromissos na igreja',
  ),
  ChurchShellNavEntry(
    Icons.view_timeline_rounded,
    'Escala Geral',
    Color(0xFF14B8A6),
    subtitle: 'Escalas de todos os departamentos',
  ),
  ChurchShellNavEntry(
    Icons.badge_rounded,
    'Cartão membro',
    Color(0xFF10B981),
    subtitle: 'Carteirinha digital do membro',
  ),
  ChurchShellNavEntry(
    Icons.verified_rounded,
    'Certificados',
    Color(0xFF7C3AED),
    subtitle: 'Emissão e histórico de certificados',
  ),
  ChurchShellNavEntry(
    Icons.mail_rounded,
    'Cartas e transferências',
    Color(0xFFA78BFA),
    subtitle: 'Cartas oficiais e mudança de igreja',
  ),
  ChurchShellNavEntry(
    Icons.analytics_rounded,
    'Relatórios',
    Color(0xFFCA8A04),
    subtitle: 'Indicadores e exportações',
  ),
  ChurchShellNavEntry(
    Icons.feedback_rounded,
    'Informações',
    Color(0xFF38BDF8),
    subtitle: 'Ajuda, versão e atualizações do app',
  ),
  ChurchShellNavEntry(
    Icons.fact_check_rounded,
    'Aprovações rápidas',
    Color(0xFF22C55E),
    subtitle: 'Membros pendentes de aprovação',
  ),
  ChurchShellNavEntry(
    Icons.account_balance_wallet_rounded,
    'Financeiro',
    Color(0xFF16A34A),
    subtitle: 'Entradas, saídas e saldo',
  ),
  ChurchShellNavEntry(
    Icons.inventory_2_rounded,
    'Patrimônio',
    Color(0xFFD97706),
    subtitle: 'Bens e inventário da igreja',
  ),
  ChurchShellNavEntry(
    kFornecedoresModuleIcon,
    'Fornecedores',
    Color(0xFF475569),
    subtitle: 'Cadastro e compromissos',
  ),
  ChurchShellNavEntry(
    Icons.favorite_rounded,
    kChurchDonationModuleLabel,
    Color(0xFFDC2626),
    subtitle: kChurchDonationModuleSubtitle,
  ),
  ChurchShellNavEntry(
    Icons.forum_rounded,
    'YahwehChat',
    Color(0xFF0D9488),
    subtitle: 'Mensagens e grupos por departamento',
  ),
  ChurchShellNavEntry(
    kUtilitariosModuleIcon,
    'Utilitários',
    Color(0xFF9333EA),
    subtitle: 'PDF, fotos e compressão — 100% local',
  ),
];

/// Acentos derivados de [kChurchShellNavEntries] — login, marketing e Torre Master SaaS
/// (uma única fonte visual com o painel da igreja).
abstract final class ChurchShellAccentTokens {
  ChurchShellAccentTokens._();

  /// **Membros** — fluxo “Sou membro”.
  static Color get loginMembro => kChurchShellNavEntries[3].accent;

  /// **Cadastro da Igreja** — gestor, nova igreja, callouts de cadastro.
  static Color get loginGestor => kChurchShellNavEntries[1].accent;

  /// **Financeiro** — resumo de planos / mensalidades.
  static Color get loginPlanos => kChurchShellNavEntries[19].accent;

  /// **Painel** — tab Clientes na Torre Master.
  static Color get masterSaasClientes => kChurchShellNavEntries[0].accent;

  /// **Relatórios** — tab Negócio (métricas e visão executiva).
  static Color get masterSaasNegocio => kChurchShellNavEntries[16].accent;
}

/// Glifos extras usados em módulos (toolbar/banners) além do menu — manter na web.
/// Inclui ícones dos cards de [DepartmentsPage] (`_iconOptions`) e telas embutidas,
/// para builds **sem** `--no-tree-shake-icons` não exibirem quadrados vazios.
const List<IconData> kChurchShellNavMaterialIconExtras = [
  Icons.insights_rounded,
  Icons.domain_rounded,
  Icons.settings_suggest_rounded,
  Icons.people_alt_rounded,
  Icons.groups_3_rounded,
  Icons.person_add_alt_1_rounded,
  Icons.campaign_rounded,
  Icons.celebration_rounded,
  Icons.event_available_rounded,
  Icons.view_timeline_rounded,
  Icons.analytics_rounded,
  Icons.chat_rounded,
  Icons.forum_rounded,
  Icons.account_balance_wallet_rounded,
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
  kUtilitariosModuleIcon,
  Icons.widgets_rounded,
  Icons.picture_as_pdf_rounded,
  Icons.table_chart_rounded,
  Icons.grid_on_rounded,
  Icons.slideshow_rounded,
  Icons.compress_rounded,
  Icons.movie_creation_rounded,
  Icons.audio_file_rounded,
  Icons.merge_type_rounded,
  Icons.content_cut_rounded,
  Icons.draw_rounded,
  Icons.folder_zip_rounded,
  Icons.image_aspect_ratio_rounded,
];
