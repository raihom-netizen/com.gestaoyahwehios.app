import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';

String _contaDisplayName(Map<String, dynamic> d) {
  final n = (d['nome'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  return 'Conta';
}

DateTime _lancInstant(Map<String, dynamic> data) =>
    financeLancamentoDate(data) ?? DateTime.now();

bool _semContaLancamento(Map<String, dynamic> d) {
  final tipo = (d['type'] ?? '').toString().toLowerCase();
  if (tipo == 'transferencia') return false;
  if (tipo.contains('entrada') || tipo.contains('receita')) {
    return financeContaDestinoReceitaId(d).isEmpty;
  }
  if (tipo.contains('saida') ||
      tipo.contains('saída') ||
      tipo.contains('despesa')) {
    return (d['contaOrigemId'] ?? '').toString().trim().isEmpty;
  }
  return false;
}

/// Atribui conta a lançamentos no intervalo (sem vincular conta) — alinhado ao Controle Total.
class FinanceBulkAssignPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final DateTime? initialRangeFrom;
  final DateTime? initialRangeTo;

  const FinanceBulkAssignPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.initialRangeFrom,
    this.initialRangeTo,
  });

  @override
  State<FinanceBulkAssignPage> createState() => _FinanceBulkAssignPageState();
}

class _FinanceBulkAssignPageState extends State<FinanceBulkAssignPage> {
  late final CollectionReference<Map<String, dynamic>> _finRef;
  late final CollectionReference<Map<String, dynamic>> _contasRef;

  _PeriodPreset _preset = _PeriodPreset.last30;
  late DateTime _from;
  late DateTime _to;
  final _filterCtrl = TextEditingController();
  String? _contaId;
  bool _loadingApply = false;
  bool _loadingList = false;
  String? _listError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _semConta = [];
  final Set<String> _checkedIds = {};

