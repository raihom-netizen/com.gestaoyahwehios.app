import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Seletor de responsáveis da agenda.
///
/// O formulário mostra só um campo de busca; a lista completa vive numa folha
/// dedicada, com foto, filtros por perfil e seleção múltipla.
class AgendaResponsiblePicker extends StatefulWidget {
  const AgendaResponsiblePicker({
    super.key,
    required this.tenantId,
    required this.selectedIds,
    required this.onChanged,
  });

  final String tenantId;
  final Set<String> selectedIds;
  final void Function(Set<String> ids, List<String> names) onChanged;

  @override
  State<AgendaResponsiblePicker> createState() =>
      _AgendaResponsiblePickerState();
}

// ─── Leitura dos campos da ficha ────────────────────────────────────────────
// A ficha canónica usa MAIÚSCULAS (`NOME_COMPLETO`, `SEXO`, `DATA_NASCIMENTO`).
// `nome`/`name` existem em pouco mais de metade dos documentos e podem estar
// vazios — consultá-los primeiro (como antes) devolvia string vazia e a busca
// por nome não achava ninguém.

String _first(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = (m[k] ?? '').toString().trim();
    if (v.isNotEmpty && v != 'null') return v;
  }
  return '';
}

String _memberName(Map<String, dynamic> member) {
  final n = _first(member, [
    'NOME_COMPLETO',
    'nomeCompleto',
    'nome',
    'name',
    'displayName',
  ]);
  return n.isEmpty ? 'Membro' : n;
}

String _memberRole(Map<String, dynamic> member) =>
    _first(member, ['CARGO', 'cargo', 'cargoNome', 'FUNCAO', 'funcao', 'role']);

String _memberDept(Map<String, dynamic> member) {
  final value =
      member['departamento'] ??
      member['departamentoNome'] ??
      member['DEPARTAMENTOS'] ??
      member['departamentos'] ??
      member['departamentosIds'] ??
      member['department'] ??
      '';
  if (value is List) {
    return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(', ');
  }
  return value.toString().trim();
}

/// `Masculino` / `Feminino` — normalizado para a 1.ª letra.
String _memberSexo(Map<String, dynamic> member) {
  final s = _first(member, ['SEXO', 'sexo', 'genero', 'gender']).toLowerCase();
  if (s.startsWith('m')) return 'M';
  if (s.startsWith('f')) return 'F';
  return '';
}

/// Idade a partir de `DATA_NASCIMENTO` (a coluna `IDADE` só existe em parte
/// das fichas, por isso não dá para confiar nela).
int? _memberIdade(Map<String, dynamic> member) {
  final raw = member['DATA_NASCIMENTO'] ?? member['dataNascimento'];
  DateTime? nasc;
  if (raw is Timestamp) {
    nasc = raw.toDate();
  } else if (raw is DateTime) {
    nasc = raw;
  } else if (raw is String && raw.trim().isNotEmpty) {
    nasc = DateTime.tryParse(raw.trim());
  }
  if (nasc != null) {
    final hoje = DateTime.now();
    var idade = hoje.year - nasc.year;
    if (hoje.month < nasc.month ||
        (hoje.month == nasc.month && hoje.day < nasc.day)) {
      idade--;
    }
    if (idade >= 0 && idade < 130) return idade;
  }
  final n = member['IDADE'] ?? member['idade'];
  if (n is num) return n.toInt();
  return int.tryParse((n ?? '').toString().trim());
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Cor estável por nome — o mesmo membro tem sempre o mesmo avatar.
List<Color> _avatarColors(String seed) {
  const palettes = <List<Color>>[
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF0EA5E9), Color(0xFF2563EB)],
    [Color(0xFF10B981), Color(0xFF059669)],
    [Color(0xFFF59E0B), Color(0xFFEA580C)],
    [Color(0xFFEC4899), Color(0xFFDB2777)],
    [Color(0xFF14B8A6), Color(0xFF0D9488)],
  ];
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palettes[h % palettes.length];
}

