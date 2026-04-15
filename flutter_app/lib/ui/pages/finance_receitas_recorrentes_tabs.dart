import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/services/finance_audit_log_service.dart';
import 'package:gestao_yahweh/services/receitas_recorrentes_geracao_service.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart'
    show showFinanceLancamentoEditorForTenant;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/finance_fixo_premium_dialogs.dart';

const _categoriasReceitaPadrao = [
  'Dízimos',
  'Doações',
  'Ofertas Missionárias',
  'Ofertas Voluntárias',
  'Campanhas',
  'Outros',
];

String? _memberTelefoneRaw(Map<String, dynamic> m) {
  final t = (m['TELEFONES'] ?? m['telefone'] ?? m['celular'] ?? m['whatsapp'] ?? '')
      .toString()
      .trim();
  return t.isEmpty ? null : t;
}

double _parseValor(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return parseBrCurrencyInput(raw.toString());
}

Future<List<String>> _categoriasReceitaTenant(String tenantId) async {
  final col = FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('categorias_receitas');
  var snap = await col.orderBy('nome').get();
  if (snap.docs.isEmpty) {
    for (final nome in _categoriasReceitaPadrao) {
      await col.add({
        'nome': nome,
        'ordem': _categoriasReceitaPadrao.indexOf(nome),
      });
    }
    snap = await col.orderBy('nome').get();
  }
  final nomes = snap.docs
      .map((d) => (d.data()['nome'] ?? '').toString())
      .where((s) => s.isNotEmpty);
  final seen = <String>{};
  return nomes.where((n) => seen.add(n)).toList();
}

Future<List<({String id, String nome})>> _contasAtivas(String tenantId) async {
  final snap = await FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .collection('contas')
      .orderBy('nome')
      .get();
  return snap.docs
      .where((d) => d.data()['ativo'] != false)
      .map((d) => (id: d.id, nome: (d.data()['nome'] ?? '').toString()))
      .where((e) => e.nome.isNotEmpty)
      .toList();
}

Future<String> _nomeIgreja(String tenantId) async {
  final d = await FirebaseFirestore.instance
      .collection('igrejas')
      .doc(tenantId)
      .get();
  return (d.data()?['nome'] ?? d.data()?['name'] ?? 'Igreja').toString().trim();
}

String _titularConciliacao(Map<String, dynamic> m) {
  final t = (m['titularNome'] ?? '').toString().trim();
  if (t.isNotEmpty) return t;
  final mn = (m['memberNome'] ?? '').toString().trim();
  if (mn.isNotEmpty) return mn;
  return (m['fornecedorNome'] ?? '').toString().trim();
}

String? _waUrl(String? phoneRaw, String message) {
  if (phoneRaw == null || phoneRaw.isEmpty) return null;
  final digits = phoneRaw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return null;
  final n = digits.startsWith('55') ? digits : '55$digits';
  final q = Uri.encodeComponent(message);
  return 'https://wa.me/$n?text=$q';
}

// ─── Tab: Receitas fixas / recorrentes ───────────────────────────────────────

class FinanceReceitasFixasTab extends StatefulWidget {
  final String tenantId;
  final String role;

