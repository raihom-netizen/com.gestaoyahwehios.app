import 'package:flutter/material.dart';

import 'agenda_module_icons.dart';
import 'anotacoes_module_icons.dart';
import 'calculator_module_icons.dart';
import 'produtividade_module_icons.dart';
import 'utilitarios_module_icons.dart';

/// Índices fixos dos módulos no [HomeShell] (ordem lógica interna).
abstract final class ShellModuleIndex {
  ShellModuleIndex._();

  static const int count = 13;

  static const int inicio = 0;
  static const int financeiro = 1;
  static const int escalas = 2;
  static const int compromissos = 3;
  static const int audiencias = 4;
  static const int produtividade = 5;
  static const int calculadora = 6;
  static const int meta = 7;
  static const int utilitarios = 8;
  static const int anotacoes = 9;
  static const int relatorios = 10;
  static const int conferencia = 11;
  static const int configuracoes = 12;

  /// Todos os índices válidos do shell.
  static const Set<int> all = {
    inicio,
    financeiro,
    escalas,
    compromissos,
    audiencias,
    produtividade,
    calculadora,
    meta,
    utilitarios,
    anotacoes,
    relatorios,
    conferencia,
    configuracoes,
  };

  /// Módulos que podem aparecer no rodapé (Conferência fica fora — sino/menu).
  static const Set<int> footerEligible = {
    inicio,
    financeiro,
    escalas,
    compromissos,
    audiencias,
    produtividade,
    calculadora,
    meta,
    utilitarios,
    anotacoes,
    relatorios,
    configuracoes,
  };

  /// Ordem fixa oficial do rodapé (sem arraste / personalização):
  /// Início / Financeiro / Compromissos / Escalas / Audiências /
  /// Calculadora / Produtividade / Utilitários / Meta /
  /// Anotações / Relatórios / Configurações.
  static const List<int> defaultFooterOrder = [
    inicio,
    financeiro,
    compromissos,
    escalas,
    audiencias,
    calculadora,
    produtividade,
    utilitarios,
    meta,
    anotacoes,
    relatorios,
    configuracoes,
  ];

  /// Ordem padrão sem Utilitários (build 4957507 v4) — migração automática.
  static const List<int> defaultFooterOrderV4 = [
    inicio,
    financeiro,
    compromissos,
    escalas,
    audiencias,
    calculadora,
    produtividade,
    meta,
    anotacoes,
    relatorios,
    configuracoes,
  ];

  /// Ordem padrão anterior (build 4957506–4957507) — migração automática para [defaultFooterOrder].
  static const List<int> defaultFooterOrderV3 = [
    inicio,
    financeiro,
    escalas,
    compromissos,
    audiencias,
    produtividade,
    calculadora,
    meta,
    utilitarios,
    anotacoes,
    relatorios,
    configuracoes,
  ];

  /// Ordem padrão antiga (antes de Financeiro em 2º) — só para migração automática.
  static const List<int> legacyDefaultFooterOrder = [
    inicio,
    escalas,
    compromissos,
    financeiro,
    audiencias,
    produtividade,
    calculadora,
    utilitarios,
    meta,
    anotacoes,
    relatorios,
    configuracoes,
  ];

  /// Converte índices gravados em versões anteriores (11 módulos) para o mapa novo.
  static int migrateLegacyIndex(int legacy) {
    switch (legacy) {
      case 2:
        return meta;
      case 3:
        return escalas;
      case 4:
        return calculadora;
      case 6:
        return relatorios;
      case 7:
        return audiencias;
      case 8:
        return anotacoes;
      case 9:
        return configuracoes;
      case 10:
        return utilitarios;
      case 0:
      case 1:
      case 5:
        return legacy;
      default:
        if (all.contains(legacy)) return legacy;
        return inicio;
    }
  }

  /// Detecta ordem do rodapé gravada antes da separação Compromissos/Audiências.
  static bool looksLikeLegacyFooterOrder(List<int> order) {
    if (order.contains(configuracoes) && !order.contains(conferencia)) {
      return true;
    }
    if (order.contains(7) && !order.contains(compromissos)) {
      return true;
    }
    return false;
  }

  static int migrateFooterIndex(int index) => migrateLegacyIndex(index);

  static List<int> migrateFooterOrder(List<int> raw) {
    if (!looksLikeLegacyFooterOrder(raw)) return raw;
    return raw.map(migrateLegacyIndex).toList();
  }
}

/// Metadados visuais por módulo (rodapé, drawer, título).
class ShellModuleMeta {
  const ShellModuleMeta({
    required this.title,
    required this.footerLabel,
    required this.footerLabelNarrow,
    required this.icon,
    required this.accent,
    required this.drawerAccent,
  });

  final String title;
  final String footerLabel;
  final String footerLabelNarrow;
  final IconData icon;
  final Color accent;
  final Color drawerAccent;

