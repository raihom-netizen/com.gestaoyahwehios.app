import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Transferência de membros entre igrejas (painel master).
///
/// Escolhe origem e destino, lista os membros da origem, permite marcar **um,
/// vários ou todos** e transfere um a um pela callable `masterTransferMembers`
/// (Admin SDK — move `membros`, o vínculo de login e refresca o cache das duas
/// igrejas).
class MasterMemberTransferCard extends StatefulWidget {
  const MasterMemberTransferCard({super.key});

  @override
  State<MasterMemberTransferCard> createState() =>
      _MasterMemberTransferCardState();
}

class _MemberRow {
  const _MemberRow({
    required this.id,
    required this.nome,
    required this.email,
    required this.status,
    required this.codigo,
  });

  final String id;
  final String nome;
  final String email;
  final String status;
  final String codigo;

  String get titulo => nome.isNotEmpty ? nome : (email.isNotEmpty ? email : id);
}

class _MasterMemberTransferCardState extends State<MasterMemberTransferCard> {
  static const Color _cIndigo = Color(0xFF4F46E5);
  static const Color _cGreen = Color(0xFF16A34A);
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cRed = Color(0xFFDC2626);
  static const Color _cSlate = Color(0xFF64748B);

  List<MasterChurchListItem> _igrejas = const [];
  String _origem = '';
  String _destino = '';

  List<_MemberRow> _membros = const [];
  final Set<String> _selecionados = <String>{};
  String _busca = '';

  bool _carregandoIgrejas = true;
  bool _carregandoMembros = false;
  bool _transferindo = false;
  int _progresso = 0;
  String? _erro;
  String? _resultado;

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(
    app: firebaseDefaultApp,
    region: 'us-central1',
  );

  @override
  void initState() {
    super.initState();
    unawaited(_carregarIgrejas());
  }

  Future<void> _carregarIgrejas() async {
    try {
      final lista = await MasterChurchesListService.loadFast();
      if (!mounted) return;
      setState(() {
        _igrejas = lista;
        _carregandoIgrejas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregandoIgrejas = false;
        _erro = 'Não foi possível carregar a lista de igrejas.';
      });
    }
  }

  String _nome(String id) {
    for (final i in _igrejas) {
      if (i.id == id) return '${i.data['nome'] ?? i.data['name'] ?? id}';
    }
    return id;
  }

  Future<void> _carregarMembros() async {
    if (_origem.isEmpty) return;
    setState(() {
      _carregandoMembros = true;
      _erro = null;
      _resultado = null;
      _membros = const [];
      _selecionados.clear();
    });
    try {
      final res = await _fn
          .httpsCallable('masterListChurchMembers')
          .call<Map<String, dynamic>>({'tenantId': _origem, 'limit': 500})
          .timeout(const Duration(seconds: 60));
      final raw = res.data['members'];
      final lista = <_MemberRow>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          lista.add(
            _MemberRow(
              id: '${m['id'] ?? ''}',
              nome: '${m['nome'] ?? ''}',
              email: '${m['email'] ?? ''}',
              status: '${m['status'] ?? ''}',
              codigo: '${m['codigo'] ?? ''}',
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _membros = lista;
        _carregandoMembros = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoMembros = false;
        _erro = _mensagem(e);
      });
    }
  }

