import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_department_members_load_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;

/// Picker full-screen — mesmo visual para «Vincular membros» e «Escolher líder».
enum ChurchDepartmentMemberPickerMode {
  /// Multi-seleção; retorna [Set] de `memberDocId`.
  linkMembers,

  /// Um líder; retorna CPF 11 dígitos ([String]).
  singleLeader,
}

/// Chip de filtro visível (evita ChoiceChip «fantasma» em fundo branco).
Widget churchDepartmentPickerFilterChip({
  required String label,
  required bool selected,
  required Color accent,
  required ValueChanged<bool> onSelected,
}) {
  return FilterChip(
    label: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
        color: selected ? accent : const Color(0xFF334155),
      ),
    ),
    selected: selected,
    showCheckmark: true,
    checkmarkColor: accent,
    selectedColor: accent.withValues(alpha: 0.2),
    backgroundColor: const Color(0xFFF8FAFC),
    side: BorderSide(
      color: selected ? accent : const Color(0xFF94A3B8),
      width: selected ? 1.6 : 1.1,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
    onSelected: onSelected,
  );
}

/// Tela moderna de seleção de membros (fotos + filtros + gradiente).
class ChurchDepartmentMemberPickerPage extends StatefulWidget {
  final String tenantId;
  final String deptName;
  final ChurchDepartmentMemberPickerMode mode;
  final String? deptId;
  final int accent1;
  final int accent2;
  final Set<String>? initialSelectedMemberIds;

  const ChurchDepartmentMemberPickerPage({
    super.key,
    required this.tenantId,
    required this.deptName,
    required this.mode,
    this.deptId,
    this.accent1 = 0xFF2563EB,
    this.accent2 = 0xFF7C3AED,
    this.initialSelectedMemberIds,
  });

  @override
  State<ChurchDepartmentMemberPickerPage> createState() =>
      _ChurchDepartmentMemberPickerPageState();
}