  const FinanceReceitasFixasTab({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  State<FinanceReceitasFixasTab> createState() =>
      _FinanceReceitasFixasTabState();
}

class _FinanceReceitasFixasTabState extends State<FinanceReceitasFixasTab> {
  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('receitas_recorrentes');

  late Future<QuerySnapshot<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _future = _col.get();
  }

  void _refresh() {
    setState(() {
      _future = _col.get();
    });
  }

  Future<void> _gerarPendentes() async {
    try {
      final n = await gerarReceitasRecorrentesPendentes(widget.tenantId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Nada novo a gerar (já existem ou fora do período).'
                : '$n lançamento(s) projetado(s) no caixa.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar: $e')),
      );
    }
  }

  Future<void> _addOuEditar(
    BuildContext context, {
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final isEdit = doc != null;
    final data = doc?.data();
    final valorInicial = isEdit ? _parseValor(data?['valor']) : 0.0;
    final valorCtrl = TextEditingController(
      text: isEdit && valorInicial > 0
          ? formatBrCurrencyInitial(valorInicial)
          : '',
    );
    final diaCtrl = TextEditingController(
      text: isEdit ? (data?['diaVencimento'] ?? '').toString() : '10',
    );
    String? memberDocId =
        isEdit ? (data?['memberDocId'] ?? '').toString() : null;
    if (memberDocId != null && memberDocId.isEmpty) memberDocId = null;
    String memberNome =
        isEdit ? (data?['memberNome'] ?? '').toString() : '';
    String? memberTelefone =
        isEdit ? (data?['memberTelefone'] ?? '').toString() : null;
    if (memberTelefone != null && memberTelefone.isEmpty) {
      memberTelefone = null;
    }
    String? fornecedorId =
        isEdit ? (data?['fornecedorId'] ?? '').toString() : null;
    if (fornecedorId != null && fornecedorId.isEmpty) fornecedorId = null;
    String fornecedorNome =
        isEdit ? (data?['fornecedorNome'] ?? '').toString() : '';
    var vinculoTipo = isEdit
        ? (data?['vinculoTipo'] ?? '').toString()
        : 'membro';
    if (vinculoTipo.isEmpty) {
      vinculoTipo =
          fornecedorId != null && fornecedorId.isNotEmpty ? 'fornecedor' : 'membro';
    }
    String categoria = isEdit ? (data?['categoria'] ?? '').toString() : '';
    String? contaId =
        isEdit ? (data?['contaDestinoId'] ?? '').toString() : null;
    if (contaId != null && contaId.isEmpty) contaId = null;
    DateTime dataInicio = DateTime.now();
    DateTime? dataFim;
    try {
      final ti = data?['dataInicio'];
      if (ti is Timestamp) dataInicio = ti.toDate();
      final tf = data?['dataFim'];
      if (tf is Timestamp) dataFim = tf.toDate();
    } catch (_) {}
    var indeterminado = data?['indeterminado'] == true;

    final dataInicioCtrl = TextEditingController(
      text: formatBrDateDdMmYyyy(dataInicio),
    );
    final dataFimCtrl = TextEditingController(
      text: dataFim == null ? '' : formatBrDateDdMmYyyy(dataFim),
    );

    final categorias = await _categoriasReceitaTenant(widget.tenantId);
    if (categoria.isNotEmpty && !categorias.contains(categoria)) {
      categoria = '';
    }
    final contas = await _contasAtivas(widget.tenantId);

    if (!context.mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit_rounded : Icons.event_repeat_rounded,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEdit ? 'Editar receita recorrente' : 'Agendar receita recorrente',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinanceFixoVinculoSegment(
                  value: vinculoTipo,
                  onChanged: (v) => setDlg(() {
                    vinculoTipo = v;
                    if (v == 'membro') {
                      fornecedorId = null;
                      fornecedorNome = '';
                    } else {
                      memberDocId = null;
                      memberNome = '';
                      memberTelefone = null;
                    }
                  }),
                ),
                const SizedBox(height: 12),
                FinanceFixoTitularCard(
                  vinculoTipo: vinculoTipo,
                  tituloPlaceholder: vinculoTipo == 'membro'
                      ? 'Titular (membro)'
                      : 'Titular (fornecedor)',
                  nomeExibicao: vinculoTipo == 'membro'
                      ? memberNome
                      : fornecedorNome,
                  onTap: () async {
                    if (vinculoTipo == 'membro') {
                      final picked = await showFinancePremiumMemberPicker(
                        context,
                        tenantId: widget.tenantId,
                      );
                      if (picked == null) return;
                      setDlg(() {
                        memberDocId = picked.$1;
                        memberNome = picked.$2;
                        memberTelefone = picked.$3;
                      });
                    } else {
                      final picked = await showFinancePremiumFornecedorPicker(
                        context,
                        tenantId: widget.tenantId,
                      );
                      if (picked == null) return;
                      setDlg(() {
                        fornecedorId = picked.$1;
                        fornecedorNome = picked.$2;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrCurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor mensal (R\$)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: diaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dia de referência (ex.: 10)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: categoria.isEmpty ? null : categoria,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  items: categorias
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDlg(() => categoria = v ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: contaId,
                  decoration: const InputDecoration(
                    labelText: 'Conta destino (caixa)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('(opcional)'),
                    ),
                    ...contas.map(
                      (c) => DropdownMenuItem<String?>(
                          value: c.id, child: Text(c.nome)),
                    ),
                  ],
                  onChanged: (v) => setDlg(() => contaId = v),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Período indeterminado'),
                  subtitle: const Text(
                    'Gera até o mês atual; depois continua mês a mês.',
                  ),
                  trailing: Switch(
                    value: indeterminado,
                    onChanged: (v) => setDlg(() {
                      indeterminado = v;
                      if (v) {
                        dataFim = null;
                        dataFimCtrl.clear();
                      }
                    }),
                  ),
                ),
                TextField(
                  controller: dataInicioCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [BrDateDdMmYyyyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Data início (DD/MM/AAAA)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.calendar_month_rounded),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: dataInicio,
                          firstDate: DateTime(2018),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) {
                          setDlg(() {
                            dataInicio = d;
                            dataInicioCtrl.text = formatBrDateDdMmYyyy(d);
                          });
                        }
                      },
                    ),
                  ),
                  onChanged: (v) {
                    final p = parseBrDateDdMmYyyy(v.trim());
                    if (p != null) setDlg(() => dataInicio = p);
                  },
                ),
                if (!indeterminado) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: dataFimCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [BrDateDdMmYyyyInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Data fim (DD/MM/AAAA)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_month_rounded),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: dataFim ?? dataInicio,
                            firstDate: dataInicio,
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            setDlg(() {
                              dataFim = d;
                              dataFimCtrl.text = formatBrDateDdMmYyyy(d);
                            });
                          }
                        },
                      ),
                    ),
                    onChanged: (v) {
                      final p = parseBrDateDdMmYyyy(v.trim());
                      if (p != null) setDlg(() => dataFim = p);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    final valorText = valorCtrl.text;
    final diaText = diaCtrl.text;
    final dataInicioText = dataInicioCtrl.text;
    final dataFimText = dataFimCtrl.text;
    valorCtrl.dispose();
    diaCtrl.dispose();
    dataInicioCtrl.dispose();
    dataFimCtrl.dispose();

    if (result != true || !mounted) return;
    if (vinculoTipo == 'membro') {
      if (memberDocId == null || memberDocId!.isEmpty || memberNome.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione um membro.')),
        );
        return;
      }
    } else {
      if (fornecedorId == null ||
          fornecedorId!.isEmpty ||
          fornecedorNome.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione um fornecedor.')),
        );
        return;
      }
    }
    final v = _parseValor(valorText);
    if (v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido.')),
      );
      return;
    }
    final dia = int.tryParse(diaText.trim());
    if (dia == null || dia < 1 || dia > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dia de referência inválido (1–31).')),
      );
      return;
    }
    if (categoria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha uma categoria.')),
      );
      return;
    }
    final parsedInicio = parseBrDateDdMmYyyy(dataInicioText.trim());
    if (parsedInicio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data de início (DD/MM/AAAA).')),
      );
      return;
    }
    DateTime? parsedFim;
    if (!indeterminado) {
      parsedFim = parseBrDateDdMmYyyy(dataFimText.trim());
      if (parsedFim == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe a data fim (DD/MM/AAAA).')),
        );
        return;
      }
      if (parsedFim.isBefore(parsedInicio)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A data fim deve ser após a data de início.')),
        );
        return;
      }
    }

    String? contaNome;
    if (contaId != null && contaId!.isNotEmpty) {
      final m = {for (final c in contas) c.id: c.nome};
      contaNome = m[contaId];
    }

    final titularNome =
        vinculoTipo == 'fornecedor' ? fornecedorNome : memberNome;
    final payload = <String, dynamic>{
      'vinculoTipo': vinculoTipo,
      'titularNome': titularNome,
      'valor': v,
      'diaVencimento': dia,
      'categoria': categoria,
      'dataInicio': Timestamp.fromDate(
        DateTime(parsedInicio.year, parsedInicio.month, parsedInicio.day),
      ),
      'indeterminado': indeterminado,
      'ativo': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (vinculoTipo == 'membro') {
      payload['memberDocId'] = memberDocId;
      payload['memberNome'] = memberNome;
      if (memberTelefone?.isNotEmpty == true) {
        payload['memberTelefone'] = memberTelefone;
      } else {
        payload['memberTelefone'] = FieldValue.delete();
      }
      payload['fornecedorId'] = FieldValue.delete();
      payload['fornecedorNome'] = FieldValue.delete();
    } else {
      payload['fornecedorId'] = fornecedorId;
      payload['fornecedorNome'] = fornecedorNome;
      payload['memberDocId'] = FieldValue.delete();
      payload['memberNome'] = FieldValue.delete();
      payload['memberTelefone'] = FieldValue.delete();
    }
    if (!indeterminado && parsedFim != null) {
      payload['dataFim'] = Timestamp.fromDate(
        DateTime(parsedFim.year, parsedFim.month, parsedFim.day),
      );
    } else {
      payload['dataFim'] = FieldValue.delete();
    }
    if (contaId != null && contaId!.isNotEmpty) {
      payload['contaDestinoId'] = contaId;
      if (contaNome != null) payload['contaDestinoNome'] = contaNome;
    } else {
      payload['contaDestinoId'] = FieldValue.delete();
      payload['contaDestinoNome'] = FieldValue.delete();
    }

    try {
      if (doc != null) {
        await doc.reference.set(payload, SetOptions(merge: true));
      } else {
        final addMap = Map<String, dynamic>.from(payload)
          ..removeWhere((_, v) => v is FieldValue);
        addMap['createdAt'] = FieldValue.serverTimestamp();
        await _col.add(addMap);
      }
      await gerarReceitasRecorrentesPendentes(widget.tenantId);
      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvo. Lançamentos projetados quando aplicável.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar receitas recorrentes',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        final raw = snap.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          raw,
        )..sort((a, b) {
            final ca = titularNomeFinanceFixo(a.data());
            final cb = titularNomeFinanceFixo(b.data());
            return ca.toLowerCase().compareTo(cb.toLowerCase());
          });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Provisão mensal (${docs.length}) — o caixa recebe lançamentos pendentes até o tesoureiro confirmar.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _gerarPendentes,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Gerar no caixa'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: () => _addOuEditar(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Agendar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
              const Expanded(child: ChurchPanelLoadingBody())
            else if (docs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.savings_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma receita recorrente.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ex.: dízimo ou doação fixa vinculada a membro ou fornecedor, com valor e período.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final nome = titularNomeFinanceFixo(d);
                      final vt = (d['vinculoTipo'] ?? 'membro').toString();
                      final valor = _parseValor(d['valor']);
                      final cat = (d['categoria'] ?? '').toString();
                      final dia = (d['diaVencimento'] ?? '').toString();
                      final ativo = d['ativo'] != false;
                      DateTime? di;
                      DateTime? df;
                      try {
                        final ti = d['dataInicio'];
                        if (ti is Timestamp) di = ti.toDate();
                        final tf = d['dataFim'];
                        if (tf is Timestamp) df = tf.toDate();
                      } catch (_) {}
                      final ind = d['indeterminado'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.trending_up_rounded,
                              color: Color(0xFF2563EB),
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  nome.isEmpty ? '(sem nome)' : nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: vt == 'fornecedor'
                                      ? const Color(0xFFF3E8FF)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  vt == 'fornecedor' ? 'Fornecedor' : 'Membro',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: vt == 'fornecedor'
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$cat · R\$ ${valor.toStringAsFixed(2)} / mês',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              if (dia.isNotEmpty)
                                Text(
                                  'Referência: dia $dia',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              if (di != null)
                                Text(
                                  ind
                                      ? 'Desde ${DateFormat('dd/MM/yyyy').format(di)} · indeterminado'
                                      : (df != null
                                          ? '${DateFormat('dd/MM/yyyy').format(di)} — ${DateFormat('dd/MM/yyyy').format(df)}'
                                          : 'Desde ${DateFormat('dd/MM/yyyy').format(di)}'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: ativo
                                      ? const Color(0xFFF0FDF4)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  ativo ? 'Ativa' : 'Inativa',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: ativo
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, size: 20),
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    _addOuEditar(context, doc: docs[i]);
                                  } else if (v == 'toggle') {
                                    await docs[i]
                                        .reference
                                        .update({'ativo': !ativo});
                                    if (mounted) _refresh();
                                  } else if (v == 'delete') {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Excluir agendamento?'),
                                        content: const Text(
                                          'Os lançamentos já gerados no caixa não são apagados.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Excluir'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await docs[i].reference.delete();
                                      if (mounted) _refresh();
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(Icons.pause_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Ativar / desativar'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Color(0xFFDC2626),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Excluir',
                                          style: TextStyle(
                                            color: Color(0xFFDC2626),
                                          ),
                                        ),
                                      ],
                                    ),
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
              ),
          ],
        );
      },
    );
  }
}

