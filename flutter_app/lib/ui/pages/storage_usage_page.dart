import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/church_storage_usage_service.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Acompanhamento de uso do Firestore (Firebase) por igreja — custos estimados e visão financeira vs plano.
class StorageUsagePage extends StatefulWidget {
  final String tenantId;
  final String role;
  final VoidCallback? onCleaned;
  /// Dentro do painel master — sem Scaffold/AppBar duplicado.
  final bool embedded;

  const StorageUsagePage({
    super.key,
    required this.tenantId,
    required this.role,
    this.onCleaned,
    this.embedded = false,
  });

  @override
  State<StorageUsagePage> createState() => _StorageUsagePageState();
}

class _StorageUsagePageState extends State<StorageUsagePage> {
  Map<String, dynamic>? _usage;
  Map<String, dynamic>? _churchData;
  String? _error;
  bool _loading = true;
  bool _usingLocalFirestoreEstimate = false;

  static const double _usdPerGbMonth = 0.18;
  static const double _brlPerUsd = 5.5;
  static const double _opsCostPerDocBrl = 0.00002;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _usage = null;
      _usingLocalFirestoreEstimate = false;
    });
    try {
      final result = await ChurchStorageUsageService.load(widget.tenantId);
      if (!mounted) return;
      setState(() {
        _usage = result.usage;
        _churchData = result.churchData;
        _loading = false;
        _usingLocalFirestoreEstimate = result.usingLocalEstimate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = MasterAdminFirestore.formatLoadError(e);
      });
    }
  }

  Future<void> _confirmarLimparDados() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Limpar todos os dados da igreja?'),
        content: const Text(
          'Todos os dados vinculados a esta igreja (membros, notícias, eventos, visitantes, financeiro, etc.) serão apagados permanentemente do banco. A igreja deixará de existir no sistema. Esta ação não pode ser desfeita.\n\nDeseja realmente continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            child: const Text('Sim, limpar tudo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await BillingLicenseService().removerIgrejaELimparDados(widget.tenantId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dados da igreja removidos. Atualize a lista de igrejas.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onCleaned?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao limpar: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    }
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String _fmtBrl(num? v) {
    if (v == null) return '—';
    return NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(v);
  }

  PlanoOficial? _planForChurch() {
    final id = (_churchData?['plano'] ?? 'free').toString().trim();
    if (id.isEmpty || id == 'free') return null;
    for (final p in planosOficiais) {
      if (p.id == id) return p;
    }
    return null;
  }

  double? _monthlyRevenueBrl() {
    final plan = _planForChurch();
    if (plan == null) return 0;
    final mp = plan.monthlyPrice;
    if (mp == null) return null;
    final cycle =
        (_churchData?['billingCycle'] ?? 'monthly').toString().trim();
    if (cycle == 'annual') {
      return mp * 10 / 12;
    }
    return mp;
  }

  ({double storage, double ops, double total}) _infraEstimate(int bytes, int totalDocs) {
    final gb = bytes / (1024 * 1024 * 1024);
    final storage = gb * _usdPerGbMonth * _brlPerUsd;
    final ops = totalDocs * _opsCostPerDocBrl;
    return (storage: storage, ops: ops, total: storage + ops);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

    final body = RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: widget.embedded
            ? EdgeInsets.zero
            : padding,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embedded) const SizedBox(height: 12),
            if (!widget.embedded)
              _PremiumHeader(
                churchName: (_churchData?['nome'] ??
                        _churchData?['razaoSocial'] ??
                        '')
                    .toString(),
              ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  MasterPremiumCard(
                    expandWidth: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: ThemeCleanPremium.error, size: 26),
                            const SizedBox(width: 10),
                            Text(
                              'Erro ao carregar',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Tentar novamente'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_usage != null) ...[
                  if (_usingLocalFirestoreEstimate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _InfoPill(
                        icon: Icons.info_outline_rounded,
                        text:
                            'Estimativa local: amostra até ${YahwehPerformanceV4.masterStorageEstimateSampleLimit} docs por coleção; totais podem ser maiores.',
                        color: Colors.amber.shade800,
                        bg: Colors.amber.shade50,
                      ),
                    ),
                  _buildEconomicsSummary(brl),
                  const SizedBox(height: 16),
                  _buildFirestoreChartsSection(),
                  const SizedBox(height: 16),
                  MasterPremiumCard(
                    expandWidth: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cleaning_services_rounded,
                                color: ThemeCleanPremium.primary, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              'Gerenciar dados',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Limpar todos os dados desta igreja libera espaço no Firebase. Use apenas se a igreja não for mais utilizar o sistema. Irreversível.',
                          style: TextStyle(
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _confirmarLimparDados,
                          icon: const Icon(Icons.delete_forever_rounded, size: 20),
                          label: const Text('Limpar todos os dados desta igreja'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error,
                            side: BorderSide(
                              color: ThemeCleanPremium.error
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            SizedBox(height: widget.embedded ? 8 : 28),
          ],
        ),
      ),
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Armazenamento Firebase'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildEconomicsSummary(NumberFormat brl) {
    final firestore = _usage!['firestore'];
    if (firestore == null) return const SizedBox.shrink();
    final map = Map<String, dynamic>.from(firestore as Map);
    final totalDocs = (map['totalDocs'] as num?)?.toInt() ?? 0;
    final estimateBytes = (map['estimateBytes'] as num?)?.toInt() ?? 0;
    final infra = _infraEstimate(estimateBytes, totalDocs);
    final rev = _monthlyRevenueBrl();
    final margin = rev != null ? rev - infra.total : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Financeiro (plano vs custo estimado de infra)',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Receita: valor mensal equivalente ao plano cadastrado. Custos: proxy aproximado (armazenamento Firestore + operações). Não substitui a fatura Google Cloud.',
          style: TextStyle(
            fontSize: 12,
            color: ThemeCleanPremium.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final plan = _planForChurch();
            final planLabel = plan?.name ?? 'Plano free / não informado';

            Widget kpi({
              required String title,
              required String value,
              required IconData icon,
              required List<Color> gradient,
            }) {
              return Expanded(
                child: _KpiTile(
                  title: title,
                  value: value,
                  icon: icon,
                  gradient: gradient,
                ),
              );
            }

            final row1 = Row(
              children: [
                kpi(
                  title: 'Receita mensal (plano)',
                  value: rev == null
                      ? 'Sob consulta'
                      : brl.format(rev),
                  icon: Icons.payments_rounded,
                  gradient: const [
                    Color(0xFF2563EB),
                    Color(0xFF1D4ED8),
                  ],
                ),
                const SizedBox(width: 10),
                kpi(
                  title: 'Custo infra (est.)',
                  value: brl.format(infra.total),
                  icon: Icons.cloud_rounded,
                  gradient: const [
                    Color(0xFF64748B),
                    Color(0xFF475569),
                  ],
                ),
              ],
            );

            final row2 = Row(
              children: [
                kpi(
                  title: margin != null && margin >= 0
                      ? 'Margem estimada'
                      : 'Saldo estimado',
                  value: margin == null ? '—' : brl.format(margin),
                  icon: margin != null && margin >= 0
                      ? Icons.trending_up_rounded
                      : Icons.warning_amber_rounded,
                  gradient: margin != null && margin >= 0
                      ? const [Color(0xFF059669), Color(0xFF047857)]
                      : const [Color(0xFFEA580C), Color(0xFFC2410C)],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _KpiTile(
                    title: 'Plano atual',
                    value: planLabel,
                    icon: Icons.workspace_premium_rounded,
                    gradient: const [
                      Color(0xFF7C3AED),
                      Color(0xFF6D28D9),
                    ],
                  ),
                ),
              ],
            );

            return Column(
              children: [
                row1,
                const SizedBox(height: 10),
                row2,
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        MasterPremiumCard(
          expandWidth: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comparativo receita × custo (estimado)',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              _HorizontalRatioBar(
                label: 'Receita mensal (plano)',
                value: rev ?? 0,
                max: _maxForBar([rev ?? 0, infra.total]),
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 10),
              _HorizontalRatioBar(
                label: 'Custo infra (est.)',
                value: infra.total,
                max: _maxForBar([rev ?? 0, infra.total]),
                color: const Color(0xFF64748B),
              ),
              const SizedBox(height: 8),
              Text(
                'Detalhe custo: armazenamento ${_fmtBrl(infra.storage)} + operações ${_fmtBrl(infra.ops)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _maxForBar(List<double> values) {
    final m = values.fold<double>(0, (a, b) => a > b ? a : b);
    return m <= 0 ? 1 : m * 1.15;
  }

  Widget _buildFirestoreChartsSection() {
    final firestore = _usage!['firestore'];
    if (firestore == null) {
      return const Text('Dados do Firestore não disponíveis.');
    }
    final map = Map<String, dynamic>.from(firestore as Map);
    final counts = map['docCounts'] as Map?;
    final totalDocs = (map['totalDocs'] as num?)?.toInt() ?? 0;
    final estimateBytes = (map['estimateBytes'] as num?)?.toInt() ?? 0;

    final entries = <MapEntry<String, int>>[];
    if (counts != null) {
      for (final e in counts.entries) {
        final n = (e.value as num?)?.toInt() ?? 0;
        entries.add(MapEntry(e.key.toString(), n));
      }
      entries.sort((a, b) => b.value.compareTo(a.value));
    }

    final maxCount =
        entries.isEmpty ? 1 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    const labels = <String, String>{
      'members': 'Membros',
      'membros': 'Membros (legado)',
      'noticias': 'Notícias / eventos',
      'avisos': 'Avisos (mural)',
      'usersIndex': 'Índice de usuários',
      'event_templates': 'Modelos de evento',
      'departamentos': 'Departamentos',
      'patrimonio': 'Patrimônio',
      'cultos': 'Cultos',
      'visitantes': 'Visitantes',
      'eventos': 'Eventos',
      'pedidosOracao': 'Pedidos de oração',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Banco de dados (Firestore)',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: ThemeCleanPremium.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Documentos por coleção e espaço estimado (tamanho aproximado dos dados).',
          style: TextStyle(
            fontSize: 12,
            color: ThemeCleanPremium.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        MasterPremiumCard(
          expandWidth: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_rounded,
                      color: ThemeCleanPremium.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Distribuição de documentos',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (entries.isEmpty)
                Text(
                  'Sem detalhamento de coleções.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              else
                ...entries.map((e) {
                  final label = labels[e.key] ?? e.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HorizontalRatioBar(
                      label: label,
                      value: e.value.toDouble(),
                      max: maxCount.toDouble(),
                      color: ThemeCleanPremium.primary,
                      valueSuffix: ' docs',
                    ),
                  );
                }),
              const Divider(height: 22),
              _HorizontalRatioBar(
                label: 'Volume estimado no banco',
                value: estimateBytes.toDouble(),
                max: _referenceBytesMax(estimateBytes).toDouble(),
                color: const Color(0xFF0EA5E9),
                displayValue: _fmtBytes(estimateBytes),
              ),
              const SizedBox(height: 6),
              Text(
                'Total: ~$totalDocs docs · ${_fmtBytes(estimateBytes)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _referenceBytesMax(int bytes) {
    final mb = bytes / (1024 * 1024);
    final cap = mb <= 1 ? 1.0 : (mb * 1.25).clamp(2.0, 500.0);
    return (cap * 1024 * 1024).ceil();
  }
}

class _PremiumHeader extends StatelessWidget {
  final String churchName;

  const _PremiumHeader({required this.churchName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary,
            ThemeCleanPremium.primary.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.dataset_linked_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Uso Firebase por igreja',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          if (churchName.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              churchName.trim(),
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Firestore e Firebase Storage. Estimativas de espaço e custo são aproximadas.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color bg;

  const _InfoPill({
    required this.icon,
    required this.text,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final List<Color> gradient;

  const _KpiTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.95), size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalRatioBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color color;
  final String? displayValue;
  final String valueSuffix;

  const _HorizontalRatioBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.displayValue,
    this.valueSuffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final frac = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    final valueText = displayValue ??
        '${value.round()}$valueSuffix';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 11,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFFE2E8F0)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: frac,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.75)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChurchStorageRowState {
  final MasterChurchListItem church;
  ChurchStorageUsageResult? result;
  String? error;
  bool loading;

  _ChurchStorageRowState({
    required this.church,
    this.result,
    this.error,
    this.loading = false,
  });
}

/// Visão master: consumo Firestore de **todas** as igrejas + detalhe sob demanda.
class StorageUsageMasterPage extends StatefulWidget {
  const StorageUsageMasterPage({super.key});

  @override
  State<StorageUsageMasterPage> createState() => _StorageUsageMasterPageState();
}

class _StorageUsageMasterPageState extends State<StorageUsageMasterPage> {
  List<MasterChurchListItem> _tenants = [];
  final Map<String, _ChurchStorageRowState> _rows = {};
  String? _tenantsError;
  bool _loadingTenants = true;
  bool _loadingUsage = false;
  String? _selectedTenantId;
  String _search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadTenants());
  }

  String _churchName(MasterChurchListItem c) =>
      (c.data['nome'] ?? c.data['razaoSocial'] ?? c.data['name'] ?? c.id)
          .toString()
          .trim();

  List<MasterChurchListItem> get _filteredTenants {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _tenants;
    return _tenants.where((c) {
      final nome = _churchName(c).toLowerCase();
      return nome.contains(q) || c.id.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadTenants({bool force = false}) async {
    final mem = MasterChurchesListService.peekMemory();
    if (!force && mem != null && mem.isNotEmpty) {
      setState(() {
        _tenants = mem;
        _loadingTenants = false;
        _tenantsError = null;
      });
      unawaited(_loadAllUsage());
    } else {
      setState(() {
        _loadingTenants = true;
        _tenantsError = null;
      });
    }

    try {
      var list = await FirestoreWebGuard.runWithWebRecovery(
        () => MasterChurchesListService.loadFast(force: force)
            .timeout(const Duration(seconds: 25)),
      );
      if (list.isEmpty && !force) {
        list = await FirestoreWebGuard.runWithWebRecovery(
          () => MasterChurchesListService.loadFast(force: true)
              .timeout(const Duration(seconds: 28)),
        );
      }
      if (!mounted) return;
      setState(() {
        _tenants = list;
        _loadingTenants = false;
        _tenantsError = list.isEmpty
            ? 'Nenhuma igreja encontrada no índice master.'
            : null;
      });
      if (list.isNotEmpty) {
        await _loadAllUsage();
      }
    } catch (e) {
      if (!mounted) return;
      final cached = MasterChurchesListService.peekMemory();
      setState(() {
        _loadingTenants = false;
        if (cached != null && cached.isNotEmpty) {
          _tenants = cached;
          _tenantsError = null;
        } else {
          _tenantsError = MasterAdminFirestore.formatLoadError(e);
        }
      });
      if (cached != null && cached.isNotEmpty) {
        unawaited(_loadAllUsage());
      }
    }
  }

  Future<void> _loadAllUsage() async {
    if (_tenants.isEmpty || !mounted) return;
    setState(() {
      _loadingUsage = true;
      for (final c in _tenants) {
        _rows[c.id] = _ChurchStorageRowState(church: c, loading: true);
      }
    });

    for (final church in _tenants) {
      if (!mounted) return;
      try {
        final result = await ChurchStorageUsageService.load(church.id);
        if (!mounted) return;
        setState(() {
          _rows[church.id] = _ChurchStorageRowState(
            church: church,
            result: result,
            loading: false,
          );
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _rows[church.id] = _ChurchStorageRowState(
            church: church,
            error: MasterAdminFirestore.formatLoadError(e),
            loading: false,
          );
        });
      }
    }

    if (mounted) setState(() => _loadingUsage = false);
  }

  int get _totalDocs => _rows.values.fold<int>(
        0,
        (acc, r) => acc + (r.result?.totalDocs ?? 0),
      );

  int get _totalBytes => _rows.values.fold<int>(
        0,
        (acc, r) => acc + (r.result?.estimateBytes ?? 0),
      );

  int get _maxBytes {
    var m = 1;
    for (final r in _rows.values) {
      final b = r.result?.estimateBytes ?? 0;
      if (b > m) m = b;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    final filtered = _filteredTenants;

    if (_loadingTenants && _tenants.isEmpty) {
      return Scaffold(
        primary: false,
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_tenants.isEmpty) {
      return Scaffold(
        primary: false,
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.church_rounded,
                      size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    _tenantsError ?? 'Nenhuma igreja cadastrada',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _loadTenants(force: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadTenants(force: true);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: padding.copyWith(bottom: 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MasterStorageHeader(
                        churchCount: _tenants.length,
                        totalDocs: _totalDocs,
                        totalBytes: _totalBytes,
                        loadingUsage: _loadingUsage,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar igreja por nome ou ID…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                      if (_tenantsError != null) ...[
                        const SizedBox(height: 12),
                        _InfoPill(
                          icon: Icons.info_outline_rounded,
                          text: _tenantsError!,
                          color: Colors.orange.shade800,
                          bg: Colors.orange.shade50,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Consumo por igreja',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Firestore — documentos e volume estimado. Toque numa igreja para ver gráficos, financeiro e limpeza de dados.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  0,
                  padding.right,
                  8,
                ),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final church = filtered[i];
                    final row = _rows[church.id];
                    return _ChurchStorageCard(
                      church: church,
                      churchName: _churchName(church),
                      row: row,
                      maxBytes: _maxBytes,
                      expanded: _selectedTenantId == church.id,
                      onTap: () => setState(() {
                        _selectedTenantId =
                            _selectedTenantId == church.id ? null : church.id;
                      }),
                      onRetry: () async {
                        setState(() {
                          _rows[church.id] = _ChurchStorageRowState(
                            church: church,
                            loading: true,
                          );
                        });
                        try {
                          final result =
                              await ChurchStorageUsageService.load(church.id);
                          if (!mounted) return;
                          setState(() {
                            _rows[church.id] = _ChurchStorageRowState(
                              church: church,
                              result: result,
                            );
                          });
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _rows[church.id] = _ChurchStorageRowState(
                              church: church,
                              error: MasterAdminFirestore.formatLoadError(e),
                            );
                          });
                        }
                      },
                    );
                  },
                ),
              ),
              if (_selectedTenantId != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    8,
                    padding.right,
                    padding.bottom + 24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: MasterPremiumCard(
                      expandWidth: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.analytics_outlined,
                                  color: ThemeCleanPremium.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Detalhe — ${_churchName(_tenants.firstWhere((c) => c.id == _selectedTenantId, orElse: () => _tenants.first))}',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fechar detalhe',
                                onPressed: () =>
                                    setState(() => _selectedTenantId = null),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: isMobile ? 520 : 640,
                            child: StorageUsagePage(
                              key: ValueKey(_selectedTenantId),
                              tenantId: _selectedTenantId!,
                              role: 'admin',
                              embedded: true,
                              onCleaned: () {
                                _loadTenants(force: true);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterStorageHeader extends StatelessWidget {
  final int churchCount;
  final int totalDocs;
  final int totalBytes;
  final bool loadingUsage;

  const _MasterStorageHeader({
    required this.churchCount,
    required this.totalDocs,
    required this.totalBytes,
    required this.loadingUsage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ThemeCleanPremium.primary,
                      ThemeCleanPremium.primaryLight,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.storage_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Armazenamento por igreja',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visão consolidada do Firestore — todas as igrejas num só painel.',
                      style: TextStyle(
                        fontSize: 13,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (loadingUsage)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 560;
              final kpis = [
                MasterKpiCard(
                  label: 'Igrejas',
                  value: '$churchCount',
                  icon: Icons.church_rounded,
                  accent: const Color(0xFF2563EB),
                ),
                MasterKpiCard(
                  label: 'Documentos (est.)',
                  value: loadingUsage ? '…' : '~$totalDocs',
                  icon: Icons.description_rounded,
                  accent: const Color(0xFF0F766E),
                ),
                MasterKpiCard(
                  label: 'Volume (est.)',
                  value: loadingUsage
                      ? '…'
                      : ChurchStorageUsageService.formatBytes(totalBytes),
                  icon: Icons.data_usage_rounded,
                  accent: const Color(0xFF7C3AED),
                ),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (var i = 0; i < kpis.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      kpis[i],
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: kpis[0]),
                  const SizedBox(width: 8),
                  Expanded(child: kpis[1]),
                  const SizedBox(width: 8),
                  Expanded(child: kpis[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChurchStorageCard extends StatelessWidget {
  final MasterChurchListItem church;
  final String churchName;
  final _ChurchStorageRowState? row;
  final int maxBytes;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  const _ChurchStorageCard({
    required this.church,
    required this.churchName,
    required this.row,
    required this.maxBytes,
    required this.expanded,
    required this.onTap,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final loading = row?.loading ?? true;
    final error = row?.error;
    final result = row?.result;
    final docs = result?.totalDocs ?? 0;
    final bytes = result?.estimateBytes ?? 0;
    final plano = (church.data['plano'] ?? 'free').toString();
    final frac = maxBytes > 0 ? (bytes / maxBytes).clamp(0.05, 1.0) : 0.05;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: expanded ? const Color(0xFFF0F9FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
              color: expanded
                  ? ThemeCleanPremium.primary.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F0),
              width: expanded ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.church_rounded,
                        color: ThemeCleanPremium.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          churchName.isEmpty ? church.id : churchName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          church.id,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Plano: $plano',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.chevron_right_rounded,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading)
                const LinearProgressIndicator(minHeight: 6)
              else if (error != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeCleanPremium.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Tentar'),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '~$docs docs',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      ChurchStorageUsageService.formatBytes(bytes),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: ThemeCleanPremium.primary,
                  ),
                ),
                if (result?.usingLocalEstimate == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Estimativa local (amostra por coleção)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
