import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/performance/firebase_performance_limits.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/pdf/membros_financeiro_geral_pdf.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_relatorios_load_service.dart';
import 'package:gestao_yahweh/ui/pages/finance_vinculo_extrato_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/utils/yahweh_date_range_picker.dart';

/// Linha do quadro: uma pessoa e o que entrou e saiu por causa dela.
class MembroFinanceiroLinha {
  MembroFinanceiroLinha({
    required this.id,
    required this.nome,
    required this.sexo,
    required this.departamentos,
    required this.idade,
  });

  final String id;
  final String nome;

  /// `m`, `f` ou vazio.
  final String sexo;
  final List<String> departamentos;

  /// `null` quando o cadastro não tem data de nascimento.
  final int? idade;

  double receitas = 0;
  double despesas = 0;
  int lancamentos = 0;
  DateTime? ultimoLancamento;

  double get saldo => receitas - despesas;
  bool get temMovimento => receitas > 0 || despesas > 0;

  /// Faixa usada nos gráficos: criança (<12), idoso (>=60) ou adulto.
  String get faixa {
    final i = idade;
    if (i == null) return 'adulto';
    if (i < 12) return 'crianca';
    if (i >= 60) return 'idoso';
    return 'adulto';
  }
}

/// Largura máxima da coluna de conteúdo. Acima disto o browser esticava a
/// tela até deixar cada número sozinho no meio de um deserto branco.
const double _larguraMaxConteudo = 1180;

enum _Periodo { ano, mes, intervalo }

enum _Ordem { alfabetica, maisReceita, maisDespesa, maiorSaldo }

/// Financeiro de **todos os membros** num só quadro.
///
/// A ficha de cada membro já mostra o extrato dele; o que faltava era a visão
/// de cima — quem contribuiu, quanto, e como isso se distribui por sexo, faixa
/// etária e departamento. É a pergunta que o pastor e o tesoureiro fazem no
/// fecho do mês, e que antes só se respondia abrindo membro a membro.
class MembrosFinanceiroGeralPage extends StatefulWidget {
  const MembrosFinanceiroGeralPage({
    super.key,
    required this.tenantId,
    required this.panelRole,
  });

  final String tenantId;
  final String panelRole;

  @override
  State<MembrosFinanceiroGeralPage> createState() =>
      _MembrosFinanceiroGeralPageState();
}