  String _mensagem(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message ?? 'Falha na operação.';
    }
    return 'Falha na operação. Tente novamente.';
  }

  List<_MemberRow> get _filtrados {
    final b = _busca.trim().toLowerCase();
    if (b.isEmpty) return _membros;
    return _membros
        .where(
          (m) =>
              m.nome.toLowerCase().contains(b) ||
              m.email.toLowerCase().contains(b) ||
              m.codigo.toLowerCase().contains(b),
        )
        .toList();
  }

  Future<void> _transferir() async {
    if (_origem.isEmpty || _destino.isEmpty || _selecionados.isEmpty) return;
    final ids = _selecionados.toList();
    final ok = await _confirmar(ids.length);
    if (!ok || !mounted) return;

    setState(() {
      _transferindo = true;
      _progresso = 0;
      _erro = null;
      _resultado = null;
    });

    var movidos = 0;
    final falhas = <String>[];

    // Um a um: o utilizador vê o progresso e uma falha isolada não aborta o
    // lote inteiro.
    for (final id in ids) {
      try {
        final res = await _fn
            .httpsCallable('masterTransferMembers')
            .call<Map<String, dynamic>>({
              'fromTenantId': _origem,
              'toTenantId': _destino,
              'memberIds': [id],
            })
            .timeout(const Duration(seconds: 120));
        final n = res.data['moved'];
        if (n is num && n > 0) {
          movidos++;
        } else {
          final f = res.data['failed'];
          final motivo = f is List && f.isNotEmpty && f.first is Map
              ? '${(f.first as Map)['reason'] ?? 'não transferido'}'
              : 'não transferido';
          falhas.add('$id: $motivo');
        }
      } catch (e) {
        falhas.add('$id: ${_mensagem(e)}');
      }
      if (!mounted) return;
      setState(() => _progresso++);
    }

    if (!mounted) return;
    setState(() {
      _transferindo = false;
      _resultado = falhas.isEmpty
          ? '$movidos membro(s) transferido(s) para ${_nome(_destino)}.'
          : '$movidos transferido(s), ${falhas.length} com erro:\n'
                '${falhas.take(5).join('\n')}';
      _selecionados.clear();
    });
    await _carregarMembros();
  }

  Future<bool> _confirmar(int quantidade) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_cIndigo, Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ThemeCleanPremium.radiusLg),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Transferir membros',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                children: [
                  Text(
                    '$quantidade membro(s) vão sair de',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, color: _cSlate),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _nome(_origem),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      color: _cIndigo,
                      size: 22,
                    ),
                  ),
                  Text(
                    _nome(_destino),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _cGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'O cadastro, a foto e o login do membro passam para a '
                    'igreja de destino. A conta de acesso continua a mesma.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: _cSlate),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Voltar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _cIndigo),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Transferir'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return MasterPremiumCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cabecalho(),
            const SizedBox(height: 16),
            if (_carregandoIgrejas)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _seletores(),
              const SizedBox(height: 14),
              if (_origem.isNotEmpty) _listaMembros(),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 12),
              _banner(_erro!, _cRed, Icons.error_outline_rounded),
            ],
            if (_resultado != null) ...[
              const SizedBox(height: 12),
              _banner(_resultado!, _cGreen, Icons.check_circle_rounded),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_cIndigo, Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.swap_horiz_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transferir membros entre igrejas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'Escolha a origem e o destino, marque um, vários ou todos.',
                style: TextStyle(fontSize: 12.5, color: _cSlate, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seletores() {
    return LayoutBuilder(
      builder: (context, c) {
        final largo = c.maxWidth >= 620;
        final origem = _dropdown(
          rotulo: 'Igreja de origem',
          valor: _origem,
          cor: _cAmber,
          icone: Icons.logout_rounded,
          onChanged: (v) {
            setState(() {
              _origem = v ?? '';
              _membros = const [];
              _selecionados.clear();
              _resultado = null;
            });
            unawaited(_carregarMembros());
          },
        );
        final destino = _dropdown(
          rotulo: 'Igreja de destino',
          valor: _destino,
          cor: _cGreen,
          icone: Icons.login_rounded,
          excluir: _origem,
          onChanged: (v) => setState(() => _destino = v ?? ''),
        );
        if (!largo) {
          return Column(
            children: [origem, const SizedBox(height: 12), destino],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: origem),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Padding(
                padding: EdgeInsets.only(top: 26),
                child: Icon(Icons.arrow_forward_rounded, color: _cIndigo),
              ),
            ),
            Expanded(child: destino),
          ],
        );
      },
    );
  }

  Widget _dropdown({
    required String rotulo,
    required String valor,
    required Color cor,
    required IconData icone,
    required ValueChanged<String?> onChanged,
    String excluir = '',
  }) {
    final itens = _igrejas.where((i) => i.id != excluir).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icone, size: 15, color: cor),
            const SizedBox(width: 5),
            Text(
              rotulo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: cor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(color: cor.withValues(alpha: 0.30)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: valor.isEmpty ? null : valor,
              hint: const Text('Selecionar igreja'),
              items: itens
                  .map(
                    (i) => DropdownMenuItem(
                      value: i.id,
                      child: Text(
                        '${i.data['nome'] ?? i.data['name'] ?? i.id}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _listaMembros() {
    if (_carregandoMembros) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_membros.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Icon(
              Icons.group_off_rounded,
              size: 40,
              color: _cSlate.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nenhum membro nesta igreja.',
              style: TextStyle(color: _cSlate, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final itens = _filtrados;
    final todosMarcados =
        itens.isNotEmpty && itens.every((m) => _selecionados.contains(m.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: 'Buscar membro por nome, e-mail ou código',
            isDense: true,
            filled: true,
            fillColor: ThemeCleanPremium.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => _busca = v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                if (todosMarcados) {
                  for (final m in itens) {
                    _selecionados.remove(m.id);
                  }
                } else {
                  for (final m in itens) {
                    _selecionados.add(m.id);
                  }
                }
              }),
              icon: Icon(
                todosMarcados
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
              ),
              label: Text(
                todosMarcados ? 'Desmarcar todos' : 'Selecionar todos',
              ),
            ),
            const Spacer(),
            Text(
              '${_selecionados.length} de ${itens.length}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: _cIndigo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: itens.length,
              itemBuilder: (_, i) {
                final m = itens[i];
                final marcado = _selecionados.contains(m.id);
                return CheckboxListTile(
                  dense: true,
                  value: marcado,
                  activeColor: _cIndigo,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _transferindo
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _selecionados.add(m.id);
                          } else {
                            _selecionados.remove(m.id);
                          }
                        }),
                  title: Text(
                    m.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (m.codigo.isNotEmpty) '#${m.codigo}',
                      if (m.email.isNotEmpty) m.email,
                      if (m.status.isNotEmpty) m.status,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _cSlate),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_transferindo) ...[
          LinearProgressIndicator(
            value: _selecionados.isEmpty
                ? null
                : _progresso / _selecionados.length,
          ),
          const SizedBox(height: 8),
          Text(
            'Transferindo $_progresso de ${_selecionados.length}…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: _cSlate),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: _cIndigo,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed:
              _transferindo || _selecionados.isEmpty || _destino.isEmpty
              ? null
              : () => unawaited(_transferir()),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(
            _destino.isEmpty
                ? 'Escolha a igreja de destino'
                : _selecionados.isEmpty
                ? 'Selecione os membros'
                : 'Transferir ${_selecionados.length} membro(s)',
          ),
        ),
      ],
    );
  }

  Widget _banner(String texto, Color cor, IconData icone) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: cor.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}
