import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/brasil_bancos.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/finance_account_migrate_service.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/finance_premium_widgets.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

enum _PeriodPreset { last30, last90, last365, custom }

enum _MigracaoModo { semConta, transferirBanco }

enum _TipoFiltro { todos, receitas, despesas }

String _contaDisplayName(Map<String, dynamic> d) {
  final n = (d['nome'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  final b = (d['bancoNome'] ?? '').toString().trim();
  return b.isNotEmpty ? b : 'Conta';
}

DateTime _lancInstant(Map<String, dynamic> data) =>
    financeLancamentoDate(data) ?? DateTime.now();

Color _contaAccent(Map<String, dynamic> d) {
  final branding = brasilBancoBrandingFor(
    codigo: (d['bancoCodigo'] ?? '').toString(),
    nome: (d['bancoNome'] ?? '').toString(),
  );
  return Color(branding.colorHex);
}

/// Assistente de migração — sem banco → conta, ou entre bancos (Controle Total).
class FinanceBulkAssignPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final DateTime? initialRangeFrom;
  final DateTime? initialRangeTo;
  final String? initialSourceAccountId;

  const FinanceBulkAssignPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.initialRangeFrom,
    this.initialRangeTo,
    this.initialSourceAccountId,
  });

  @override
  State<FinanceBulkAssignPage> createState() => _FinanceBulkAssignPageState();
}

class _FinanceBulkAssignPageState extends State<FinanceBulkAssignPage> {
  late final CollectionReference<Map<String, dynamic>> _finRef;
  late final CollectionReference<Map<String, dynamic>> _contasRef;

  _MigracaoModo _modo = _MigracaoModo.semConta;
  _TipoFiltro _tipoFiltro = _TipoFiltro.todos;
  _PeriodPreset _preset = _PeriodPreset.last30;
  late DateTime _from;
  late DateTime _to;
  final _filterCtrl = TextEditingController();
  String? _sourceAccountId;
  String? _destAccountId;
  bool _loadingApply = false;
  bool _loadingList = false;
  String? _listError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _transactions = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _contas = [];
  bool _loadingContas = true;
  String? _contasError;
  final Set<String> _checkedIds = {};

