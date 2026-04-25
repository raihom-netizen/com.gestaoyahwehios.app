import 'dart:async' show Timer;

import 'dart:convert' show utf8;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';
import 'package:gestao_yahweh/controle_total_sync/smart_input_live_mask.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/services/finance_despesas_categorias_tenant.dart'
    show getCategoriasDespesaForTenant, kCategoriasDespesaPadrao;
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
  final _textFocus = FocusNode();
  bool _applyingMask = false;
  bool _importing = false;
  bool _saving = false;
  String? _contaId;
  final _categoriaSaida = TextEditingController(text: 'Outros');
  final _categoriaEntrada = TextEditingController(text: 'Outros');
  final Set<int> _selected = {};
  List<BankNotificationParseResult> _rows = const [];
  /// Após parar de escrever (máscara a cada tecla; análise em lote atrasada).
  Timer? _reparseDebounce;
  static const _kReparseDebounce = Duration(milliseconds: 320);
  List<String> _categoriasDespesa = kCategoriasDespesaPadrao;

  @override
  void initState() {
    super.initState();
    getCategoriasDespesaForTenant(widget.tenantId).then((c) {
      if (c.isNotEmpty && mounted) {
        setState(() => _categoriasDespesa = c);
      }
    });
  }

  @override
  void dispose() {
    _reparseDebounce?.cancel();
    _textFocus.dispose();
    _text.dispose();
    _categoriaSaida.dispose();
    _categoriaEntrada.dispose();
    super.dispose();
  }

  void _cancelReparseDebounce() {
    _reparseDebounce?.cancel();
    _reparseDebounce = null;
  }

  void _scheduleReparse() {
    _cancelReparseDebounce();
    _reparseDebounce = Timer(_kReparseDebounce, () {
      _reparseDebounce = null;
      if (!mounted) return;
      _reparse();
    });
  }

  /// Só formatação (dd/mm, R$); **não** gera a lista (usa [_scheduleReparse]).
  void _applyLiveMask() {
    if (_applyingMask) return;
    if (_text.text.isEmpty) return;
    if (_text.text.length > BankNotificationParser.kMaxParseInputChars) {
      return;
    }
    final y = DateTime.now().year;
    final next = SmartInputLiveMask.apply(_text.text, y);
    if (next != _text.text) {
      _applyingMask = true;
      _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _applyingMask = false;
    }
  }

  void _onMainTextChanged() {
    if (_applyingMask) return;
    if (_text.text.isEmpty) {
      _cancelReparseDebounce();
      _reparse();
      return;
    }
    if (_text.text.length > BankNotificationParser.kMaxParseInputChars) {
      _cancelReparseDebounce();
      setState(() {
        _rows = const [];
        _selected.clear();
      });
      return;
    }
    _applyLiveMask();
    _scheduleReparse();
  }

  /// Máscara + análise imediata (colar, exemplos, botão Analisar).
  void _applyMaskAndReparseNow() {
    if (_applyingMask) return;
    if (_text.text.isEmpty) {
      _cancelReparseDebounce();
      _reparse();
      return;
    }
    if (_text.text.length > BankNotificationParser.kMaxParseInputChars) {
      setState(() {
        _rows = const [];
        _selected.clear();
      });
      return;
    }
    _applyLiveMask();
    _cancelReparseDebounce();
    _reparse();
  }

  String? _categoriaSugeridaDespesa(BankNotificationParseResult r) {
    if (r.type == 'income' || (r.descricao ?? '').isEmpty) return null;
    return FinanceSmartInputCategoryHints.suggestDespesaCategoria(
      r.descricao!,
      validCategorias: _categoriasDespesa,
    );
  }

  void _selecionarTudoTexto() {
    if (_text.text.isEmpty) return;
    _textFocus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  void _inserirExemploParcela(String trecho) {
    _textFocus.requestFocus();
    if (_text.text.isEmpty) {
      _text.text = trecho;
    } else {
      _text.text = '${_text.text.trim()}\n$trecho';
    }
    _applyMaskAndReparseNow();
  }

  Widget _parcelaExemploChip({required String label, required String inserir}) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
      onPressed: _saving
          ? null
          : () {
              ThemeCleanPremium.hapticAction();
              _inserirExemploParcela(inserir);
            },
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
      ),
      backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.08),
    );
  }

  void _marcarTodosLancamentos(bool marcar) {
    if (_rows.isEmpty) return;
    setState(() {
      if (marcar) {
        _selected
          ..clear()
          ..addAll(List<int>.generate(_rows.length, (i) => i));
      } else {
        _selected.clear();
      }
    });
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
    _applyMaskAndReparseNow();
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
          _cancelReparseDebounce();
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
        _applyMaskAndReparseNow();
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
            onPressed: _saving || _text.text.isEmpty
                ? null
                : _selecionarTudoTexto,
            child: const Text('Selecionar tudo', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    if (_text.text.isNotEmpty) {
                      _cancelReparseDebounce();
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
                  focusNode: _textFocus,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => _onMainTextChanged(),
                  minLines: 3,
                  maxLines: 14,
                  decoration: InputDecoration(
                    hintText:
                        'Enter = nova linha. Vários itens: 50 posto | 12/04 luz 80,00. Frases: 1.500,00 em 6x compra, 10x de 250,00. A lista monta após parar de digitar.',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    side: BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: ThemeCleanPremium.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Sugestões (parcelas)',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.grey.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Toque para inserir; o analisador divide o total e marca (1/n). Categorias sugeridas na lista (igual ao gravar).',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _parcelaExemploChip(
                              label: '1.500,00 em 6×',
                              inserir: '1.500,00 em 6x compra geladeira',
                            ),
                            _parcelaExemploChip(
                              label: '10× 250,00 + item',
                              inserir: '10x de 250,00 móveis | 40,00 frete',
                            ),
                            _parcelaExemploChip(
                              label: '6 parcelas de 200,00',
                              inserir: '6 parcelas de 200,00 material creche',
                            ),
                            _parcelaExemploChip(
                              label: '3.000,00 em 4× (sem centavos)',
                              inserir: '3000 em 4x cama e colchão',
                            ),
                          ],
                        ),
                      ],
                    ),
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
                      onPressed: _saving ? null : _applyMaskAndReparseNow,
                      child: const Text('Analisar agora'),
                    ),
                    if (_rows.isNotEmpty) ...[
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _marcarTodosLancamentos(true),
                        child: const Text('Marcar todos'),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _marcarTodosLancamentos(false),
                        child: const Text('Desmarcar'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _text.text.isEmpty
                      ? ''
                      : 'Detetado(s) ${_rows.length} lançamento(s) (atualizam ~0,3s após parar de digitar ou «Analisar agora»).',
                  style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                  ),
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
                    'Cole, escreva (Enter muda de linha; | separa itens) ou abra um CSV. A pré-visualização monta ao fim da digitação — ou toque em «Analisar agora».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _rows.length,
                    itemBuilder: (c, i) {
                      final r = _rows[i];
                      final cat = _categoriaSugeridaDespesa(r);
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
                        subtitle: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.type == "income" ? "Receita" : "Despesa"} · R\$ ${(r.valor ?? 0).toStringAsFixed(2).replaceAll(".", ",")} · ${(r.data != null) ? r.data.toString() : "—"}',
                            ),
                            if (cat != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Categoria sugerida: $cat',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: cat != null,
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