/// Foto do membro com recuo para as iniciais.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.name,
    required this.photoRef,
    this.size = 46,
  });

  final String name;
  final String photoRef;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = _avatarColors(name);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (photoRef.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        // SafeNetworkImage resolve tanto URL https como path do Storage
        // (`igrejas/{tenant}/membros/.../foto_perfil.jpg`).
        child: SafeNetworkImage(
          imageUrl: photoRef,
          fit: BoxFit.cover,
          width: size,
          height: size,
          memCacheWidth: 160,
          placeholder: fallback,
          errorWidget: fallback,
        ),
      ),
    );
  }
}

/// Filtros de perfil da folha.
enum _PerfilFiltro { todos, homens, mulheres, criancas, idosos }

extension _PerfilFiltroX on _PerfilFiltro {
  String get label => switch (this) {
    _PerfilFiltro.todos => 'Todos',
    _PerfilFiltro.homens => 'Homens',
    _PerfilFiltro.mulheres => 'Mulheres',
    _PerfilFiltro.criancas => 'Crianças',
    _PerfilFiltro.idosos => 'Idosos',
  };

  IconData get icon => switch (this) {
    _PerfilFiltro.todos => Icons.groups_rounded,
    _PerfilFiltro.homens => Icons.man_rounded,
    _PerfilFiltro.mulheres => Icons.woman_rounded,
    _PerfilFiltro.criancas => Icons.child_care_rounded,
    _PerfilFiltro.idosos => Icons.elderly_rounded,
  };

  Color get color => switch (this) {
    _PerfilFiltro.todos => const Color(0xFF2563EB),
    _PerfilFiltro.homens => const Color(0xFF0EA5E9),
    _PerfilFiltro.mulheres => const Color(0xFFEC4899),
    _PerfilFiltro.criancas => const Color(0xFFF59E0B),
    _PerfilFiltro.idosos => const Color(0xFF7C3AED),
  };

  /// Criança < 12 anos; idoso a partir de 60 (Estatuto do Idoso).
  bool matches(Map<String, dynamic> m) {
    switch (this) {
      case _PerfilFiltro.todos:
        return true;
      case _PerfilFiltro.homens:
        return _memberSexo(m) == 'M';
      case _PerfilFiltro.mulheres:
        return _memberSexo(m) == 'F';
      case _PerfilFiltro.criancas:
        final i = _memberIdade(m);
        return i != null && i < 12;
      case _PerfilFiltro.idosos:
        final i = _memberIdade(m);
        return i != null && i >= 60;
    }
  }
}

