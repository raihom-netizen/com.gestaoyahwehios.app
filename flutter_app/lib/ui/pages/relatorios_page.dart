import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';
import 'package:gestao_yahweh/utils/pdf_text_sanitize.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show sanitizeImageUrl;
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;
import 'package:gestao_yahweh/ui/pages/relatorio_gastos_fornecedores_page.dart';
import '../../services/app_permissions.dart';

/// Fecha no máximo uma rota (relatório sobre o painel). Nunca usa rootNavigator.
void _popUmaRotaRelatorio(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) nav.pop();
}

/// Chip de filtro com texto sempre legível (Material 3 / tema podem deixar label invisível quando não selecionado).
class _PremiumFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color accent;

  const _PremiumFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      showCheckmark: true,
      checkmarkColor: accent,
      selectedColor: accent.withValues(alpha: 0.2),
      backgroundColor: ThemeCleanPremium.cardBackground,
      side: BorderSide(
        color: selected ? accent : const Color(0xFFE2E8F4),
        width: selected ? 1.5 : 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          fontSize: 13,
          color: selected ? accent : ThemeCleanPremium.onSurface,
        ),
      ),
      selected: selected,
      onSelected: onSelected,
    );
  }
}

/// Módulo Relatórios: Membros (campos selecionáveis), Aniversariantes (dia/semana/mês/anual/período), Financeiro (se tiver permissão).
class RelatoriosPage extends StatelessWidget {
  final String tenantId;
  final String role;
  /// Gestor liberou financeiro para este membro (role membro).
  final bool? podeVerFinanceiro;
  /// Gestor liberou patrimônio para este membro (role membro).
  final bool? podeVerPatrimonio;
  /// Gestor liberou PDFs de membros/aniversariantes; senão só Relatório de Eventos.
  final bool? podeEmitirRelatoriosCompletos;
  final List<String>? permissions;
  /// Dentro do [IgrejaCleanShell]: sem AppBar duplicada no mobile e sem “voltar” que pareça sair do painel.
  final bool embeddedInShell;

  const RelatoriosPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.podeVerFinanceiro,
    this.podeVerPatrimonio,
    this.podeEmitirRelatoriosCompletos,
    this.permissions,
    this.embeddedInShell = false,
  });

  bool get _canFinance => AppPermissions.canViewFinance(
        role,
        memberCanViewFinance: podeVerFinanceiro,
        permissions: permissions,
      );
  bool get _canPatrimonio => AppPermissions.canViewPatrimonio(
        role,
        memberCanViewPatrimonio: podeVerPatrimonio,
        permissions: permissions,
      );

  /// Membro/visitante: só eventos, salvo gestor liberar ou permissão `relatorios`.
  bool get _canFullReports => AppPermissions.canEmitFullChurchReports(
        role,
        memberCanEmitFullReports: podeEmitirRelatoriosCompletos,
        permissions: permissions,
      );

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    final hideAppBarMobile = isMobile && (embeddedInShell || !Navigator.canPop(context));
    return Scaffold(
      primary: !embeddedInShell,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: hideAppBarMobile ? null : AppBar(
        elevation: 0,
        leading: Navigator.canPop(context) ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _popUmaRotaRelatorio(context), tooltip: 'Voltar', style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget))) : null,
        title: const Text('Relatórios', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: ThemeCleanPremium.churchPanelBodyGradient,
          ),
          child: ListView(
            padding: padding,
            children: [
              if (isMobile && !embeddedInShell) ...[
                Text('Relatórios', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
              ],
              if (AppPermissions.isRestrictedMember(role) && !_canFullReports) ...[
                Container(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      Expanded(
                        child: Text(
                          'Seu perfil permite apenas o Relatório de Eventos. '
                          'Para exportar membros, aniversariantes ou outros PDFs, o gestor pode liberar em seu cadastro (Membros → editar ficha).',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
              ],
            _ReportCard(
              icon: Icons.event_rounded,
              title: 'Relatório de Eventos',
              subtitle: 'Eventos ativos, confirmações de presença (RSVP). Filtros: diário, mensal, anual ou por período. Exportar PDF.',
              color: const Color(0xFF0EA5E9),
              onTap: () => _openRelatorioEventos(context),
            ),
            if (_canFullReports) ...[
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ReportCard(
                icon: Icons.people_rounded,
                title: 'Relatório de Membros',
                subtitle: 'Escolha os campos que deseja incluir e exporte em PDF.',
                color: ThemeCleanPremium.primary,
                onTap: () => _openRelatorioMembros(context),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ReportCard(
                icon: Icons.cake_rounded,
                title: 'Relatório de Aniversariantes',
                subtitle:
                    'Filtro Hoje/Semana/Mês/Personalizado/Ano, fotos, WhatsApp e PDF mural.',
                color: const Color(0xFFE11D48),
                onTap: () => _openRelatorioAniversariantes(context),
              ),
            ],
            if (_canFinance) ...[
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ReportCard(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Relatório Financeiro',
                subtitle:
                    'Dashboard com gráficos, tabela paginada, CSV e fechamento de mês em PDF.',
                color: const Color(0xFF059669),
                onTap: () => _openRelatorioFinanceiro(context),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ReportCard(
                icon: Icons.business_center_rounded,
                title: 'Fornecedores e prestadores',
                subtitle:
                    'Despesas e receitas por período, gráficos, PDF e exportação CSV.',
                color: const Color(0xFF0F766E),
                onTap: () => _openRelatorioGastosFornecedores(context),
              ),
            ],
            if (_canPatrimonio) ...[
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ReportCard(
                icon: Icons.inventory_2_rounded,
                title: 'Relatório de Patrimônio',
                subtitle: 'Bens ativos, inativos, por status. Exportar PDF completo.',
                color: const Color(0xFF7C3AED),
                onTap: () => _openRelatorioPatrimonio(context),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
        ),
      ),
    );
  }

  void _openRelatorioMembros(BuildContext context) {
    if (!_canFullReports) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RelatorioMembrosPage(tenantId: tenantId, role: role)));
  }

  void _openRelatorioAniversariantes(BuildContext context) {
    if (!_canFullReports) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RelatorioAniversariantesPage(tenantId: tenantId)));
  }

  void _openRelatorioFinanceiro(BuildContext context) {
    if (!_canFinance) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelatorioFinanceiroPage(tenantId: tenantId),
      ),
    );
  }

  void _openRelatorioGastosFornecedores(BuildContext context) {
    if (!_canFinance) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RelatorioGastosFornecedoresPage(tenantId: tenantId),
      ),
    );
  }

  void _openRelatorioPatrimonio(BuildContext context) {
    if (!_canPatrimonio) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RelatorioPatrimonioPage(tenantId: tenantId)));
  }

  void _openRelatorioEventos(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RelatorioEventosPage(tenantId: tenantId)));
  }
}

class _ReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ReportCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accentEnd = Color.lerp(color, const Color(0xFF0F172A), 0.28) ?? color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ThemeCleanPremium.hapticAction();
          onTap();
        },
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            color: ThemeCleanPremium.cardBackground,
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: color.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                color.withValues(alpha: 0.07),
                ThemeCleanPremium.cardBackground,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceLg,
              vertical: ThemeCleanPremium.spaceMd + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, accentEnd],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.75),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Relatório de Membros (seleção de campos) ────────────────────────────────
class _RelatorioMembrosPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const _RelatorioMembrosPage({required this.tenantId, required this.role});

  @override
  State<_RelatorioMembrosPage> createState() => _RelatorioMembrosPageState();
}