// ─── Tab: Conciliação de receitas recorrentes ───────────────────────────────

class FinanceConciliacaoReceitasTab extends StatefulWidget {
  final String tenantId;
  final String role;

  const FinanceConciliacaoReceitasTab({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  State<FinanceConciliacaoReceitasTab> createState() =>
      _FinanceConciliacaoReceitasTabState();
}

class _FinanceConciliacaoReceitasTabState
    extends State<FinanceConciliacaoReceitasTab> {
  CollectionReference<Map<String, dynamic>> get _fin =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('finance');

  late String _competencia;
  final Set<String> _selected = {};
  bool _loading = false;
  String _filtroContaId = '__geral__';
  String _filtroCategoria = 'todas';
  late Future<QuerySnapshot<Map<String, dynamic>>> _contasFuture;
  late Future<List<String>> _catsFuture;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _competencia = competenciaFinanceira(n);
    FirebaseAuth.instance.currentUser?.getIdToken(true);
    _contasFuture = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('contas')
        .orderBy('nome')
        .get();
    _catsFuture = _categoriasReceitaTenant(widget.tenantId);
  }

  List<String> _competenciaOpcoes() {
    final now = DateTime.now();
    final out = <String>[];
    for (var i = 0; i < 18; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      out.add(competenciaFinanceira(d));
    }
    return out;
  }

  Future<void> _confirmar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendentes,
  ) async {
    if (_selected.isEmpty) return;
    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pendentes) {
        if (!_selected.contains(doc.id)) continue;
        batch.update(doc.reference, {
          'recebimentoConfirmado': true,
          'pendenteConciliacaoRecorrencia': false,
          'conciliadoEm': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        setState(() {
          _selected.clear();
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lançamentos confirmados no caixa.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _confirmarUm(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool sendWhatsApp = false,
  }) async {
    setState(() => _loading = true);
    try {
      final m = doc.data() ?? {};
      await doc.reference.update({
        'recebimentoConfirmado': true,
        'pendenteConciliacaoRecorrencia': false,
        'conciliadoEm': FieldValue.serverTimestamp(),
      });
      if (sendWhatsApp && mounted) {
        final mid = (m['memberDocId'] ?? '').toString().trim();
        if (mid.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'WhatsApp de agradecimento está disponível para receitas vinculadas a membro.',
              ),
            ),
          );
        } else {
          final nomeIgreja = await _nomeIgreja(widget.tenantId);
          final nome = _titularConciliacao(m);
          final valor = _parseValor(m['amount'] ?? m['valor']);
          var phone = (m['memberTelefone'] ?? '').toString().trim();
          if (phone.isEmpty) {
            final ms = await FirebaseFirestore.instance
                .collection('igrejas')
                .doc(widget.tenantId)
                .collection('membros')
                .doc(mid)
                .get();
            final p = _memberTelefoneRaw(ms.data() ?? {});
            if (p != null && p.isNotEmpty) phone = p;
          }
          final msg =
              'Olá $nome, sua contribuição de R\$ ${valor.toStringAsFixed(2)} foi recebida com sucesso. Que Deus te abençoe! Equipe $nomeIgreja.';
          final url = _waUrl(phone.isEmpty ? null : phone, msg);
          if (url != null) {
            final u = Uri.parse(url);
            if (await canLaunchUrl(u)) {
              await launchUrl(u, mode: LaunchMode.externalApplication);
            }
          }
        }
      }
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receita confirmada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _confirmarTodos(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty || _loading) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Conciliar todas'),
        content: Text(
          'Confirmar ${docs.length} receita(s) pendente(s) no caixa (competência $_competencia)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Conciliar todas'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        batch.update(doc.reference, {
          'recebimentoConfirmado': true,
          'pendenteConciliacaoRecorrencia': false,
          'conciliadoEm': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        setState(() {
          _selected.clear();
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${docs.length} receita(s) conciliada(s).')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _excluirDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text(
          'Excluir este lançamento? O registro ficará no histórico de auditoria.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await logFinanceiroAuditoria(
        tenantId: widget.tenantId,
        acao: 'exclusao',
        lancamentoId: doc.id,
        dadosAntes: Map<String, dynamic>.from(doc.data() ?? {}),
      );
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lançamento excluído.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opcoes = _competenciaOpcoes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Confirme o que já caiu na conta. Até confirmar, o valor não entra no saldo efetivo.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _competencia,
                    items: opcoes
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: _loading
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() {
                              _competencia = v;
                              _selected.clear();
                            });
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<dynamic>>(
                future: Future.wait([_contasFuture, _catsFuture]),
                builder: (context, meta) {
                  if (!meta.hasData) {
                    return const SizedBox(height: 8);
                  }
                  final contasSnap =
                      meta.data![0] as QuerySnapshot<Map<String, dynamic>>;
                  final cats = meta.data![1] as List<String>;
                  final contasAtivas = contasSnap.docs
                      .where((c) => c.data()['ativo'] != false)
                      .toList();
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: contasAtivas.any((c) => c.id == _filtroContaId)
                              ? _filtroContaId
                              : '__geral__',
                          decoration: const InputDecoration(
                            labelText: 'Conta / caixa',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '__geral__',
                              child: Text('Todas'),
                            ),
                            ...contasAtivas.map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  (c.data()['nome'] ?? 'Conta').toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _loading
                              ? null
                              : (v) => setState(() {
                                    _filtroContaId = v ?? '__geral__';
                                    _selected.clear();
                                  }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: cats.contains(_filtroCategoria)
                              ? _filtroCategoria
                              : 'todas',
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'todas',
                              child: Text('Todas'),
                            ),
                            ...cats.map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ),
                            ),
                          ],
                          onChanged: _loading
                              ? null
                              : (v) => setState(() {
                                    _filtroCategoria = v ?? 'todas';
                                    _selected.clear();
                                  }),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fin
                .where('pendenteConciliacaoRecorrencia', isEqualTo: true)
                .where('competencia', isEqualTo: _competencia)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return ChurchPanelErrorBody(
                  title: 'Não foi possível carregar pendências',
                  error: snap.error,
                  onRetry: () => setState(() {}),
                );
              }
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const ChurchPanelLoadingBody();
              }
              final raw = snap.data?.docs ?? [];
              var docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                raw,
              )..sort((a, b) {
                  final ca = _titularConciliacao(a.data());
                  final cb = _titularConciliacao(b.data());
                  return ca.toLowerCase().compareTo(cb.toLowerCase());
                });
              docs = docs.where((d) {
                final m = d.data();
                if (_filtroContaId != '__geral__' &&
                    financeContaDestinoReceitaId(m) != _filtroContaId) {
                  return false;
                }
                if (_filtroCategoria != 'todas' &&
                    (m['categoria'] ?? '').toString() != _filtroCategoria) {
                  return false;
                }
                return true;
              }).toList();
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.task_alt_rounded,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhuma receita pendente neste mês.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  if (docs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _loading
                                ? null
                                : () => _confirmarTodos(docs),
                            icon: const Icon(Icons.done_all_rounded, size: 20),
                            label: const Text('Conciliar todas'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                      _selected
                                        ..clear()
                                        ..addAll(docs.map((d) => d.id));
                                    }),
                            icon: const Icon(Icons.select_all_rounded, size: 20),
                            label: const Text('Selecionar todas'),
                          ),
                        ],
                      ),
                    ),
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            '${_selected.length} selecionado(s)',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(_selected.clear),
                            child: const Text('Limpar'),
                          ),
                          FilledButton.icon(
                            onPressed: _loading
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text(
                                          'Confirmar selecionados',
                                        ),
                                        content: Text(
                                          'Confirmar ${_selected.length} receita(s) no caixa? '
                                          'O WhatsApp de agradecimento está disponível ao confirmar cada linha.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Confirmar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true || !context.mounted) return;
                                    await _confirmar(docs);
                                  },
                            icon: const Icon(Icons.check_circle_rounded, size: 20),
                            label: const Text('Confirmar selecionados'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final m = doc.data();
                        final nome = _titularConciliacao(m);
                        final vt = (m['vinculoTipo'] ?? 'membro').toString();
                        final cat = (m['categoria'] ?? '').toString();
                        final valor = _parseValor(m['amount'] ?? m['valor']);
                        final desc = (m['descricao'] ?? '').toString();
                        final sel = _selected.contains(doc.id);

                        return Card(
                          elevation: 0,
                          color: const Color(0xFFFFFBEB),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            side: BorderSide(color: Colors.amber.shade200),
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CheckboxListTile(
                                value: sel,
                                onChanged: _loading
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(doc.id);
                                          } else {
                                            _selected.remove(doc.id);
                                          }
                                        });
                                      },
                                secondary: CircleAvatar(
                                  backgroundColor: Colors.amber.shade100,
                                  child: Icon(
                                    Icons.schedule_rounded,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nome.isEmpty ? '(titular)' : nome,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: vt == 'fornecedor'
                                            ? const Color(0xFFF3E8FF)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        vt == 'fornecedor'
                                            ? 'Fornecedor'
                                            : 'Membro',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: vt == 'fornecedor'
                                              ? const Color(0xFF7C3AED)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$cat · R\$ ${valor.toStringAsFixed(2)}',
                                    ),
                                    if (desc.isNotEmpty)
                                      Text(
                                        desc,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                  ],
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () async {
                                              final wa =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text(
                                                    'Confirmar recebimento',
                                                  ),
                                                  content: const Text(
                                                    'Abrir WhatsApp de agradecimento?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              c, false),
                                                      child: const Text(
                                                        'Não',
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              c, true),
                                                      child: const Text(
                                                        'Sim',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (!context.mounted) return;
                                              await _confirmarUm(
                                                doc,
                                                sendWhatsApp: wa == true,
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                      ),
                                      label: const Text('Confirmar'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF16A34A),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () async {
                                              await showFinanceLancamentoEditorForTenant(
                                                context,
                                                tenantId: widget.tenantId,
                                                existingDoc: doc,
                                                panelRole: widget.role,
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Editar valor'),
                                    ),
                                    IconButton.filledTonal(
                                      tooltip: 'Excluir',
                                      onPressed: _loading
                                          ? null
                                          : () => _excluirDoc(doc),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
