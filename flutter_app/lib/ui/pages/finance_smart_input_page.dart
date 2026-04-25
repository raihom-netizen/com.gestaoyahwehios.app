import 'dart:convert' show utf8;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/finance_save_snackbar.dart';
import 'package:gestao_yahweh/services/finance_smart_batch_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

const _categoriasReceitaPadrao = <String>[
  'Dízimos',
  'Ofertas',
  'Doações',
  'Campanhas',
  'Eventos',
  'Outros'
];

String _contaNome(Map<String, dynamic> d) {
  final n = (d['nome'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  return 'Conta';
}

String _foldCat(String s) {
  final m = <String, String>{
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  final low = s.toLowerCase();
  final sb = StringBuffer();
  for (final ch in low.split('')) {
    sb.write(m[ch] ?? ch);
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  bool _importing = false;
  bool _saving = false;
  String? _contaId;
  final _categoriaSaida = TextEditingController(text: 'Outros');
  final _categoriaEntrada = TextEditingController(text: 'Outros');
  final Set<int> _selected = {};
  List<BankNotificationParseResult> _rows = const [];
  final Map<int, String> _categoriaPorLinha = {};
  List<String> _categoriasDespesa = const [];
  List<String> _categoriasReceita = const [];
  bool _somenteSemCategoria = false;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
  }

  @override
  void dispose() {
    _textFocus.dispose();
    _text.dispose();
    _categoriaSaida.dispose();
    _categoriaEntrada.dispose();
    super.dispose();
  }

  Future<void> _carregarCategorias() async {
    try {
      final despSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('categorias_despesas')
          .orderBy('ordem')
          .get();
      final desp = despSnap.docs
          .map((d) => (d.data()['nome'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final recSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('categorias_receitas')
          .orderBy('ordem')
          .get();
      final rec = recSnap.docs
          .map((d) => (d.data()['nome'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _categoriasDespesa = desp;
        _categoriasReceita =
            rec.isEmpty ? List<String>.from(_categoriasReceitaPadrao) : rec;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categoriasReceita = List<String>.from(_categoriasReceitaPadrao);
      });
    }
  }

  String _categoriaSugerida(BankNotificationParseResult r) {
    if (r.type == 'income') {
      final fallback = _categoriaEntrada.text.trim();
      return fallback.isEmpty ? 'Outros' : fallback;
    }
    final desc = _foldCat((r.descricao ?? '').trim());
    if (desc.isNotEmpty) {
      for (final c in _categoriasDespesa) {
        final k = _foldCat(c);
        if (k.length >= 4 && desc.contains(k)) return c;
      }
    }
    return '';
  }

  String _rowKey(BankNotificationParseResult r) {
    final d = r.data;
    final ds = d == null ? 'sem_data' : '${d.year}-${d.month}-${d.day}';
    final v = (r.valor ?? 0).toStringAsFixed(2);
    final desc = (r.descricao ?? '').trim().toLowerCase();
    return '$ds|$v|$desc|${r.type}';
  }

  Future<void> _criarCategoriaNaLinha({
    required bool isIncome,
    required int idx,
  }) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(isIncome
                  ? 'Nova categoria de receita'
                  : 'Nova categoria de despesa'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da categoria',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Criar'),
                ),
              ],
            ),
          ) ??
          false;
      final nome = ctrl.text.trim();
      if (!ok || nome.isEmpty) return;
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection(isIncome ? 'categorias_receitas' : 'categorias_despesas');
      await col.add({'nome': nome, 'ordem': DateTime.now().millisecondsSinceEpoch});
      await _carregarCategorias();
      if (!mounted) return;
      setState(() => _categoriaPorLinha[idx] = nome);
      showFinanceSaveSnackBar(context, message: 'Categoria "$nome" criada.');
    } finally {
      ctrl.dispose();
    }
  }

  /// Texto livre: não analisa automaticamente (evita categorias/linhas inesperadas).
  void _onMainTextChanged() {
    if (_rows.isEmpty && _selected.isEmpty) return;
    setState(() {
      _rows = const [];
      _selected.clear();
      _categoriaPorLinha.clear();
    });
  }

  /// Aplica máscara opcional e monta a pré-visualização (único ponto de análise).
  void _gerarLancamentos() {
    if (_text.text.isEmpty) {
      setState(() {
        _rows = const [];
        _selected.clear();
        _categoriaPorLinha.clear();
      });
      return;
    }
    if (_text.text.length > BankNotificationParser.kMaxParseInputChars) {
      setState(() {
        _rows = const [];
        _selected.clear();
        _categoriaPorLinha.clear();
      });
      if (mounted) {
        showFinanceSaveSnackBar(
          context,
          message: 'Texto demasiado longo para analisar de uma vez.',
          isError: true,
        );
      }
      return;
    }
    final t = _text.text;
    final fromCsv = BankNotificationParser.parseFromCsvText(t);
    if (fromCsv.isNotEmpty) {
      final sorted = [...fromCsv]
        ..sort((a, b) {
          final ad = a.data ?? DateTime(2100);
          final bd = b.data ?? DateTime(2100);
          final c1 = ad.compareTo(bd);
          if (c1 != 0) return c1;
          return (a.descricao ?? '').compareTo(b.descricao ?? '');
        });
      final catMap = <int, String>{};
      for (var i = 0; i < sorted.length; i++) {
        catMap[i] = _categoriaSugerida(sorted[i]);
      }
      setState(() {
        _rows = sorted;
        _categoriaPorLinha
          ..clear()
          ..addAll(catMap);
        _selected
          ..clear()
          ..addAll(List<int>.generate(sorted.length, (i) => i));
      });
      if (mounted) {
        showFinanceSaveSnackBar(
          context,
          message: '${fromCsv.length} linha(s) de CSV na pré-visualização.',
        );
      }
      return;
    }
    final list = BankNotificationParser.parseManyForBatch(t);
    if (list.isNotEmpty) {
      final sorted = [...list]
        ..sort((a, b) {
          final ad = a.data ?? DateTime(2100);
          final bd = b.data ?? DateTime(2100);
          final c1 = ad.compareTo(bd);
          if (c1 != 0) return c1;
          return (a.descricao ?? '').compareTo(b.descricao ?? '');
        });
      final catMap = <int, String>{};
      for (var i = 0; i < sorted.length; i++) {
        catMap[i] = _categoriaSugerida(sorted[i]);
      }
      setState(() {
        _rows = sorted;
        _categoriaPorLinha
          ..clear()
          ..addAll(catMap);
        _selected
          ..clear()
          ..addAll(List<int>.generate(sorted.length, (i) => i));
      });
      return;
    }
    final one = BankNotificationParser.parse(t);
    setState(() {
      _rows = [one];
      _categoriaPorLinha
        ..clear()
        ..addAll({0: _categoriaSugerida(one)});
      _selected
        ..clear()
        ..add(0);
    });
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
    setState(() {
      _rows = const [];
      _selected.clear();
      _categoriaPorLinha.clear();
    });
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

  void _marcarSomenteSemCategoria() {
    if (_rows.isEmpty) return;
    final idx = List<int>.generate(_rows.length, (i) => i)
        .where((i) => (_categoriaPorLinha[i] ?? '').trim().isEmpty)
        .toList();
    setState(() {
      _selected
        ..clear()
        ..addAll(idx);
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
      _rows = const [];
      _selected.clear();
      _categoriaPorLinha.clear();
    });
    if (mounted) {
      showFinanceSaveSnackBar(
        context,
        message: 'Texto colado. Toque em «Gerar lançamentos» para pré-visualizar.',
      );
    }
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
      if (mounted) {
        setState(() {
          _text.text = text;
          _rows = const [];
          _selected.clear();
          _categoriaPorLinha.clear();
        });
        showFinanceSaveSnackBar(
          context,
          message:
              'Ficheiro carregado no campo. Toque em «Gerar lançamentos» para pré-visualizar.',
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
    final catByKey = <String, String>{};
    final semCategoria = <int>[];
    for (final i in _selected) {
      if (i >= 0 && i < _rows.length) {
        if (_rows[i].hasMinimumForConfirmation) {
          final cat = (_categoriaPorLinha[i] ?? '').trim();
          if (cat.isEmpty) {
            semCategoria.add(i);
            continue;
          }
          chosen.add(_rows[i]);
          catByKey[_rowKey(_rows[i])] = cat;
        }
      }
    }
    if (semCategoria.isNotEmpty) {
      showFinanceSaveSnackBar(
        context,
        message:
            'Existem ${semCategoria.length} lançamento(s) sem categoria. Defina antes de gravar.',
        isError: true,
      );
      return;
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
          categoriaForRow: (r) => catByKey[_rowKey(r)],
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
          categoriaForRow: (r) => catByKey[_rowKey(r)],
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

  List<String> _categoriasParaLinha(BankNotificationParseResult r) {
    return r.type == 'income' ? _categoriasReceita : _categoriasDespesa;
  }

  String _fmtData(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  List<int> _previewOrder() {
    final idx = List<int>.generate(_rows.length, (i) => i);
    idx.sort((a, b) {
      final ca = (_categoriaPorLinha[a] ?? '').trim();
      final cb = (_categoriaPorLinha[b] ?? '').trim();
      final aSem = ca.isEmpty;
      final bSem = cb.isEmpty;
      if (aSem != bSem) return aSem ? -1 : 1;
      final da = _rows[a].data ?? DateTime(2100);
      final db = _rows[b].data ?? DateTime(2100);
      final cd = da.compareTo(db);
      if (cd != 0) return cd;
      final cc = ca.toLowerCase().compareTo(cb.toLowerCase());
      if (cc != 0) return cc;
      return (_rows[a].descricao ?? '').compareTo(_rows[b].descricao ?? '');
    });
    if (!_somenteSemCategoria) return idx;
    return idx.where((i) => (_categoriaPorLinha[i] ?? '').trim().isEmpty).toList();
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
                      setState(() {
                        _text.clear();
                        _rows = const [];
                        _selected.clear();
                        _categoriaPorLinha.clear();
                      });
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
                        'Cole/digite livremente (ex.: 100,00, 85.50, 6 parcelas de 250, 1000,00 em 4x). Sem máscara automática.',
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
                          'Toque para inserir texto de exemplo e depois «Gerar lançamentos». Após gerar, revise categoria em cada linha antes de gravar.',
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
                    FilledButton.icon(
                      onPressed: _saving ? null : _gerarLancamentos,
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
                      label: const Text('Gerar lançamentos'),
                    ),
                    if (_rows.isNotEmpty) ...[
                      FilterChip(
                        selected: _somenteSemCategoria,
                        onSelected: _saving
                            ? null
                            : (v) => setState(() => _somenteSemCategoria = v),
                        label: const Text('Somente sem categoria'),
                        avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                        selectedColor:
                            ThemeCleanPremium.primary.withValues(alpha: 0.16),
                      ),
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => _marcarTodosLancamentos(true),
                        child: const Text('Marcar todos'),
                      ),
                      TextButton(
                        onPressed:
                            _saving ? null : _marcarSomenteSemCategoria,
                        child: const Text('Marcar sem categoria'),
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
                      : (_rows.isEmpty
                          ? 'Texto pronto — toque em «Gerar lançamentos» para pré-visualizar.'
                          : 'Pré-visualização: ${_rows.length} lançamento(s).${_somenteSemCategoria ? ' Filtro: somente sem categoria.' : ''}'),
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
                      initialValue: valueConta,
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
                    'Cole, escreva (Enter = nova linha; | separa itens) ou abra um CSV. Toque em «Gerar lançamentos» para ver a lista antes de gravar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ))
                : Builder(
                    builder: (ctx) {
                      final ordered = _previewOrder();
                      if (ordered.isEmpty) {
                        return Center(
                          child: Text(
                            _somenteSemCategoria
                                ? 'Nenhum lançamento sem categoria no filtro atual.'
                                : 'Nenhum lançamento disponível.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        );
                      }
                      return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: ordered.length,
                    itemBuilder: (c, orderIdx) {
                      final i = ordered[orderIdx];
                      final r = _rows[i];
                      final categoriaAtual = (_categoriaPorLinha[i] ?? '').trim();
                      final categoriaCabecalho =
                          categoriaAtual.isEmpty ? 'Sem categoria' : categoriaAtual;
                      final groupKey = '${_fmtData(r.data)} • $categoriaCabecalho';
                      String? prevGroupKey;
                      if (orderIdx > 0) {
                        final pi = ordered[orderIdx - 1];
                        final pr = _rows[pi];
                        final prevCat = (_categoriaPorLinha[pi] ?? '').trim();
                        final prevCatHead =
                            prevCat.isEmpty ? 'Sem categoria' : prevCat;
                        prevGroupKey = '${_fmtData(pr.data)} • $prevCatHead';
                      }
                      final showHeader = orderIdx == 0 || groupKey != prevGroupKey;
                      final categorias = _categoriasParaLinha(r);
                      final semCategoria = categoriaAtual.isEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader)
                            Container(
                              margin: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.20),
                                ),
                              ),
                              child: Text(
                                groupKey,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                            ),
                          CheckboxListTile(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r.type == "income" ? "Receita" : "Despesa"} · R\$ ${(r.valor ?? 0).toStringAsFixed(2).replaceAll(".", ",")} · ${_fmtData(r.data)}',
                                ),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue:
                                      categoriaAtual.isEmpty ? null : categoriaAtual,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: semCategoria
                                        ? 'Sem categoria (defina antes de gravar)'
                                        : 'Categoria',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: const OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: '',
                                      child: Text('Sem categoria'),
                                    ),
                                    ...categorias.map((cat) =>
                                        DropdownMenuItem<String>(
                                          value: cat,
                                          child: Text(cat,
                                              overflow: TextOverflow.ellipsis),
                                        )),
                                  ],
                                  onChanged: (v) {
                                    setState(() {
                                      _categoriaPorLinha[i] = (v ?? '').trim();
                                    });
                                  },
                                ),
                                if (semCategoria)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _saving
                                          ? null
                                          : () => _criarCategoriaNaLinha(
                                                isIncome: r.type == 'income',
                                                idx: i,
                                              ),
                                      icon: const Icon(Icons.add_circle_outline,
                                          size: 18),
                                      label: const Text('Criar categoria'),
                                    ),
                                  ),
                              ],
                            ),
                            secondary: r.hasMinimumForConfirmation
                                ? const Icon(Icons.check_circle,
                                    color: Color(0xFF16A34A))
                                : const Icon(Icons.warning,
                                    color: Color(0xFFF59E0B)),
                            isThreeLine: true,
                          ),
                        ],
                      );
                    },
                  );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
