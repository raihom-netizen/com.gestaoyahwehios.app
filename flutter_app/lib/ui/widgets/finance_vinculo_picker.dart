import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, SafeNetworkImage;

/// Pessoa vinculada a um lançamento financeiro (membro ou fornecedor).
///
/// A regra de negócio vive em [FinanceVinculoSelecao]: **só quando há um
/// vínculo** o valor é atribuído à pessoa e conta no total dela.
class FinanceVinculo {
  const FinanceVinculo({
    required this.tipo,
    required this.id,
    required this.nome,
  });

  /// `membro` ou `fornecedor`.
  final String tipo;
  final String id;
  final String nome;

  bool get ehMembro => tipo == 'membro';

  /// Campos gravados no documento do lançamento.
  ///
  /// Escreve o par escolhido e **apaga o outro** — editar um lançamento de
  /// fornecedor para membro não pode deixar o fornecedor antigo colado.
  Map<String, dynamic> paraFirestore() => ehMembro
      ? {
          'membroId': id,
          'membroNome': nome,
          'memberId': id,
          'fornecedorId': null,
          'fornecedorNome': null,
        }
      : {
          'fornecedorId': id,
          'fornecedorNome': nome,
          'membroId': null,
          'membroNome': null,
          'memberId': null,
        };

  static Map<String, dynamic> limparNoFirestore() => {
        'membroId': null,
        'membroNome': null,
        'memberId': null,
        'fornecedorId': null,
        'fornecedorNome': null,
      };

  static FinanceVinculo? deFirestore(Map<String, dynamic>? d) {
    if (d == null) return null;
    String s(List<String> ks) {
      for (final k in ks) {
        final v = (d[k] ?? '').toString().trim();
        if (v.isNotEmpty && v != 'null') return v;
      }
      return '';
    }

    final fid = s(['fornecedorId']);
    if (fid.isNotEmpty) {
      return FinanceVinculo(
        tipo: 'fornecedor',
        id: fid,
        nome: s(['fornecedorNome', 'fornecedor']),
      );
    }
    final mid = s(['membroId', 'memberId']);
    if (mid.isNotEmpty) {
      return FinanceVinculo(
        tipo: 'membro',
        id: mid,
        nome: s(['membroNome', 'memberNome', 'donorName']),
      );
    }
    return null;
  }
}

/// Rótulo de quem é o lançamento, para as grelhas do Financeiro, do membro e
/// do fornecedor: nome do membro, do fornecedor, do doador do Pix/site, ou
/// «N pessoas» quando o lançamento foi marcado para várias.
///
/// `null` quando o lançamento não tem vínculo nenhum (despesa geral da igreja).
({String texto, bool ehFornecedor, bool multiplo})? financeVinculoGridLabel(
  Map<String, dynamic>? d,
) {
  if (d == null) return null;
  if (d['vinculoMultiplo'] == true) {
    final lista = d['vinculos'];
    final n = lista is List ? lista.length : 0;
    return (
      texto: n > 1 ? '$n pessoas' : 'Várias pessoas',
      ehFornecedor: false,
      multiplo: true,
    );
  }
  final v = FinanceVinculo.deFirestore(d);
  if (v != null && v.nome.trim().isNotEmpty) {
    final tipo = v.ehMembro ? 'Membro' : 'Fornecedor';
    return (
      texto: '$tipo · ${v.nome.trim()}',
      ehFornecedor: !v.ehMembro,
      multiplo: false,
    );
  }
  // Doação do Pix/site público sem membro ligado: fica o nome de quem doou.
  final doador = _campo(d, ['donorName', 'doadorNome', 'memberName']);
  if (doador.isNotEmpty) {
    return (texto: 'Doador · $doador', ehFornecedor: false, multiplo: false);
  }
  // Vínculo com id mas sem nome guardado (registo antigo).
  if (v != null) {
    return (
      texto: v.ehMembro ? 'Membro' : 'Fornecedor',
      ehFornecedor: !v.ehMembro,
      multiplo: false,
    );
  }
  return null;
}

/// Seleção de vínculo de um lançamento: **um** ou **vários**.
///
/// A distinção não é cosmética — muda o que o lançamento significa:
///
/// * **Um** membro ou fornecedor: o valor é atribuído a essa pessoa. Entra no
///   histórico individual dela e conta nos totais «quanto gastámos com este
///   fornecedor» / «quanto este membro contribuiu».
/// * **Vários**: não há como dividir o valor sem inventar um rateio, por isso
///   o lançamento fica **só no histórico geral**, com as pessoas registadas
///   para referência — e **não** entra no total individual de ninguém.
///
/// O utilizador é avisado disto na própria folha de escolha, assim que marca
/// o segundo nome.
class FinanceVinculoSelecao {
  const FinanceVinculoSelecao(this.itens);

  const FinanceVinculoSelecao.vazia() : itens = const [];

