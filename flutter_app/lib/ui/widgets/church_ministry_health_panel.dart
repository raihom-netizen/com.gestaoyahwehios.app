import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/dashboard/church_ministry_intel.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart';
import 'package:gestao_yahweh/ui/pages/visitors_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Painel "Saúde ministerial & BI" no dashboard da igreja (pastéis, responsivo).
class ChurchMinistryHealthPanel extends StatefulWidget {
  final String tenantId;
  /// Papel do utilizador no painel (pastor, gestor, …) — abrir fichas com as mesmas permissões do módulo.
  final String role;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> memberDocs;
  final bool canViewFinance;
  final VoidCallback? onNavigateToMembers;
  final VoidCallback? onRefreshDashboard;

  const ChurchMinistryHealthPanel({
    super.key,
    required this.tenantId,
    required this.role,
    required this.memberDocs,
    required this.canViewFinance,
    this.onNavigateToMembers,
    this.onRefreshDashboard,
  });

  @override
  State<ChurchMinistryHealthPanel> createState() =>
      _ChurchMinistryHealthPanelState();
}

class _ChurchMinistryHealthPanelState extends State<ChurchMinistryHealthPanel> {
  bool _loading = true;
  String? _error;
  ChurchMinistryIntel? _intel;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visitanteDocs = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _financePanelDocs = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _contasDocs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChurchMinistryHealthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.memberDocs.length != widget.memberDocs.length) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.tenantId.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId.trim());
      final futures = <Future<dynamic>>[
        base.collection('escalas').orderBy('date', descending: true).limit(400).get(),
        base.collection('noticias').orderBy('createdAt', descending: true).limit(200).get(),
        base.collection('visitantes').orderBy('createdAt', descending: true).limit(300).get(),
      ];
      if (widget.canViewFinance) {
        futures.add(base
            .collection('finance')
            .orderBy('createdAt', descending: true)
            .limit(1000)
            .get());
        futures.add(base.collection('contas').orderBy('nome').get());
      }
      futures.add(base.get());
      final out = await Future.wait(futures);
      var i = 0;
      final esc = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      final not = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      final vis = out[i++] as QuerySnapshot<Map<String, dynamic>>;
      List<QueryDocumentSnapshot<Map<String, dynamic>>> finDocs = const [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> contasList = const [];
      if (widget.canViewFinance) {
        finDocs = (out[i++] as QuerySnapshot<Map<String, dynamic>>).docs;
        contasList = (out[i++] as QuerySnapshot<Map<String, dynamic>>).docs;
      }
      final church =
          (out[i] as DocumentSnapshot<Map<String, dynamic>>).data();

      final intel = ChurchMinistryIntelService.build(
        members: widget.memberDocs,
        escalas: esc.docs,
        noticias: not.docs,
        visitantes: vis.docs,
        financeDocs: finDocs,
        churchData: church,
        includeFinance: widget.canViewFinance,
      );
      if (mounted) {
        setState(() {
          _intel = intel;
          _visitanteDocs = vis.docs;
          _financePanelDocs = finDocs;
          _contasDocs = contasList;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível carregar o painel de inteligência.';
          _loading = false;
        });
      }
    }
  }

  static final _brMoney = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w < ThemeCleanPremium.breakpointMobile;

    if (_loading) {
      return _shell(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_error != null) {
      return _shell(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(_error!, style: TextStyle(color: Colors.grey.shade700))),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar'),
              ),
            ],
          ),
        ),
      );
    }
    final intel = _intel!;
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saúde ministerial & inteligência',
                      style: TextStyle(
                        fontSize: narrow ? 17 : 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Últimos ${ChurchMinistryIntelService.staleDays} dias · escalas, eventos (RSVP) e visitantes',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Atualizar dados',
                onPressed: () {
                  _load();
                  widget.onRefreshDashboard?.call();
                },
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpiChip(
                icon: Icons.volunteer_activism_rounded,
                color: const Color(0xFFEF4444),
                label: 'Atenção pastoral',
                value: '${intel.alerts.length}',
                subtitle: 'sem engajamento recente',
              ),
              _kpiChip(
                icon: Icons.how_to_reg_rounded,
                color: const Color(0xFF8B5CF6),
                label: 'Visitantes (mês)',
                value: '${intel.funnel.novosNoMes}',
                subtitle: '${intel.funnel.convertidosNoMes} integrados · ${intel.funnel.emAcompanhamento} em acompanhamento',
              ),
            ],
          ),
          if (intel.alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Membros que precisam de atenção / visita',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            ...intel.alerts.take(8).map((a) => _alertTile(a)),
            if (intel.alerts.length > 8)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onNavigateToMembers,
                  icon: const Icon(Icons.people_rounded, size: 18),
                  label: Text('Ver todos (${intel.alerts.length})'),
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text(
            'Movimento de membros (12 meses)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Novos cadastros, batismos registrados e saídas (inativações por mês)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: narrow ? 200 : 220,
            child: _TriLineChart(flow: intel.last12Months),
          ),
          const SizedBox(height: 16),
          _funnelCard(context, intel.funnel, narrow),
          if (widget.canViewFinance && intel.finance != null) ...[
            const SizedBox(height: 20),
            _financeBlock(context, intel.finance!, narrow),
          ],
          const SizedBox(height: 12),
          Text(
            'Contribuições por membro: quando os lançamentos financeiros passarem a registrar CPF, o algoritmo poderá incluir esse sinal.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _kpiChip({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
                Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertTile(MemberPastoralAlert a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_search_rounded, color: Colors.red.shade400, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(a.summary, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _visitTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is Map) {
      final sec = v['seconds'] ?? v['_seconds'];
      if (sec != null) {
        return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
      }
    }
    return DateTime.tryParse(v.toString());
  }

  /// Mesma regra de [ChurchMinistryIntelService.build] para "novos no mês".
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _funnelDocsNovosMes() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final list = _visitanteDocs.where((d) {
      final ca = _visitTs(d.data()['createdAt']);
      return ca != null && ca.year == start.year && ca.month == start.month;
    }).toList();
    list.sort((a, b) {
      final ta = _visitTs(a.data()['createdAt']);
      final tb = _visitTs(b.data()['createdAt']);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  /// Status exatamente `Em acompanhamento` (contagem do funil).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _funnelDocsAcompanhamento() {
    final list = _visitanteDocs.where((d) {
      final st = (d.data()['status'] ?? 'Novo').toString();
      return st == 'Em acompanhamento';
    }).toList();
    list.sort((a, b) {
      final ta = _visitTs(a.data()['updatedAt']) ?? _visitTs(a.data()['createdAt']);
      final tb = _visitTs(b.data()['updatedAt']) ?? _visitTs(b.data()['createdAt']);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  /// Convertidos com `updatedAt` no mês corrente (igual ao funil).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _funnelDocsIntegradosMes() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final list = _visitanteDocs.where((d) {
      final v = d.data();
      final st = (v['status'] ?? '').toString();
      if (st != 'Convertido') return false;
      final ua = _visitTs(v['updatedAt']);
      return ua != null && ua.year == start.year && ua.month == start.month;
    }).toList();
    list.sort((a, b) {
      final ta = _visitTs(a.data()['updatedAt']);
      final tb = _visitTs(b.data()['updatedAt']);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  Future<void> _openFunnelVisitorListSheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) async {
    final rootCtx = context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.28,
          maxChildSize: 0.92,
          builder: (ctx, sc) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: docs.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Nenhum visitante nesta etapa.',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: sc,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final d = docs[i];
                            final m = d.data();
                            final nome =
                                (m['nome'] ?? m['name'] ?? 'Visitante').toString();
                            final tel = (m['telefone'] ?? '').toString();
                            final st = (m['status'] ?? '').toString();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF8B5CF6)
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      nome.isNotEmpty
                                          ? nome[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6D28D9),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    nome,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    tel.isNotEmpty ? tel : st,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  trailing:
                                      const Icon(Icons.chevron_right_rounded),
                                  onTap: () async {
                                    Navigator.pop(ctx);
                                    if (!rootCtx.mounted) return;
                                    await openChurchVisitorFichaFromDashboard(
                                      rootCtx,
                                      tenantId: widget.tenantId.trim(),
                                      role: widget.role,
                                      visitorDocId: d.id,
                                    );
                                    widget.onRefreshDashboard?.call();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _funnelCard(BuildContext context, VisitorFunnelSnapshot f, bool narrow) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFEEF2FF),
            const Color(0xFFF5F3FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Funil de visitantes',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Toque em cada etapa para ver a lista. Na ficha: editar, follow-up ou excluir.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.25),
          ),
          const SizedBox(height: 6),
          Text(
            'Visitante → Acompanhamento → Membro (convertido)',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (narrow)
            Column(
              children: [
                _funnelStep(
                  'Neste mês',
                  f.novosNoMes,
                  Icons.person_add_rounded,
                  const Color(0xFF6366F1),
                  onTap: () => _openFunnelVisitorListSheet(
                    context,
                    title: 'Novos no mês (${f.novosNoMes})',
                    subtitle:
                        'Visitantes cadastrados neste mês — abre a ficha para editar ou excluir.',
                    docs: _funnelDocsNovosMes(),
                  ),
                ),
                const SizedBox(height: 8),
                _funnelStep(
                  'Em acompanhamento',
                  f.emAcompanhamento,
                  Icons.support_agent_rounded,
                  const Color(0xFF8B5CF6),
                  onTap: () => _openFunnelVisitorListSheet(
                    context,
                    title: 'Em acompanhamento (${f.emAcompanhamento})',
                    subtitle:
                        'Status «Em acompanhamento» — toque no nome para gerir a ficha.',
                    docs: _funnelDocsAcompanhamento(),
                  ),
                ),
                const SizedBox(height: 8),
                _funnelStep(
                  'Integrados no mês',
                  f.convertidosNoMes,
                  Icons.verified_rounded,
                  const Color(0xFF10B981),
                  onTap: () => _openFunnelVisitorListSheet(
                    context,
                    title: 'Integrados no mês (${f.convertidosNoMes})',
                    subtitle:
                        'Convertidos neste mês (data de atualização) — ficha completa ao toque.',
                    docs: _funnelDocsIntegradosMes(),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _funnelStep(
                    'Novos (mês)',
                    f.novosNoMes,
                    Icons.person_add_rounded,
                    const Color(0xFF6366F1),
                    onTap: () => _openFunnelVisitorListSheet(
                      context,
                      title: 'Novos no mês (${f.novosNoMes})',
                      subtitle:
                          'Cadastrados neste mês — toque para abrir a ficha (editar / excluir).',
                      docs: _funnelDocsNovosMes(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _funnelStep(
                    'Acompanhamento',
                    f.emAcompanhamento,
                    Icons.support_agent_rounded,
                    const Color(0xFF8B5CF6),
                    onTap: () => _openFunnelVisitorListSheet(
                      context,
                      title: 'Em acompanhamento (${f.emAcompanhamento})',
                      subtitle:
                          'Lista em acompanhamento pastoral — mesma ficha do módulo Visitantes.',
                      docs: _funnelDocsAcompanhamento(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _funnelStep(
                    'Integrados (mês)',
                    f.convertidosNoMes,
                    Icons.verified_rounded,
                    const Color(0xFF10B981),
                    onTap: () => _openFunnelVisitorListSheet(
                      context,
                      title: 'Integrados no mês (${f.convertidosNoMes})',
                      subtitle:
                          'Status convertido atualizado neste mês.',
                      docs: _funnelDocsIntegradosMes(),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _funnelStep(
    String label,
    int n,
    IconData icon,
    Color c, {
    VoidCallback? onTap,
  }) {
    final inner = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: c.withValues(alpha: 0.5)),
        ],
      ),
    );
    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: inner,
      ),
    );
  }

  Future<void> _openPanelFinanceAccountSheet(
      BuildContext context, String contaId, String contaNome) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.38,
        maxChildSize: 0.96,
        builder: (_, scrollCtrl) => _PanelFinanceContaMovimentos(
          tenantId: widget.tenantId,
          contaId: contaId,
          contaNome: contaNome,
          scrollController: scrollCtrl,
          onReloadParent: () async {
            await _load();
            widget.onRefreshDashboard?.call();
          },
        ),
      ),
    );
  }

  Widget _financeBlock(
      BuildContext context, ChurchFinanceInsight fi, bool narrow) {
    final meta = fi.metaValor != null && fi.metaValor! > 0;
    final pct = meta && fi.metaAcumulado != null
        ? (fi.metaAcumulado!.clamp(0.0, fi.metaValor!) / fi.metaValor!)
            .clamp(0.0, 1.0)
        : 0.0;
    final contasAtivas =
        _contasDocs.where((c) => c.data()['ativo'] != false).toList();
    final saldoPorConta = <String, double>{};
    for (final c in contasAtivas) {
      saldoPorConta[c.id] = 0.0;
    }
    for (final d in _financePanelDocs) {
      final data = d.data();
      final tipo = (data['type'] ?? '').toString().toLowerCase();
      if (tipo != 'transferencia') continue;
      final valor =
          _churchPanelParseValor(data['amount'] ?? data['valor']);
      final origemId = (data['contaOrigemId'] ?? '').toString();
      final destinoId = (data['contaDestinoId'] ?? '').toString();
      if (destinoId.isNotEmpty && saldoPorConta.containsKey(destinoId)) {
        saldoPorConta[destinoId] =
            (saldoPorConta[destinoId] ?? 0) + valor;
      }
      if (origemId.isNotEmpty && saldoPorConta.containsKey(origemId)) {
        saldoPorConta[origemId] = (saldoPorConta[origemId] ?? 0) - valor;
      }
    }

    Widget contaCards() {
      if (contasAtivas.isEmpty) {
        return Text(
          'Cadastre contas em Financeiro → aba Contas para ver saldos e lançamentos por conta aqui.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        );
      }
      final children = contasAtivas.map((acc) {
        final id = acc.id;
        final nome = (acc.data()['nome'] ?? 'Conta').toString();
        final saldo = saldoPorConta[id] ?? 0.0;
        final cor = saldo >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openPanelFinanceAccountSheet(context, id, nome),
            child: Container(
              width: narrow ? null : 168,
              constraints:
                  BoxConstraints(minWidth: narrow ? 0 : 168, maxWidth: narrow ? double.infinity : 168),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: cor.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_rounded,
                          size: 18, color: cor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      Icon(Icons.touch_app_rounded,
                          size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _brMoney.format(saldo),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: cor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Toque para lançamentos',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList();

      if (narrow) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children,
        );
      }
      return SizedBox(
        height: 118,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => children[i],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF0FDF4),
            const Color(0xFFEFF6FF),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.payments_rounded,
                    color: Colors.green.shade700, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Finanças no painel',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text(
                      'Saldos por conta · toque para ver, editar e anexar comprovantes sem sair do painel.',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Saldos por conta (transferências)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          contaCards(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded,
                        color: Colors.green.shade700, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Inteligência (últimos lançamentos carregados)',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Colors.grey.shade800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (narrow) ...[
                  _finRow('Média entradas / mês', _brMoney.format(fi.mediaEntradasMensal)),
                  _finRow('Média saídas / mês', _brMoney.format(fi.mediaSaidasMensal)),
                  _finRow('Projeção saídas', _brMoney.format(fi.projecaoSaidasProxMes)),
                ] else
                  Row(
                    children: [
                      Expanded(
                          child: _finRow('Média entradas / mês',
                              _brMoney.format(fi.mediaEntradasMensal))),
                      Expanded(
                          child: _finRow('Média saídas / mês',
                              _brMoney.format(fi.mediaSaidasMensal))),
                      Expanded(
                          child: _finRow(
                              'Projeção saídas', _brMoney.format(fi.projecaoSaidasProxMes))),
                    ],
                  ),
              ],
            ),
          ),
          if (meta) ...[
            const SizedBox(height: 14),
            Text(
              fi.metaTitulo ?? 'Meta ministerial',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.green.shade900),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 14,
                backgroundColor: Colors.white,
                color: const Color(0xFF22C55E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_brMoney.format(fi.metaAcumulado ?? 0)} de ${_brMoney.format(fi.metaValor!)} (${(pct * 100).toStringAsFixed(0)}%)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            Text(
              'Edite em Cadastro da igreja → seção Meta ministerial (painel).',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _finRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

double _churchPanelParseValor(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0;
}

DateTime _churchPanelParseDate(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String && raw.length >= 10) {
    return DateTime.tryParse(raw.substring(0, 10)) ?? DateTime.now();
  }
  return DateTime.now();
}

bool _churchPanelFinanceDocTouchesAccount(
    QueryDocumentSnapshot<Map<String, dynamic>> d, String contaId) {
  final data = d.data();
  final tipo = (data['type'] ?? '').toString().toLowerCase();
  if (tipo == 'transferencia') {
    return (data['contaOrigemId'] ?? '').toString() == contaId ||
        (data['contaDestinoId'] ?? '').toString() == contaId;
  }
  return (data['contaDestinoId'] ?? '').toString() == contaId ||
      (data['contaOrigemId'] ?? '').toString() == contaId;
}

class _PanelFinanceContaMovimentos extends StatefulWidget {
  final String tenantId;
  final String contaId;
  final String contaNome;
  final ScrollController scrollController;
  final Future<void> Function() onReloadParent;

  const _PanelFinanceContaMovimentos({
    required this.tenantId,
    required this.contaId,
    required this.contaNome,
    required this.scrollController,
    required this.onReloadParent,
  });

  @override
  State<_PanelFinanceContaMovimentos> createState() =>
      _PanelFinanceContaMovimentosState();
}

class _PanelFinanceContaMovimentosState extends State<_PanelFinanceContaMovimentos> {
  bool _loading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('finance')
          .orderBy('createdAt', descending: true)
          .limit(1000)
          .get();
      if (!mounted) return;
      final list = snap.docs
          .where((d) => _churchPanelFinanceDocTouchesAccount(d, widget.contaId))
          .toList();
      list.sort((a, b) => _churchPanelParseDate(b.data()['createdAt'] ?? b.data()['date'])
          .compareTo(_churchPanelParseDate(a.data()['createdAt'] ?? a.data()['date'])));
      setState(() {
        _docs = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _afterMutation() async {
    await _sync();
    await widget.onReloadParent();
  }

  Future<void> _excluir(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await doc.reference.delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lançamento excluído.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    await _afterMutation();
  }

  Future<void> _togglePagamento(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final atual = data['pagamentoConfirmado'] == true;
    await doc.reference.update({'pagamentoConfirmado': !atual});
    await _afterMutation();
  }

  @override
  Widget build(BuildContext context) {
    final br = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.contaNome,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      Text(
                        '${_docs.length} lançamento(s) nesta conta',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _sync,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum lançamento vinculado a esta conta ainda.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: _docs.length,
                        itemBuilder: (context, i) {
                          final doc = _docs[i];
                          final data = doc.data();
                          final tipo =
                              (data['type'] ?? 'entrada').toString().toLowerCase();
                          final isTransfer = tipo == 'transferencia';
                          final isEntrada = !isTransfer &&
                              (tipo.contains('entrada') ||
                                  tipo.contains('receita'));
                          final valor =
                              _churchPanelParseValor(data['amount'] ?? data['valor']);
                          final categoria = (data['categoria'] ?? 'Sem categoria')
                              .toString();
                          final desc = (data['descricao'] ?? '').toString();
                          final dt = _churchPanelParseDate(
                              data['createdAt'] ?? data['date']);
                          final dataStr =
                              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                          final comprovanteUrl =
                              (data['comprovanteUrl'] ?? '').toString();
                          final confirmado = data['pagamentoConfirmado'] == true;
                          final color = isTransfer
                              ? const Color(0xFF6366F1)
                              : (isEntrada
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFFDC2626));
                          final titulo =
                              isTransfer ? 'Transferência' : categoria;
                          final subtitulo = isTransfer
                              ? '${(data['contaOrigemNome'] ?? '')} → ${(data['contaDestinoNome'] ?? '')}'
                              : desc;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => showFinanceLancamentoDetailsBottomSheet(
                                      context,
                                      data: data,
                                      comprovanteUrl: comprovanteUrl,
                                      dataStr: dataStr,
                                      isEntrada: isEntrada,
                                      isTransfer: isTransfer,
                                      color: color,
                                      valor: valor,
                                      titulo: titulo,
                                      subtitulo: subtitulo,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              isTransfer
                                                  ? Icons.swap_horiz_rounded
                                                  : (isEntrada
                                                      ? Icons.trending_up_rounded
                                                      : Icons
                                                          .trending_down_rounded),
                                              color: color,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  titulo,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (subtitulo.isNotEmpty)
                                                  Text(
                                                    subtitulo,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade600,
                                                    ),
                                                  ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      dataStr,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Colors.grey.shade500,
                                                      ),
                                                    ),
                                                    if (comprovanteUrl
                                                        .isNotEmpty)
                                                      Icon(Icons.attach_file_rounded,
                                                          size: 14,
                                                          color: Colors
                                                              .grey.shade500),
                                                    if (confirmado)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                                  0xFFDCFCE7)
                                                              .withValues(
                                                                  alpha: 0.9),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                  999),
                                                        ),
                                                        child: const Text(
                                                          'Pagamento confirmado',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Color(
                                                                0xFF166534),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            isTransfer
                                                ? br.format(valor)
                                                : '${isEntrada ? '+' : '-'} ${br.format(valor)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                              color: color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          await showFinanceLancamentoEditorForTenant(
                                            context,
                                            tenantId: widget.tenantId,
                                            existingDoc: doc,
                                          );
                                          await _afterMutation();
                                        },
                                        icon: const Icon(Icons.edit_rounded, size: 18),
                                        label: const Text('Editar'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _excluir(doc),
                                        icon: const Icon(Icons.delete_outline_rounded,
                                            size: 18),
                                        label: const Text('Excluir'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFDC2626),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            uploadFinanceComprovanteForLancamento(
                                          context,
                                          tenantId: widget.tenantId,
                                          doc: doc,
                                        ).then((_) => _afterMutation()),
                                        icon: const Icon(Icons.photo_camera_rounded,
                                            size: 18),
                                        label: Text(comprovanteUrl.isEmpty
                                            ? 'Anexar'
                                            : 'Trocar anexo'),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: () => _togglePagamento(doc),
                                        icon: Icon(
                                          confirmado
                                              ? Icons.undo_rounded
                                              : Icons.verified_rounded,
                                          size: 18,
                                        ),
                                        label: Text(confirmado
                                            ? 'Desfazer confirmação'
                                            : 'Confirmar pagamento'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _TriLineChart extends StatelessWidget {
  final List<MonthlyMemberFlow> flow;

  const _TriLineChart({required this.flow});

  @override
  Widget build(BuildContext context) {
    if (flow.isEmpty) {
      return const Center(child: Text('Sem dados'));
    }
    final spotsN = <FlSpot>[];
    final spotsB = <FlSpot>[];
    final spotsS = <FlSpot>[];
    double maxY = 4;
    for (var i = 0; i < flow.length; i++) {
      final f = flow[i];
      spotsN.add(FlSpot(i.toDouble(), f.novos.toDouble()));
      spotsB.add(FlSpot(i.toDouble(), f.batismos.toDouble()));
      spotsS.add(FlSpot(i.toDouble(), f.saidas.toDouble()));
      maxY = [maxY, f.novos.toDouble(), f.batismos.toDouble(), f.saidas.toDouble()]
          .reduce((a, b) => a > b ? a : b);
    }
    maxY = maxY < 4 ? 4 : maxY * 1.15;

    String labelX(double v) {
      final i = v.toInt();
      if (i < 0 || i >= flow.length) return '';
      final p = flow[i].key.split('-');
      if (p.length < 2) return '';
      final m = int.tryParse(p[1]) ?? 1;
      const abbr = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
      return abbr[(m - 1).clamp(0, 11)];
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  labelX(v),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spotsN,
            isCurved: true,
            color: const Color(0xFF3B82F6),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: spotsB,
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: spotsS,
            isCurved: true,
            color: const Color(0xFFF97316),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
    );
  }
}
