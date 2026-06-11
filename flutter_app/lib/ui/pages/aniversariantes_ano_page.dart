import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/church_birthday_query_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';

/// Página «Aniversariantes do ano» — um mês por secção (query indexada).
class AniversariantesAnoPage extends StatefulWidget {
  /// Legado: docs do stream local (opcional). Se vazio, carrega via [ChurchBirthdayQueryService].
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String tenantId;

  const AniversariantesAnoPage({
    super.key,
    this.docs = const [],
    this.tenantId = '',
  });

  @override
  State<AniversariantesAnoPage> createState() => _AniversariantesAnoPageState();
}

class _AniversariantesAnoPageState extends State<AniversariantesAnoPage> {
  bool _loading = true;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  static const List<String> _meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.docs.isNotEmpty) {
      _docs = widget.docs;
      _loading = false;
    } else {
      _load();
    }
  }

  String get _effectiveTenantId {
    final bound = ChurchContext.currentChurchId?.trim() ?? '';
    if (bound.isNotEmpty) return bound;
    final panel = ChurchContextService.panelChurchId(widget.tenantId);
    return panel.isNotEmpty ? panel : widget.tenantId.trim();
  }

  Future<void> _load() async {
    final tid = _effectiveTenantId;
    if (tid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Igreja não identificada.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await ChurchTenantResilientReads.preparePanelRead();
    final loaded = await ChurchBirthdayQueryService.fetchYearAllMonths(
      tenantId: tid,
      perMonthLimit: ChurchBirthdayQueryService.yearViewPerMonthLimit,
    );
    if (!mounted) return;
    setState(() {
      _docs = loaded;
      _loading = false;
      _error = null;
    });
  }

  static DateTime? _parseBirthDate(Map<String, dynamic> data) =>
      birthDateFromMemberData(data);

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString();

  static Color _avatarColor(Map<String, dynamic> d) {
    final g = genderCategoryFromMemberData(d);
    if (g == 'M') return Colors.blue.shade600;
    if (g == 'F') return Colors.pink.shade400;
    return Colors.grey.shade600;
  }

  static int? _diaDoMes(Map<String, dynamic> data) =>
      _parseBirthDate(data)?.day;

  Map<int, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _porMes() {
    final porMes = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (var m = 1; m <= 12; m++) porMes[m] = [];
    for (final d in _docs) {
      final dt = _parseBirthDate(d.data());
      if (dt == null) continue;
      porMes[dt.month]!.add(d);
    }
    for (var m = 1; m <= 12; m++) {
      porMes[m]!.sort((a, b) {
        final da = _parseBirthDate(a.data());
        final db = _parseBirthDate(b.data());
        if (da == null || db == null) return 0;
        return da.day.compareTo(db.day);
      });
    }
    return porMes;
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Aniversariantes do ano'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: padding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Tentar de novo'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final porMes = _porMes();
                      final total = _docs.length;
                      return ListView(
                        padding: padding,
                        children: [
                          Text(
                            total > 0
                                ? '$total aniversariantes com data cadastrada, organizados por mês.'
                                : 'Nenhum membro com data de nascimento cadastrada.',
                            style: TextStyle(
                              fontSize: 14,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          for (var m = 1; m <= 12; m++) ...[
                            _MesSection(
                              mes: m,
                              mesNome: _meses[m - 1],
                              membros: porMes[m]!,
                              nome: _nome,
                              avatarColor: _avatarColor,
                              diaDoMes: _diaDoMes,
                              tenantId: _effectiveTenantId,
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                          ],
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _ItemAniversariante extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int dia;
  final String Function(Map<String, dynamic>) nome;
  final Color Function(Map<String, dynamic>) avatarColor;
  final String tenantId;

  const _ItemAniversariante({
    required this.doc,
    required this.dia,
    required this.nome,
    required this.avatarColor,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final n = nome(data);
    final cpf = (data['CPF'] ?? data['cpf'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              dia.toString().padLeft(2, '0'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.primary,
                fontSize: 15,
              ),
            ),
          ),
          FotoMembroWidget(
            tenantId: tenantId,
            memberId: doc.id,
            memberData: data,
            cpfDigits: cpf.replaceAll(RegExp(r'\D'), ''),
            size: 44,
            preferListThumbnail: true,
            backgroundColor: avatarColor(data),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              n,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MesSection extends StatelessWidget {
  final int mes;
  final String mesNome;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> membros;
  final String Function(Map<String, dynamic>) nome;
  final Color Function(Map<String, dynamic>) avatarColor;
  final int? Function(Map<String, dynamic>) diaDoMes;
  final String tenantId;

  const _MesSection({
    required this.mes,
    required this.mesNome,
    required this.membros,
    required this.nome,
    required this.avatarColor,
    required this.diaDoMes,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                mesNome,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('${membros.length}'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          if (membros.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nenhum aniversariante em ${_mesesLabel(mes)}.',
                style: TextStyle(
                  color: ThemeCleanPremium.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...membros.map((d) {
              final dia = diaDoMes(d.data()) ?? 0;
              return _ItemAniversariante(
                doc: d,
                dia: dia,
                nome: nome,
                avatarColor: avatarColor,
                tenantId: tenantId,
              );
            }),
        ],
      ),
    );
  }

  static String _mesesLabel(int m) {
    const names = [
      'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