class _RelatorioMembrosPageState extends State<_RelatorioMembrosPage> {
  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _loadDepartamentos();
  }

  Future<void> _loadDepartamentos() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('departamentos')
          .get();
      if (mounted) {
        setState(() {
          _departamentos = snap.docs
              .map((d) => (
                    id: d.id,
                    name: churchDepartmentNameFromDoc(d),
                  ))
              .where((e) => e.name.isNotEmpty)
              .toList();
          _departamentos.sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          _deptsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _deptsLoaded = true);
    }
  }

  List<Map<String, dynamic>> _aplicarFiltros(List<Map<String, dynamic>> list) {
    var out = list;
    if (_busca.trim().isNotEmpty) {
      final q = _busca.trim().toLowerCase();
      out = out.where((m) {
        final nome = (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString().toLowerCase();
        final email = (m['EMAIL'] ?? m['email'] ?? '').toString().toLowerCase();
        return nome.contains(q) || email.contains(q);
      }).toList();
    }
    if (_filtroStatus != 'todos') {
      out = out.where((m) {
        final s = (m['STATUS'] ?? m['status'] ?? m['active'] ?? '').toString().toLowerCase();
        final inativo = s.contains('inativ') || s == 'inativo';
        return _filtroStatus == 'ativos' ? !inativo : inativo;
      }).toList();
    }
    if (_filtroGenero != 'todos') {
      out = out.where((m) {
        final s = (m['SEXO'] ?? m['sexo'] ?? m['genero'] ?? '').toString().toLowerCase();
        return _filtroGenero == 'masculino' ? (s.startsWith('m')) : s.startsWith('f');
      }).toList();
    }
    if (_filtroDepartamento != 'todos') {
      out = out.where((m) {
        final depts = m['DEPARTAMENTOS'] ?? m['departamentos'];
        if (depts is List) return depts.any((x) => x.toString() == _filtroDepartamento);
        final d = (m['departamento'] ?? m['DEPARTAMENTO'] ?? '').toString();
        return d == _filtroDepartamento || d == (_departamentos.where((e) => e.id == _filtroDepartamento).firstOrNull?.name ?? '');
      }).toList();
    }
    if (_filtroFaixaEtaria != 'todas') {
      out = out.where((m) {
        final idade = ageFromMemberData(m);
        if (idade == null) return _filtroFaixaEtaria == 'todas';
        switch (_filtroFaixaEtaria) {
          case 'criancas': return idade < 13;
          case 'adolescentes': return idade >= 13 && idade < 18;
          case 'adultos': return idade >= 18 && idade < 60;
          case 'idosos': return idade >= 60;
          default: return true;
        }
      }).toList();
    }
    return out;
  }

  static const _fieldOptions = [
    ('nome', 'Nome'),
    ('email', 'E-mail'),
    ('telefone', 'Telefone'),
    ('cpf', 'CPF'),
    ('dataNascimento', 'Data de nascimento'),
    ('sexo', 'Gênero'),
    ('departamento', 'Departamento'),
    ('faixaEtaria', 'Faixa etária'),
    ('status', 'Status'),
  ];
  final _selected = <String>{'nome', 'email', 'telefone', 'status'};
  String _filtroFaixaEtaria = 'todas'; // todas, criancas, adolescentes, adultos, idosos
  String _filtroDepartamento = 'todos';
  String _filtroGenero = 'todos'; // todos, masculino, feminino
  String _filtroStatus = 'todos'; // todos, ativos, inativos
  String _busca = '';
  List<({String id, String name})> _departamentos = [];
  bool _loading = false;
  bool _deptsLoaded = false;
  bool _pdfLandscape = false;

  CollectionReference<Map<String, dynamic>> get _members => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membros => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membersIgrejas => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membrosIgrejas => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');

  Future<List<Map<String, dynamic>>> _fetchMembers() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final snapM = await _members.limit(500).get();
    final snapMb = await _membros.limit(500).get();
    final snapMI = await _membersIgrejas.limit(500).get();
    final snapMbI = await _membrosIgrejas.limit(500).get();
    final seen = <String>{};
    final list = <Map<String, dynamic>>[];
    for (final d in snapM.docs) {
      if (seen.add(d.id)) list.add({...d.data(), 'id': d.id});
    }
    for (final d in snapMb.docs) {
      if (seen.add(d.id)) list.add({...d.data(), 'id': d.id});
    }
    for (final d in snapMI.docs) {
      if (seen.add(d.id)) list.add({...d.data(), 'id': d.id});
    }
    for (final d in snapMbI.docs) {
      if (seen.add(d.id)) list.add({...d.data(), 'id': d.id});
    }
    return list;
  }

  String _val(Map<String, dynamic> m, String key) {
    if (key == 'nome') return (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString();
    if (key == 'email') return (m['EMAIL'] ?? m['email'] ?? '').toString();
    if (key == 'telefone') return (m['TELEFONES'] ?? m['telefone'] ?? '').toString();
    if (key == 'cpf') return (m['CPF'] ?? m['cpf'] ?? '').toString();
    if (key == 'dataNascimento') {
      final t = m['DATA_NASCIMENTO'] ?? m['dataNascimento'] ?? m['birthDate'];
      if (t == null) return '';
      if (t is Timestamp) return DateFormat('dd/MM/yyyy').format(t.toDate());
      return t.toString();
    }
    if (key == 'sexo') {
      final s = (m['SEXO'] ?? m['sexo'] ?? '').toString().trim();
      if (s.isEmpty) return '';
      final sl = s.toLowerCase();
      if (sl.startsWith('m')) return 'Masculino';
      if (sl.startsWith('f')) return 'Feminino';
      return s;
    }
    if (key == 'faixaEtaria') {
      final idade = ageFromMemberData(m);
      if (idade == null) return '—';
      if (idade < 13) return 'Criança';
      if (idade < 18) return 'Adolescente';
      if (idade < 60) return 'Adulto';
      return 'Idoso';
    }
    if (key == 'departamento') {
      final depts = m['DEPARTAMENTOS'] ?? m['departamentos'];
      if (depts is List && depts.isNotEmpty) {
        final names = <String>[];
        for (final raw in depts) {
          final idStr = raw.toString().trim();
          if (idStr.isEmpty) continue;
          for (final e in _departamentos) {
            if (e.id == idStr) {
              names.add(e.name);
              break;
            }
          }
        }
        if (names.isNotEmpty) return names.join(', ');
      }
      return (m['departamento'] ?? m['DEPARTAMENTO'] ?? '').toString();
    }
    if (key == 'status') {
      final raw = (m['STATUS'] ?? m['status'] ?? '').toString().trim();
      if (raw.isEmpty) return '';
      return raw
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map((w) =>
              '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}')
          .join(' ');
    }
    return '';
  }

  /// Evita quebras de linha no meio de e-mail/telefone no PDF (coluna # e índice ficam legíveis).
  String _pdfSanitizeCell(String fieldKey, String value) {
    var s = value.trim();
    if (fieldKey == 'telefone') {
      s = s.replaceAll(RegExp(r'[\r\n]+'), ' ');
      s = s.replaceAll(RegExp(r' +'), ' ');
    } else if (fieldKey == 'email') {
      s = s.replaceAll(RegExp(r'[\r\n\t]+'), '');
      s = s.replaceAll(RegExp(r' +'), '');
      return pdfEmailBreakOpportunities(s);
    }
    return s;
  }

  Future<void> _exportPdf() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ao menos um campo.')));
      return;
    }
    setState(() => _loading = true);
    try {
      var list = await _fetchMembers();
      list = _aplicarFiltros(list);
      if (list.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum membro para exportar.')));
        return;
      }
      list.sort((a, b) {
        final na = (a['NOME_COMPLETO'] ?? a['nome'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final nb = (b['NOME_COMPLETO'] ?? b['nome'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        return na.compareTo(nb);
      });
      final keys = _fieldOptions.where((e) => _selected.contains(e.$1)).map((e) => e.$1).toList();
      final headers = [
        '#',
        ..._fieldOptions.where((e) => _selected.contains(e.$1)).map((e) => e.$2),
      ];
      final data = list.asMap().entries.map((e) {
        return [
          '${e.key + 1}',
          ...keys.map((k) => _pdfSanitizeCell(k, _val(e.value, k))),
        ];
      }).toList();

      final branding = await loadReportPdfBranding(widget.tenantId);
      final format = _pdfLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              'Relatório de Membros',
              branding: branding,
              extraLines: ['Total de membros: ${list.length}'],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            PdfSuperPremiumTheme.fromTextArray(
              headers: headers,
              data: data,
              accent: branding.accent,
              columnWidths:
                  PdfSuperPremiumTheme.columnWidthsMemberReport(keys),
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) await showPdfActions(context, bytes: bytes, filename: 'relatorio_membros.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = ThemeCleanPremium.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _popUmaRotaRelatorio(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: const Text('Relatório de Membros'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            _FilterSection(title: 'Busca', icon: Icons.search_rounded, color: color, child: TextField(
              decoration: const InputDecoration(hintText: 'Nome ou e-mail...', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) => setState(() => _busca = v),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Status', icon: Icons.person_rounded, color: color, child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['todos', 'ativos', 'inativos'].map((v) {
                final lbl = v == 'todos' ? 'Todos' : v == 'ativos' ? 'Ativos' : 'Inativos';
                return _PremiumFilterChip(
                  label: lbl,
                  selected: _filtroStatus == v,
                  accent: color,
                  onSelected: (x) => setState(() => _filtroStatus = x ? v : 'todos'),
                );
              }).toList(),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Gênero', icon: Icons.people_rounded, color: color, child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['todos', 'masculino', 'feminino'].map((v) {
                final lbl = v == 'todos' ? 'Todos' : v == 'masculino' ? 'Masculino' : 'Feminino';
                return _PremiumFilterChip(
                  label: lbl,
                  selected: _filtroGenero == v,
                  accent: color,
                  onSelected: (x) => setState(() => _filtroGenero = x ? v : 'todos'),
                );
              }).toList(),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Faixa etária', icon: Icons.cake_rounded, color: color, child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['todas', 'criancas', 'adolescentes', 'adultos', 'idosos'].map((v) {
                final lbl = v == 'todas' ? 'Todas' : v == 'criancas' ? 'Crianças (<13)' : v == 'adolescentes' ? 'Adolescentes (13-17)' : v == 'adultos' ? 'Adultos (18-59)' : 'Idosos (60+)';
                return _PremiumFilterChip(
                  label: lbl,
                  selected: _filtroFaixaEtaria == v,
                  accent: color,
                  onSelected: (x) => setState(() => _filtroFaixaEtaria = x ? v : 'todas'),
                );
              }).toList(),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Departamento', icon: Icons.business_rounded, color: color, child: _deptsLoaded
                ? DropdownButtonFormField<String>(
                    value: _filtroDepartamento,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    items: [const DropdownMenuItem(value: 'todos', child: Text('Todos'))]
                        ..addAll(_departamentos.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))),
                    onChanged: (v) => setState(() => _filtroDepartamento = v ?? 'todos'),
                  )
                : const Center(
                    child: SizedBox(
                      height: 48,
                      child: ChurchPanelLoadingBody(),
                    ),
                  )),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text('Campos a incluir no relatório:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ThemeCleanPremium.onSurfaceVariant)),
            const SizedBox(height: 12),
            ..._fieldOptions.map((e) => CheckboxListTile(
                  value: _selected.contains(e.$1),
                  onChanged: (v) => setState(() => v == true ? _selected.add(e.$1) : _selected.remove(e.$1)),
                  title: Text(e.$2),
                  controlAffinity: ListTileControlAffinity.leading,
                )),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            PremiumPdfOrientationBar(landscape: _pdfLandscape, onChanged: (v) => setState(() => _pdfLandscape = v)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _exportPdf,
              icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_loading ? 'Gerando...' : 'Exportar PDF'),
              style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Relatório de Aniversariantes (dia, semana, mês, anual, período) ───────────
class _RelatorioAniversariantesPage extends StatefulWidget {
  final String tenantId;

  const _RelatorioAniversariantesPage({required this.tenantId});

  @override
  State<_RelatorioAniversariantesPage> createState() => _RelatorioAniversariantesPageState();
}

class _RelatorioAniversariantesPageState extends State<_RelatorioAniversariantesPage> {
  /// 0=hoje, 1=semana, 2=mês, 3=personalizado, 4=anual (lista completa)
  int _filtro = 2;
  DateTime? _dataInicio;
  DateTime? _dataFim;
  bool _loading = false;
  bool _pdfLandscape = false;
  String _busca = '';
  int _page = 0;
  static const int _perPage = 15;
  List<Map<String, dynamic>> _todosMembros = [];
  bool _loadingMembros = true;
  String? _erroMembros;

  CollectionReference<Map<String, dynamic>> get _members => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membros => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membersIgrejas => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');
  CollectionReference<Map<String, dynamic>> get _membrosIgrejas => FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('membros');

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _carregarMembros();
  }

  Future<void> _carregarMembros() async {
    setState(() {
      _loadingMembros = true;
      _erroMembros = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snapM = await _members.limit(1000).get();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final snapMb = await _membros.limit(1000).get();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final snapMI = await _membersIgrejas.limit(1000).get();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final snapMbI = await _membrosIgrejas.limit(1000).get();
      final all = <Map<String, dynamic>>[];
      for (final d in snapM.docs) all.add({...d.data(), 'id': d.id});
      for (final d in snapMb.docs) {
        if (!all.any((e) => e['id'] == d.id)) all.add({...d.data(), 'id': d.id});
      }
      for (final d in snapMI.docs) {
        if (!all.any((e) => e['id'] == d.id)) all.add({...d.data(), 'id': d.id});
      }
      for (final d in snapMbI.docs) {
        if (!all.any((e) => e['id'] == d.id)) all.add({...d.data(), 'id': d.id});
      }
      if (mounted) {
        setState(() {
          _todosMembros = all;
          _loadingMembros = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erroMembros = e.toString();
          _loadingMembros = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _listaAniversariantesFiltrada() {
    DateTime? parseBirth(Map<String, dynamic> m) => birthDateFromMemberData(m);

    final now = DateTime.now();
    List<Map<String, dynamic>> filter(bool Function(DateTime b) fn) {
      return _todosMembros.where((m) {
        final b = parseBirth(m);
        return b != null && fn(b);
      }).toList();
    }

    List<Map<String, dynamic>> out;
    if (_filtro == 0) {
      out = filter((b) => b.month == now.month && b.day == now.day);
    } else if (_filtro == 1) {
      final end = now.add(const Duration(days: 7));
      out = filter((b) {
        final bThisYear = DateTime(now.year, b.month, b.day);
        return bThisYear.isAfter(now.subtract(const Duration(days: 1))) &&
            bThisYear.isBefore(end.add(const Duration(days: 1)));
      });
    } else if (_filtro == 2) {
      out = filter((b) => b.month == now.month);
    } else if (_filtro == 3 &&
        _dataInicio != null &&
        _dataFim != null) {
      out = filter((b) {
        final bThisYear = DateTime(now.year, b.month, b.day);
        return !bThisYear.isBefore(_dataInicio!) &&
            !bThisYear.isAfter(_dataFim!);
      });
    } else if (_filtro == 4) {
      out = filter((_) => true);
    } else {
      out = filter((b) => b.month == now.month);
    }

    out.sort((a, b) {
      final da = parseBirth(a);
      final db = parseBirth(b);
      if (da == null || db == null) return 0;
      final ca = da.month * 32 + da.day;
      final cb = db.month * 32 + db.day;
      return ca.compareTo(cb);
    });
    return out;
  }

  String _nome(Map<String, dynamic> m) => (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString();
  String _dataNasc(Map<String, dynamic> m) {
    final dt = birthDateFromMemberData(m);
    if (dt == null) return '';
    return DateFormat('dd/MM').format(dt);
  }

  String _telefoneRaw(Map<String, dynamic> m) {
    final t = (m['TELEFONE'] ?? m['telefone'] ?? m['CELULAR'] ?? m['celular'] ?? m['WHATSAPP'] ?? '').toString();
    return t.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _parabensWhatsApp(Map<String, dynamic> m) async {
    final nome = _nome(m).trim().split(' ').first;
    var d = _telefoneRaw(m);
    if (d.length == 11 && !d.startsWith('55')) d = '55$d';
    if (d.length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Telefone não encontrado ou incompleto para este membro.')),
        );
      }
      return;
    }
    final msg = Uri.encodeComponent(
      'Olá, $nome! Feliz aniversário! Que Deus abençoe seu novo ciclo. 🙏',
    );
    final uri = Uri.parse('https://wa.me/$d?text=$msg');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
      }
    }
  }

  Future<void> _exportPdf({bool mural = false}) async {
    if (_filtro == 3 && (_dataInicio == null || _dataFim == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Defina o período (data início e fim).')));
      return;
    }
    setState(() => _loading = true);
    try {
      final list = _listaAniversariantesFiltrada();
      final titulo = _filtro == 0
          ? 'Aniversariantes — Hoje'
          : _filtro == 1
              ? 'Aniversariantes — Semana'
              : _filtro == 2
                  ? 'Aniversariantes — Mês'
                  : _filtro == 4
                      ? 'Aniversariantes — Ano'
                      : 'Aniversariantes — Período';
      final branding = await loadReportPdfBranding(widget.tenantId);
      final format = _pdfLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              mural ? '$titulo — Mural' : titulo,
              branding: branding,
              extraLines: ['Total de aniversariantes: ${list.length}'],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) {
            if (list.isEmpty) {
              return [
                pw.Center(
                    child: pw.Padding(
                        padding: const pw.EdgeInsets.all(24),
                        child: pw.Text('Nenhum aniversariante no período.',
                            style: const pw.TextStyle(fontSize: 12)))),
              ];
            }
            if (mural) {
              final byDay = <int, List<Map<String, dynamic>>>{};
              for (final m in list) {
                final b = birthDateFromMemberData(m);
                if (b == null) continue;
                byDay.putIfAbsent(b.day, () => []).add(m);
              }
              final dias = byDay.keys.toList()..sort();
              final blocks = <pw.Widget>[];
              var seq = 1;
              for (final d in dias) {
                blocks.add(pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
                  child: pw.Text(
                    'Dia $d',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800),
                  ),
                ));
                final sub = byDay[d]!
                  ..sort((a, b) => _nome(a).compareTo(_nome(b)));
                blocks.add(
                  PdfSuperPremiumTheme.fromTextArray(
                    headers: const ['#', 'Nome', 'Nasc.', 'Idade'],
                    data: sub.map((m) {
                      final b = birthDateFromMemberData(m)!;
                      final ref = DateTime.now();
                      final idade = ageInYearsAt(b, ref);
                      return [
                        '${seq++}',
                        _nome(m),
                        _dataNasc(m),
                        '$idade anos',
                      ];
                    }).toList(),
                    accent: branding.accent,
                    columnWidths:
                        PdfSuperPremiumTheme.columnWidthsAniversariantesSimples,
                  ),
                );
              }
              return blocks;
            }
            return [
              PdfSuperPremiumTheme.fromTextArray(
                headers: const [
                  '#',
                  'Nome',
                  'Data (dia/mês)',
                  'Idade (atual)'
                ],
                data: list.asMap().entries.map((e) {
                  final m = e.value;
                  final b = birthDateFromMemberData(m);
                  final idade = b == null
                      ? '—'
                      : '${ageInYearsAt(b, DateTime.now())} anos';
                  return ['${e.key + 1}', _nome(m), _dataNasc(m), idade];
                }).toList(),
                accent: branding.accent,
                columnWidths:
                    PdfSuperPremiumTheme.columnWidthsAniversariantesSimples,
              ),
            ];
          },
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) {
        await showPdfActions(
          context,
          bytes: bytes,
          filename: mural
              ? 'aniversariantes_mural.pdf'
              : 'relatorio_aniversariantes.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF. Tente novamente.'),
            action: SnackBarAction(label: 'Tentar de novo', onPressed: () => _exportPdf()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _listaAniversariantesFiltrada();
    final q = _busca.trim().toLowerCase();
    final filtradaBusca = q.isEmpty
        ? lista
        : lista
            .where((m) => _nome(m).toLowerCase().contains(q))
            .toList();
    final totalP = filtradaBusca.isEmpty
        ? 1
        : (filtradaBusca.length / _perPage).ceil();
    var pg = _page;
    if (pg >= totalP) pg = totalP - 1;
    if (pg < 0) pg = 0;
    final slice =
        filtradaBusca.skip(pg * _perPage).take(_perPage).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _popUmaRotaRelatorio(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                  ThemeCleanPremium.minTouchTarget)),
        ),
        title: const Text('Aniversariantes'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
                minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget)),
            onPressed: _loadingMembros ? null : _carregarMembros,
          ),
        ],
      ),
      body: SafeArea(
        child: _erroMembros != null && _todosMembros.isEmpty
            ? ChurchPanelErrorBody(
                title: 'Não foi possível carregar os membros',
                error: _erroMembros,
                onRetry: _carregarMembros,
              )
            : _loadingMembros
                ? const Center(child: ChurchPanelLoadingBody())
                : ListView(
                    padding: ThemeCleanPremium.pagePadding(context),
                    children: [
                      Text(
                        'Filtro inteligente',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                              value: 0,
                              label: Text('Hoje'),
                              icon: Icon(Icons.wb_sunny_outlined, size: 18)),
                          ButtonSegment(
                              value: 1,
                              label: Text('Semana'),
                              icon: Icon(Icons.date_range_outlined, size: 18)),
                          ButtonSegment(
                              value: 2,
                              label: Text('Mês'),
                              icon: Icon(Icons.calendar_month_outlined,
                                  size: 18)),
                          ButtonSegment(
                              value: 3,
                              label: Text('Personalizado'),
                              icon: Icon(Icons.tune_rounded, size: 18)),
                          ButtonSegment(
                              value: 4,
                              label: Text('Ano'),
                              icon: Icon(Icons.calendar_today_outlined,
                                  size: 18)),
                        ],
                        selected: {_filtro},
                        onSelectionChanged: (s) {
                          final v = s.first;
                          setState(() {
                            _filtro = v;
                            _page = 0;
                          });
                        },
                        multiSelectionEnabled: false,
                        emptySelectionAllowed: false,
                      ),
                      if (_filtro == 3) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data início'),
                          subtitle: Text(_dataInicio == null
                              ? 'Toque para escolher'
                              : DateFormat('dd/MM/yyyy')
                                  .format(_dataInicio!)),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setState(() {
                                _dataInicio = d;
                                _page = 0;
                              });
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Data fim'),
                          subtitle: Text(_dataFim == null
                              ? 'Toque para escolher'
                              : DateFormat('dd/MM/yyyy').format(_dataFim!)),
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _dataFim ?? DateTime.now(),
                              firstDate: _dataInicio ?? DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setState(() {
                                _dataFim = d;
                                _page = 0;
                              });
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm),
                          ),
                        ),
                        onChanged: (v) => setState(() {
                          _busca = v;
                          _page = 0;
                        }),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${filtradaBusca.length} aniversariante(s) no filtro',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (slice.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Ninguém neste filtro. Ajuste o período ou a busca.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        ...slice.map((m) {
                          final b = birthDateFromMemberData(m);
                          final idade = b == null
                              ? null
                              : ageInYearsAt(b, DateTime.now());
                          final mid = (m['id'] ?? '').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              leading: FotoMembroWidget(
                                size: ThemeCleanPremium.minTouchTarget,
                                tenantId: widget.tenantId,
                                memberId: mid.isNotEmpty ? mid : null,
                                memberData: m,
                              ),
                              title: Text(
                                _nome(m),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${_dataNasc(m)}${idade != null ? ' • $idade anos' : ''}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Parabéns no WhatsApp',
                                icon: Icon(Icons.chat_rounded,
                                    color: Colors.green.shade600),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(
                                      ThemeCleanPremium.minTouchTarget,
                                      ThemeCleanPremium.minTouchTarget),
                                ),
                                onPressed: () => _parabensWhatsApp(m),
                              ),
                            ),
                          );
                        }),
                      if (totalP > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: pg <= 0
                                  ? null
                                  : () => setState(() => _page = pg - 1),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Text('Página ${pg + 1} de $totalP'),
                            IconButton(
                              onPressed: pg >= totalP - 1
                                  ? null
                                  : () => setState(() => _page = pg + 1),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      const SizedBox(height: ThemeCleanPremium.spaceLg),
                      PremiumPdfOrientationBar(
                          landscape: _pdfLandscape,
                          onChanged: (v) => setState(() => _pdfLandscape = v)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _loading ? null : () => _exportPdf(),
                            icon: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.picture_as_pdf_rounded),
                            label: Text(
                                _loading ? 'Gerando...' : 'Exportar PDF'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 16),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => _exportPdf(mural: true),
                            icon: const Icon(Icons.grid_on_rounded),
                            label: const Text('PDF mural (por dia)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ThemeCleanPremium.primary,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
      ),
    );
  }
}

