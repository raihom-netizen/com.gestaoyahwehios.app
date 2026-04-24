import 'dart:convert' show utf8;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/services/finance_despesas_categorias_tenant.dart';
import 'package:gestao_yahweh/services/finance_smart_batch_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/finance_smart_input_category_hints.dart';

String _contaNome(Map<String, dynamic> d) {
  final n = (d['nome'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  return 'Conta';
}

/// Lançamento em lote: texto, colar, ou ficheiro CSV (exportado do banco / cartão).
class FinanceSmartInputPage extends StatefulWidget {
  final String tenantId;
  final String? panelRole;

  const FinanceSmartInputPage({
    super.key,
    required this.tenantId,
    this.panelRole,
  });

  @override
  State<FinanceSmartInputPage> createState() => _FinanceSmartInputPageState();
}

class _FinanceSmartInputPageState extends State<FinanceSmartInputPage> {
  final _text = TextEditingController();
  bool _importing = false;
  bool _saving = false;
  String? _contaId;
  final _categoriaSaida = TextEditingController(text: 'Outros');
  final _categoriaEntrada = TextEditingController(text: 'Outros');
  final Set<int> _selected = {};
  List<BankNotificationParseResult> _rows = const [];

  @override
  void dispose() {
    _text.dispose();
    _categoriaSaida.dispose();
    _categoriaEntrada.dispose();
    super.dispose();
  }

  void _reparse() {
    final t = _text.text;
    if (t.isEmpty) {
      setState(() {
        _rows = const [];
        _selected.clear();
      });
      return;
    }
    if (t.length > BankNotificationParser.kMaxParseInputChars) {
      setState(() {
        _rows = const [];
        _selected.clear();
      });
      return;
    }
    final list = BankNotificationParser.parseManyForBatch(t);
    if (list.isNotEmpty) {
      setState(() {
        _rows = list;
        _selected
          ..clear()
          ..addAll(List<int>.generate(list.length, (i) => i));
      });
      return;
    }
    final one = BankNotificationParser.parse(t);
    setState(() {
      _rows = [one];
      _selected
        ..clear()
        ..add(0);
    });
  }

  Future<void> _colar() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t == null || t.isEmpty) {
      if (mounted) {
        showFinanceSaveSnackBar(context,
            message: 'Nada na área de transferência.',
            isError: true);
      }
      return;
    }
    setState(() {
      if (_text.text.isEmpty) {
        _text.text = t;
      } else {
        _text.text = '${_text.text.trim()}\n\n$t';
      }
    });
    _reparse();
  }

  Future<void> _pickCsv() async {
    setState(() => _importing = true);
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      final b = f.bytes;
      if (b == null || b.isEmpty) {
        if (mounted) {
          showFinanceSaveSnackBar(context,
              message: 'Ficheiro vazio ou inacessível.',
              isError: true);
        }
        return;
      }
      var text = utf8.decode(b, allowMalformed: true);
      if (text.startsWith('\ufeff')) {
        text = text.substring(1);
      }
      if (text.length > BankNotificationParser.kMaxParseInputChars) {
        text = text.substring(0, BankNotificationParser.kMaxParseInputChars);
      }
      final fromCsv = BankNotificationParser.parseFromCsvText(text);
      if (fromCsv.isNotEmpty) {
        if (mounted) {
          setState(() {
            _text.text = text;
            _rows = fromCsv;
            _selected
              ..clear()
              ..addAll(List<int>.generate(fromCsv.length, (i) => i));
          });
        }
        if (mounted) {
          showFinanceSaveSnackBar(context,
              message:
                  '${fromCsv.length} linha(s) de CSV reconhecida(s). Ajuste se for preciso.');
        }
        return;
      }
      if (mounted) {
        setState(() {
          _text.text = text;
        });
        _reparse();
        showFinanceSaveSnackBar(
          context,
          message:
              'Cabeçalho não reconhecido como fatura/CSV. Analisámos como texto livre.',
        );
      }
    } catch (e) {
      if (mounted) {
        showFinanceSaveSnackBar(context,
            message: 'Ficheiro: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _gravar() async {
    final chosen = <BankNotificationParseResult>[];
    for (final i in _selected) {
      if (i >= 0 && i < _rows.length) {
        if (_rows[i].hasMinimumForConfirmation) {
          chosen.add(_rows[i]);
        }
      }
    }
    if (chosen.isEmpty) {
      showFinanceSaveSnackBar(
        context,
        message: 'Nenhum lançamento válido (valor e descrição).',
        isError: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final contas = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('contas')
          .orderBy('nome')
          .get();
      QueryDocumentSnapshot<Map<String, dynamic>>? cDoc;
      for (final d in contas.docs) {
        if (d.id == _contaId) {
          cDoc = d;
          break;
        }
      }
      cDoc ??= contas.docs.isNotEmpty ? contas.docs.first : null;
      if (cDoc == null) {
        if (mounted) {
          showFinanceSaveSnackBar(context,
              message: 'Nenhuma conta disponível.', isError: true);
        }
        return;
      }
      final nome = _contaNome(cDoc.data());
      final settings = await FinanceTenantSettings.load(widget.tenantId);
      final batchId = 'sp_${DateTime.now().millisecondsSinceEpoch}';
      final catsDespesa = await getCategoriasDespesaForTenant(widget.tenantId);
      String? categoriaDespesaFor(BankNotificationParseResult r) {
        return FinanceSmartInputCategoryHints.suggestDespesaCategoria(
          r.descricao ?? '',
          validCategorias: catsDespesa,
        );
      }

      int total = 0;
      final incomeRows = chosen.where((r) => r.type == 'income').toList();
      final expenseRows = chosen.where((r) => r.type != 'income').toList();
      if (incomeRows.isNotEmpty) {
        total += await FinanceSmartBatchService.writeRows(
          financeCol: FirebaseFirestore.instance
              .collection('igrejas')
              .doc(widget.tenantId)
              .collection('finance'),
          rows: incomeRows,
          contaId: cDoc.id,
          contaNome: nome,
          categoria: _categoriaEntrada.text.trim().isEmpty
              ? 'Outros'
              : _categoriaEntrada.text,
          smartPasteBatchId: batchId,
          source: 'smart_paste',
          panelRole: widget.panelRole,
          settings: settings,
        );
      }
      if (expenseRows.isNotEmpty) {
        total += await FinanceSmartBatchService.writeRows(
          financeCol: FirebaseFirestore.instance
              .collection('igrejas')
              .doc(widget.tenantId)
              .collection('finance'),
          rows: expenseRows,
          contaId: cDoc.id,
          contaNome: nome,
          categoria: _categoriaSaida.text.trim().isEmpty
              ? 'Outros'
              : _categoriaSaida.text,
          categoriaForRow: categoriaDespesaFor,
          smartPasteBatchId: batchId,
          source: 'smart_paste',
          panelRole: widget.panelRole,
          settings: settings,
        );
      }
      if (mounted) {
        showFinanceSaveSnackBar(
            context, message: '$total lançamento(s) importados com sucesso.');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showFinanceSaveSnackBar(context, message: '$e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Importar / colar extrato',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    if (_text.text.isNotEmpty) {
                      _text.clear();
                      _reparse();
                    }
                  },
            child: const Text('Limpar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _text,
                  onChanged: (_) {
                    if (_text.text.length <=
                        BankNotificationParser.kMaxParseInputChars) {
                      _reparse();
                    }
                  },
                  maxLines: 7,
                  decoration: InputDecoration(
                    hintText:
                        'Cole extrato, SMS, ou múltiplas linhas (separado por |). Ficheiro: CSV de fatura/banco.',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                        onPressed: _importing ? null : _colar,
                        icon: const Icon(Icons.paste, size: 18),
                        label: const Text('Colar')),
                    OutlinedButton.icon(
                      onPressed: _importing || _saving ? null : _pickCsv,
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: Text(
                          _importing ? 'A abrir…' : 'Ficheiro CSV (extrato)'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _reparse,
                      child: const Text('Analisar'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _text.text.isEmpty
                      ? ''
                      : 'Detetado(s) ${_rows.length} lançamento(s) (marque o que deseja importar).',
                  style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _categoriaEntrada,
                        decoration: const InputDecoration(
                            labelText: 'Cat. padrão receita',
                            border: OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _categoriaSaida,
                        decoration: const InputDecoration(
                            labelText: 'Cat. padrão despesa',
                            border: OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance
                      .collection('igrejas')
                      .doc(widget.tenantId)
                      .collection('contas')
                      .orderBy('nome')
                      .get(),
                  builder: (c, s) {
                    if (!s.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final docs = s.data!.docs
                        .where((d) => d.data()['ativo'] != false)
                        .toList();
                    if (docs.isEmpty) {
                      return const Text(
                        'Crie uma conta bancária no separador Contas.',
                        style: TextStyle(color: Color(0xFFDC2626)),
                      );
                    }
                    final valueConta = _contaId ?? docs.first.id;
                    return DropdownButtonFormField<String>(
                      value: valueConta,
                      isExpanded: true,
                      items: docs
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(
                                  _contaNome(d.data()),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _contaId = v),
                      decoration: const InputDecoration(
                        labelText: 'Conta (débito e crédito do lote)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving || _importing || _rows.isEmpty
                      ? null
                      : _gravar,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                      _saving
                          ? 'A importar…'
                          : 'Gravar selecionados no financeiro',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,),
                ),
              ],
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                    'Cole o texto, carregue um CSV, e toque em «Analisar».',
                    style: TextStyle(color: Colors.grey.shade600),
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _rows.length,
                    itemBuilder: (c, i) {
                      final r = _rows[i];
                      return CheckboxListTile(
                        value: _selected.contains(i),
                        onChanged: (b) {
                          setState(() {
                            if (b == true) {
                              _selected.add(i);
                            } else {
                              _selected.remove(i);
                            }
                          });
                        },
                        title: Text(
                          (r.descricao ?? '-').toString(),
                          maxLines: 2,
                        ),
                        subtitle: Text(
                          '${r.type == "income" ? "Receita" : "Despesa"} · R\$ ${(r.valor ?? 0).toStringAsFixed(2).replaceAll(".", ",")} · ${(r.data != null) ? r.data.toString() : "—"}',
                        ),
                        secondary: r.hasMinimumForConfirmation
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFF16A34A))
                            : const Icon(Icons.warning, color: Color(0xFFF59E0B)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