  @override
  void initState() {
    super.initState();
    _finRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('finance');
    _contasRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('contas');
    _filterCtrl.addListener(_onFilterChanged);
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
    } else {
      _applyPreset(_PeriodPreset.last30);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_reloadList()));
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

  void _applyPreset(_PeriodPreset p) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    DateTime start;
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
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredList() {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      return List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          _semConta);
    }
    return _semConta.where((doc) {
      final d = doc.data();
      final cat = (d['categoria'] ?? '').toString();
      final desc = (d['descricao'] ?? '').toString();
      final tipo = (d['type'] ?? '').toString();
      final blob = '$cat $desc $tipo'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  void _retainCheckedInFiltered() {
    final vis = _filteredList().map((e) => e.id).toSet();
    _checkedIds.removeWhere((id) => !vis.contains(id));
  }

  void _selectAllFiltered() {
    setState(() {
      _checkedIds.addAll(_filteredList().map((e) => e.id));
    });
  }

  void _deselectFiltered() {
    setState(() {
      for (final id in _filteredList().map((e) => e.id)) {
        _checkedIds.remove(id);
      }
    });
  }

  Future<void> _reloadList() async {
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
        if (!_semContaLancamento(doc.data())) return false;
        final instant = _lancInstant(doc.data());
        if (instant.isBefore(f) || instant.isAfter(t)) return false;
        return true;
      }).toList();
      setState(() {
        _semConta = list;
        _loadingList = false;
      });
      setState(() {
        _checkedIds
          ..clear()
          ..addAll(_semConta.map((e) => e.id));
      });
      _retainCheckedInFiltered();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _semConta = [];
        _checkedIds.clear();
        _listError = e.toString();
        _loadingList = false;
      });
    }
  }

  Future<void> _apply() async {
    if (_contaId == null || _contaId!.isEmpty) {
      showFinanceSaveSnackBar(
        context,
        message: 'Escolha a conta de destino (receita) / origem (despesa).',
        isError: true,
      );
      return;
    }
    final contasSnap = await _contasRef.get();
    if (!mounted) return;
    QueryDocumentSnapshot<Map<String, dynamic>>? cDoc;
    for (final d in contasSnap.docs) {
      if (d.id == _contaId) {
        cDoc = d;
        break;
      }
    }
    if (cDoc == null) {
      showFinanceSaveSnackBar(
        context,
        message: 'Conta inválida.',
        isError: true,
      );
      return;
    }
    final nome = _contaDisplayName(cDoc.data());
    final targets = _filteredList()
        .where((d) => _checkedIds.contains(d.id))
        .toList();
    if (targets.isEmpty) {
      showFinanceSaveSnackBar(
        context,
        message: 'Marque ao menos um lançamento.',
        isError: true,
      );
      return;
    }
    setState(() => _loadingApply = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      const chunk = 400;
      for (var i = 0; i < targets.length; i += chunk) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in targets.skip(i).take(chunk)) {
          final m = doc.data();
          final tipo = (m['type'] ?? '').toString().toLowerCase();
          if (tipo.contains('entrada') || tipo.contains('receita')) {
            batch.update(doc.reference, {
              'contaDestinoId': _contaId,
              'contaDestinoNome': nome,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            batch.update(doc.reference, {
              'contaOrigemId': _contaId,
              'contaOrigemNome': nome,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        await batch.commit();
      }
      if (mounted) {
        showFinanceSaveSnackBar(
          context,
          message: '${targets.length} lançamento(s) vinculados a «$nome».',
        );
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Vincular em massa',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_PeriodPreset>(
                  segments: const [
                    ButtonSegment(
                        value: _PeriodPreset.last30, label: Text('30d')),
                    ButtonSegment(
                        value: _PeriodPreset.last90, label: Text('90d')),
                    ButtonSegment(
                        value: _PeriodPreset.last365, label: Text('365d')),
                  ],
                  selected: {_preset},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) {
                      _applyPreset(s.first);
                      unawaited(_reloadList());
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final a = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2018),
                            lastDate: DateTime(2100),
                            initialDate: _from,
                          );
                          if (a != null) {
                            setState(
                                () => _from = DateTime(a.year, a.month, a.day));
                            unawaited(_reloadList());
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text('De: ${DateFormat('dd/MM/yyyy').format(_from)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final a = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2018),
                            lastDate: DateTime(2100),
                            initialDate: _to,
                          );
                          if (a != null) {
                            setState(
                              () => _to = DateTime(a.year, a.month, a.day, 23, 59, 59),
                            );
                            unawaited(_reloadList());
                          }
                        },
                        icon: const Icon(Icons.event, size: 18),
                        label: Text('Até: ${DateFormat('dd/MM/yyyy').format(_to)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _filterCtrl,
                  decoration: InputDecoration(
                    hintText: 'Filtrar categoria, descrição, tipo...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: _contasRef.orderBy('nome').get(),
                  builder: (c, s) {
                    if (!s.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final docs = s.data!.docs
                        .where((d) => d.data()['ativo'] != false)
                        .toList();
                    return DropdownButtonFormField<String>(
                      value: _contaId,
                      isExpanded: true,
                      hint: const Text('Conta para vincular'),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: docs
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                _contaDisplayName(d.data()),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _contaId = v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                        onPressed: _selectAllFiltered, child: const Text('Marcar visíveis')),
                    TextButton(
                        onPressed: _deselectFiltered,
                        child: const Text('Desmarcar visíveis')),
                    const Spacer(),
                    FilledButton(
                      onPressed: _loadingApply || _loadingList ? null : _apply,
                      child: _loadingApply
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Aplicar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_listError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_listError!,
                  style: const TextStyle(color: Color(0xFFDC2626))),
            )
          else if (_loadingList)
            const LinearProgressIndicator()
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _semConta.isEmpty
                    ? 'Nenhum lançamento sem conta no período.'
                    : '${_semConta.length} sem conta — ${_checkedIds.length} selecionados',
                style: TextStyle(
                    color: Colors.grey.shade800, fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: _semConta.isEmpty
                ? const SizedBox()
                : ListView.builder(
                    itemCount: _filteredList().length,
                    itemBuilder: (c, i) {
                      final doc = _filteredList()[i];
                      final m = doc.data();
                      final tipo = (m['type'] ?? '').toString();
                      final val = parseBrCurrencyInput(
                          (m['amount'] ?? m['valor'] ?? 0).toString());
                      return CheckboxListTile(
                        value: _checkedIds.contains(doc.id),
                        onChanged: (b) {
                          setState(() {
                            if (b == true) {
                              _checkedIds.add(doc.id);
                            } else {
                              _checkedIds.remove(doc.id);
                            }
                          });
                        },
                        title: Text(
                          (m['descricao'] ?? m['categoria'] ?? '-')
                              .toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                            '${DateFormat('dd/MM/yy').format(_lancInstant(m))} · $tipo · ${formatBrCurrencyInitial(val)}',
                            style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _PeriodPreset { last30, last90, last365, custom }
