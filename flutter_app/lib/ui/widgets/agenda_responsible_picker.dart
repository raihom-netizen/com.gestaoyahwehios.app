import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';

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

class _AgendaResponsiblePickerState extends State<AgendaResponsiblePicker> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _members = const [];
  Set<String> _selected = <String>{};
  String _query = '';
  String _department = 'Todos';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = <String>{...widget.selectedIds};
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      // Antes: `ChurchUiCollections.membros(...).get()` — leitura direta pelo
      // SDK. No Web cada `.get()` cria um alvo de Listen temporário e acaba na
      // INTERNAL ASSERTION, que envenena o cliente: era isto que fazia o picker
      // de responsáveis dizer «não foi possível carregar os membros».
      // O gateway lê por REST no Web e mantém o SDK no nativo.
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
            (a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()),
          );
      setState(() {
        _members = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('AgendaResponsiblePicker: falha ao carregar membros: $e');
      setState(() {
        _members = const [];
        _loading = false;
        _error = 'Não foi possível carregar os membros agora.';
      });
    }
  }

  String _name(Map<String, dynamic> member) =>
      (member['nome'] ??
              member['NOME_COMPLETO'] ??
              member['nomeCompleto'] ??
              member['displayName'] ??
              member['name'] ??
              'Membro')
          .toString()
          .trim();

  String _role(Map<String, dynamic> member) =>
      (member['cargo'] ??
              member['cargoNome'] ??
              member['role'] ??
              member['funcao'] ??
              '')
          .toString()
          .trim();

  String _dept(Map<String, dynamic> member) {
    final value =
        member['departamento'] ??
        member['departamentoNome'] ??
        member['departamentos'] ??
        member['department'] ??
        '';
    if (value is List) return value.map((e) => e.toString()).join(', ').trim();
    return value.toString().trim();
  }

  void _emit() {
    final names = _selected
        .map((id) {
          for (final member in _members) {
            if (member['id'].toString() == id) return _name(member);
          }
          return '';
        })
        .where((name) => name.isNotEmpty)
        .toList();
    widget.onChanged(<String>{..._selected}, names);
  }

  @override
  Widget build(BuildContext context) {
    final departments = <String>{
      'Todos',
      ..._members.map(_dept).where((value) => value.isNotEmpty),
    }.toList()..sort();
    final query = _query.toLowerCase().trim();
    final filtered = _members.where((member) {
      final text = '${_name(member)} ${_role(member)} ${_dept(member)}'
          .toLowerCase();
      return (query.isEmpty || text.contains(query)) &&
          (_department == 'Todos' || _dept(member) == _department);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_rounded),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Responsáveis',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text('${_selected.length} selecionado(s)'),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Buscar por nome, cargo ou departamento',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: departments.contains(_department)
              ? _department
              : 'Todos',
          decoration: const InputDecoration(
            labelText: 'Filtrar por departamento',
            prefixIcon: Icon(Icons.account_tree_rounded),
          ),
          items: departments
              .map(
                (department) => DropdownMenuItem(
                  value: department,
                  child: Text(department),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _department = value);
          },
        ),
        const SizedBox(height: 10),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Row(
            children: [
              Expanded(child: Text(_error!)),
              IconButton(
                tooltip: 'Tentar novamente',
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadMembers();
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        if (!_loading && _error == null)
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum membro encontrado.'),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final id = member['id'].toString();
                      final subtitle = [
                        _role(member),
                        _dept(member),
                      ].where((value) => value.isNotEmpty).join(' • ');
                      return CheckboxListTile(
                        dense: true,
                        value: _selected.contains(id),
                        title: Text(_name(member)),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        secondary: const Icon(Icons.person_outline_rounded),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                          _emit();
                        },
                      );
                    },
                  ),
          ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selected.map((id) {
              final member = _members.cast<Map<String, dynamic>?>().firstWhere(
                (item) => item?['id'].toString() == id,
                orElse: () => null,
              );
              return Chip(
                avatar: const Icon(Icons.person_rounded, size: 16),
                label: Text(member == null ? id : _name(member)),
                onDeleted: () {
                  setState(() => _selected.remove(id));
                  _emit();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