class _MembrosFinanceiroGeralPageState
    extends State<MembrosFinanceiroGeralPage> {
  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  bool _carregando = true;
  bool _atualizandoSilenciosamente = false;
  bool _exportando = false;
  String _erro = '';
  int _revisaoHub = -1;

  List<Map<String, dynamic>> _membros = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lancamentos = const [];

  _Periodo _periodo = _Periodo.ano;
  late int _ano = DateTime.now().year;
  late int _mes = DateTime.now().month;
  DateTimeRange? _intervalo;

  _Ordem _ordem = _Ordem.maisReceita;
  String _filtroSexo = 'todos';
  String _filtroDepartamento = 'todos';
  final _buscaCtrl = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    FinanceTransactionsHub.revision.addListener(_aoMudarNoFinanceiro);
    unawaited(_carregar());
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_aoMudarNoFinanceiro);
    _buscaCtrl.dispose();
    super.dispose();
  }

  void _aoMudarNoFinanceiro() {
    final r = FinanceTransactionsHub.revision.value;
    if (r == _revisaoHub) return;
    _revisaoHub = r;
    if (mounted) unawaited(_carregar(force: true));
  }

  String get _tid => ChurchRepository.churchId(widget.tenantId);

  Future<void> _carregar({bool force = false}) async {
    if (mounted) setState(() => _carregando = _membros.isEmpty);
    try {
      final res = await Future.wait([
        ChurchRelatoriosLoadService.loadMembrosRows(
          churchIdHint: _tid,
          limit: 800,
          forceRefresh: force,
        ),
        ChurchFinanceLoadService.loadLancamentos(
          seedTenantId: _tid,
          limit: FirebasePerformanceLimits.financeiroPage,
          forceRefresh: force,
          forceServer: force,
        ),
      ]);
      if (!mounted) return;
      final financeResult = res[1] as ChurchFinanceLoadResult;
      setState(() {
        _membros = res[0] as List<Map<String, dynamic>>;
        _lancamentos = financeResult.docs;
        _carregando = false;
        _erro = '';
      });
      // Cache primeiro pinta a tela imediatamente. Em seguida confirma no
      // servidor e repinta silenciosamente; antes o refresh em background
      // atualizava apenas o cache do serviço, deixando a tela presa no total
      // anterior (por exemplo, R$ 50 em vez de incluir os novos R$ 150).
      if (!force &&
          financeResult.fromCache &&
          !_atualizandoSilenciosamente) {
        _atualizandoSilenciosamente = true;
        unawaited(_atualizarFinanceiroSilencioso().whenComplete(() {
          _atualizandoSilenciosamente = false;
        }));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar: $e';
      });
    }
  }

  Future<void> _atualizarFinanceiroSilencioso() async {
    try {
      final result = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: _tid,
        limit: FirebasePerformanceLimits.financeiroPage,
        forceRefresh: true,
        forceServer: true,
      );
      if (!mounted) return;
      setState(() {
        _lancamentos = result.docs;
        _erro = '';
      });
    } catch (_) {
      // Mantém a leitura cache-first visível se a rede estiver indisponível.
    }
  }

  // ───────────────────────────────────────────── dados

  static String _txt(Map<String, dynamic> m, List<String> chaves) {
    for (final k in chaves) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static int? _idadeDe(Map<String, dynamic> m) {
    final raw = m['DATA_NASCIMENTO'] ?? m['dataNascimento'] ?? m['birthDate'];
    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is DateTime) {
      dt = raw;
    } else if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      final n = sec is num ? sec.toInt() : int.tryParse('$sec');
      if (n != null && n > 0) {
        dt = DateTime.fromMillisecondsSinceEpoch(n * 1000);
      }
    } else if (raw != null) {
      dt = DateTime.tryParse(raw.toString());
    }
    if (dt == null) return null;
    final hoje = DateTime.now();
    var anos = hoje.year - dt.year;
    if (hoje.month < dt.month ||
        (hoje.month == dt.month && hoje.day < dt.day)) {
      anos--;
    }
    return anos < 0 || anos > 130 ? null : anos;
  }

  static List<String> _departamentosDe(Map<String, dynamic> m) {
    final raw = m['DEPARTAMENTOS'] ?? m['departamentos'];
    if (raw is List) {
      return [
        for (final e in raw)
          if ((e ?? '').toString().trim().isNotEmpty) e.toString().trim(),
      ];
    }
    final unico = _txt(m, ['departamento', 'DEPARTAMENTO']);
    return unico.isEmpty ? const [] : [unico];
  }

  bool _noPeriodo(Map<String, dynamic> d) {
    final dt = financeLancamentoDate(d);
    if (dt == null) return false;
    switch (_periodo) {
      case _Periodo.ano:
        return dt.year == _ano;
      case _Periodo.mes:
        return dt.year == _ano && dt.month == _mes;
      case _Periodo.intervalo:
        final r = _intervalo;
        if (r == null) return true;
        final ini = DateTime(r.start.year, r.start.month, r.start.day);
        final fim = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !dt.isBefore(ini) && !dt.isAfter(fim);
    }
  }

  String get _periodoLabel {
    switch (_periodo) {
      case _Periodo.ano:
        return 'Ano de $_ano';
      case _Periodo.mes:
        return DateFormat('MMMM \'de\' y', 'pt_BR').format(DateTime(_ano, _mes));
      case _Periodo.intervalo:
        final r = _intervalo;
        if (r == null) return 'Período livre';
        final f = DateFormat('dd/MM/yyyy', 'pt_BR');
        return '${f.format(r.start)} a ${f.format(r.end)}';
    }
  }

  /// Quadro por pessoa, já filtrado e ordenado.
  List<MembroFinanceiroLinha> get _linhas {
    final porId = <String, MembroFinanceiroLinha>{};
    final porNome = <String, MembroFinanceiroLinha>{};
    for (final m in _membros) {
      final id = (m['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final nome = _txt(m, [
        'NOME_COMPLETO',
        'nomeCompleto',
        'NOME',
        'nome',
        'name',
      ]);
      if (nome.isEmpty) continue;
      final sexoRaw = _txt(m, ['SEXO', 'sexo', 'genero']).toLowerCase();
      final linha = MembroFinanceiroLinha(
        id: id,
        nome: nome,
        sexo: sexoRaw.startsWith('m')
            ? 'm'
            : (sexoRaw.startsWith('f') ? 'f' : ''),
        departamentos: _departamentosDe(m),
        idade: _idadeDe(m),
      );
      porId[id] = linha;
      porNome[_normalizarNome(nome)] = linha;
    }

    for (final doc in _lancamentos) {
      final d = doc.data();
      // Só vínculo individual: com várias pessoas o valor não é de ninguém
      // em particular e somá-lo a cada uma contaria o mesmo dinheiro várias
      // vezes.
      if (d['vinculoMultiplo'] == true) continue;
      final mid = (d['membroId'] ?? d['memberId'] ?? '').toString().trim();
      var linha = mid.isEmpty ? null : porId[mid];
      // Compatibilidade com lançamentos antigos/importados: algumas versões
      // guardavam o nome, ou um código do membro, no lugar do docId. O nome só
      // é usado como fallback quando identifica uma pessoa cadastrada.
      if (linha == null) {
        final nomeVinculo = _txt(d, const [
          'membroNome',
          'memberNome',
          'memberName',
          'donorName',
        ]);
        if (nomeVinculo.isNotEmpty) {
          linha = porNome[_normalizarNome(nomeVinculo)];
        }
      }
      if (linha == null) continue;
      if (!_noPeriodo(d)) continue;
      final t = financeInferTipo(d);
      if (t == 'transferencia') continue;
      final v = financeParseValorBr(d['amount'] ?? d['valor']);
      if (t.contains('entrada') || t.contains('receita')) {
        linha.receitas += v;
      } else if (t.contains('saida') || t.contains('despesa')) {
        linha.despesas += v;
      } else {
        continue;
      }
      linha.lancamentos++;
      final data = financeLancamentoDate(d);
      if (data != null &&
          (linha.ultimoLancamento == null ||
              data.isAfter(linha.ultimoLancamento!))) {
        linha.ultimoLancamento = data;
      }
    }

    var out = porId.values.where((l) => l.temMovimento).toList();

    if (_filtroSexo != 'todos') {
      out = out.where((l) => l.sexo == _filtroSexo).toList();
    }
    if (_filtroDepartamento != 'todos') {
      out = out
          .where((l) => l.departamentos.contains(_filtroDepartamento))
          .toList();
    }
    if (_busca.isNotEmpty) {
      final q = _busca.toLowerCase();
      out = out.where((l) => l.nome.toLowerCase().contains(q)).toList();
    }

    switch (_ordem) {
      case _Ordem.alfabetica:
        out.sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );
      case _Ordem.maisReceita:
        out.sort((a, b) {
          final valor = b.receitas.compareTo(a.receitas);
          return valor != 0
              ? valor
              : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        });
      case _Ordem.maisDespesa:
        out.sort((a, b) {
          final valor = b.despesas.compareTo(a.despesas);
          return valor != 0
              ? valor
              : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        });
      case _Ordem.maiorSaldo:
        out.sort((a, b) {
          final valor = b.saldo.compareTo(a.saldo);
          return valor != 0
              ? valor
              : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        });
    }
    return out;
  }

  static String _normalizarNome(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  List<String> get _todosDepartamentos {
    final s = <String>{};
    for (final m in _membros) {
      s.addAll(_departamentosDe(m));
    }
    final l = s.toList()..sort();
    return l;
  }

  /// Entradas e saídas mês a mês, só das pessoas visíveis no filtro.
  List<({int mes, double receitas, double despesas})> _porMes(
    List<MembroFinanceiroLinha> linhas,
  ) {
    final ids = {for (final l in linhas) l.id};
    final nomes = {for (final l in linhas) _normalizarNome(l.nome)};
    final rec = List<double>.filled(12, 0);
    final des = List<double>.filled(12, 0);
    for (final doc in _lancamentos) {
      final d = doc.data();
      if (d['vinculoMultiplo'] == true) continue;
      final mid = (d['membroId'] ?? d['memberId'] ?? '').toString().trim();
      final nomeVinculo = _normalizarNome(_txt(d, const [
        'membroNome',
        'memberNome',
        'memberName',
        'donorName',
      ]));
      if (!ids.contains(mid) && !nomes.contains(nomeVinculo)) continue;
      if (!_noPeriodo(d)) continue;
      final dt = financeLancamentoDate(d);
      if (dt == null) continue;
      final t = financeInferTipo(d);
      final v = financeParseValorBr(d['amount'] ?? d['valor']);
      if (t.contains('entrada') || t.contains('receita')) {
        rec[dt.month - 1] += v;
      } else if (t.contains('saida') || t.contains('despesa')) {
        des[dt.month - 1] += v;
      }
    }
    return [
      for (var i = 0; i < 12; i++)
        (mes: i + 1, receitas: rec[i], despesas: des[i]),
    ];
  }

  Map<String, double> _receitaPorDepartamento(
    List<MembroFinanceiroLinha> linhas,
  ) {
    final out = <String, double>{};
    for (final l in linhas) {
      if (l.receitas <= 0) continue;
      if (l.departamentos.isEmpty) {
        out['Sem departamento'] = (out['Sem departamento'] ?? 0) + l.receitas;
        continue;
      }
      // Sem rateio: quem esta em dois departamentos conta nos dois. E uma
      // leitura de participacao, nao de caixa — somar as fatias nao tem de
      // bater com o total.
      for (final d in l.departamentos) {
        out[d] = (out[d] ?? 0) + l.receitas;
      }
    }
    return out;
  }

  Map<String, double> _receitaPorPerfil(List<MembroFinanceiroLinha> linhas) {
    final out = <String, double>{
      'Homens': 0,
      'Mulheres': 0,
      'Crianças': 0,
      'Idosos': 0,
    };
    for (final l in linhas) {
      if (l.receitas <= 0) continue;
      if (l.faixa == 'crianca') {
        out['Crianças'] = out['Crianças']! + l.receitas;
      } else if (l.faixa == 'idoso') {
        out['Idosos'] = out['Idosos']! + l.receitas;
      } else if (l.sexo == 'm') {
        out['Homens'] = out['Homens']! + l.receitas;
      } else if (l.sexo == 'f') {
        out['Mulheres'] = out['Mulheres']! + l.receitas;
      }
    }
    out.removeWhere((_, v) => v <= 0);
    return out;
  }

  // ───────────────────────────────────────────── ações

  Future<void> _abrirExtrato(MembroFinanceiroLinha l) =>
      abrirExtratoFinanceiroDoVinculo(
        context,
        tenantId: widget.tenantId,
        tipo: 'membro',
        vinculoId: l.id,
        nome: l.nome,
        panelRole: widget.panelRole,
        onChanged: () => unawaited(_carregar(force: true)),
      );

  Future<void> _escolherIntervalo() async {
    final agora = DateTime.now();
    final r = await escolherIntervaloDeDatas(
      context,
      firstDate: DateTime(agora.year - 8),
      lastDate: DateTime(agora.year + 1, 12, 31),
      initialDateRange: _intervalo ??
          DateTimeRange(
            start: DateTime(agora.year, agora.month, 1),
            end: agora,
          ),
    );
    if (r != null && mounted) {
      setState(() {
        _intervalo = r;
        _periodo = _Periodo.intervalo;
      });
    }
  }

  Future<void> _exportarPdf() async {
    if (_exportando) return;
    setState(() => _exportando = true);
    try {
      await _carregar(force: true);
      if (!mounted) return;
      final linhasFiltradas = _linhas;
      final branding = await loadReportPdfBranding(_tid);
      final bytes = await buildMembrosFinanceiroGeralPdf(
        branding: branding,
        linhas: linhasFiltradas,
        periodoLabel: _periodoLabel,
        filtroLabel: _filtroLabel,
      );
      if (!mounted) return;
      await showPdfActions(
        context,
        bytes: bytes,
        filename: 'financeiro_membros_$_ano.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  String get _filtroLabel {
    final partes = <String>[];
    if (_filtroSexo == 'm') partes.add('Homens');
    if (_filtroSexo == 'f') partes.add('Mulheres');
    if (_filtroDepartamento != 'todos') partes.add(_filtroDepartamento);
    if (_busca.trim().isNotEmpty) partes.add('Pesquisa: "${_busca.trim()}"');
    return partes.isEmpty ? 'Todos os membros' : partes.join(' · ');
  }

  // ───────────────────────────────────────────── UI

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    // Consolida uma única vez por frame. Antes cada card/gráfico reconstruía
    // toda a relação membros x lançamentos, multiplicando o custo da tela.
    final receitas = linhas.fold<double>(0, (a, l) => a + l.receitas);
    final despesas = linhas.fold<double>(0, (a, l) => a + l.despesas);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Financeiro geral',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              'Contribuições e despesas por membro',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : () => _carregar(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: _exportando ? null : _exportarPdf,
            icon: _exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: _carregando && _membros.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _carregar(force: true),
              // No telemóvel a tela era boa; no browser esticava tudo até aos
              // 1900px — o campo de busca com meio metro de largura e cada
              // membro sozinho numa faixa vazia. Coluna central com largura
              // máxima + grelha resolve os dois de uma vez.
              child: LayoutBuilder(
                builder: (context, restricoes) {
                  final largo = restricoes.maxWidth >= 900;
                  final recuo = largo ? 24.0 : 14.0;
                  final util = (restricoes.maxWidth - recuo * 2)
                      .clamp(280.0, _larguraMaxConteudo);
                  final maiorReceita = linhas.isEmpty
                      ? 0.0
                      : linhas
                          .map((l) => l.receitas)
                          .reduce((a, b) => a > b ? a : b);
                  final distribuicao = _graficoDistribuicao(linhas);
                  return ListView(
                    padding: EdgeInsets.fromLTRB(recuo, 14, recuo, 28),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _larguraMaxConteudo,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_erro.isNotEmpty) _banner(_erro),
                              _cartaoPeriodo(),
                              const SizedBox(height: 12),
                              _cartoesTotais(
                                receitas,
                                despesas,
                                linhas,
                                largo: largo,
                              ),
                              const SizedBox(height: 12),
                              if (largo && distribuicao != null)
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _graficoMesAMes(linhas),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(flex: 2, child: distribuicao),
                                    ],
                                  ),
                                )
                              else ...[
                                _graficoMesAMes(linhas),
                                if (distribuicao != null) ...[
                                  const SizedBox(height: 12),
                                  distribuicao,
                                ],
                              ],
                              const SizedBox(height: 12),
                              _barraFiltros(largo),
                              const SizedBox(height: 12),
                              if (linhas.isEmpty)
                                _semMembros()
                              else
                                _grelhaMembros(linhas, util, maiorReceita),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _banner(String texto) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF991B1B),
          ),
        ),
      );

  BoxDecoration get _cardDeco => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      );

  Widget _cartaoPeriodo() {
    final anos = <int>{
      DateTime.now().year,
      _ano,
      for (final d in _lancamentos)
        if (financeLancamentoDate(d.data()) != null)
          financeLancamentoDate(d.data())!.year,
    }.toList()
      ..sort((a, b) => b.compareTo(a));

    Widget chip(String label, _Periodo p) {
      final sel = _periodo == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : ThemeCleanPremium.primary,
          ),
          selectedColor: ThemeCleanPremium.primary,
          onSelected: (_) {
            if (p == _Periodo.intervalo) {
              unawaited(_escolherIntervalo());
              return;
            }
            setState(() => _periodo = p);
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'PERÍODO',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _periodoLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('Ano', _Periodo.ano),
                chip('Mês atual', _Periodo.mes),
                chip('Período', _Periodo.intervalo),
              ],
            ),
          ),
          if (_periodo != _Periodo.intervalo) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: anos.contains(_ano) ? _ano : anos.first,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Ano',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final a in anos)
                        DropdownMenuItem(value: a, child: Text('$a')),
                    ],
                    onChanged: (v) => setState(() => _ano = v ?? _ano),
                  ),
                ),
                if (_periodo == _Periodo.mes) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _mes,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Mês',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              DateFormat('MMM', 'pt_BR')
                                  .format(DateTime(2000, m)),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _mes = v ?? _mes),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartoesTotais(
    double receitas,
    double despesas,
    List<MembroFinanceiroLinha> linhas, {
    bool largo = false,
  }) {
    // Cada card abre a lista já ordenada pelo que ele mostra — o número e a
    // lista que o explica ficam a um toque.
    return Row(
      children: [
        Expanded(
          child: _CardTotal(
            titulo: 'Contribuições',
            valor: _money.format(receitas),
            cor: const Color(0xFF15803D),
            icone: Icons.trending_up_rounded,
            onTap: () => setState(() => _ordem = _Ordem.maisReceita),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Despesas',
            valor: _money.format(despesas),
            cor: const Color(0xFFB91C1C),
            icone: Icons.trending_down_rounded,
            onTap: () => setState(() => _ordem = _Ordem.maisDespesa),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CardTotal(
            titulo: 'Saldo',
            valor: _money.format(receitas - despesas),
            cor: receitas - despesas >= 0
                ? const Color(0xFF1D4ED8)
                : const Color(0xFFB91C1C),
            icone: Icons.account_balance_wallet_rounded,
            onTap: () => setState(() => _ordem = _Ordem.maiorSaldo),
          ),
        ),
        if (largo) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _CardTotal(
              titulo: 'Membros',
              valor: '${linhas.length}',
              cor: const Color(0xFF7C3AED),
              icone: Icons.groups_rounded,
              onTap: () => setState(() => _ordem = _Ordem.alfabetica),
            ),
          ),
        ],
      ],
    );
  }

  Widget _graficoMesAMes(List<MembroFinanceiroLinha> linhas) {
    final dados = _porMes(linhas);
    final maxV = dados.fold<double>(
      0,
      (a, e) => [a, e.receitas, e.despesas].reduce((x, y) => x > y ? x : y),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'EVOLUÇÃO MÊS A MÊS',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
              const Spacer(),
              const _Legenda(cor: Color(0xFF15803D), texto: 'Entradas'),
              const SizedBox(width: 8),
              const _Legenda(cor: Color(0xFFB91C1C), texto: 'Saídas'),
            ],
          ),
          const SizedBox(height: 12),
          if (maxV <= 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Sem movimento no período escolhido.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in dados)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: _Barra(
                                    altura: 94 * (e.receitas / maxV),
                                    cor: const Color(0xFF15803D),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: _Barra(
                                    altura: 94 * (e.despesas / maxV),
                                    cor: const Color(0xFFB91C1C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              DateFormat('MMM', 'pt_BR')
                                  .format(DateTime(2000, e.mes))
                                  .substring(0, 3),
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// `null` quando não há nada para mostrar — quem chama decide o espaço.
  Widget? _graficoDistribuicao(List<MembroFinanceiroLinha> linhas) {
    final perfil = _receitaPorPerfil(linhas);
    final depts = _receitaPorDepartamento(linhas).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (perfil.isEmpty && depts.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_rounded,
                size: 18,
                color: ThemeCleanPremium.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'DE ONDE VEM',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          if (perfil.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in perfil.entries)
              _LinhaProporcao(
                rotulo: e.key,
                valor: e.value,
                maximo: perfil.values.reduce((a, b) => a > b ? a : b),
                money: _money,
                cor: const Color(0xFF15803D),
              ),
          ],
          if (depts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'POR DEPARTAMENTO',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 8),
            for (final e in depts.take(8))
              _LinhaProporcao(
                rotulo: e.key,
                valor: e.value,
                maximo: depts.first.value,
                money: _money,
                cor: const Color(0xFF2563EB),
              ),
            const SizedBox(height: 6),
            const Text(
              'Quem está em mais de um departamento conta em todos — é '
              'participação, não caixa; as fatias não somam o total.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _semMembros() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: _cardDeco,
        child: const Column(
          children: [
            Icon(
              Icons.person_search_rounded,
              size: 34,
              color: Color(0xFFCBD5E1),
            ),
            SizedBox(height: 10),
            Text(
              'Nenhum membro com movimento no período.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF334155),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Vincule o membro ao lançar receitas e despesas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      );

  /// Grelha de membros: 1 coluna no telemóvel, 2 no tablet, 3 no browser.
  ///
  /// Antes era sempre uma coluna — no browser cada membro ocupava uma faixa
  /// de 1900px com três números perdidos no meio e obrigava a rolar por uma
  /// lista que cabia num ecrã.
  Widget _grelhaMembros(
    List<MembroFinanceiroLinha> linhas,
    double util,
    double maiorReceita,
  ) {
    final colunas = util >= 1120 ? 3 : (util >= 720 ? 2 : 1);
    const espaco = 12.0;
    final largura =
        colunas == 1 ? util : (util - espaco * (colunas - 1)) / colunas;
    return Wrap(
      spacing: espaco,
      runSpacing: espaco,
      children: [
        for (var i = 0; i < linhas.length; i++)
          SizedBox(
            width: largura,
            child: _linhaMembro(linhas[i], i + 1, maiorReceita),
          ),
      ],
    );
  }

  Widget _barraFiltros(bool largo) {
    Widget chipSexo(String v, String label) {
      final sel = _filtroSexo == v;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : const Color(0xFF334155),
          ),
          selectedColor: ThemeCleanPremium.primary,
          onSelected: (_) => setState(() => _filtroSexo = v),
        ),
      );
    }

    Widget chipOrdem(_Ordem v, String label) {
      final sel = _ordem == v;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: sel ? Colors.white : const Color(0xFF334155),
          ),
          selectedColor: const Color(0xFF7C3AED),
          onSelected: (_) => setState(() => _ordem = v),
        ),
      );
    }

    final depts = _todosDepartamentos;
    final busca = TextField(
      controller: _buscaCtrl,
      onChanged: (v) => setState(() => _busca = v.trim()),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar membro pelo nome…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _busca.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _buscaCtrl.clear();
                  setState(() => _busca = '');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
    final dropDepto = DropdownButtonFormField<String>(
      initialValue: _filtroDepartamento,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Departamento',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        const DropdownMenuItem(
          value: 'todos',
          child: Text('Todos os departamentos'),
        ),
        for (final d in depts) DropdownMenuItem(value: d, child: Text(d)),
      ],
      onChanged: (v) => setState(() => _filtroDepartamento = v ?? 'todos'),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No browser a busca e o departamento cabem na mesma linha; no
          // telemóvel continuam empilhados.
          if (largo && depts.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: busca),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: dropDepto),
              ],
            )
          else ...[
            busca,
            if (depts.isNotEmpty) ...[
              const SizedBox(height: 10),
              dropDepto,
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 0,
            runSpacing: 6,
            children: [
              chipSexo('todos', 'Todos'),
              chipSexo('m', 'Homens'),
              chipSexo('f', 'Mulheres'),
              const SizedBox(width: 6),
              chipOrdem(_Ordem.maisReceita, 'Mais contribuiu'),
              chipOrdem(_Ordem.maisDespesa, 'Mais despesa'),
              chipOrdem(_Ordem.maiorSaldo, 'Maior saldo'),
              chipOrdem(_Ordem.alfabetica, 'Nome A–Z'),
            ],
          ),
        ],
      ),
    );
  }

  /// Cartão de um membro na grelha.
  ///
  /// Leva **posição** e **barra de proporção** porque a lista está ordenada por
  /// um critério (mais contribuiu, maior saldo…): sem isso, dois cartões lado a
  /// lado no browser não diziam qual pesava mais.
  Widget _linhaMembro(
    MembroFinanceiroLinha l,
    int posicao,
    double maiorReceita,
  ) {
    final frac = maiorReceita <= 0
        ? 0.0
        : (l.receitas / maiorReceita).clamp(0.0, 1.0);
    final iniciais = _iniciaisDe(l.nome);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => unawaited(_abrirExtrato(l)),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary,
                          ThemeCleanPremium.primary.withValues(alpha: 0.72),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Text(
                      iniciais,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (l.departamentos.isNotEmpty)
                          Text(
                            l.departamentos.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$posicao',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 5,
                  children: [
                    _MiniInfoChip(
                      icon: Icons.receipt_long_rounded,
                      label: '${l.lancamentos} lançamento(s)',
                    ),
                    if (l.ultimoLancamento != null)
                      _MiniInfoChip(
                        icon: Icons.schedule_rounded,
                        label: DateFormat('dd/MM/yyyy', 'pt_BR')
                            .format(l.ultimoLancamento!),
                      ),
                  ],
                ),
              ),
              if (maiorReceita > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF15803D),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Valor(
                      rotulo: 'Contribuiu',
                      valor: _money.format(l.receitas),
                      cor: const Color(0xFF15803D),
                    ),
                  ),
                  Expanded(
                    child: _Valor(
                      rotulo: 'Despesas',
                      valor: _money.format(l.despesas),
                      cor: const Color(0xFFB91C1C),
                    ),
                  ),
                  Expanded(
                    child: _Valor(
                      rotulo: 'Saldo',
                      valor: _money.format(l.saldo),
                      cor: l.saldo >= 0
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Duas iniciais do nome — o avatar do extrato usa a mesma leitura.
  static String _iniciaisDe(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1))
        .toUpperCase();
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF475569)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ),
      );
}

class _CardTotal extends StatelessWidget {
  const _CardTotal({
    required this.titulo,
    required this.valor,
    required this.cor,
    required this.icone,
    required this.onTap,
  });

  final String titulo;
  final String valor;
  final Color cor;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cor.withValues(alpha: 0.18),
                      cor.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, size: 17, color: cor),
              ),
              const SizedBox(height: 9),
              Text(
                titulo.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: cor,
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

class _Valor extends StatelessWidget {
  const _Valor({
    required this.rotulo,
    required this.valor,
    required this.cor,
  });

  final String rotulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: cor,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinhaProporcao extends StatelessWidget {
  const _LinhaProporcao({
    required this.rotulo,
    required this.valor,
    required this.maximo,
    required this.money,
    required this.cor,
  });

  final String rotulo;
  final double valor;
  final double maximo;
  final NumberFormat money;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final frac = maximo <= 0 ? 0.0 : (valor / maximo).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              Text(
                money.format(valor),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: cor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.altura, required this.cor});

  final double altura;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura.isFinite && altura > 0 ? altura.clamp(3.0, 94.0) : 3,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor, cor.withValues(alpha: 0.62)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.cor, required this.texto});

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