class _AgendaResponsiblePickerState extends State<AgendaResponsiblePicker> {
  List<Map<String, dynamic>> _members = const [];
  Set<String> _selected = <String>{};
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = <String>{...widget.selectedIds};
    // Pré-carrega em silêncio: quando o utilizador toca, a folha já abre cheia.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureMembers());
  }

  @override
  void didUpdateWidget(AgendaResponsiblePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _selected = <String>{...widget.selectedIds};
    }
  }

  Future<void> _ensureMembers() async {
    if (_loaded || _loading) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // Gateway: REST no Web (o `.get()` cru criava alvo de Listen temporário
      // e caía na INTERNAL ASSERTION, que envenenava o cliente) e SDK no nativo.
      final snap = await ChurchFirestoreAccess.listOnce(
        module: 'agenda_responsaveis',
        churchId: widget.tenantId,
        subcollectionName: 'membros',
        limit: 500,
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final rows =
          snap.docs.map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            return data;
          }).toList()..sort(
            (a, b) => _memberName(
              a,
            ).toLowerCase().compareTo(_memberName(b).toLowerCase()),
          );
      setState(() {
        _members = rows;
        _loaded = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('AgendaResponsiblePicker: falha ao carregar membros: $e');
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os membros agora.';
      });
    }
  }

  void _emit() {
    final names = _selected
        .map((id) {
          for (final member in _members) {
            if (member['id'].toString() == id) return _memberName(member);
          }
          return '';
        })
        .where((name) => name.isNotEmpty)
        .toList();
    widget.onChanged(<String>{..._selected}, names);
  }

  Map<String, dynamic>? _memberById(String id) {
    for (final m in _members) {
      if (m['id'].toString() == id) return m;
    }
    return null;
  }

  Future<void> _openSearch() async {
    if (!_loaded) {
      _loaded = false;
      await _ensureMembers();
    }
    if (!mounted) return;
    if (_members.isEmpty && _error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_error!)));
      return;
    }
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResponsibleSearchSheet(
        members: _members,
        initialSelected: <String>{..._selected},
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selected = result);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selected.isEmpty
                          ? (_loading
                                ? 'Carregando membros…'
                                : 'Buscar e escolher responsáveis')
                          : '${_selected.length} responsável(is) selecionado(s)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _selected.isEmpty
                            ? theme.hintColor
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                      color: theme.hintColor,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selected.map((id) {
              final member = _memberById(id);
              final name = member == null ? id : _memberName(member);
              final photo = member == null ? '' : imageUrlFromMap(member);
              return Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MemberAvatar(name: name, photoRef: photo, size: 26),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setState(() => _selected.remove(id));
                        _emit();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

/// Folha de escolha — todos os membros à vista, com filtros de perfil.
/// Escolha de **vários** membros na mesma tela dos «Responsáveis».
///
/// É o caso da folha: marcar dez membros e lançar a despesa de cada um sem
/// repetir o formulário dez vezes. Dentro da folha há «Selecionar todos», que
/// marca **o resultado da pesquisa atual** — filtrar por «Músicos» e marcar
/// todos de uma vez, por exemplo.
///
/// Devolve lista vazia se o utilizador fechar sem escolher.
Future<List<MembroEscolhido>> escolherMembrosNaGrelha(
  BuildContext context, {
  required String tenantId,
  Set<String> selecionadosIds = const {},
}) async {
  final membros = await _carregarMembrosParaGrelha(tenantId);
  if (!context.mounted || membros.isEmpty) return const [];

  final ids = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ResponsibleSearchSheet(
      members: membros,
      initialSelected: <String>{...selecionadosIds},
    ),
  );
  if (ids == null || ids.isEmpty) return const [];
  final porId = {for (final m in membros) (m['id'] ?? '').toString(): m};
  return [
    for (final id in ids)
      if (porId[id] != null) (id: id, nome: _memberName(porId[id]!)),
  ];
}

/// Leitura única dos membros para as grelhas de escolha.
Future<List<Map<String, dynamic>>> _carregarMembrosParaGrelha(
  String tenantId,
) async {
  try {
    final snap = await ChurchFirestoreAccess.listOnce(
      module: 'membro_picker',
      churchId: tenantId,
      subcollectionName: 'membros',
      limit: 500,
    ).timeout(const Duration(seconds: 15));
    return snap.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).toList()
      ..sort(
        (a, b) =>
            _memberName(a).toLowerCase().compareTo(_memberName(b).toLowerCase()),
      );
  } catch (e) {
    debugPrint('_carregarMembrosParaGrelha: $e');
    return const [];
  }
}

/// Membro escolhido na grelha.
typedef MembroEscolhido = ({String id, String nome});

/// Escolha de **um** membro na mesma tela dos «Responsáveis»: grelha com foto,
/// nome completo, cargo/idade e os filtros Todos / Homens / Mulheres /
/// Crianças / Idosos.
///
/// Existe para o certificado de casamento (noivo e noiva) não ter um seletor
/// próprio, pior, só com texto. Devolve `null` se o utilizador fechar sem
/// escolher — nesse caso quem chamou mantém o nome escrito à mão.
Future<MembroEscolhido?> escolherMembroNaGrelha(
  BuildContext context, {
  required String tenantId,
  String? selecionadoId,
}) async {
  final membros = await _carregarMembrosParaGrelha(tenantId);
  if (!context.mounted || membros.isEmpty) return null;

  final ids = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ResponsibleSearchSheet(
      members: membros,
      initialSelected: <String>{
        if ((selecionadoId ?? '').trim().isNotEmpty) selecionadoId!.trim(),
      },
      escolhaUnica: true,
    ),
  );
  final id = (ids == null || ids.isEmpty) ? '' : ids.first;
  if (id.isEmpty) return null;
  for (final m in membros) {
    if ((m['id'] ?? '').toString() == id) {
      return (id: id, nome: _memberName(m));
    }
  }
  return null;
}

class _ResponsibleSearchSheet extends StatefulWidget {
  const _ResponsibleSearchSheet({
    required this.members,
    required this.initialSelected,
    this.escolhaUnica = false,
  });

  final List<Map<String, dynamic>> members;
  final Set<String> initialSelected;