// ─── Relatório Financeiro (filtros completos: período, tipo, categoria, conta, aberta/paga) ─
Map<String, dynamic> _financeSummaryCompute(Map<String, dynamic> input) {
  final rowsRaw = (input['rows'] as List).cast<Map>();
  final filtroTipo = (input['filtroTipo'] ?? 'todos').toString();
  final filtroCategoria = (input['filtroCategoria'] ?? 'todas').toString();
  final filtroConta = (input['filtroConta'] ?? 'todas').toString();
  final filtroStatusDespesa = (input['filtroStatusDespesa'] ?? 'todas').toString();
  final contaLabels = <String, String>{};
  final rawLabels = input['contaLabels'];
  if (rawLabels is Map) {
    for (final e in rawLabels.entries) {
      contaLabels[e.key.toString()] = e.value.toString();
    }
  }

  /// Visão do mês completo (ignora filtros da tabela) — gráficos de BI.
  double dizimosMes = 0;
  double ofertasMes = 0;
  final gastosPorCategoriaMes = <String, double>{};
  for (final raw in rowsRaw) {
    final mx = Map<String, dynamic>.from(raw.cast<String, dynamic>());
    final tipo0 = (mx['tipo'] ?? '').toString().toLowerCase();
    final categoria0 = (mx['categoria'] ?? '').toString();
    final valor0 = (mx['valor'] is num) ? (mx['valor'] as num).toDouble() : 0.0;
    if (tipo0 == 'transferencia') continue;
    if (tipo0.contains('entrada') || tipo0.contains('receita')) {
      final cl = categoria0.toLowerCase();
      if (cl.contains('dízim') || cl.contains('dizim')) {
        dizimosMes += valor0;
      } else if (cl.contains('oferta')) {
        ofertasMes += valor0;
      }
    } else if (tipo0.contains('saida') || tipo0.contains('despesa')) {
      final cat = categoria0.isEmpty ? 'Sem categoria' : categoria0;
      gastosPorCategoriaMes[cat] = (gastosPorCategoriaMes[cat] ?? 0) + valor0;
    }
  }
  final gastosMesOrdenados = gastosPorCategoriaMes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final outRows = <Map<String, dynamic>>[];
  final saidasPorCategoria = <String, double>{};
  double entradas = 0;
  double saidas = 0;
  double aReceberPendente = 0;
  double aPagarPendente = 0;
  final porConta = <String, Map<String, double>>{};

  for (final raw in rowsRaw) {
    final m = Map<String, dynamic>.from(raw.cast<String, dynamic>());
    final tipo = (m['tipo'] ?? '').toString().toLowerCase();
    final categoria = (m['categoria'] ?? '').toString();
    final contaOrigemId = (m['contaOrigemId'] ?? '').toString();
    final contaDestinoId = (m['contaDestinoId'] ?? '').toString();
    final statusPagamento = (m['statusPagamento'] ?? '').toString().toLowerCase();
    final pago = m['pago'] == true;

    if (filtroTipo != 'todos') {
      if (filtroTipo == 'receitas' && !(tipo.contains('entrada') || tipo.contains('receita'))) continue;
      if (filtroTipo == 'despesas' && !(tipo.contains('saida') || tipo.contains('despesa'))) continue;
      if (filtroTipo == 'transferencias' && tipo != 'transferencia') continue;
    }
    if (filtroCategoria != 'todas' && categoria != filtroCategoria) continue;
    if (filtroConta != 'todas' && contaOrigemId != filtroConta && contaDestinoId != filtroConta) continue;
    if (filtroStatusDespesa != 'todas' && (tipo.contains('saida') || tipo.contains('despesa'))) {
      final isPago = pago || statusPagamento.contains('pago') || statusPagamento == 'paga';
      if (filtroStatusDespesa == 'paga' && !isPago) continue;
      if (filtroStatusDespesa == 'aberta' && isPago) continue;
    }

    final valor = (m['valor'] is num) ? (m['valor'] as num).toDouble() : 0.0;
    if (tipo == 'transferencia') {
      outRows.add(m);
      continue;
    }
    final rowPolicy = <String, dynamic>{
      'type': m['tipo'] ?? '',
      'recebimentoConfirmado': m['recebimentoConfirmado'],
      'pagamentoConfirmado': m['pagamentoConfirmado'],
    };
    if (financeLancamentoPendenteRecebimento(rowPolicy)) {
      aReceberPendente += valor;
    }
    if (financeLancamentoPendentePagamento(rowPolicy)) {
      aPagarPendente += valor;
    }
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      entradas += valor;
      final cid = contaDestinoId;
      if (cid.isNotEmpty) {
        porConta.putIfAbsent(cid, () => {'entradas': 0.0, 'saidas': 0.0});
        porConta[cid]!['entradas'] =
            (porConta[cid]!['entradas'] ?? 0) + valor;
      }
    } else {
      saidas += valor;
      final cat = categoria.isEmpty ? 'Sem categoria' : categoria;
      saidasPorCategoria[cat] = (saidasPorCategoria[cat] ?? 0) + valor;
      final cid = contaOrigemId;
      if (cid.isNotEmpty) {
        porConta.putIfAbsent(cid, () => {'entradas': 0.0, 'saidas': 0.0});
        porConta[cid]!['saidas'] = (porConta[cid]!['saidas'] ?? 0) + valor;
      }
    }
    outRows.add(m);
  }

  outRows.sort((a, b) => ((b['createdAtMs'] ?? 0) as int).compareTo((a['createdAtMs'] ?? 0) as int));
  final saldo = entradas - saidas;
  final totalSaidasForPct = saidas <= 0 ? 1.0 : saidas;
  final categoriasOrdenadas = saidasPorCategoria.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final categoriasResumo = categoriasOrdenadas.map((e) {
    final pct = (e.value / totalSaidasForPct) * 100;
    return {
      'categoria': e.key,
      'valor': e.value,
      'percentual': pct,
    };
  }).toList();

  final porContaLista = porConta.entries.map((e) {
    final inn = ((e.value['entradas'] ?? 0) as num).toDouble();
    final out = ((e.value['saidas'] ?? 0) as num).toDouble();
    final liq = inn - out;
    final id = e.key;
    return {
      'id': id,
      'nome': (contaLabels[id] ?? id).toString(),
      'entradas': inn,
      'saidas': out,
      'liquido': liq,
    };
  }).toList()
    ..sort((a, b) => ((b['liquido'] as num).toDouble().abs())
        .compareTo((a['liquido'] as num).toDouble().abs()));

  final fluxoPrevisto = saldo + aReceberPendente - aPagarPendente;

  return {
    'rows': outRows,
    'entradas': entradas,
    'saidas': saidas,
    'saldo': saldo,
    'aReceberPendente': aReceberPendente,
    'aPagarPendente': aPagarPendente,
    'fluxoPrevisto': fluxoPrevisto,
    'porConta': porContaLista,
    'categoriasResumo': categoriasResumo,
    'dizimosMes': dizimosMes,
    'ofertasMes': ofertasMes,
    'gastosPorCategoriaMes': gastosMesOrdenados
        .map((e) => {'categoria': e.key, 'valor': e.value})
        .toList(),
  };
}