  final List<FinanceVinculo> itens;

  bool get vazio => itens.isEmpty;

  /// `true` quando o valor é atribuído a uma pessoa concreta.
  bool get individual => itens.length == 1;

  /// `true` quando entra apenas no histórico geral.
  bool get somenteHistorico => itens.length > 1;

  String get resumo {
    if (vazio) return 'Sem vínculo';
    if (individual) return itens.first.nome;
    return '${itens.length} pessoas — só no histórico';
  }

  /// Campos gravados no lançamento.
  ///
  /// Com vários, `membroId`/`fornecedorId` ficam a `null` **de propósito**:
  /// são esses campos que alimentam os totais por pessoa, e atribuir o valor
  /// inteiro a cada um contaria o mesmo dinheiro várias vezes.
  Map<String, dynamic> paraFirestore() {
    if (vazio) {
      return {
        ...FinanceVinculo.limparNoFirestore(),
        'vinculos': null,
        'vinculoMultiplo': false,
      };
    }
    if (individual) {
      return {
        ...itens.first.paraFirestore(),
        'vinculos': null,
        'vinculoMultiplo': false,
      };
    }
    return {
      ...FinanceVinculo.limparNoFirestore(),
      'vinculoMultiplo': true,
      'vinculos': [
        for (final v in itens)
          {'tipo': v.tipo, 'id': v.id, 'nome': v.nome},
      ],
    };
  }

  static FinanceVinculoSelecao deFirestore(Map<String, dynamic>? d) {
    if (d == null) return const FinanceVinculoSelecao.vazia();
    final lista = d['vinculos'];
    if (lista is List && lista.length > 1) {
      return FinanceVinculoSelecao([
        for (final e in lista)
          if (e is Map)
            FinanceVinculo(
              tipo: (e['tipo'] ?? '').toString(),
              id: (e['id'] ?? '').toString(),
              nome: (e['nome'] ?? '').toString(),
            ),
      ]);
    }
    final unico = FinanceVinculo.deFirestore(d);
    return unico == null
        ? const FinanceVinculoSelecao.vazia()
        : FinanceVinculoSelecao([unico]);
  }
}

String _campo(Map<String, dynamic> m, List<String> chaves) {
  for (final k in chaves) {
    final v = (m[k] ?? '').toString().trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  return '';
}

/// Abre o seletor de vínculo. Devolve `null` se fechar sem confirmar.
Future<FinanceVinculoSelecao?> escolherVinculoFinanceiro(
  BuildContext context, {
  required String tenantId,
  FinanceVinculoSelecao? atual,
}) {
  return showModalBottomSheet<FinanceVinculoSelecao>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, controller) => _VinculoSheet(
        tenantId: tenantId,
        atual: atual,
        scrollController: controller,
      ),
    ),
  );
}

class _VinculoSheet extends StatefulWidget {
  const _VinculoSheet({
    required this.tenantId,
    required this.atual,
    required this.scrollController,
  });

  final String tenantId;
  final FinanceVinculoSelecao? atual;
  final ScrollController scrollController;

  @override
  State<_VinculoSheet> createState() => _VinculoSheetState();
}

class _VinculoSheetState extends State<_VinculoSheet> {
  final _buscaCtrl = TextEditingController();
  late String _aba =
      (widget.atual?.itens.isNotEmpty ?? false) &&
          !widget.atual!.itens.first.ehMembro
      ? 'fornecedor'
      : 'membro';