  static ShellModuleMeta of(int index, {bool footerNarrow = false}) {
    final m = _byIndex[index] ?? _byIndex[ShellModuleIndex.inicio]!;
    return m;
  }

  String footerLabelFor({required bool narrow}) =>
      narrow ? footerLabelNarrow : footerLabel;
}

const Map<int, ShellModuleMeta> kShellModuleMeta = {
  ShellModuleIndex.inicio: ShellModuleMeta(
    title: 'Início',
    footerLabel: 'Início',
    footerLabelNarrow: 'Início',
    icon: Icons.home_rounded,
    accent: Color(0xFF3B82F6),
    drawerAccent: Color(0xFF93C5FD),
  ),
  ShellModuleIndex.financeiro: ShellModuleMeta(
    title: 'Financeiro',
    footerLabel: 'Financeiro',
    footerLabelNarrow: 'Financ.',
    icon: Icons.account_balance_wallet_rounded,
    accent: Color(0xFF14B8A6),
    drawerAccent: Color(0xFF5EEAD4),
  ),
  ShellModuleIndex.escalas: ShellModuleMeta(
    title: 'Agenda/Escala',
    footerLabel: 'Agenda',
    footerLabelNarrow: 'Agenda',
    icon: Icons.event_note_rounded,
    accent: Color(0xFF4F46E5),
    drawerAccent: Color(0xFF818CF8),
  ),
  ShellModuleIndex.compromissos: ShellModuleMeta(
    title: 'Compromissos',
    footerLabel: 'Compromissos',
    footerLabelNarrow: 'Compr.',
    icon: AgendaModuleIcons.compromissoNav,
    accent: Color(0xFF2563EB),
    drawerAccent: Color(0xFF60A5FA),
  ),
  ShellModuleIndex.audiencias: ShellModuleMeta(
    title: 'Audiências',
    footerLabel: 'Audiências',
    footerLabelNarrow: 'Audiên.',
    icon: AgendaModuleIcons.audienciaNav,
    accent: Color(0xFF9333EA),
    drawerAccent: Color(0xFFC084FC),
  ),
  ShellModuleIndex.produtividade: ShellModuleMeta(
    title: 'Produtividade / Ocorrências',
    footerLabel: 'Produtividade',
    footerLabelNarrow: 'Produt.',
    icon: ProdutividadeModuleIcons.nav,
    accent: Color(0xFF10B981),
    drawerAccent: Color(0xFFC4B5FD),
  ),
  ShellModuleIndex.calculadora: ShellModuleMeta(
    title: 'Calculadora Banco de Horas',
    footerLabel: 'Calculadora',
    footerLabelNarrow: 'Calc.',
    icon: CalculatorModuleIcons.nav,
    accent: Color(0xFFF97316),
    drawerAccent: Color(0xFFFDBA74),
  ),
  ShellModuleIndex.meta: ShellModuleMeta(
    title: 'Meta',
    footerLabel: 'Meta',
    footerLabelNarrow: 'Meta',
    icon: Icons.flag_rounded,
    accent: Color(0xFFFBBF24),
    drawerAccent: Color(0xFFFBBF24),
  ),
  ShellModuleIndex.utilitarios: ShellModuleMeta(
    title: 'Utilitários',
    footerLabel: 'Utilitários',
    footerLabelNarrow: 'Util.',
    icon: UtilitariosModuleIcons.nav,
    accent: Color(0xFF0EA5E9),
    drawerAccent: Color(0xFFF472B6),
  ),
  ShellModuleIndex.anotacoes: ShellModuleMeta(
    title: 'Minhas Anotações',
    footerLabel: 'Anotações',
    footerLabelNarrow: 'Anot.',
    icon: AnotacoesModuleIcons.nav,
    accent: Color(0xFFEC4899),
    drawerAccent: Color(0xFF7DD3FC),
  ),
  ShellModuleIndex.relatorios: ShellModuleMeta(
    title: 'Relatórios',
    footerLabel: 'Relatórios',
    footerLabelNarrow: 'Relat.',
    icon: Icons.assessment_rounded,
    accent: Color(0xFF8B5CF6),
    drawerAccent: Color(0xFF86EFAC),
  ),
  ShellModuleIndex.conferencia: ShellModuleMeta(
    title: 'Conferência',
    footerLabel: 'Conferência',
    footerLabelNarrow: 'Confer.',
    icon: Icons.fact_check_rounded,
    accent: Color(0xFFEF4444),
    drawerAccent: Color(0xFFFCA5A5),
  ),
  ShellModuleIndex.configuracoes: ShellModuleMeta(
    title: 'Configurações',
    footerLabel: 'Configurações',
    footerLabelNarrow: 'Config.',
    icon: Icons.settings_rounded,
    accent: Color(0xFF64748B),
    drawerAccent: Color(0xFFCBD5E1),
  ),
};

final Map<int, ShellModuleMeta> _byIndex = kShellModuleMeta;