/// Modo de período do relatório financeiro (mês, ano civil ou intervalo).
enum _FinancePeriodMode { month, fullYear, custom }

/// Série temporal para gráfico de linhas (entradas x saídas no período filtrado).
class _FinanceEvolucao {
  final List<String> labels;
  final List<double> entradas;
  final List<double> saidas;

  const _FinanceEvolucao({
    required this.labels,
    required this.entradas,
    required this.saidas,
  });

  bool get isEffectivelyEmpty {
    if (labels.isEmpty) return true;
    double t = 0;
    for (final v in entradas) {
      t += v;
    }
    for (final v in saidas) {
      t += v;
    }
    return t < 0.0001;
  }
}

_FinanceEvolucao _computeFinanceEvolucao(
  List<Map<String, dynamic>> rows,
  _FinancePeriodMode mode,
  DateTime inicio,
  DateTime fim,
) {
  final inicioD = DateTime(inicio.year, inicio.month, inicio.day);
  final fimD = DateTime(fim.year, fim.month, fim.day);
  final spanDays = fimD.difference(inicioD).inDays + 1;

  late final int n;
  late final bool monthly;
  if (mode == _FinancePeriodMode.fullYear) {
    monthly = true;
    n = 12;
  } else if (mode == _FinancePeriodMode.month) {
    monthly = false;
    n = DateTime(inicio.year, inicio.month + 1, 0).day;
  } else {
    monthly = spanDays > 90;
    n = monthly
        ? (fim.year - inicio.year) * 12 + (fim.month - inicio.month) + 1
        : spanDays;
  }

  final ent = List<double>.filled(n, 0);
  final sai = List<double>.filled(n, 0);

  for (final m in rows) {
    final tipo = (m['tipo'] ?? '').toString().toLowerCase();
    if (tipo == 'transferencia') continue;
    final ms = (m['createdAtMs'] ?? 0) as int;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final valor = (m['valor'] is num) ? (m['valor'] as num).toDouble() : 0.0;
    var idx = -1;
    if (mode == _FinancePeriodMode.fullYear) {
      if (dt.year == inicio.year) idx = dt.month - 1;
    } else if (mode == _FinancePeriodMode.month) {
      if (dt.year == inicio.year && dt.month == inicio.month) {
        idx = dt.day - 1;
      }
    } else if (monthly) {
      idx = (dt.year - inicio.year) * 12 + (dt.month - inicio.month);
      if (idx < 0 || idx >= n) idx = -1;
    } else {
      idx = DateTime(dt.year, dt.month, dt.day).difference(inicioD).inDays;
      if (idx < 0 || idx >= n) idx = -1;
    }
    if (idx < 0) continue;
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      ent[idx] += valor;
    } else if (tipo.contains('saida') || tipo.contains('despesa')) {
      sai[idx] += valor;
    }
  }

  final labels = <String>[];
  if (monthly) {
    if (mode == _FinancePeriodMode.fullYear) {
      const ab = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      labels.addAll(ab);
    } else {
      for (var i = 0; i < n; i++) {
        final d = DateTime(inicio.year, inicio.month + i);
        labels.add(DateFormat('MMM/yy', 'pt_BR').format(d));
      }
    }
  } else {
    for (var i = 0; i < n; i++) {
      final d = inicioD.add(Duration(days: i));
      labels.add('${d.day}/${d.month}');
    }
  }

  return _FinanceEvolucao(labels: labels, entradas: ent, saidas: sai);
}

/// BI financeiro no cliente (Firestore `igrejas/{id}/finance`).
/// Igrejas muito grandes (ex.: milhares de lançamentos/mês) podem evoluir para
/// agregação via Cloud Function para não sobrecarregar o dispositivo.
///
/// [embeddedInFinanceModule]: quando true, usado na aba «Relatórios» do módulo
/// Financeiro — sem AppBar próprio e com [onEmbeddedBackToResumo] para voltar ao resumo.
class RelatorioFinanceiroPage extends StatefulWidget {
  final String tenantId;
  final bool embeddedInFinanceModule;
  final VoidCallback? onEmbeddedBackToResumo;

  const RelatorioFinanceiroPage({
    super.key,
    required this.tenantId,
    this.embeddedInFinanceModule = false,
    this.onEmbeddedBackToResumo,
  });

  @override
  State<RelatorioFinanceiroPage> createState() =>
      RelatorioFinanceiroPageState();
}