  /// Escolhidos por id — guarda o objeto para nao depender da aba aberta.
  late final Map<String, FinanceVinculo> _escolhidos = {
    for (final v in widget.atual?.itens ?? const <FinanceVinculo>[]) v.id: v,
  };
  String _query = '';
  bool _carregando = true;
  List<Map<String, dynamic>> _membros = const [];
  List<Map<String, dynamic>> _fornecedores = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _lista(String sub) async {
    try {
      final snap = await ChurchFirestoreAccess.listOnce(
        module: 'finance_vinculo',
        churchId: widget.tenantId,
        subcollectionName: sub,
        limit: 500,
      ).timeout(const Duration(seconds: 15));
      return snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _carregar() async {
    // As duas listas em paralelo: em série, abrir o seletor custava duas idas
    // ao Firestore encadeadas antes de pintar seja o que for.
    final r = await Future.wait([_lista('membros'), _lista('fornecedores')]);
    if (!mounted) return;
    int porNome(Map<String, dynamic> a, Map<String, dynamic> b) => _nome(
      a,
    ).toLowerCase().compareTo(_nome(b).toLowerCase());
    setState(() {
      _membros = r[0]..sort(porNome);
      _fornecedores = r[1]..sort(porNome);
      _carregando = false;
    });
  }

  String _nome(Map<String, dynamic> m) {
    final n = _campo(m, [
      'NOME_COMPLETO',
      'nomeCompleto',
      'nome',
      'name',
      'razaoSocial',
      'fantasia',
    ]);
    return n.isEmpty ? 'Sem nome' : n;
  }

  String _detalhe(Map<String, dynamic> m) => _campo(m, [
    'CARGO',
    'cargo',
    'categoria',
    'tipo',
    'FUNCAO',
    'funcao',
    'cidade',
  ]);

  List<Map<String, dynamic>> get _resultado {
    final base = _aba == 'membro' ? _membros : _fornecedores;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base
        .where((m) => '${_nome(m)} ${_detalhe(m)}'.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final res = _resultado;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Vincular lançamento',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_escolhidos.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      const FinanceVinculoSelecao.vazia(),
                    ),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: const Text('Remover'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'membro',
                  label: Text('Membros (${_membros.length})'),
                  icon: const Icon(Icons.person_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 'fornecedor',
                  label: Text('Fornecedores (${_fornecedores.length})'),
                  icon: const Icon(Icons.local_shipping_rounded, size: 18),
                ),
              ],
              selected: {_aba},
              onSelectionChanged: (s) => setState(() => _aba = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              controller: _buscaCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: _aba == 'membro'
                    ? 'Buscar membro por nome ou cargo…'
                    : 'Buscar fornecedor por nome ou categoria…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!_carregando && res.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _alternarTodosDaPesquisa(res),
                    icon: Icon(
                      _todosMarcados(res)
                          ? Icons.remove_done_rounded
                          : Icons.done_all_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _todosMarcados(res)
                          ? 'Desmarcar os ${res.length}'
                          : 'Selecionar todos (${res.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_escolhidos.isNotEmpty)
                    Text(
                      '${_escolhidos.length} marcado(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                ],
              ),
            ),
          // Aviso: com mais de um nome o lançamento deixa de contar no total
          // individual. Aparece assim que marca o segundo — antes de gravar,
          // não depois.
          if (_escolhidos.length > 1)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_rounded,
                    color: Color(0xFFEA580C),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(
                            text: '${_escolhidos.length} pessoas marcadas: ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text:
                                'o lançamento fica apenas no histórico geral e '
                                'NÃO entra no total individual de cada uma — '
                                'dividir o valor exigiria um rateio que o '
                                'sistema não pode inventar. Deixe só um nome '
                                'marcado para atribuir o valor a essa pessoa.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : res.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty
                          ? 'Nada cadastrado ainda.'
                          : 'Nenhum resultado para «$_query».',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.separated(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: res.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final m = res[i];
                      final id = (m['id'] ?? '').toString();
                      final nome = _nome(m);
                      final det = _detalhe(m);
                      final escolhido = _escolhidos.containsKey(id);
                      return Material(
                        color: escolhido
                            ? ThemeCleanPremium.primary.withValues(alpha: 0.10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            if (_escolhidos.containsKey(id)) {
                              _escolhidos.remove(id);
                            } else {
                              _escolhidos[id] = FinanceVinculo(
                                tipo: _aba,
                                id: id,
                                nome: nome,
                              );
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                _Avatar(nome: nome, fotoRef: imageUrlFromMap(m)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nome,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      if (det.isNotEmpty)
                                        Text(
                                          det,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (escolhido)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF16A34A),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    FinanceVinculoSelecao(_escolhidos.values.toList()),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    _escolhidos.isEmpty
                        ? 'Sem vínculo'
                        : _escolhidos.length == 1
                        ? 'Vincular a ${_escolhidos.values.first.nome}'
                        : 'Confirmar ${_escolhidos.length} (só histórico)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _todosMarcados(List<Map<String, dynamic>> res) => res.isNotEmpty &&
      res.every((m) => _escolhidos.containsKey((m['id'] ?? '').toString()));

  /// Marca (ou desmarca) **o resultado da pesquisa atual** — não a lista toda.
  void _alternarTodosDaPesquisa(List<Map<String, dynamic>> res) {
    setState(() {
      if (_todosMarcados(res)) {
        for (final m in res) {
          _escolhidos.remove((m['id'] ?? '').toString());
        }
        return;
      }
      for (final m in res) {
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        _escolhidos[id] = FinanceVinculo(
          tipo: _aba,
          id: id,
          nome: _nome(m),
        );
      }
    });
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nome, required this.fotoRef});

  final String nome;
  final String fotoRef;

  @override
  Widget build(BuildContext context) {
    final iniciais = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final fallback = CircleAvatar(
      radius: 22,
      backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
      child: Text(
        iniciais.isEmpty ? '?' : iniciais,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: ThemeCleanPremium.primary,
        ),
      ),
    );
    if (fotoRef.trim().isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: SafeNetworkImage(
          imageUrl: fotoRef,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          memCacheWidth: 132,
          placeholder: fallback,
          errorWidget: fallback,
        ),
      ),
    );
  }
}
