import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';

/// Seletor de responsáveis da agenda.
///
/// A lista de membros **não** fica exposta no formulário: o campo abre uma
/// folha de busca e os resultados só aparecem depois de escrever. Antes o
/// formulário despejava uma lista rolável com a igreja inteira, o que enchia
/// o ecrã e obrigava a rolar por dezenas de nomes para achar um.
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

String _memberName(Map<String, dynamic> member) =>
    (member['nome'] ??
            member['NOME_COMPLETO'] ??
            member['nomeCompleto'] ??
            member['displayName'] ??
            member['name'] ??
            'Membro')
        .toString()
        .trim();

String _memberRole(Map<String, dynamic> member) =>
    (member['cargo'] ??
            member['cargoNome'] ??
            member['role'] ??
            member['funcao'] ??
            '')
        .toString()
        .trim();

String _memberDept(Map<String, dynamic> member) {
  final value =
      member['departamento'] ??
      member['departamentoNome'] ??
      member['departamentos'] ??
      member['department'] ??
      '';
  if (value is List) return value.map((e) => e.toString()).join(', ').trim();
  return value.toString().trim();
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
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

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = _avatarColors(name);
    return Container(
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
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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
  }

  @override
  void didUpdateWidget(AgendaResponsiblePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _selected = <String>{...widget.selectedIds};
    }
  }

  /// Carrega só quando o utilizador abre a busca — o formulário da agenda
  /// deixa de esperar por 500 membros para conseguir pintar.
  Future<void> _ensureMembers() async {
    if (_loaded || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Gateway: REST no Web (o `.get()` cru criava alvo de Listen temporário
      // e caía na INTERNAL ASSERTION, que envenenava o cliente) e SDK no nativo.
      final snap = await ChurchFirestoreAccess.listOnce(
        module: 'agenda_responsaveis',
        churchId: widget.tenantId,
        subcollectionName: 'membros',
        limit: 500,
      );
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
    await _ensureMembers();
    if (!mounted) return;
    if (_error != null) {
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
        // Campo que parece uma busca, mas abre a folha — nada de lista aqui.
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _loading ? null : _openSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
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
                          ? 'Buscar membro pelo nome…'
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
                    _MemberAvatar(name: name, size: 26),
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

/// Folha de busca — resultados só depois de escrever.
class _ResponsibleSearchSheet extends StatefulWidget {
  const _ResponsibleSearchSheet({
    required this.members,
    required this.initialSelected,
  });

  final List<Map<String, dynamic>> members;
  final Set<String> initialSelected;

  @override
  State<_ResponsibleSearchSheet> createState() =>
      _ResponsibleSearchSheetState();
}

class _ResponsibleSearchSheetState extends State<_ResponsibleSearchSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final Set<String> _selected = <String>{...widget.initialSelected};
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _results {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) {
      // Sem busca mostra só quem já está escolhido — nunca a igreja inteira.
      return widget.members
          .where((m) => _selected.contains(m['id'].toString()))
          .toList();
    }
    return widget.members.where((m) {
      final text = '${_memberName(m)} ${_memberRole(m)} ${_memberDept(m)}'
          .toLowerCase();
      return text.contains(q);
    }).take(40).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    final searching = _query.trim().isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Responsáveis',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Concluir'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
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
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selected.length} selecionado(s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: results.isEmpty
                  ? _EmptyState(searching: searching)
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final m = results[i];
                        final id = m['id'].toString();
                        final name = _memberName(m);
                        final subtitle = [
                          _memberRole(m),
                          _memberDept(m),
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
                            onTap: () => setState(() {
                              if (picked) {
                                _selected.remove(id);
                              } else {
                                _selected.add(id);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  _MemberAvatar(name: name),
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
              searching
                  ? Icons.search_off_rounded
                  : Icons.person_search_rounded,
              size: 46,
              color: theme.hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'Nenhum membro encontrado.'
                  : 'Escreva o nome do membro para buscar.',
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