class _ChurchDepartmentMemberPickerPageState
    extends State<ChurchDepartmentMemberPickerPage> {
  late Set<String> _selected;
  List<ChurchDepartmentMemberRow> _members = const [];
  bool _loading = true;
  String? _loadError;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;
  String _sexFilter = '';
  String _presetFilter = 'todos';

  Color get _cA => Color(widget.accent1);
  Color get _cB => Color(widget.accent2);
  bool get _singleLeader =>
      widget.mode == ChurchDepartmentMemberPickerMode.singleLeader;

  @override
  void initState() {
    super.initState();
    _selected = {...?widget.initialSelectedMemberIds};
    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_loadMembers());
  }

  Future<void> _loadMembers() async {
    if (!mounted) return;
    if (_members.isEmpty) setState(() => _loading = true);
    try {
      final loaded = await ChurchDepartmentMembersLoadService.loadAllForPicker(
        seedTenantId: widget.tenantId,
      );
      if (!mounted) return;
      final selected = <String>{..._selected};
      final deptId = widget.deptId?.trim() ?? '';
      if (!_singleLeader && deptId.isNotEmpty && selected.isEmpty) {
        for (final row in loaded.members) {
          if (ChurchDepartmentMembersLoadService.memberInDepartment(
            row.data,
            deptId,
          )) {
            selected.add(row.memberDocId);
          }
        }
      }
      setState(() {
        _members = loaded.members;
        _selected = selected;
        _loading = false;
        _loadError = loaded.members.isEmpty ? loaded.softError : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final q = _searchCtrl.text.trim();
      if (q == _searchQuery) return;
      setState(() => _searchQuery = q);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _cpfDigits(Map<String, dynamic> d) =>
      (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  bool _memberMatchesFilters(ChurchDepartmentMemberRow row) {
    final d = row.data;
    final q = _searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      final name = row.displayName.toLowerCase();
      final cpf = _cpfDigits(d);
      if (!name.contains(q) && !cpf.contains(q)) return false;
    }
    final gender = genderCategoryFromMemberData(d);
    if (_sexFilter.isNotEmpty && gender != _sexFilter) return false;
    final age = ageFromMemberData(d);
    switch (_presetFilter) {
      case 'todos':
        return true;
      case 'homem':
        if (gender != 'M') return false;
        if (age == null) return false;
        return age >= 18 && age < 60;
      case 'menino':
        if (gender != 'M') return false;
        if (age == null) return false;
        return age < 18;
      case 'menina':
        if (gender != 'F') return false;
        if (age == null) return false;
        return age < 18;
      case 'mulher':
        if (gender != 'F') return false;
        if (age == null) return false;
        return age >= 18 && age < 60;
      case 'idoso':
        if (age == null) return false;
        return age >= 60;
      case 'crianca':
        if (age == null) return false;
        return age < 13;
      default:
        return true;
    }
  }

  List<ChurchDepartmentMemberRow> get _visibleMembers {
    final sorted = List<ChurchDepartmentMemberRow>.from(_members)
      ..sort((a, b) => a.displayName
          .toLowerCase()
          .compareTo(b.displayName.toLowerCase()));
    return sorted.where(_memberMatchesFilters).toList();
  }

  void _onLeaderTap(ChurchDepartmentMemberRow row) {
    final cpf = _cpfDigits(row.data);
    if (cpf.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este membro não tem CPF válido para líder.'),
        ),
      );
      return;
    }
    Navigator.pop(context, cpf);
  }

  void _confirmMulti() => Navigator.pop(context, _selected);

  Widget _memberTile(ChurchDepartmentMemberRow row) {
    final id = row.memberDocId;
    final d = row.data;
    final checked = _selected.contains(id);
    final fotoUrl = imageUrlFromMap(d);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final mem = (48 * dpr).round().clamp(96, 220);

    if (_singleLeader) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _onLeaderTap(row),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _cA.withValues(alpha: 0.14),
                ),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        FotoMembroWidget(
                          size: 52,
                          tenantId: widget.tenantId,
                          memberId: id,
                          imageUrl: fotoUrl.isEmpty ? null : fotoUrl,
                          cpfDigits: _cpfDigits(d),
                          memberData: d,
                          preferListThumbnail: true,
                          memCacheWidth: mem,
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFF59E0B),
                                  _cA,
                                ],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _cpfDigits(d).length == 11
                                ? 'Toque para definir como líder'
                                : 'CPF inválido — edite em Membros',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _cpfDigits(d).length == 11
                                  ? _cA
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: _cA),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              if (checked) {
                _selected.remove(id);
              } else {
                _selected.add(id);
              }
            });
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: checked
                    ? _cA.withValues(alpha: 0.55)
                    : _cA.withValues(alpha: 0.12),
                width: checked ? 1.8 : 1,
              ),
              gradient: checked
                  ? LinearGradient(
                      colors: [
                        _cA.withValues(alpha: 0.08),
                        _cB.withValues(alpha: 0.06),
                      ],
                    )
                  : null,
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: checked,
                    activeColor: _cA,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      row.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: checked
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FotoMembroWidget(
                    size: 48,
                    tenantId: widget.tenantId,
                    memberId: id,
                    imageUrl: fotoUrl.isEmpty ? null : fotoUrl,
                    cpfDigits: _cpfDigits(d),
                    memberData: d,
                    preferListThumbnail: true,
                    memCacheWidth: mem,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleMembers;
    final pagePad = ThemeCleanPremium.pagePadding(context);
    final title = _singleLeader ? 'Escolher líder' : 'Vincular membros';
    final subtitle = _singleLeader
        ? '${widget.deptName} — toque no membro para definir como líder do departamento.'
        : '${widget.deptName} — marque quem participa de escalas e reuniões.';

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_cA, _cB],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _cA.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: pagePad.copyWith(top: 12, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _singleLeader
                      ? 'Buscar nome ou CPF…'
                      : 'Buscar por nome…',
                  prefixIcon: Icon(Icons.search_rounded, color: _cA),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _cA.withValues(alpha: 0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _cA.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _cA, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sexo',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    churchDepartmentPickerFilterChip(
                      label: 'Todos',
                      selected: _sexFilter.isEmpty,
                      accent: _cA,
                      onSelected: (v) {
                        if (v) setState(() => _sexFilter = '');
                      },
                    ),
                    const SizedBox(width: 8),
                    churchDepartmentPickerFilterChip(
                      label: 'Masculino',
                      selected: _sexFilter == 'M',
                      accent: _cA,
                      onSelected: (v) {
                        if (v) setState(() => _sexFilter = 'M');
                      },
                    ),
                    const SizedBox(width: 8),
                    churchDepartmentPickerFilterChip(
                      label: 'Feminino',
                      selected: _sexFilter == 'F',
                      accent: _cB,
                      onSelected: (v) {
                        if (v) setState(() => _sexFilter = 'F');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Idade / perfil',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (id, label) in [
                      ('todos', 'Todos'),
                      ('crianca', 'Criança'),
                      ('menino', 'Menino'),
                      ('menina', 'Menina'),
                      ('homem', 'Homem'),
                      ('mulher', 'Mulher'),
                      ('idoso', 'Idoso'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: churchDepartmentPickerFilterChip(
                          label: label,
                          selected: _presetFilter == id,
                          accent: _cB,
                          onSelected: (v) {
                            if (v) setState(() => _presetFilter = id);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ordem alfabética · ${visible.length} de ${_members.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: _cA))
                    : _loadError != null && _members.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_loadError!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _loadMembers,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _cA,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          )
                        : visible.isEmpty
                            ? Center(
                                child: Text(
                                  'Nenhum membro corresponde aos filtros.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (_, i) =>
                                    _memberTile(visible[i]),
                              ),
              ),
              if (!_singleLeader) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _cA,
                          side: BorderSide(color: _cA, width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _confirmMulti,
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: Text('Salvar (${_selected.length})'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _cA,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
