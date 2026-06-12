import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';

/// Membro normalizado para pickers de Cartas e transferências.
class ChurchLetterMemberEntry {
  const ChurchLetterMemberEntry({
    required this.id,
    required this.name,
    required this.cpfDigits,
    required this.data,
    required this.active,
  });

  final String id;
  final String name;
  final String cpfDigits;
  final Map<String, dynamic> data;
  final bool active;

  String get cargoLabel => signatoryCargoDisplayLabel(data);

  bool get canSignDocuments => memberCanSignChurchDocuments(data);

  static String nameFromData(Map<String, dynamic> m) {
    for (final k in ['NOME_COMPLETO', 'nome', 'name', 'displayName', 'NOME']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String cpfDigitsFromData(Map<String, dynamic> m) {
    return (m['CPF'] ?? m['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
  }
}

/// Grelha colorida dos membros escolhidos para a carta.
class ChurchLetterSelectedMembersGrid extends StatelessWidget {
  const ChurchLetterSelectedMembersGrid({
    super.key,
    required this.tenantId,
    required this.entries,
    required this.onRemove,
  });

  final String tenantId;
  final List<ChurchLetterMemberEntry> entries;
  final ValueChanged<String> onRemove;

  static const _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
  ];

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 520 ? 3 : (w >= 340 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 1 ? 3.2 : 2.35,
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            final accent = _palette[i % _palette.length];
            final name =
                e.name.isNotEmpty ? e.name : '(sem nome)';
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onRemove(e.id),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.14),
                        accent.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Row(
                    children: [
                      FotoMembroWidget(
                        tenantId: tenantId,
                        memberId: e.id,
                        memberData: e.data,
                        cpfDigits:
                            e.cpfDigits.length == 11 ? e.cpfDigits : null,
                        size: 44,
                        memCacheWidth: 120,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                height: 1.2,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            if (e.cpfDigits.length == 11)
                              Text(
                                'CPF ${e.cpfDigits}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent.withValues(alpha: 0.9),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onRemove(e.id),
                        icon: Icon(Icons.close_rounded, color: accent),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

bool churchLetterMemberMatchesDepartment(
  Map<String, dynamic> data,
  String deptDocId,
  List<({String id, String name})> deptList,
) {
  if (deptDocId == 'todos') return true;
  String? deptName;
  for (final e in deptList) {
    if (e.id == deptDocId) {
      deptName = e.name;
      break;
    }
  }
  final depts = data['DEPARTAMENTOS'] ?? data['departamentos'];
  if (depts is List && depts.any((x) => x.toString() == deptDocId)) {
    return true;
  }
  final deptIds = data['departamentosIds'];
  if (deptIds is List && deptIds.any((x) => x.toString() == deptDocId)) {
    return true;
  }
  final d =
      (data['departamento'] ?? data['DEPARTAMENTO'] ?? '').toString().trim();
  if (d == deptDocId) return true;
  if (deptName != null && d == deptName) return true;
  return false;
}

/// Escolha única — só liderança (pastor, gestor, secretário, tesoureiro, líder dept., admin).
Future<String?> showChurchLetterSignerPicker(
  BuildContext context, {
  required String title,
  required String tenantId,
  required List<ChurchLetterMemberEntry> signers,
  String? selectedId,
  String? excludeId,
}) async {
  final pool = signers
      .where((e) => e.active && e.canSignDocuments)
      .where((e) => excludeId == null || e.id != excludeId)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  if (pool.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nenhum assinante elegível. Cadastre pastor, gestor, secretário, tesoureiro ou líder de departamento em Membros.',
        ),
      ),
    );
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchLetterSignerPickerSheet(
      title: title,
      tenantId: tenantId,
      signers: pool,
      selectedId: selectedId,
    ),
  );
}

class _ChurchLetterSignerPickerSheet extends StatefulWidget {
  const _ChurchLetterSignerPickerSheet({
    required this.title,
    required this.tenantId,
    required this.signers,
    this.selectedId,
  });

  final String title;
  final String tenantId;
  final List<ChurchLetterMemberEntry> signers;
  final String? selectedId;

  @override
  State<_ChurchLetterSignerPickerSheet> createState() =>
      _ChurchLetterSignerPickerSheetState();
}

class _ChurchLetterSignerPickerSheetState
    extends State<_ChurchLetterSignerPickerSheet> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _q = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChurchLetterMemberEntry> get _filtered {
    if (_q.isEmpty) return widget.signers;
    return widget.signers.where((e) {
      final n = e.name.toLowerCase();
      final c = e.cpfDigits;
      final qDigits = _q.replaceAll(RegExp(r'\D'), '');
      if (n.contains(_q)) return true;
      if (qDigits.length >= 3 && c.contains(qDigits)) return true;
      return e.cargoLabel.toLowerCase().contains(_q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height * 0.82;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: h.clamp(340.0, 900.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Pastor, gestor, secretário, tesoureiro, administrador ou líder de departamento.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome, CPF ou cargo…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${_filtered.length} assinante(s) elegível(is)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
                const Divider(height: 16),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum assinante com este filtro.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final e = _filtered[i];
                            final sel = e.id == widget.selectedId;
                            return Material(
                              color: sel
                                  ? ThemeCleanPremium.primary
                                      .withValues(alpha: 0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(context, e.id),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: sel
                                          ? ThemeCleanPremium.primary
                                              .withValues(alpha: 0.35)
                                          : Colors.grey.shade200,
                                    ),
                                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                                  ),
                                  child: Row(
                                    children: [
                                      FotoMembroWidget(
                                        tenantId: widget.tenantId,
                                        memberId: e.id,
                                        memberData: e.data,
                                        cpfDigits: e.cpfDigits.length == 11
                                            ? e.cpfDigits
                                            : null,
                                        size: 44,
                                        memCacheWidth: 120,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.name.isEmpty
                                                  ? '(sem nome)'
                                                  : e.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              e.cargoLabel,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: ThemeCleanPremium.primary,
                                              ),
                                            ),
                                            if (e.cpfDigits.length == 11)
                                              Text(
                                                'CPF: ${e.cpfDigits}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (sel)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: ThemeCleanPremium.primary,
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
        ),
      ),
    );
  }
}

/// Seleção múltipla — todos os membros ativos, filtro geral ou por departamento.
Future<Set<String>?> showChurchLetterRecipientsPicker(
  BuildContext context, {
  required String tenantId,
  required List<ChurchLetterMemberEntry> members,
  required Set<String> initialSelected,
  List<({String id, String name})> departments = const [],
}) async {
  final active = members.where((e) => e.active).toList();
  if (active.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nenhum membro ativo no cadastro.'),
      ),
    );
    return null;
  }

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchLetterRecipientsPickerSheet(
      tenantId: tenantId,
      members: active,
      initialSelected: initialSelected,
      departments: departments,
    ),
  );
}

class _ChurchLetterRecipientsPickerSheet extends StatefulWidget {
  const _ChurchLetterRecipientsPickerSheet({
    required this.tenantId,
    required this.members,
    required this.initialSelected,
    required this.departments,
  });

  final String tenantId;
  final List<ChurchLetterMemberEntry> members;
  final Set<String> initialSelected;
  final List<({String id, String name})> departments;

  @override
  State<_ChurchLetterRecipientsPickerSheet> createState() =>
      _ChurchLetterRecipientsPickerSheetState();
}

class _ChurchLetterRecipientsPickerSheetState
    extends State<_ChurchLetterRecipientsPickerSheet> {
  late Set<String> _sel;
  final _search = TextEditingController();
  String _q = '';
  String _deptFilter = 'todos';

  @override
  void initState() {
    super.initState();
    _sel = Set<String>.from(widget.initialSelected);
    _search.addListener(() {
      setState(() => _q = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChurchLetterMemberEntry> get _filtered {
    return widget.members.where((e) {
      if (!churchLetterMemberMatchesDepartment(
        e.data,
        _deptFilter,
        widget.departments,
      )) {
        return false;
      }
      if (_q.isEmpty) return true;
      final n = e.name.toLowerCase();
      final qDigits = _q.replaceAll(RegExp(r'\D'), '');
      if (n.contains(_q)) return true;
      if (qDigits.length >= 3 && e.cpfDigits.contains(qDigits)) return true;
      return e.id.toLowerCase().contains(_q);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: h.clamp(380.0, 920.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Expanded(
                        child: Text(
                          'Membros da carta',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, Set<String>.from(_sel)),
                        child: Text('Confirmar (${_sel.length})'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Buscar nome ou CPF…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('Geral'),
                          selected: _deptFilter == 'todos',
                          onSelected: (_) =>
                              setState(() => _deptFilter = 'todos'),
                          selectedColor:
                              ThemeCleanPremium.primary.withValues(alpha: 0.14),
                        ),
                      ),
                      ...widget.departments.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(d.name),
                            selected: _deptFilter == d.id,
                            onSelected: (_) =>
                                setState(() => _deptFilter = d.id),
                            selectedColor: ThemeCleanPremium.primary
                                .withValues(alpha: 0.14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '${_sel.length} selecionado(s) · ${_filtered.length} visível(is)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: ThemeCleanPremium.primary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(_sel.clear),
                        child: const Text('Limpar'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _sel
                            ..clear()
                            ..addAll(_filtered.map((e) => e.id));
                        }),
                        child: const Text('Filtrados'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum membro com este filtro.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 4),
                          itemBuilder: (context, i) {
                            final e = _filtered[i];
                            final sel = _sel.contains(e.id);
                            return Material(
                              color: sel
                                  ? ThemeCleanPremium.primary
                                      .withValues(alpha: 0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: CheckboxListTile(
                                value: sel,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _sel.add(e.id);
                                    } else {
                                      _sel.remove(e.id);
                                    }
                                  });
                                },
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                secondary: FotoMembroWidget(
                                  tenantId: widget.tenantId,
                                  memberId: e.id,
                                  memberData: e.data,
                                  cpfDigits: e.cpfDigits.length == 11
                                      ? e.cpfDigits
                                      : null,
                                  size: 42,
                                  memCacheWidth: 120,
                                ),
                                title: Text(
                                  e.name.isEmpty ? '(sem nome)' : e.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: e.cpfDigits.length == 11
                                    ? Text(
                                        'CPF: ${e.cpfDigits}',
                                        style: const TextStyle(fontSize: 12),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão compacto para escolher assinante na tela principal.
class ChurchLetterSignerTile extends StatelessWidget {
  const ChurchLetterSignerTile({
    super.key,
    required this.label,
    required this.tenantId,
    required this.entry,
    required this.onTap,
    this.optional = false,
  });

  final String label;
  final String tenantId;
  final ChurchLetterMemberEntry? entry;
  final VoidCallback onTap;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final accent = ThemeCleanPremium.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Row(
            children: [
              if (entry != null)
                FotoMembroWidget(
                  tenantId: tenantId,
                  memberId: entry!.id,
                  memberData: entry!.data,
                  cpfDigits: entry!.cpfDigits.length == 11
                      ? entry!.cpfDigits
                      : null,
                  size: 44,
                  memCacheWidth: 120,
                )
              else
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Icon(Icons.person_search_rounded, color: accent),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry?.name ??
                          (optional ? 'Toque para escolher (opcional)' : 'Toque para escolher *'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: entry == null ? Colors.grey.shade700 : null,
                      ),
                    ),
                    if (entry != null)
                      Text(
                        entry!.cargoLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