  /// `true` no certificado de casamento: tocar num membro escolhe e fecha.
  final bool escolhaUnica;

  @override
  State<_ResponsibleSearchSheet> createState() =>
      _ResponsibleSearchSheetState();
}

class _ResponsibleSearchSheetState extends State<_ResponsibleSearchSheet> {
  final _controller = TextEditingController();
  late final Set<String> _selected = <String>{...widget.initialSelected};
  String _query = '';
  _PerfilFiltro _filtro = _PerfilFiltro.todos;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _results {
    final q = _query.toLowerCase().trim();
    return widget.members.where((m) {
      if (!_filtro.matches(m)) return false;
      if (q.isEmpty) return true;
      final text = '${_memberName(m)} ${_memberRole(m)} ${_memberDept(m)}'
          .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  int _countFor(_PerfilFiltro f) =>
      widget.members.where(f.matches).length;

  /// Marca (ou desmarca) **tudo o que a pesquisa atual mostra**.
  ///
  /// Com filtro «Músicos» ou uma busca por nome, marca só esses — não a
  /// igreja inteira. É o que serve para lançar folha por departamento.
  void _alternarTodosDaPesquisa() {
    final visiveis = _results
        .map((m) => (m['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (visiveis.isEmpty) return;
    final todosMarcados = visiveis.every(_selected.contains);
    setState(() {
      if (todosMarcados) {
        _selected.removeAll(visiveis);
      } else {
        _selected.addAll(visiveis);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // Cabeçalho com VOLTAR à esquerda e Concluir à direita.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Responsáveis',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      _selected.isEmpty
                          ? 'Concluir'
                          : 'Concluir (${_selected.length})',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Nome, cargo ou departamento',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            // Filtros de perfil, com a contagem de cada um.
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _PerfilFiltro.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _PerfilFiltro.values[i];
                  final on = f == _filtro;
                  final n = _countFor(f);
                  return GestureDetector(
                    onTap: () => setState(() => _filtro = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: on
                            ? f.color
                            : f.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            f.icon,
                            size: 16,
                            color: on ? Colors.white : f.color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${f.label} ($n)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: on ? Colors.white : f.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // «Selecionar todos» age sobre o RESULTADO DA PESQUISA, nao sobre a
            // igreja toda — filtrar e marcar em bloco e o que serve para folha.
            if (!widget.escolhaUnica && results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _alternarTodosDaPesquisa,
                      icon: Icon(
                        results
                                .map((m) => (m['id'] ?? '').toString())
                                .every(_selected.contains)
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        size: 18,
                      ),
                      label: Text(
                        results
                                .map((m) => (m['id'] ?? '').toString())
                                .every(_selected.contains)
                            ? 'Desmarcar os ${results.length}'
                            : 'Selecionar todos (${results.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      Text(
                        '${_selected.length} marcado(s)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? _EmptyState(
                      searching: _query.trim().isNotEmpty ||
                          _filtro != _PerfilFiltro.todos,
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final m = results[i];
                        final id = m['id'].toString();
                        final name = _memberName(m);
                        final idade = _memberIdade(m);
                        final subtitle = [
                          _memberRole(m),
                          if (idade != null) '$idade anos',
                        ].where((v) => v.isNotEmpty).join(' • ');
                        final picked = _selected.contains(id);
                        return Material(
                          color: picked
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.35,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              // Escolha unica (certificado de casamento):
                              // tocar escolhe e fecha, sem passar pelo
                              // "Concluir".
                              if (widget.escolhaUnica) {
                                Navigator.pop(context, <String>{id});
                                return;
                              }
                              setState(() {
                                if (picked) {
                                  _selected.remove(id);
                                } else {
                                  _selected.add(id);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  _MemberAvatar(
                                    name: name,
                                    photoRef: imageUrlFromMap(m),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty)
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme.hintColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: picked
                                          ? theme.colorScheme.primary
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: picked
                                            ? theme.colorScheme.primary
                                            : theme.dividerColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: picked
                                        ? const Icon(
                                            Icons.check_rounded,
                                            size: 17,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.groups_rounded,
              size: 46,
              color: theme.hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'Nenhum membro para este filtro.'
                  : 'Nenhum membro cadastrado.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