  @override
  void initState() {
    super.initState();
    _finRef = ChurchUiCollections.financeiro(widget.tenantId);
    _contasRef = ChurchUiCollections.contas(widget.tenantId);
    _filterCtrl.addListener(_onFilterChanged);

    final src = widget.initialSourceAccountId?.trim();
    if (src != null && src.isNotEmpty) {
      _modo = _MigracaoModo.transferirBanco;
      _sourceAccountId = src;
    }

    if (widget.initialRangeFrom != null && widget.initialRangeTo != null) {
      _from = DateTime(
        widget.initialRangeFrom!.year,
        widget.initialRangeFrom!.month,
        widget.initialRangeFrom!.day,
      );
      _to = DateTime(
        widget.initialRangeTo!.year,
        widget.initialRangeTo!.month,
        widget.initialRangeTo!.day,
        23,
        59,
        59,
      );
      _preset = _PeriodPreset.custom;
    } else {
      _applyPreset(_PeriodPreset.last30, reload: false);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      unawaited(_loadContas());
      unawaited(_reloadList());
    });
  }

  Future<void> _loadContas() async {
    setState(() {
      _loadingContas = true;
      _contasError = null;
    });
    try {
      final churchId = ChurchRepository.churchId(widget.tenantId);
      final result = await ChurchFinanceLoadService.loadContas(
        seedTenantId: churchId,
        forceRefresh: false,
      );
      if (!mounted) return;
      setState(() {
        _contas = dedupeContasDocuments(result.docs);
        _loadingContas = false;
        if (_destAccountId == null) {
          final first = _contas
              .where((d) => d.data()['ativo'] != false)
              .map((d) => d.id)
              .toList();
          if (first.isNotEmpty) _destAccountId = first.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contas = [];
        _loadingContas = false;
        _contasError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _filterCtrl.removeListener(_onFilterChanged);
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    _retainCheckedInFiltered();
    setState(() {});
  }

  void _applyPreset(_PeriodPreset p, {bool reload = true}) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    late DateTime start;
    switch (p) {
      case _PeriodPreset.last30:
        final s = end.subtract(const Duration(days: 29));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.last90:
        final s = end.subtract(const Duration(days: 89));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.last365:
        final s = end.subtract(const Duration(days: 364));
        start = DateTime(s.year, s.month, s.day);
        break;
      case _PeriodPreset.custom:
        return;
    }
    setState(() {
      _preset = p;
      _from = start;
      _to = end;
    });
    if (reload) unawaited(_reloadList());
  }

  bool _passesTipo(Map<String, dynamic> d) {
    final tipo = financeInferTipo(d);
    switch (_tipoFiltro) {
      case _TipoFiltro.todos:
        return true;
      case _TipoFiltro.receitas:
        return tipo.contains('entrada') || tipo.contains('receita');
      case _TipoFiltro.despesas:
        return tipo.contains('saida') ||
            tipo.contains('saída') ||
            tipo.contains('despesa');
    }
  }

  bool _passesOrigem(Map<String, dynamic> d) {
    if (_modo == _MigracaoModo.semConta) {
      return FinanceAccountMigrateService.semContaLancamento(d);
    }
    final src = _sourceAccountId?.trim() ?? '';
    if (src.isEmpty) return false;
    return FinanceAccountMigrateService.lancamentoVinculadoConta(d, contaId: src);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredList() {
    final q = _filterCtrl.text.trim().toLowerCase();
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> list = _transactions;
    if (q.isNotEmpty) {
      list = list.where((doc) {
        final d = doc.data();
        final cat = (d['categoria'] ?? '').toString();
        final desc = (d['descricao'] ?? '').toString();
        final tipo = financeInferTipo(d);
        final val = formatBrCurrencyInitial(
            financeParseValorBr(d['amount'] ?? d['valor']));
        final blob = '$cat $desc $tipo $val'.toLowerCase();
        return blob.contains(q);
      });
    }
    return list.toList();
  }

  void _retainCheckedInFiltered() {
    final vis = _filteredList().map((e) => e.id).toSet();
    _checkedIds.removeWhere((id) => !vis.contains(id));
  }

  void _selectAllFiltered() =>
      setState(() => _checkedIds.addAll(_filteredList().map((e) => e.id)));

  void _deselectFiltered() {
    setState(() {
      for (final id in _filteredList().map((e) => e.id)) {
        _checkedIds.remove(id);
      }
    });
  }

  Future<void> _reloadList() async {
    if (_modo == _MigracaoModo.transferirBanco &&
        (_sourceAccountId == null || _sourceAccountId!.trim().isEmpty)) {
      setState(() {
        _transactions = [];
        _checkedIds.clear();
        _loadingList = false;
        _listError = null;
      });
      return;
    }

    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      var f = DateTime(_from.year, _from.month, _from.day);
      var t = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
      if (t.isBefore(f)) {
        final tmp = f;
        f = DateTime(t.year, t.month, t.day);
        t = DateTime(tmp.year, tmp.month, tmp.day, 23, 59, 59);
      }
      final snap = await _finRef.orderBy('createdAt', descending: true).get();
      if (!mounted) return;
      final list = snap.docs.where((doc) {
        final d = doc.data();
        if (!_passesOrigem(d) || !_passesTipo(d)) return false;
        final instant = _lancInstant(d);
        return !instant.isBefore(f) && !instant.isAfter(t);
      }).toList();
      setState(() {
        _transactions = list;
        _loadingList = false;
        _checkedIds
          ..clear()
          ..addAll(list.map((e) => e.id));
      });
      _retainCheckedInFiltered();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transactions = [];
        _checkedIds.clear();
        _listError = e.toString();
        _loadingList = false;
      });
    }
  }

  Future<bool> _confirmApply(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> contas, int count) async {
    if (_modo == _MigracaoModo.semConta) return true;
    final src = _sourceAccountId!;
    final dest = _destAccountId!;
    String label(String? id) {
      for (final d in contas) {
        if (d.id == id) return _contaDisplayName(d.data());
      }
      return 'Conta';
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(Icons.swap_horiz_rounded,
            color: ThemeCleanPremium.primary, size: 40),
        title: const Text('Confirmar migração', textAlign: TextAlign.center),
        content: Text(
          'Mover $count lançamento(s) de «${label(src)}» para «${label(dest)}»? '
          'Os saldos das contas serão recalculados automaticamente.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, migrar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _apply(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> contas) async {
    final dest = _destAccountId?.trim();
    if (dest == null || dest.isEmpty) {
      showFinanceSaveSnackBar(
        context,
        message: 'Escolha o banco de destino.',
        isError: true,
      );
      return;
    }
    if (_modo == _MigracaoModo.transferirBanco) {
      final src = _sourceAccountId?.trim();
      if (src == null || src.isEmpty) {
        showFinanceSaveSnackBar(
          context,
          message: 'Escolha o banco de origem.',
          isError: true,
        );
        return;
      }
      if (src == dest) {
        showFinanceSaveSnackBar(
          context,
          message: 'Origem e destino devem ser bancos diferentes.',
          isError: true,
        );
        return;
      }
    }

    final destNome = _contaDisplayName(
      contas.firstWhere((d) => d.id == dest).data(),
    );
    final targets =
        _filteredList().where((d) => _checkedIds.contains(d.id)).toList();
    if (targets.isEmpty) {
      showFinanceSaveSnackBar(
        context,
        message: 'Marque ao menos um lançamento.',
        isError: true,
      );
      return;
    }

    if (!await _confirmApply(contas, targets.length)) return;

    setState(() => _loadingApply = true);
    try {
      final n = await FinanceAccountMigrateService.migrateDocuments(
        churchId: widget.tenantId,
        docs: targets,
        destAccountId: dest,
        destAccountName: destNome,
        sourceAccountId: _modo == _MigracaoModo.transferirBanco
            ? _sourceAccountId
            : null,
      );
      if (!mounted) return;
      showFinanceSaveSnackBar(
        context,
        message: _modo == _MigracaoModo.semConta
            ? '$n lançamento(s) vinculados a «$destNome».'
            : '$n lançamento(s) migrados para «$destNome».',
      );
      await _reloadList();
    } catch (e) {
      if (mounted) {
        showFinanceSaveSnackBar(
          context,
          message: 'Erro: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingApply = false);
    }
  }

  Widget _headerHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Migrar lançamentos',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _modo == _MigracaoModo.semConta
                ? 'Vincule receitas e despesas sem banco a uma conta de destino.'
                : 'Transfira lançamentos de um banco/cartão para outro — saldos atualizados.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipoChip(String label, _TipoFiltro tipo, Color color, IconData icon) {
    final selected = _tipoFiltro == tipo;
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : color)),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      onSelected: (_) {
        setState(() => _tipoFiltro = tipo);
        unawaited(_reloadList());
      },
    );
  }

  Widget _accountDropdown({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> contas,
    required String? value,
    required String hint,
    required ValueChanged<String?> onChanged,
    String? excludeId,
  }) {
    final items = contas
        .where((d) => d.data()['ativo'] != false)
        .where((d) => excludeId == null || d.id != excludeId)
        .toList();
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value != null && items.any((d) => d.id == value) ? value : null,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      hint: Text(hint),
      items: items
          .map(
            (d) => DropdownMenuItem<String>(
              value: d.id,
              child: Row(
                children: [
                  FinanceBankMiniLogo(
                    bancoCodigo: (d.data()['bancoCodigo'] ?? '').toString(),
                    bancoNome: (d.data()['bancoNome'] ?? '').toString(),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _contaDisplayName(d.data()),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _txCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final tipo = financeInferTipo(d);
    final income =
        tipo.contains('entrada') || tipo.contains('receita');
    final accent = income
        ? const Color(0xFF16A34A)
        : tipo == 'transferencia'
            ? const Color(0xFF6366F1)
            : const Color(0xFFDC2626);
    final checked = _checkedIds.contains(doc.id);
    final val = financeParseValorBr(d['amount'] ?? d['valor']);
    final title = (d['descricao'] ?? d['categoria'] ?? '-').toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() {
          if (checked) {
            _checkedIds.remove(doc.id);
          } else {
            _checkedIds.add(doc.id);
          }
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: checked ? accent : const Color(0xFFE2E8F0),
              width: checked ? 2 : 1,
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 72,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Checkbox(
                value: checked,
                activeColor: accent,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _checkedIds.add(doc.id);
                  } else {
                    _checkedIds.remove(doc.id);
                  }
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('dd/MM/yyyy').format(_lancInstant(d))} · $tipo',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  formatBrCurrencyInitial(val),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredList();
    final visibleIds = filtered.map((e) => e.id).toSet();
    final nSel = _checkedIds.where(visibleIds.contains).length;

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Migrar lançamentos',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loadingList ? null : _reloadList,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loadingContas
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_contasError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Erro ao carregar contas: $_contasError',
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: [
                    _headerHero(),
                    const SizedBox(height: 16),
                    SegmentedButton<_MigracaoModo>(
                      segments: const [
                        ButtonSegment(
                          value: _MigracaoModo.semConta,
                          label: Text('Sem banco'),
                          icon: Icon(Icons.link_off_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: _MigracaoModo.transferirBanco,
                          label: Text('Entre bancos'),
                          icon: Icon(Icons.swap_horiz_rounded, size: 18),
                        ),
                      ],
                      selected: {_modo},
                      onSelectionChanged: (s) {
                        setState(() {
                          _modo = s.first;
                          _checkedIds.clear();
                        });
                        unawaited(_reloadList());
                      },
                    ),
                    const SizedBox(height: 14),
                    if (!_loadingList && _listError == null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.2)),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: Text(
                          _transactions.isEmpty
                              ? 'Nenhum lançamento neste filtro.'
                              : '${_transactions.length} lançamento(s) · ${DateFormat('dd/MM/yyyy').format(_from)} → ${DateFormat('dd/MM/yyyy').format(_to)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text('Tipo',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _tipoChip('Todos', _TipoFiltro.todos,
                            ThemeCleanPremium.primary, Icons.payments_rounded),
                        _tipoChip('Receitas', _TipoFiltro.receitas,
                            const Color(0xFF16A34A), Icons.trending_up_rounded),
                        _tipoChip('Despesas', _TipoFiltro.despesas,
                            const Color(0xFFDC2626), Icons.trending_down_rounded),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final p in _PeriodPreset.values)
                          if (p != _PeriodPreset.custom)
                            ChoiceChip(
                              label: Text(switch (p) {
                                _PeriodPreset.last30 => '30 dias',
                                _PeriodPreset.last90 => '90 dias',
                                _PeriodPreset.last365 => '365 dias',
                                _ => 'Custom',
                              }),
                              selected: _preset == p,
                              onSelected: (v) {
                                if (v) _applyPreset(p);
                              },
                            ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _from,
                                firstDate: DateTime(2018),
                                lastDate: DateTime(2100),
                              );
                              if (d != null) {
                                setState(() {
                                  _from = DateTime(d.year, d.month, d.day);
                                  _preset = _PeriodPreset.custom;
                                });
                                unawaited(_reloadList());
                              }
                            },
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(
                                'De ${DateFormat('dd/MM/yyyy').format(_from)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _to,
                                firstDate: _from,
                                lastDate: DateTime(2100),
                              );
                              if (d != null) {
                                setState(() {
                                  _to = DateTime(
                                      d.year, d.month, d.day, 23, 59, 59);
                                  _preset = _PeriodPreset.custom;
                                });
                                unawaited(_reloadList());
                              }
                            },
                            icon: const Icon(Icons.event_available_rounded,
                                size: 18),
                            label: Text(
                                'Até ${DateFormat('dd/MM/yyyy').format(_to)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_modo == _MigracaoModo.transferirBanco) ...[
                      const Text('Banco de origem',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      _contas.isEmpty
                          ? const Text('Cadastre contas na aba Contas.')
                          : _accountDropdown(
                              contas: _contas,
                              value: _sourceAccountId,
                              hint: 'De qual banco/cartão?',
                              excludeId: _destAccountId,
                              onChanged: (v) {
                                setState(() => _sourceAccountId = v);
                                unawaited(_reloadList());
                              },
                            ),
                      const SizedBox(height: 16),
                    ],
                    const Text('Banco de destino',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    _contas.isEmpty
                        ? const Text('Cadastre ao menos uma conta.')
                        : _accountDropdown(
                            contas: _contas,
                            value: _destAccountId,
                            hint: 'Para qual banco/cartão?',
                            excludeId: _modo == _MigracaoModo.transferirBanco
                                ? _sourceAccountId
                                : null,
                            onChanged: (v) => setState(() => _destAccountId = v),
                          ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _filterCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar descrição, categoria, valor…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed:
                              filtered.isEmpty ? null : _selectAllFiltered,
                          icon: const Icon(Icons.checklist_rounded, size: 20),
                          label: const Text('Marcar todos'),
                        ),
                        TextButton.icon(
                          onPressed:
                              filtered.isEmpty ? null : _deselectFiltered,
                          icon: const Icon(Icons.deselect_rounded, size: 20),
                          label: const Text('Desmarcar'),
                        ),
                      ],
                    ),
                    if (_loadingList)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_listError != null)
                      Text(_listError!,
                          style: const TextStyle(color: Color(0xFFDC2626)))
                    else ...[
                      Text(
                        '${filtered.length} na lista · $nSel selecionado(s)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 8),
                      ...filtered.map(_txCard),
                    ],
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _loadingApply ||
                          _loadingList ||
                          _contas.isEmpty
                      ? null
                      : () => _apply(_contas),
                  icon: _loadingApply
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_modo == _MigracaoModo.semConta
                          ? Icons.link_rounded
                          : Icons.swap_horiz_rounded),
                  label: Text(_loadingApply
                      ? 'Aplicando…'
                      : _modo == _MigracaoModo.semConta
                          ? 'Vincular selecionados'
                          : 'Migrar selecionados'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _modo == _MigracaoModo.semConta
                        ? ThemeCleanPremium.primary
                        : const Color(0xFF7C3AED),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