class RelatorioFinanceiroPageState extends State<RelatorioFinanceiroPage> {
  late int _mes;
  late int _ano;
  String _filtroTipo = 'todos'; // todos, receitas, despesas, transferencias
  String _filtroCategoria = 'todas';
  String _filtroConta = 'todas';
  String _filtroStatusDespesa = 'todas'; // todas, aberta, paga
  List<String> _categorias = [];
  List<({String id, String nome})> _contas = [];
  bool _loading = false;
  bool _initLoaded = false;
  bool _pdfLandscape = false;
  String _buscaLancamentos = '';
  int _pageLancamentos = 0;
  static const int _rowsPerPageLancamentos = 12;
  _FinancePeriodMode _periodMode = _FinancePeriodMode.month;
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  DocumentReference<Map<String, dynamic>> get _tenantRef =>
      FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId);

  bool get _embedded => widget.embeddedInFinanceModule;

  Future<void> _loadCategoriasContas() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final catsReceita = await _tenantRef.collection('categorias_receitas').orderBy('nome').get();
    final catsDespesa = await _tenantRef.collection('categorias_despesas').orderBy('nome').get();
    final cats = <String>{};
    for (final d in catsReceita.docs) cats.add((d.data()['nome'] ?? '').toString());
    for (final d in catsDespesa.docs) cats.add((d.data()['nome'] ?? '').toString());
    final contasSnap = await _tenantRef.collection('contas').orderBy('nome').get();
    final contas = contasSnap.docs.map((d) => (id: d.id, nome: (d.data()['nome'] ?? '').toString())).where((e) => e.nome.isNotEmpty).toList();
    if (mounted) setState(() {
      _categorias = cats.toList()..sort();
      _contas = contas;
      _initLoaded = true;
    });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mes = now.month;
    _ano = now.year;
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _loadCategoriasContas();
  }

  ({DateTime inicio, DateTime fim}) _periodoSelecionado() {
    switch (_periodMode) {
      case _FinancePeriodMode.month:
        final inicio = DateTime(_ano, _mes, 1);
        final fim = DateTime(_ano, _mes + 1, 0, 23, 59, 59);
        return (inicio: inicio, fim: fim);
      case _FinancePeriodMode.fullYear:
        return (
          inicio: DateTime(_ano, 1, 1),
          fim: DateTime(_ano, 12, 31, 23, 59, 59),
        );
      case _FinancePeriodMode.custom:
        final now = DateTime.now();
        var a = _customRangeStart ?? DateTime(_ano, _mes, 1);
        var b = _customRangeEnd ?? DateTime(_ano, _mes + 1, 0);
        var inicio = DateTime(a.year, a.month, a.day);
        var fim = DateTime(b.year, b.month, b.day, 23, 59, 59);
        if (inicio.isAfter(fim)) {
          final t = inicio;
          inicio = DateTime(fim.year, fim.month, fim.day);
          fim = DateTime(t.year, t.month, t.day, 23, 59, 59);
        }
        if (fim.isAfter(DateTime(now.year + 1, 12, 31))) {
          fim = DateTime(now.year + 1, 12, 31, 23, 59, 59);
        }
        return (inicio: inicio, fim: fim);
    }
  }

  String _periodoLabelHumano() {
    final p = _periodoSelecionado();
    switch (_periodMode) {
      case _FinancePeriodMode.month:
        return DateFormat('MM/yyyy').format(p.inicio);
      case _FinancePeriodMode.fullYear:
        return 'Ano ${_ano}';
      case _FinancePeriodMode.custom:
        return '${DateFormat('dd/MM/yyyy').format(p.inicio)} — ${DateFormat('dd/MM/yyyy').format(p.fim)}';
    }
  }

  String _fechamentoPdfFilename() {
    final p = _periodoSelecionado();
    switch (_periodMode) {
      case _FinancePeriodMode.month:
        return 'fechamento_${_ano}_${_mes.toString().padLeft(2, '0')}.pdf';
      case _FinancePeriodMode.fullYear:
        return 'fechamento_ano_${_ano}.pdf';
      case _FinancePeriodMode.custom:
        return 'fechamento_${DateFormat('yyyyMMdd').format(p.inicio)}_${DateFormat('yyyyMMdd').format(p.fim)}.pdf';
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final start = _customRangeStart ?? DateTime(_ano, _mes, 1);
    final end = _customRangeEnd ?? DateTime(_ano, _mes + 1, 0);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: start, end: end),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF059669),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: ThemeCleanPremium.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _periodMode = _FinancePeriodMode.custom;
      _customRangeStart = range.start;
      _customRangeEnd = range.end;
      _pageLancamentos = 0;
    });
  }

  Future<List<Map<String, dynamic>>> _queryFinanceRows() async {
    final p = _periodoSelecionado();
    final snap = await _tenantRef
        .collection('finance')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(p.inicio))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(p.fim))
        .orderBy('createdAt', descending: true)
        .limit(2000)
        .get();
    return snap.docs.map((d) {
      final m = d.data();
      final ts = m['createdAt'];
      final created = ts is Timestamp ? ts.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
      final valorRaw = m['amount'] ?? m['valor'] ?? 0;
      final valor = valorRaw is num ? valorRaw.toDouble() : 0.0;
      return {
        'id': d.id,
        'createdAtMs': created.millisecondsSinceEpoch,
        'tipo': (m['type'] ?? m['tipo'] ?? '').toString(),
        'categoria': (m['categoria'] ?? '').toString(),
        'descricao': (m['descricao'] ?? m['anotacoes'] ?? '').toString(),
        'valor': valor,
        'contaOrigemId': (m['contaOrigemId'] ?? '').toString(),
        'contaDestinoId': (m['contaDestinoId'] ?? '').toString(),
        'pago': m['pago'] == true,
        'statusPagamento': (m['statusPagamento'] ?? m['status'] ?? '').toString(),
        'comprovanteUrl': (m['comprovanteUrl'] ?? '').toString(),
        'recebimentoConfirmado': m['recebimentoConfirmado'],
        'pagamentoConfirmado': m['pagamentoConfirmado'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> _loadFinanceSummary() async {
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final rows = await _queryFinanceRows();
    final contaLabels = <String, String>{
      for (final c in _contas) c.id: c.nome,
    };
    return compute(_financeSummaryCompute, {
      'rows': rows,
      'filtroTipo': _filtroTipo,
      'filtroCategoria': _filtroCategoria,
      'filtroConta': _filtroConta,
      'filtroStatusDespesa': _filtroStatusDespesa,
      'contaLabels': contaLabels,
    });
  }

  Future<Uint8List?> _loadSignerSignatureBytes(String rawUrl) async {
    final url = sanitizeImageUrl(rawUrl.trim());
    if (url.isEmpty) return null;
    final b = await ImageHelper.getBytesFromUrlOrNull(
      url,
      timeout: const Duration(seconds: 14),
    );
    if (b == null || b.length < 24) return null;
    return b;
  }

  Future<({
    String leftName,
    String rightName,
    Uint8List? leftSig,
    Uint8List? rightSig,
    bool showDigital
  })?> _pickFinanceReportSigners() async {
    final snap = await _tenantRef.collection('membros').get();
    final members = snap.docs
        .map((d) {
          final m = d.data();
          final nome = (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
              .toString()
              .trim();
          final cargo = (m['CARGO'] ?? m['FUNCAO'] ?? m['cargo'] ?? '')
              .toString()
              .trim();
          final assinatura =
              (m['assinaturaUrl'] ?? m['assinatura_url'] ?? '').toString().trim();
          return (
            id: d.id,
            nome: nome,
            cargo: cargo,
            assinatura: assinatura,
          );
        })
        .where((e) => e.nome.isNotEmpty)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    if (!mounted) return null;
    String? leftId;
    String? rightId;
    var showDigital = true;

    return showDialog<
        ({
          String leftName,
          String rightName,
          Uint8List? leftSig,
          Uint8List? rightSig,
          bool showDigital
        })>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          DropdownButtonFormField<String> signerField({
            required String label,
            required String? value,
            required ValueChanged<String?> onChanged,
          }) {
            return DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('— Não definido —'),
                ),
                ...members.map(
                  (e) => DropdownMenuItem<String>(
                    value: e.id,
                    child: Text(
                      e.cargo.isEmpty ? e.nome : '${e.nome} — ${e.cargo}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: onChanged,
            );
          }

          return AlertDialog(
            title: const Text('Assinaturas do relatório'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  signerField(
                    label: 'Nome da caixa esquerda',
                    value: leftId,
                    onChanged: (v) => setDlg(() => leftId = v),
                  ),
                  const SizedBox(height: 10),
                  signerField(
                    label: 'Nome da caixa direita',
                    value: rightId,
                    onChanged: (v) => setDlg(() => rightId = v),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    value: showDigital,
                    onChanged: (v) => setDlg(() => showDigital = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Carregar assinatura digital'),
                    subtitle: const Text(
                        'Desative para gerar apenas linhas para assinatura manual.'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  ({String id, String nome, String cargo, String assinatura})? byId(
                      String? id) {
                    if (id == null || id.isEmpty) return null;
                    for (final e in members) {
                      if (e.id == id) return e;
                    }
                    return null;
                  }

                  final left = byId(leftId);
                  final right = byId(rightId);
                  Uint8List? leftSig;
                  Uint8List? rightSig;
                  if (showDigital) {
                    if (left != null && left.assinatura.isNotEmpty) {
                      leftSig = await _loadSignerSignatureBytes(left.assinatura);
                    }
                    if (right != null && right.assinatura.isNotEmpty) {
                      rightSig = await _loadSignerSignatureBytes(right.assinatura);
                    }
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(
                    ctx,
                    (
                      leftName: left?.nome ?? 'Tesoureiro(a)',
                      rightName: right?.nome ?? 'Pastor Presidente',
                      leftSig: leftSig,
                      rightSig: rightSig,
                      showDigital: showDigital,
                    ),
                  );
                },
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportPdf({bool fechamentoOficial = false}) async {
    setState(() => _loading = true);
    try {
      final signerSel = await _pickFinanceReportSigners();
      if (signerSel == null) return;
      final tenantSnap = await _tenantRef.get();
      final tenant = tenantSnap.data() ?? <String, dynamic>{};
      final branding = await loadReportPdfBranding(widget.tenantId);
      final summary = await _loadFinanceSummary();
      final rows = (summary['rows'] as List).cast<Map<String, dynamic>>();
      final entradas = (summary['entradas'] as num).toDouble();
      final saidas = (summary['saidas'] as num).toDouble();
      final saldo = (summary['saldo'] as num).toDouble();
      final categorias = (summary['categoriasResumo'] as List).cast<Map<String, dynamic>>();

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum lançamento no período selecionado.')));
        }
        return;
      }

      final cnpj = (tenant['cnpj'] ?? tenant['CNPJ'] ?? '').toString().trim();
      final periodoTxt = _periodoLabelHumano();
      final tituloFechamento = fechamentoOficial
          ? (_periodMode == _FinancePeriodMode.fullYear
              ? 'Fechamento anual (oficial)'
              : _periodMode == _FinancePeriodMode.custom
                  ? 'Fechamento do período (oficial)'
                  : 'Fechamento de mês (oficial)')
          : 'Relatório financeiro';
      final extraFinance = <String>[
        if (cnpj.isNotEmpty) 'CNPJ: $cnpj',
        'Período: $periodoTxt',
        'Total de lançamentos: ${rows.length}',
        if (fechamentoOficial)
          'DOCUMENTO OFICIAL DE FECHAMENTO — gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        if (_resumoFiltros().isNotEmpty) 'Filtros: ${_resumoFiltros()}',
      ];
      final format = _pdfLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();

      final headerRowPdf = pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blue50),
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Data', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Tipo', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Categoria', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Descrição', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Valor', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
        ],
      );
      final dataRowsPdf = List<pw.TableRow>.generate(rows.length, (i) {
        final m = rows[i];
        final dt = DateTime.fromMillisecondsSinceEpoch((m['createdAtMs'] ?? 0) as int);
        final tipo = (m['tipo'] ?? '').toString();
        final cat = (m['categoria'] ?? '').toString();
        final desc = (m['descricao'] ?? '').toString();
        final val = ((m['valor'] ?? 0) as num).toDouble();
        return pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : PdfColors.grey100),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(DateFormat('dd/MM/yyyy').format(dt), style: const pw.TextStyle(fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(tipo, style: const pw.TextStyle(fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(cat.isEmpty ? '-' : cat, style: const pw.TextStyle(fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(desc.isEmpty ? '-' : desc, style: const pw.TextStyle(fontSize: 8))),
            pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('R\$ ${val.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
          ],
        );
      });
      const tableChunk = 28;
      final tableWidgets = <pw.Widget>[];
      for (var start = 0; start < dataRowsPdf.length; start += tableChunk) {
        final end = math.min(start + tableChunk, dataRowsPdf.length);
        if (start > 0) {
          tableWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.yellow50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'Continuação — linhas ${start + 1} a $end',
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                ),
              ),
            ),
          );
        }
        tableWidgets.add(
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.55),
              1: pw.FlexColumnWidth(1.25),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(1.45),
              4: pw.FlexColumnWidth(3.15),
              5: pw.FlexColumnWidth(1.35),
            },
            children: [
              if (start == 0) headerRowPdf,
              ...dataRowsPdf.sublist(start, end),
            ],
          ),
        );
        if (end < dataRowsPdf.length) {
          tableWidgets.add(pw.SizedBox(height: 10));
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: PdfSuperPremiumTheme.header(
              tituloFechamento,
              branding: branding,
              extraLines: extraFinance,
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            if (fechamentoOficial)
              pw.Container(
                height: 48,
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Transform.rotate(
                  angle: -0.3,
                  child: pw.Opacity(
                    opacity: 0.08,
                    child: pw.Text(
                      'FECHAMENTO OFICIAL',
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ),
                ),
              ),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(1),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  children: [
                    _pdfKpiCard('Total Entradas', entradas, PdfColors.green700),
                    _pdfKpiCard('Total Saídas', saidas, PdfColors.red700),
                    _pdfKpiCard('Saldo Final', saldo, saldo >= 0 ? PdfColors.blue700 : PdfColors.grey700),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            if (categorias.isNotEmpty) ...[
              pw.Text('Distribuição das Saídas por Categoria', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...categorias.take(8).map((c) {
                final pct = ((c['percentual'] as num).toDouble()).clamp(0, 100);
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 3, child: pw.Text((c['categoria'] ?? '').toString(), style: const pw.TextStyle(fontSize: 9))),
                      pw.Expanded(
                        flex: 5,
                        child: pw.Container(
                          height: 8,
                          decoration: pw.BoxDecoration(color: PdfColors.grey300, borderRadius: pw.BorderRadius.circular(4)),
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Container(
                              width: pct * 2,
                              decoration: pw.BoxDecoration(color: PdfColors.orange600, borderRadius: pw.BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Text('${pct.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                );
              }),
              pw.SizedBox(height: 8),
            ],
            ...tableWidgets,
            pw.SizedBox(height: 22),
            if (fechamentoOficial)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(
                  'Este PDF é um extrato fixo do período para arquivo contábil. '
                  'Alterações posteriores nos lançamentos não modificam este documento.',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                ),
              ),
            PdfSuperPremiumTheme.reportDualSignatureAttestation(
              accent: branding.accent,
              leftTitle: 'Responsável financeiro',
              rightTitle: 'Responsável pastoral',
              leftSignerName: signerSel.leftName,
              rightSignerName: signerSel.rightName,
              leftSignatureImageBytes: signerSel.leftSig,
              rightSignatureImageBytes: signerSel.rightSig,
              showDigitalSignatures: signerSel.showDigital,
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      final fname = fechamentoOficial ? _fechamentoPdfFilename() : 'relatorio_financeiro.pdf';
      if (mounted) await showPdfActions(context, bytes: bytes, filename: fname);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _loading = true);
    try {
      final summary = await _loadFinanceSummary();
      final rows = (summary['rows'] as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nenhum lançamento para exportar.')));
        }
        return;
      }
      final buf = StringBuffer();
      buf.writeln('Data;Tipo;Categoria;Descricao;Valor;Comprovante');
      for (final m in rows) {
        final dt = DateTime.fromMillisecondsSinceEpoch((m['createdAtMs'] ?? 0) as int);
        final comp = (m['comprovanteUrl'] ?? '').toString().replaceAll(';', ',');
        buf.writeln(
          '${DateFormat('dd/MM/yyyy').format(dt)};${(m['tipo'] ?? '').toString().replaceAll(';', ',')};${(m['categoria'] ?? '').toString().replaceAll(';', ',')};${(m['descricao'] ?? '').toString().replaceAll(';', ',')};${(m['valor'] ?? 0).toString().replaceAll('.', ',')};$comp',
        );
      }
      final bytes = utf8.encode(buf.toString());
      final p = _periodoSelecionado();
      final name = _periodMode == _FinancePeriodMode.month
          ? 'financeiro_${p.inicio.year}_${p.inicio.month.toString().padLeft(2, '0')}.csv'
          : _periodMode == _FinancePeriodMode.fullYear
              ? 'financeiro_ano_${p.inicio.year}.csv'
              : 'financeiro_${DateFormat('yyyyMMdd').format(p.inicio)}_${DateFormat('yyyyMMdd').format(p.fim)}.csv';
      await Share.shareXFiles(
        [XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: 'text/csv')],
        subject: 'Exportação financeira CSV',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao exportar CSV: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirComprovante(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('URL do comprovante inválida.')));
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível abrir o comprovante.')));
      }
    }
  }

  String _resumoFiltros() {
    final parts = <String>[];
    if (_filtroTipo != 'todos') parts.add('Tipo: ${_filtroTipo == 'receitas' ? 'Receitas' : _filtroTipo == 'despesas' ? 'Despesas' : 'Transferências'}');
    if (_filtroCategoria != 'todas') parts.add('Categoria: $_filtroCategoria');
    if (_filtroConta != 'todas') parts.add('Conta: ${_contas.where((c) => c.id == _filtroConta).firstOrNull?.nome ?? _filtroConta}');
    if (_filtroStatusDespesa != 'todas') parts.add('Status: ${_filtroStatusDespesa == 'paga' ? 'Pagas' : 'Em aberto'}');
    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    final meses = const [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    final anos = List<int>.generate(6, (i) => DateTime.now().year - 3 + i);
    const finEmerald = Color(0xFF059669);
    final isNarrow = MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointMobile;
    final listChildren = <Widget>[
            if (_embedded && widget.onEmbeddedBackToResumo != null) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onEmbeddedBackToResumo,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          ThemeCleanPremium.primary.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      border: Border.all(
                        color:
                            ThemeCleanPremium.primary.withValues(alpha: 0.2),
                      ),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Voltar ao resumo financeiro',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    letterSpacing: -0.2,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Retorna à aba Resumo sem sair do módulo Financeiro.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.25,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.dashboard_rounded,
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.65),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Container(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    finEmerald.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                border: Border.all(color: const Color(0xFFE2E8F4)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.date_range_rounded, color: finEmerald, size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Período',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _periodoLabelHumano(),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_FinancePeriodMode>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      selectedBackgroundColor: finEmerald,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: ThemeCleanPremium.onSurfaceVariant,
                      side: const BorderSide(color: Color(0xFFE2E8F4)),
                    ),
                    segments: const [
                      ButtonSegment<_FinancePeriodMode>(
                        value: _FinancePeriodMode.month,
                        label: Text('Mês', style: TextStyle(fontWeight: FontWeight.w700)),
                        icon: Icon(Icons.calendar_month_rounded, size: 18),
                      ),
                      ButtonSegment<_FinancePeriodMode>(
                        value: _FinancePeriodMode.fullYear,
                        label: Text('Ano inteiro', style: TextStyle(fontWeight: FontWeight.w700)),
                        icon: Icon(Icons.calendar_view_month_rounded, size: 18),
                      ),
                      ButtonSegment<_FinancePeriodMode>(
                        value: _FinancePeriodMode.custom,
                        label: Text('Período', style: TextStyle(fontWeight: FontWeight.w700)),
                        icon: Icon(Icons.edit_calendar_rounded, size: 18),
                      ),
                    ],
                    selected: {_periodMode},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      setState(() {
                        _periodMode = next.first;
                        _pageLancamentos = 0;
                        if (_periodMode == _FinancePeriodMode.custom &&
                            (_customRangeStart == null || _customRangeEnd == null)) {
                          _customRangeStart = DateTime(_ano, _mes, 1);
                          _customRangeEnd = DateTime(_ano, _mes + 1, 0);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final ref = DateTime(_ano, _mes);
                        final prev = DateTime(ref.year, ref.month - 1);
                        setState(() {
                          _periodMode = _FinancePeriodMode.month;
                          _mes = prev.month;
                          _ano = prev.year;
                          _pageLancamentos = 0;
                        });
                      },
                      icon: const Icon(Icons.history_rounded, size: 20),
                      label: const Text('Mês anterior'),
                      style: TextButton.styleFrom(
                        foregroundColor: finEmerald,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_periodMode == _FinancePeriodMode.month)
                    isNarrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int>(
                                value: _mes,
                                decoration: InputDecoration(
                                  labelText: 'Mês',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                ),
                                items: List.generate(
                                    12, (i) => DropdownMenuItem(value: i + 1, child: Text(meses[i]))),
                                onChanged: (v) => setState(() {
                                  _mes = v ?? DateTime.now().month;
                                  _pageLancamentos = 0;
                                }),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<int>(
                                value: _ano,
                                decoration: InputDecoration(
                                  labelText: 'Ano',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                ),
                                items: anos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
                                onChanged: (v) => setState(() {
                                  _ano = v ?? DateTime.now().year;
                                  _pageLancamentos = 0;
                                }),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _mes,
                                  decoration: InputDecoration(
                                    labelText: 'Mês',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  ),
                                  items: List.generate(
                                      12, (i) => DropdownMenuItem(value: i + 1, child: Text(meses[i]))),
                                  onChanged: (v) => setState(() {
                                    _mes = v ?? DateTime.now().month;
                                    _pageLancamentos = 0;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _ano,
                                  decoration: InputDecoration(
                                    labelText: 'Ano',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                  ),
                                  items: anos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
                                  onChanged: (v) => setState(() {
                                    _ano = v ?? DateTime.now().year;
                                    _pageLancamentos = 0;
                                  }),
                                ),
                              ),
                            ],
                          ),
                  if (_periodMode == _FinancePeriodMode.fullYear)
                    DropdownButtonFormField<int>(
                      value: _ano,
                      decoration: InputDecoration(
                        labelText: 'Ano (1 jan — 31 dez)',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                      ),
                      items: anos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
                      onChanged: (v) => setState(() {
                        _ano = v ?? DateTime.now().year;
                        _pageLancamentos = 0;
                      }),
                    ),
                  if (_periodMode == _FinancePeriodMode.custom) ...[
                    OutlinedButton.icon(
                      onPressed: _pickCustomRange,
                      icon: const Icon(Icons.date_range_rounded),
                      label: const Text('Escolher datas no calendário'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: finEmerald,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        side: BorderSide(color: finEmerald.withValues(alpha: 0.45)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _periodoLabelHumano(),
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Tipo', icon: Icons.swap_horiz_rounded, color: finEmerald, child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['todos', 'receitas', 'despesas', 'transferencias'].map((v) {
                final lbl = v == 'todos' ? 'Todos' : v == 'receitas' ? 'Receitas' : v == 'despesas' ? 'Despesas' : 'Transferências';
                final sel = _filtroTipo == v;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => setState(() {
                      _filtroTipo = sel ? 'todos' : v;
                      _pageLancamentos = 0;
                    }),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: sel
                            ? LinearGradient(colors: [finEmerald, Color.lerp(finEmerald, Colors.white, 0.12)!])
                            : null,
                        color: sel ? null : Colors.white,
                        border: Border.all(color: sel ? Colors.transparent : const Color(0xFFE2E8F4)),
                        boxShadow: sel
                            ? [BoxShadow(color: finEmerald.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]
                            : ThemeCleanPremium.softUiCardShadow,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        lbl,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: sel ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Status despesas', icon: Icons.payment_rounded, color: finEmerald, child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['todas', 'aberta', 'paga'].map((v) {
                final lbl = v == 'todas' ? 'Todas' : v == 'aberta' ? 'Em aberto' : 'Pagas';
                final sel = _filtroStatusDespesa == v;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => setState(() {
                      _filtroStatusDespesa = sel ? 'todas' : v;
                      _pageLancamentos = 0;
                    }),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: sel
                            ? LinearGradient(colors: [finEmerald, Color.lerp(finEmerald, Colors.white, 0.12)!])
                            : null,
                        color: sel ? null : Colors.white,
                        border: Border.all(color: sel ? Colors.transparent : const Color(0xFFE2E8F4)),
                        boxShadow: sel
                            ? [BoxShadow(color: finEmerald.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]
                            : ThemeCleanPremium.softUiCardShadow,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        lbl,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: sel ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Categoria', icon: Icons.category_rounded, color: finEmerald, child: _initLoaded
                ? DropdownButtonFormField<String>(
                    value: _filtroCategoria,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    items: [const DropdownMenuItem(value: 'todas', child: Text('Todas categorias'))]
                        ..addAll(_categorias.map((c) => DropdownMenuItem(value: c, child: Text(c)))),
                    onChanged: (v) => setState(() {
                      _filtroCategoria = v ?? 'todas';
                      _pageLancamentos = 0;
                    }),
                  )
                : const Center(
                    child: SizedBox(
                      height: 48,
                      child: ChurchPanelLoadingBody(),
                    ),
                  )),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            _FilterSection(title: 'Conta', icon: Icons.account_balance_rounded, color: finEmerald, child: _initLoaded
                ? DropdownButtonFormField<String>(
                    value: _filtroConta,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                    items: [const DropdownMenuItem(value: 'todas', child: Text('Todas contas'))]
                        ..addAll(_contas.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nome)))),
                    onChanged: (v) => setState(() {
                      _filtroConta = v ?? 'todas';
                      _pageLancamentos = 0;
                    }),
                  )
                : const Center(
                    child: SizedBox(
                      height: 48,
                      child: ChurchPanelLoadingBody(),
                    ),
                  )),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            FutureBuilder<Map<String, dynamic>>(
              key: ValueKey<String>(
                  '${widget.tenantId}_$_periodMode$_mes$_ano${_customRangeStart?.millisecondsSinceEpoch}_${_customRangeEnd?.millisecondsSinceEpoch}_$_filtroTipo$_filtroCategoria$_filtroConta$_filtroStatusDespesa'),
              future: _loadFinanceSummary(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: ChurchPanelErrorBody(
                      title: 'Não foi possível carregar o resumo financeiro',
                      error: snap.error,
                      onRetry: () => setState(() {}),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: ChurchPanelLoadingBody(),
                  );
                }
                final entradas = ((snap.data!['entradas'] ?? 0) as num).toDouble();
                final saidas = ((snap.data!['saidas'] ?? 0) as num).toDouble();
                final saldo = ((snap.data!['saldo'] ?? 0) as num).toDouble();
                final aReceberPendente =
                    ((snap.data!['aReceberPendente'] ?? 0) as num).toDouble();
                final aPagarPendente =
                    ((snap.data!['aPagarPendente'] ?? 0) as num).toDouble();
                final fluxoPrevisto =
                    ((snap.data!['fluxoPrevisto'] ?? 0) as num).toDouble();
                final porContaDetalhe = (snap.data!['porConta'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    <Map<String, dynamic>>[];
                final dizimos = ((snap.data!['dizimosMes'] ?? 0) as num).toDouble();
                final ofertas = ((snap.data!['ofertasMes'] ?? 0) as num).toDouble();
                final gastosMes = (snap.data!['gastosPorCategoriaMes'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    <Map<String, dynamic>>[];
                final allRows =
                    (snap.data!['rows'] as List).cast<Map<String, dynamic>>();
                final q = _buscaLancamentos.trim().toLowerCase();
                final filteredRows = q.isEmpty
                    ? allRows
                    : allRows.where((m) {
                        final blob =
                            '${m['tipo']} ${m['categoria']} ${m['descricao']}'
                                .toLowerCase();
                        return blob.contains(q);
                      }).toList();
                final totalPages = filteredRows.isEmpty
                    ? 1
                    : (filteredRows.length / _rowsPerPageLancamentos).ceil();
                var page = _pageLancamentos;
                if (page >= totalPages) page = totalPages - 1;
                if (page < 0) page = 0;
                final slice = filteredRows
                    .skip(page * _rowsPerPageLancamentos)
                    .take(_rowsPerPageLancamentos)
                    .toList();
                final periodoSel = _periodoSelecionado();
                final evolucao = _computeFinanceEvolucao(
                  allRows,
                  _periodMode,
                  periodoSel.inicio,
                  periodoSel.fim,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _FinanceStatCard(
                                title: 'Entradas',
                                value: entradas,
                                color: const Color(0xFF16A34A))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _FinanceStatCard(
                                title: 'Saídas',
                                value: saidas,
                                color: const Color(0xFFDC2626))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FinanceStatCard(
                            title: 'Saldo líquido',
                            value: saldo,
                            color: saldo >= 0
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Previsão (contas a receber / a pagar)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Valores em aberto: receitas não confirmadas e despesas não pagas (lançamentos do período).',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (ctx, c) {
                        final narrow = c.maxWidth < 520;
                        final w = narrow ? double.infinity : null;
                        Widget cardARec = SizedBox(
                          width: w,
                          child: _FinanceStatCard(
                            title: 'A receber (pendente)',
                            value: aReceberPendente,
                            color: const Color(0xFF0891B2),
                          ),
                        );
                        Widget cardAPag = SizedBox(
                          width: w,
                          child: _FinanceStatCard(
                            title: 'A pagar (pendente)',
                            value: aPagarPendente,
                            color: const Color(0xFFEA580C),
                          ),
                        );
                        Widget cardFluxo = SizedBox(
                          width: w,
                          child: _FinanceStatCard(
                            title: 'Saldo + previsão',
                            value: fluxoPrevisto,
                            color: fluxoPrevisto >= 0
                                ? const Color(0xFF0D9488)
                                : const Color(0xFFB91C1C),
                          ),
                        );
                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cardARec,
                              const SizedBox(height: 8),
                              cardAPag,
                              const SizedBox(height: 8),
                              cardFluxo,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cardARec),
                            const SizedBox(width: 8),
                            Expanded(child: cardAPag),
                            const SizedBox(width: 8),
                            Expanded(child: cardFluxo),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      _periodMode == _FinancePeriodMode.month
                          ? 'Painel visual (mês selecionado)'
                          : _periodMode == _FinancePeriodMode.fullYear
                              ? 'Painel visual (ano completo)'
                              : 'Painel visual (período personalizado)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FinanceEvolucaoLineChart(data: evolucao),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    if (porContaDetalhe.isNotEmpty)
                      _FinancePorContaPanel(rows: porContaDetalhe),
                    if (porContaDetalhe.isNotEmpty)
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                    _FinanceBiCharts(
                        dizimos: dizimos,
                        ofertas: ofertas,
                        gastosMes: gastosMes),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    TextField(
                      decoration: InputDecoration(
                        hintText:
                            'Buscar na lista (tipo, categoria, descrição)...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                      onChanged: (v) => setState(() {
                        _buscaLancamentos = v;
                        _pageLancamentos = 0;
                      }),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Lançamentos filtrados (${filteredRows.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.cardBackground,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFF1F5F9)),
                            columns: const [
                              DataColumn(label: Text('Data')),
                              DataColumn(label: Text('Tipo')),
                              DataColumn(label: Text('Valor')),
                              DataColumn(label: Text('Categoria')),
                              DataColumn(label: Text('Descrição')),
                              DataColumn(label: Text('Comp.')),
                            ],
                            rows: [
                              for (final m in slice)
                                DataRow(
                                  cells: [
                                    DataCell(Text(DateFormat('dd/MM/yyyy')
                                        .format(DateTime
                                            .fromMillisecondsSinceEpoch(
                                                (m['createdAtMs'] ?? 0)
                                                    as int)))),
                                    DataCell(Text((m['tipo'] ?? '').toString(),
                                        maxLines: 2)),
                                    DataCell(Text(
                                      'R\$ ${((m['valor'] ?? 0) as num).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: () {
                                          final t = (m['tipo'] ?? '')
                                              .toString()
                                              .toLowerCase();
                                          if (t.contains('entrada') ||
                                              t.contains('receita')) {
                                            return const Color(0xFF16A34A);
                                          }
                                          if (t.contains('saida') ||
                                              t.contains('despesa')) {
                                            return const Color(0xFFDC2626);
                                          }
                                          return ThemeCleanPremium.onSurface;
                                        }(),
                                      ),
                                    )),
                                    DataCell(Text(
                                        (m['categoria'] ?? '-').toString(),
                                        maxLines: 2)),
                                    DataCell(SizedBox(
                                      width: 200,
                                      child: Text(
                                        (m['descricao'] ?? '').toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(
                                      (m['comprovanteUrl'] ?? '')
                                              .toString()
                                              .trim()
                                              .isEmpty
                                          ? const Text('—')
                                          : IconButton(
                                              icon: const Icon(
                                                  Icons.receipt_long_rounded,
                                                  color: Color(0xFF059669)),
                                              tooltip: 'Ver comprovante',
                                              style: IconButton.styleFrom(
                                                minimumSize: const Size(
                                                    ThemeCleanPremium
                                                        .minTouchTarget,
                                                    ThemeCleanPremium
                                                        .minTouchTarget),
                                              ),
                                              onPressed: () =>
                                                  _abrirComprovante(
                                                      (m['comprovanteUrl'] ??
                                                              '')
                                                          .toString()),
                                            ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (totalPages > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: page <= 0
                                  ? null
                                  : () => setState(
                                      () => _pageLancamentos = page - 1),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Text('Página ${page + 1} de $totalPages'),
                            IconButton(
                              onPressed: page >= totalPages - 1
                                  ? null
                                  : () => setState(
                                      () => _pageLancamentos = page + 1),
                              icon: const Icon(Icons.chevron_right_rounded),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            PremiumPdfOrientationBar(landscape: _pdfLandscape, onChanged: (v) => setState(() => _pdfLandscape = v)),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : () => _exportPdf(),
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(_loading ? 'Gerando...' : 'Exportar PDF'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16)),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _exportPdf(fechamentoOficial: true),
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Fechamento de mês (oficial)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _exportCsv,
                  icon: const Icon(Icons.table_chart_rounded),
                  label: const Text('Exportar Excel (CSV)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                  ),
                ),
              ],
            ),
    ];
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: _embedded
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _popUmaRotaRelatorio(context),
                tooltip: 'Voltar',
                style: IconButton.styleFrom(
                  minimumSize: const Size(
                    ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget,
                  ),
                ),
              ),
              title: const Text('Relatório financeiro'),
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
            ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: listChildren,
        ),
      ),
    );
  }

  pw.Widget _pdfKpiCard(String title, double value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.10),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 9, color: color, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text('R\$ ${value.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Linhas: entradas e saídas agregadas por dia ou mês no período.
class _FinanceEvolucaoLineChart extends StatelessWidget {
  final _FinanceEvolucao data;

  const _FinanceEvolucaoLineChart({required this.data});

  static const _anim = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    if (data.labels.isEmpty) {
      return const SizedBox.shrink();
    }
    if (data.isEffectivelyEmpty) {
      return Container(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Text(
          'Sem movimentação no período para o gráfico de evolução.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    final maxVal = [
      ...data.entradas,
      ...data.saidas,
    ].reduce(math.max);
    final maxY = maxVal <= 0 ? 100.0 : maxVal * 1.12;
    final n = data.labels.length;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFF059669).withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    color: Color(0xFF059669), size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Evolução no período',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Entradas e saídas por dia ou mês, conforme o filtro.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (v, _) => Text(
                        NumberFormat.compactCurrency(
                                locale: 'pt_BR', symbol: r'R$')
                            .format(v),
                        style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: n > 14 ? (n / 8).ceilToDouble() : 1,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i >= 0 && i < n) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              data.labels[i],
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      n,
                      (i) => FlSpot(i.toDouble(), data.entradas[i]),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.22,
                    color: const Color(0xFF16A34A),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: List.generate(
                      n,
                      (i) => FlSpot(i.toDouble(), data.saidas[i]),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.22,
                    color: const Color(0xFFDC2626),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFDC2626).withValues(alpha: 0.06),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((t) {
                        final i = t.x.toInt();
                        if (i < 0 || i >= n) return null;
                        final isEntradas = t.barIndex == 0;
                        final label = isEntradas ? 'Entradas' : 'Saídas';
                        final val =
                            isEntradas ? data.entradas[i] : data.saidas[i];
                        return LineTooltipItem(
                          '$label\n${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(val)}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        );
                      }).whereType<LineTooltipItem>().toList();
                    },
                  ),
                ),
              ),
              duration: _anim,
              curve: Curves.easeOutCubic,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDotFinance(color: const Color(0xFF16A34A), label: 'Entradas'),
              const SizedBox(width: 20),
              _LegendDotFinance(color: const Color(0xFFDC2626), label: 'Saídas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDotFinance extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDotFinance({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

/// Resumo por conta no período (entradas na conta / saídas da conta).
class _FinancePorContaPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _FinancePorContaPanel({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF059669), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Por conta (detalhe)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Entradas creditadas e saídas debitadas em cada conta no período filtrado.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              columns: const [
                DataColumn(label: Text('Conta')),
                DataColumn(label: Text('Entradas')),
                DataColumn(label: Text('Saídas')),
                DataColumn(label: Text('Líquido')),
              ],
              rows: [
                for (final m in rows.take(24))
                  DataRow(
                    cells: [
                      DataCell(Text(
                        (m['nome'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )),
                      DataCell(Text(
                        'R\$ ${((m['entradas'] ?? 0) as num).toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w600),
                      )),
                      DataCell(Text(
                        'R\$ ${((m['saidas'] ?? 0) as num).toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600),
                      )),
                      DataCell(Text(
                        'R\$ ${((m['liquido'] ?? 0) as num).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ((m['liquido'] ?? 0) as num).toDouble() >= 0
                              ? const Color(0xFF0D9488)
                              : const Color(0xFFB91C1C),
                        ),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gráficos do painel BI (dízimos x ofertas + pizza de despesas do mês).
class _FinanceBiCharts extends StatelessWidget {
  final double dizimos;
  final double ofertas;
  final List<Map<String, dynamic>> gastosMes;

  const _FinanceBiCharts({
    required this.dizimos,
    required this.ofertas,
    required this.gastosMes,
  });

  static const _anim = Duration(milliseconds: 750);

  List<PieChartSectionData> _pieSections() {
    const palette = [
      Color(0xFFDC2626),
      Color(0xFFEA580C),
      Color(0xFFCA8A04),
      Color(0xFF16A34A),
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFFDB2777),
      Color(0xFF0891B2),
    ];
    final top = gastosMes.take(8).toList();
    final total = top.fold<double>(
        0, (a, e) => a + ((e['valor'] ?? 0) as num).toDouble());
    if (total <= 0) return [];
    return List.generate(top.length, (i) {
      final val = ((top[i]['valor'] ?? 0) as num).toDouble();
      return PieChartSectionData(
        value: val,
        title: '${(100 * val / total).toStringAsFixed(0)}%',
        color: palette[i % palette.length],
        radius: 52,
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(100.0, math.max(dizimos, ofertas) * 1.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dízimos vs ofertas (receitas do mês por categoria)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, m) {
                            if (v.toInt() == 0) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Dízimos',
                                    style: TextStyle(fontSize: 11)),
                              );
                            }
                            if (v.toInt() == 1) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Ofertas',
                                    style: TextStyle(fontSize: 11)),
                              );
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          getTitlesWidget: (v, m) => Text(
                            NumberFormat.compactCurrency(
                                    locale: 'pt_BR', symbol: r'R$')
                                .format(v),
                            style: const TextStyle(fontSize: 9),
                          ),
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData:
                        FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: dizimos,
                            color: const Color(0xFF15803D),
                            width: 28,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: ofertas,
                            color: const Color(0xFFCA8A04),
                            width: 28,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                    ],
                  ),
                  swapAnimationDuration: _anim,
                  swapAnimationCurve: Curves.easeOutCubic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: gastosMes.isEmpty
              ? Text(
                  'Sem despesas registradas no mês para o gráfico por categoria.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final pie = SizedBox(
                      height: 200,
                      width: narrow ? c.maxWidth : 200,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 36,
                          sections: _pieSections(),
                        ),
                        swapAnimationDuration: _anim,
                        swapAnimationCurve: Curves.easeOutCubic,
                      ),
                    );
                    final legend = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gastos por categoria',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 8),
                        ...gastosMes.take(8).map((e) {
                          final cat = (e['categoria'] ?? '').toString();
                          final val =
                              ((e['valor'] ?? 0) as num).toDouble();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '$cat — R\$ ${val.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pie,
                          const SizedBox(height: 12),
                          legend,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pie,
                        const SizedBox(width: 16),
                        Expanded(child: legend),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FinanceStatCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _FinanceStatCard({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text('R\$ ${value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Card de filtro (Relatórios)
class _FilterSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? color;

  const _FilterSection({required this.title, required this.icon, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF059669);
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        gradient: color != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ThemeCleanPremium.cardBackground,
                  c.withValues(alpha: 0.05),
                ],
              )
            : null,
        color: color != null ? null : ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          child,
        ],
      ),
    );
  }
}

// ─── Relatório de Patrimônio (grade antes de imprimir, ordenação, campos selecionáveis) ─────────
class _RelatorioPatrimonioPage extends StatefulWidget {
  final String tenantId;

  const _RelatorioPatrimonioPage({required this.tenantId});

  @override
  State<_RelatorioPatrimonioPage> createState() => _RelatorioPatrimonioPageState();
}

class _RelatorioPatrimonioPageState extends State<_RelatorioPatrimonioPage> {
  static const _statusOptions = [
    ('', 'Todos'),
    ('bom', 'Bom'),
    ('em_manutencao', 'Manutenção'),
    ('danificado', 'Danificado'),
    ('obsoleto', 'Obsoleto'),
  ];

  /// Ordenação: nome_az, nome_za, valor_asc, valor_desc
  static const _sortOptions = [
    ('nome_az', 'Nome A–Z'),
    ('nome_za', 'Nome Z–A'),
    ('valor_asc', 'Valor (menor)'),
    ('valor_desc', 'Valor (maior)'),
  ];

  static const _fieldOptions = [
    ('nome', 'Nome'),
    ('categoria', 'Categoria'),
    ('status', 'Status'),
    ('valor', 'Valor (R\$)'),
    ('localizacao', 'Localização'),
    ('responsavel', 'Responsável'),
    ('numeroSerie', 'Nº Série'),
    ('dataAquisicao', 'Data Aquisição'),
    ('proximaManutencao', 'Próx. Manutenção'),
    ('descricao', 'Descrição'),
  ];

  String _filterStatus = '';
  String _sortBy = 'nome_az';
  final Set<String> _selectedFields = {'nome', 'categoria', 'status', 'valor', 'localizacao', 'responsavel', 'numeroSerie', 'dataAquisicao', 'proximaManutencao'};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;
  String? _loadError;
  bool _exporting = false;
  bool _pdfLandscape = true;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('patrimonio');

  static String _statusLabel(String key) {
    final f = _statusOptions.where((e) => e.$1 == key).firstOrNull;
    return f != null ? f.$2 : key;
  }

  static String _fmtMoney(dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null) return '—';
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static String _fmtDate(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) return DateFormat('dd/MM/yyyy').format(v.toDate());
    if (v is DateTime) return DateFormat('dd/MM/yyyy').format(v);
    return v.toString();
  }

  String _cellValue(Map<String, dynamic> m, String key) {
    switch (key) {
      case 'nome': return (m['nome'] ?? '').toString();
      case 'categoria': return (m['categoria'] ?? '').toString();
      case 'status': return _statusLabel((m['status'] ?? '').toString());
      case 'valor': return _fmtMoney(m['valor']);
      case 'localizacao': return (m['localizacao'] ?? '').toString();
      case 'responsavel': return (m['responsavel'] ?? '').toString();
      case 'numeroSerie': return (m['numeroSerie'] ?? '').toString();
      case 'dataAquisicao': return _fmtDate(m['dataAquisicao']);
      case 'proximaManutencao': return _fmtDate(m['proximaManutencao']);
      case 'descricao': return (m['descricao'] ?? '').toString();
      default: return '';
    }
  }

  List<String> get _orderedSelectedKeys => _fieldOptions.map((e) => e.$1).where(_selectedFields.contains).toList();

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snap = await _col.orderBy('nome').get();
      if (mounted) {
        setState(() {
          _docs = snap.docs;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  /// Lista filtrada por status e depois ordenada (sem nova requisição).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredAndSortedDocs() {
    var list = _docs;
    if (_filterStatus.isNotEmpty) {
      list = list.where((d) => (d.data()['status'] ?? '').toString() == _filterStatus).toList();
    }
    final copy = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(list);
    switch (_sortBy) {
      case 'nome_az':
        copy.sort((a, b) => ((a.data()['nome'] ?? '').toString().toLowerCase()).compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
        break;
      case 'nome_za':
        copy.sort((a, b) => ((b.data()['nome'] ?? '').toString().toLowerCase()).compareTo((a.data()['nome'] ?? '').toString().toLowerCase()));
        break;
      case 'valor_asc':
        copy.sort((a, b) {
          final va = (a.data()['valor'] is num) ? (a.data()['valor'] as num).toDouble() : 0.0;
          final vb = (b.data()['valor'] is num) ? (b.data()['valor'] as num).toDouble() : 0.0;
          return va.compareTo(vb);
        });
        break;
      case 'valor_desc':
        copy.sort((a, b) {
          final va = (a.data()['valor'] is num) ? (a.data()['valor'] as num).toDouble() : 0.0;
          final vb = (b.data()['valor'] is num) ? (b.data()['valor'] as num).toDouble() : 0.0;
          return vb.compareTo(va);
        });
        break;
    }
    return copy;
  }

  Future<void> _exportPdf() async {
    if (_selectedFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione ao menos um campo para imprimir.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final docs = _filteredAndSortedDocs();
      if (docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum item para exportar.')));
        return;
      }
      final keys = _orderedSelectedKeys;
      final headers = ['#', ...keys.map((k) => _fieldOptions.firstWhere((e) => e.$1 == k).$2)];
      final data = docs.asMap().entries.map((e) {
        return [
          '${e.key + 1}',
          ...keys.map((k) => _cellValue(e.value.data(), k)),
        ];
      }).toList();
      double valorTotal = 0;
      for (final d in docs) {
        final v = d.data()['valor'];
        if (v is num) valorTotal += v.toDouble();
      }

      final branding = await loadReportPdfBranding(widget.tenantId);
      final extraPat = <String>[
        'Quantidade de bens: ${docs.length}',
        'Valor total: ${_fmtMoney(valorTotal)}',
        if (_filterStatus.isNotEmpty) 'Filtro: ${_statusLabel(_filterStatus)}',
      ];
      final format = _pdfLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              'Relatório de Patrimônio',
              branding: branding,
              extraLines: extraPat,
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            PdfSuperPremiumTheme.fromTextArray(
              headers: headers,
              data: data,
              accent: branding.accent,
              columnWidths:
                  PdfSuperPremiumTheme.columnWidthsPatrimonioReport(keys),
            ),
            pw.SizedBox(height: 18),
            PdfSuperPremiumTheme.reportPastoralSignatureBox(
              accent: branding.accent,
              sectionTitle: 'Conferência e validação',
              label: 'Assinatura do responsável pelo patrimônio ou pastor',
            ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) await showPdfActions(context, bytes: bytes, filename: 'relatorio_patrimonio.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _filteredAndSortedDocs();
    final keys = _orderedSelectedKeys;
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _popUmaRotaRelatorio(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: const Text('Relatório de Patrimônio', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2)),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _loadError != null && _docs.isEmpty
            ? ChurchPanelErrorBody(
                title: 'Não foi possível carregar o patrimônio',
                error: _loadError,
                onRetry: _load,
              )
            : _loading && _docs.isEmpty
                ? const ChurchPanelLoadingBody()
                : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: padding,
                  children: [
                    // ── Filtrar por status (Super Premium) ──
                    _SectionCard(
                      title: 'Filtrar por status',
                      icon: Icons.filter_list_rounded,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statusOptions.map((e) {
                          final selected = _filterStatus == e.$1;
                          return _PremiumFilterChip(
                            label: e.$2,
                            selected: selected,
                            accent: const Color(0xFF7C3AED),
                            onSelected: (v) => setState(() => _filterStatus = v == true ? e.$1 : ''),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    // ── Ordenar (Super Premium) ──
                    _SectionCard(
                      title: 'Ordenar',
                      icon: Icons.sort_rounded,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _sortOptions.map((e) {
                          final selected = _sortBy == e.$1;
                          return _PremiumFilterChip(
                            label: e.$2,
                            selected: selected,
                            accent: const Color(0xFF7C3AED),
                            onSelected: (v) => setState(() => _sortBy = v == true ? e.$1 : _sortBy),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    // ── Campos a exibir e imprimir ──
                    _SectionCard(
                      title: 'Campos a exibir e imprimir',
                      icon: Icons.view_column_rounded,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _fieldOptions.map((e) {
                          final selected = _selectedFields.contains(e.$1);
                          return _PremiumFilterChip(
                            label: e.$2,
                            selected: selected,
                            accent: const Color(0xFF7C3AED),
                            onSelected: (v) => setState(() {
                              if (v == true) _selectedFields.add(e.$1);
                              else _selectedFields.remove(e.$1);
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    // ── Grade de dados ──
                    Text(
                      'Pré-visualização (${sorted.length} itens)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    Container(
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.cardBackground,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: keys.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                                  child: Text('Selecione ao menos um campo acima.', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                                )
                              : DataTable(
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                  headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ThemeCleanPremium.onSurface),
                                  dataTextStyle: const TextStyle(fontSize: 12, color: ThemeCleanPremium.onSurface),
                                  columnSpacing: 20,
                                  horizontalMargin: 16,
                                  columns: keys.map((k) => DataColumn(label: Text(_fieldOptions.firstWhere((e) => e.$1 == k).$2))).toList(),
                                  rows: sorted.map((d) {
                                    final m = d.data();
                                    return DataRow(
                                      cells: keys.map((k) => DataCell(Text(_cellValue(m, k), overflow: TextOverflow.ellipsis, maxLines: 2))).toList(),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    PremiumPdfOrientationBar(landscape: _pdfLandscape, onChanged: (v) => setState(() => _pdfLandscape = v)),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    FilledButton.icon(
                      onPressed: (_exporting || _selectedFields.isEmpty) ? null : _exportPdf,
                      icon: _exporting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.picture_as_pdf_rounded, size: 22),
                      label: Text(_exporting ? 'Gerando PDF...' : 'Exportar PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─── Relatório de Eventos (eventos ativos, confirmações RSVP, filtros diário/mensal/anual/período) ───
class _RelatorioEventosPage extends StatefulWidget {
  final String tenantId;

  const _RelatorioEventosPage({required this.tenantId});

  @override
  State<_RelatorioEventosPage> createState() => _RelatorioEventosPageState();
}

class _RelatorioEventosPageState extends State<_RelatorioEventosPage> {
  String _tipo = 'mes'; // dia, mes, anual, periodo
  DateTime? _dataInicio;
  DateTime? _dataFim;
  bool _loading = false;
  String? _carregarError;
  bool _pdfLandscape = false;
  List<Map<String, dynamic>> _eventos = [];

  CollectionReference<Map<String, dynamic>> get _noticias =>
      FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).collection('noticias');

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _carregarError = null;
    });
    _eventos = [];
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snap = await _noticias.where('type', isEqualTo: 'evento').get();
      final now = DateTime.now();
      DateTime start;
      DateTime end;
      if (_tipo == 'dia') {
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (_tipo == 'mes') {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      } else if (_tipo == 'anual') {
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31, 23, 59, 59);
      } else if (_tipo == 'periodo' && _dataInicio != null && _dataFim != null) {
        start = _dataInicio!;
        end = DateTime(_dataFim!.year, _dataFim!.month, _dataFim!.day, 23, 59, 59);
      } else {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
      for (final d in snap.docs) {
        final data = d.data();
        final startAt = data['startAt'];
        if (startAt == null) continue;
        DateTime dt;
        if (startAt is Timestamp) dt = startAt.toDate();
        else if (startAt is DateTime) dt = startAt;
        else continue;
        if (dt.isBefore(start) || dt.isAfter(end)) continue;
        final rsvp = (data['rsvp'] as List?) ?? [];
        final likes = (data['likes'] as List?) ?? [];
        _eventos.add({
          'id': d.id,
          'title': (data['title'] ?? 'Evento').toString(),
          'date': dt,
          'rsvpCount': rsvp.length,
          'likesCount': likes.length,
          'location': (data['location'] ?? '').toString(),
        });
      }
      _eventos.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    } catch (e) {
      if (mounted) {
        setState(() => _carregarError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _exportPdf() async {
    if (_tipo == 'periodo' && (_dataInicio == null || _dataFim == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Defina o período (data início e fim).')));
      return;
    }
    setState(() => _loading = true);
    try {
      await _carregar();
      final titulo = _tipo == 'dia' ? 'Relatório de Eventos — Dia' : _tipo == 'mes' ? 'Relatório de Eventos — Mês' : _tipo == 'anual' ? 'Relatório de Eventos — Ano' : 'Relatório de Eventos — Período';
      final branding = await loadReportPdfBranding(widget.tenantId);
      final format = _pdfLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      final pdf = await PdfSuperPremiumTheme.newPdfDocument();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: PdfSuperPremiumTheme.pageMargin,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: PdfSuperPremiumTheme.header(
              titulo,
              branding: branding,
              extraLines: [
                'Total de eventos: ${_eventos.length}',
              ],
            ),
          ),
          footer: (ctx) => PdfSuperPremiumTheme.footer(
            ctx,
            churchName: branding.churchName,
          ),
          build: (ctx) => [
            if (_eventos.isEmpty)
              pw.Center(child: pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Text('Nenhum evento no período.', style: const pw.TextStyle(fontSize: 12))))
            else
              PdfSuperPremiumTheme.fromTextArray(
                headers: const [
                  '#',
                  'Evento',
                  'Data/Hora',
                  'Confirmações (RSVP)',
                  'Curtidas',
                  'Local'
                ],
                data: _eventos.asMap().entries.map((e) {
                  final ev = e.value;
                  return <String>[
                    '${e.key + 1}',
                    (ev['title'] as String).length > 40 ? '${(ev['title'] as String).substring(0, 40)}...' : ev['title'] as String,
                    DateFormat('dd/MM/yyyy HH:mm').format(ev['date'] as DateTime),
                    '${ev['rsvpCount']}',
                    '${ev['likesCount']}',
                    (ev['location'] as String).length > 25 ? '${(ev['location'] as String).substring(0, 25)}...' : ev['location'] as String,
                  ];
                }).toList(),
                accent: branding.accent,
                columnWidths: PdfSuperPremiumTheme.columnWidthsEventosReport,
              ),
          ],
        ),
      );
      final bytes = Uint8List.fromList(await pdf.save());
      if (mounted) await showPdfActions(context, bytes: bytes, filename: 'relatorio_eventos.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _popUmaRotaRelatorio(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: const Text('Relatório de Eventos'),
        backgroundColor: const Color(0xFF0EA5E9),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            _FilterSection(
              title: 'Período',
              icon: Icons.date_range_rounded,
              color: const Color(0xFF0EA5E9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...['dia', 'mes', 'anual', 'periodo'].map((v) => RadioListTile<String>(
                        value: v,
                        groupValue: _tipo,
                        onChanged: (x) => setState(() { _tipo = x ?? _tipo; _carregar(); }),
                        title: Text(v == 'dia' ? 'Diário' : v == 'mes' ? 'Mensal' : v == 'anual' ? 'Anual' : 'Por período'),
                        dense: true,
                      )),
                  if (_tipo == 'periodo') ...[
                    const SizedBox(height: 8),
                    ListTile(
                      title: const Text('Data início'),
                      subtitle: Text(_dataInicio == null ? 'Toque para escolher' : DateFormat('dd/MM/yyyy').format(_dataInicio!)),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                        if (d != null) setState(() { _dataInicio = d; _carregar(); });
                      },
                    ),
                    ListTile(
                      title: const Text('Data fim'),
                      subtitle: Text(_dataFim == null ? 'Toque para escolher' : DateFormat('dd/MM/yyyy').format(_dataFim!)),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: _dataFim ?? DateTime.now(), firstDate: _dataInicio ?? DateTime(2020), lastDate: DateTime(2030));
                        if (d != null) setState(() { _dataFim = d; _carregar(); });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            if (_carregarError != null && _eventos.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ChurchPanelErrorBody(
                  title: 'Não foi possível carregar os eventos',
                  error: _carregarError,
                  onRetry: _carregar,
                ),
              )
            else if (_loading && _eventos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: ChurchPanelLoadingBody(),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_available_rounded, color: const Color(0xFF0EA5E9), size: 22),
                        const SizedBox(width: 10),
                        Text('Eventos ativos e confirmações de presença', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_eventos.isEmpty)
                      Padding(padding: const EdgeInsets.all(16), child: Text('Nenhum evento no período.', style: TextStyle(color: Colors.grey.shade600)))
                    else
                      ..._eventos.map((e) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text((e['title'] as String), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(e['date'] as DateTime) + (e['rsvpCount'] as int > 0 ? ' • ${e['rsvpCount']} confirmações' : '')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _chip('${e['rsvpCount']}', Icons.check_circle_rounded, ThemeCleanPremium.success),
                              const SizedBox(width: 6),
                              _chip('${e['likesCount']}', Icons.favorite_rounded, Colors.red.shade400),
                            ],
                          ),
                        ),
                      )),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              PremiumPdfOrientationBar(landscape: _pdfLandscape, onChanged: (v) => setState(() => _pdfLandscape = v)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loading ? null : _exportPdf,
                icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.picture_as_pdf_rounded),
                label: Text(_loading ? 'Gerando...' : 'Exportar PDF'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))]),
    );
  }
}

/// Card de seção para filtros/ordenação/campos — Super Premium
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: const Color(0xFF7C3AED), size: 22),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface)),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          child,
        ],
      ),
    );
  }
}

/// Abre o relatório de membros com filtros (sexo, faixa etária, departamento, busca)
/// e escolha de campos para PDF — mesma tela do menu Relatórios.
void openRelatorioMembrosAvancado(
  BuildContext context, {
  required String tenantId,
  required String role,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _RelatorioMembrosPage(tenantId: tenantId, role: role),
    ),
  );
}
