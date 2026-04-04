import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

class GroupsPage extends StatefulWidget {
  final String tenantId;
  final String role;
  const GroupsPage({super.key, required this.tenantId, required this.role});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  String _search = '';
  String _filter = 'Todos';

  bool get _canWrite {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  CollectionReference<Map<String, dynamic>> get _gruposCol =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('grupos');

  static const _diasSemana = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];

  static const _diaColors = <String, Color>{
    'Segunda': Color(0xFF3B82F6),
    'Terça': Color(0xFF10B981),
    'Quarta': Color(0xFFF59E0B),
    'Quinta': Color(0xFF8B5CF6),
    'Sexta': Color(0xFFEF4444),
    'Sábado': Color(0xFF14B8A6),
    'Domingo': Color(0xFFD97706),
  };

  Color _colorForDay(String dia) =>
      _diaColors[dia] ?? ThemeCleanPremium.primaryLight;

  Future<int> _encontrosMes() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final gruposSnap = await _gruposCol.get();
    int total = 0;
    for (final g in gruposSnap.docs) {
      final qs = await g.reference
          .collection('encontros')
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data', isLessThan: Timestamp.fromDate(end))
          .get();
      total += qs.size;
    }
    return total;
  }

  void _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _GroupFormPage(
            tenantId: widget.tenantId,
            doc: doc,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollCtrl) => _GroupFormPage(
            tenantId: widget.tenantId,
            doc: doc,
            scrollController: scrollCtrl,
            isSheet: true,
          ),
        ),
      );
    }
  }

  void _openDetail(DocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _GroupDetailPage(
          tenantId: widget.tenantId,
          groupDoc: doc,
          canWrite: _canWrite,
        ),
      ),
    );
  }

  Future<void> _deleteGroup(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir grupo'),
        content: Text(
            'Deseja excluir "${doc.data()?['nome'] ?? ''}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await doc.reference.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Grupo excluído', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir: $e')),
          );
        }
      }
    }
  }

  Widget _buildSummaryCards(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ativos = docs.where((d) {
      final s = (d.data()['status'] ?? 'Ativo').toString();
      return s == 'Ativo';
    }).toList();
    final totalParticipantes = docs.fold<int>(
      0,
      (sum, d) => sum + ((d.data()['membrosCount'] as num?) ?? 0).toInt(),
    );

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ThemeCleanPremium.spaceSm),
        children: [
          _SummaryCard(
            icon: Icons.groups_rounded,
            color: ThemeCleanPremium.primaryLight,
            label: 'Grupos Ativos',
            value: '${ativos.length}',
          ),
          _SummaryCard(
            icon: Icons.people_rounded,
            color: ThemeCleanPremium.success,
            label: 'Participantes',
            value: '$totalParticipantes',
          ),
          FutureBuilder<int>(
            future: _encontrosMes(),
            builder: (_, snap) => _SummaryCard(
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFFF59E0B),
              label: 'Encontros este mês',
              value: snap.hasData ? '${snap.data}' : '…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeCleanPremium.spaceSm,
        vertical: ThemeCleanPremium.spaceXs,
      ),
      child: TextField(
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Buscar grupo…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _search = ''),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    const filters = ['Todos', 'Ativos', 'Inativos'];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeCleanPremium.spaceSm,
        vertical: ThemeCleanPremium.spaceXs,
      ),
      child: Row(
        children: filters.map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: ThemeCleanPremium.primaryLight.withOpacity(0.15),
              checkmarkColor: ThemeCleanPremium.primary,
              labelStyle: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? ThemeCleanPremium.primary
                    : ThemeCleanPremium.onSurfaceVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              ),
              side: BorderSide.none,
            ),
          );
        }).toList(),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs.toList();
    if (_filter == 'Ativos') {
      filtered = filtered
          .where((d) => (d.data()['status'] ?? 'Ativo') == 'Ativo')
          .toList();
    } else if (_filter == 'Inativos') {
      filtered =
          filtered.where((d) => d.data()['status'] == 'Inativo').toList();
    }
    if (_search.isNotEmpty) {
      filtered = filtered.where((d) {
        final data = d.data();
        final nome = (data['nome'] ?? '').toString().toLowerCase();
        final lider = (data['liderNome'] ?? '').toString().toLowerCase();
        final bairro = (data['bairro'] ?? '').toString().toLowerCase();
        return nome.contains(_search) ||
            lider.contains(_search) ||
            bairro.contains(_search);
      }).toList();
    }
    return filtered;
  }

  Widget _buildGroupCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final nome = (data['nome'] ?? '').toString();
    final descricao = (data['descricao'] ?? '').toString();
    final liderNome = (data['liderNome'] ?? '').toString();
    final diaSemana = (data['diaSemana'] ?? '').toString();
    final horario = (data['horario'] ?? '').toString();
    final endereco = (data['endereco'] ?? '').toString();
    final bairro = (data['bairro'] ?? '').toString();
    final status = (data['status'] ?? 'Ativo').toString();
    final membrosCount = ((data['membrosCount'] as num?) ?? 0).toInt();
    final dayColor = _colorForDay(diaSemana);
    final isActive = status == 'Ativo';

    return GestureDetector(
      onTap: () => _openDetail(doc),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: ThemeCleanPremium.spaceSm,
          vertical: ThemeCleanPremium.spaceXs,
        ),
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: ThemeCleanPremium.softUiCardShadow,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: dayColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(ThemeCleanPremium.radiusMd),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: dayColor.withOpacity(0.12),
                            child: Text(
                              liderNome.isNotEmpty
                                  ? liderNome[0].toUpperCase()
                                  : 'G',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: dayColor,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: ThemeCleanPremium.spaceSm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (liderNome.isNotEmpty)
                                  Text(
                                    'Líder: $liderNome',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_canWrite)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: ThemeCleanPremium.onSurfaceVariant),
                              onSelected: (v) {
                                if (v == 'edit') _openForm(doc: doc);
                                if (v == 'delete') _deleteGroup(doc);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text('Editar'),
                                    ])),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_rounded,
                                          size: 18, color: ThemeCleanPremium.error),
                                      SizedBox(width: 8),
                                      Text('Excluir',
                                          style:
                                              TextStyle(color: ThemeCleanPremium.error)),
                                    ])),
                              ],
                            ),
                        ],
                      ),
                      if (descricao.isNotEmpty) ...[
                        const SizedBox(height: ThemeCleanPremium.spaceXs),
                        Text(
                          descricao,
                          style: const TextStyle(
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: ThemeCleanPremium.spaceSm),
                      Wrap(
                        spacing: ThemeCleanPremium.spaceSm,
                        runSpacing: ThemeCleanPremium.spaceXs,
                        children: [
                          if (diaSemana.isNotEmpty || horario.isNotEmpty)
                            _InfoChip(
                              icon: Icons.schedule_rounded,
                              label:
                                  [diaSemana, horario].where((e) => e.isNotEmpty).join(' · '),
                              color: dayColor,
                            ),
                          if (bairro.isNotEmpty)
                            _InfoChip(
                              icon: Icons.location_on_rounded,
                              label: bairro,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          _InfoChip(
                            icon: Icons.people_rounded,
                            label: '$membrosCount',
                            color: ThemeCleanPremium.primaryLight,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (endereco.isNotEmpty) ...[
                        const SizedBox(height: ThemeCleanPremium.spaceXs),
                        Text(
                          endereco,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_3_rounded, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Text(
            'Nenhum grupo cadastrado',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceXs),
          Text(
            'Crie seu primeiro grupo ou célula',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          if (_canWrite) ...[
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo Grupo'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceLg,
                  vertical: ThemeCleanPremium.spaceSm,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Grupos / Células'),
              actions: [
                if (_canWrite)
                  IconButton(
                    tooltip: 'Novo grupo',
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _canWrite && isMobile
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              backgroundColor: ThemeCleanPremium.primary,
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _gruposCol.orderBy('nome').snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: ThemeCleanPremium.error),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      Text(
                        'Erro ao carregar grupos.',
                        style: TextStyle(
                            color: ThemeCleanPremium.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              );
            }

            final allDocs = snap.hasData
                ? snap.data!.docs
                : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            if (allDocs.isEmpty) return _buildEmptyState();

            final docs = _applyFilters(allDocs);

            return Column(
              children: [
                if (isMobile)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: ThemeCleanPremium.spaceSm,
                      right: ThemeCleanPremium.spaceSm,
                      top: ThemeCleanPremium.spaceMd,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups_3_rounded,
                            color: ThemeCleanPremium.primary, size: 28),
                        const SizedBox(width: ThemeCleanPremium.spaceSm),
                        const Expanded(
                          child: Text(
                            'Grupos / Células',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: ThemeCleanPremium.spaceXs),
                _buildSummaryCards(allDocs),
                _buildSearch(),
                _buildFilterChips(),
                Expanded(
                  child: docs.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum grupo encontrado',
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                              bottom: ThemeCleanPremium.spaceXxl + 24),
                          itemCount: docs.length,
                          itemBuilder: (_, i) => _buildGroupCard(docs[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary Card
// ---------------------------------------------------------------------------
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      margin: const EdgeInsets.only(right: ThemeCleanPremium.spaceSm),
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info Chip (schedule, location, members count)
// ---------------------------------------------------------------------------
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group Form Page (create / edit)
// ---------------------------------------------------------------------------
class _GroupFormPage extends StatefulWidget {
  final String tenantId;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final ScrollController? scrollController;
  final bool isSheet;

  const _GroupFormPage({
    required this.tenantId,
    this.doc,
    this.scrollController,
    this.isSheet = false,
  });

  @override
  State<_GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends State<_GroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _liderCtrl;
  late final TextEditingController _enderecoCtrl;
  late final TextEditingController _bairroCtrl;
  late String _diaSemana;
  late String _horario;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    _nomeCtrl = TextEditingController(text: (data['nome'] ?? '').toString());
    _descCtrl = TextEditingController(text: (data['descricao'] ?? '').toString());
    _liderCtrl = TextEditingController(text: (data['liderNome'] ?? '').toString());
    _enderecoCtrl = TextEditingController(text: (data['endereco'] ?? '').toString());
    _bairroCtrl = TextEditingController(text: (data['bairro'] ?? '').toString());
    _diaSemana = (data['diaSemana'] ?? 'Quarta').toString();
    _horario = (data['horario'] ?? '19:30').toString();
    _status = (data['status'] ?? 'Ativo').toString();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    _liderCtrl.dispose();
    _enderecoCtrl.dispose();
    _bairroCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parts = _horario.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 19,
      minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 30,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        _horario =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('grupos');

      final payload = <String, dynamic>{
        'nome': _nomeCtrl.text.trim(),
        'descricao': _descCtrl.text.trim(),
        'liderNome': _liderCtrl.text.trim(),
        'diaSemana': _diaSemana,
        'horario': _horario,
        'endereco': _enderecoCtrl.text.trim(),
        'bairro': _bairroCtrl.text.trim(),
        'status': _status,
        'updatedAt': Timestamp.now(),
      };

      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (widget.doc == null) {
        payload['createdAt'] = Timestamp.now();
        payload['membrosCount'] = 0;
        payload['membros'] = <Map<String, dynamic>>[];
        await col.add(payload);
      } else {
        await widget.doc!.reference.update(payload);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Form(
      key: _formKey,
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(
          ThemeCleanPremium.spaceLg,
          ThemeCleanPremium.spaceLg,
          ThemeCleanPremium.spaceLg,
          MediaQuery.of(context).viewInsets.bottom + ThemeCleanPremium.spaceLg,
        ),
        children: [
          if (widget.isSheet)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Text(
            widget.doc == null ? 'Novo Grupo' : 'Editar Grupo',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurface,
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          TextFormField(
            controller: _nomeCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do grupo *',
              prefixIcon: Icon(Icons.groups_rounded),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _liderCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do líder',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          DropdownButtonFormField<String>(
            value: _GroupsPageState._diasSemana.contains(_diaSemana)
                ? _diaSemana
                : 'Quarta',
            decoration: const InputDecoration(
              labelText: 'Dia da semana',
              prefixIcon: Icon(Icons.calendar_today_rounded),
            ),
            items: _GroupsPageState._diasSemana
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _diaSemana = v ?? _diaSemana),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          InkWell(
            onTap: _pickTime,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Horário',
                prefixIcon: Icon(Icons.access_time_rounded),
              ),
              child: Text(_horario),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _enderecoCtrl,
            decoration: const InputDecoration(
              labelText: 'Endereço',
              prefixIcon: Icon(Icons.location_on_rounded),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _bairroCtrl,
            decoration: const InputDecoration(
              labelText: 'Bairro',
              prefixIcon: Icon(Icons.map_rounded),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              prefixIcon: Icon(Icons.toggle_on_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'Ativo', child: Text('Ativo')),
              DropdownMenuItem(value: 'Inativo', child: Text('Inativo')),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceSm),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.isSheet) return content;

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: Text(widget.doc == null ? 'Novo Grupo' : 'Editar Grupo'),
      ),
      body: SafeArea(child: content),
    );
  }
}

// ---------------------------------------------------------------------------
// Group Detail Page (tabs: Info, Membros, Encontros)
// ---------------------------------------------------------------------------
class _GroupDetailPage extends StatefulWidget {
  final String tenantId;
  final DocumentSnapshot<Map<String, dynamic>> groupDoc;
  final bool canWrite;

  const _GroupDetailPage({
    required this.tenantId,
    required this.groupDoc,
    required this.canWrite,
  });

  @override
  State<_GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<_GroupDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('grupos')
          .doc(widget.groupDoc.id);

  CollectionReference<Map<String, dynamic>> get _encontrosCol =>
      _groupRef.collection('encontros');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Widget _buildInfoTab(Map<String, dynamic> data) {
    final nome = (data['nome'] ?? '').toString();
    final descricao = (data['descricao'] ?? '').toString();
    final liderNome = (data['liderNome'] ?? '').toString();
    final diaSemana = (data['diaSemana'] ?? '').toString();
    final horario = (data['horario'] ?? '').toString();
    final endereco = (data['endereco'] ?? '').toString();
    final bairro = (data['bairro'] ?? '').toString();
    final status = (data['status'] ?? 'Ativo').toString();
    final isActive = status == 'Ativo';
    final dayColor = _GroupsPageState._diaColors[diaSemana] ??
        ThemeCleanPremium.primaryLight;

    return ListView(
      padding: ThemeCleanPremium.pagePadding(context),
      children: [
        Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: dayColor.withOpacity(0.12),
                child: Text(
                  nome.isNotEmpty ? nome[0].toUpperCase() : 'G',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: dayColor,
                  ),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Text(
                nome,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              if (descricao.isNotEmpty) ...[
                const SizedBox(height: ThemeCleanPremium.spaceXs),
                Text(
                  descricao,
                  style: const TextStyle(
                    fontSize: 14,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? const Color(0xFF166534)
                        : const Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ThemeCleanPremium.spaceMd),
        _DetailInfoTile(
            icon: Icons.person_rounded, label: 'Líder', value: liderNome),
        _DetailInfoTile(
          icon: Icons.schedule_rounded,
          label: 'Horário',
          value: '$diaSemana · $horario',
        ),
        _DetailInfoTile(
            icon: Icons.location_on_rounded,
            label: 'Endereço',
            value: endereco),
        _DetailInfoTile(
            icon: Icons.map_rounded, label: 'Bairro', value: bairro),
      ],
    );
  }

  // -- Membros Tab --
  Widget _buildMembrosTab(Map<String, dynamic> data) {
    final membros = List<Map<String, dynamic>>.from(data['membros'] ?? []);

    return Column(
      children: [
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
            child: FilledButton.icon(
              onPressed: _addMembro,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Adicionar membro'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                minimumSize: const Size(
                    double.infinity, ThemeCleanPremium.minTouchTarget),
              ),
            ),
          ),
        Expanded(
          child: membros.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: ThemeCleanPremium.spaceSm),
                      Text(
                        'Nenhum membro adicionado',
                        style: TextStyle(
                            color: ThemeCleanPremium.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
                  itemCount: membros.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: ThemeCleanPremium.spaceXs),
                  itemBuilder: (_, i) {
                    final m = membros[i];
                    final nome = (m['nome'] ?? '').toString();
                    return Container(
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.cardBackground,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              ThemeCleanPremium.primaryLight.withOpacity(0.12),
                          child: Text(
                            nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ThemeCleanPremium.primaryLight,
                            ),
                          ),
                        ),
                        title: Text(nome,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: widget.canWrite
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_rounded,
                                    color: ThemeCleanPremium.error, size: 20),
                                onPressed: () => _removeMembro(i, membros),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(
                                    ThemeCleanPremium.minTouchTarget,
                                    ThemeCleanPremium.minTouchTarget,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addMembro() async {
    final membersCol = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros');

    final searchCtrl = TextEditingController();
    String q = '';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (v) => setD(() => q = v.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Buscar membro…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: ThemeCleanPremium.surfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: membersCol.orderBy('NOME_COMPLETO').snapshots(),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return const Center(
                            child: Text('Erro ao buscar membros'));
                      }
                      var docs = snap.data?.docs ?? [];
                      if (q.isNotEmpty) {
                        docs = docs.where((d) {
                          final n = (d.data()['NOME_COMPLETO'] ?? '')
                              .toString()
                              .toLowerCase();
                          return n.contains(q);
                        }).toList();
                      }
                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'Nenhum membro encontrado',
                            style: TextStyle(
                                color: ThemeCleanPremium.onSurfaceVariant),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: scrollCtrl,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i];
                          final nome =
                              (d.data()['NOME_COMPLETO'] ?? '').toString();
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: ThemeCleanPremium.primaryLight
                                  .withOpacity(0.12),
                              child: Text(
                                nome.isNotEmpty
                                    ? nome[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.primaryLight,
                                ),
                              ),
                            ),
                            title: Text(nome),
                            onTap: () => Navigator.pop(
                                ctx, {'id': d.id, 'nome': nome}),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == null) return;

    final currentSnap = await _groupRef.get();
    final currentData = currentSnap.data() ?? {};
    final membros =
        List<Map<String, dynamic>>.from(currentData['membros'] ?? []);

    if (membros.any((m) => m['id'] == result['id'])) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Membro já adicionado ao grupo')),
        );
      }
      return;
    }

    membros.add({'id': result['id'], 'nome': result['nome']});
    await _groupRef.update({
      'membros': membros,
      'membrosCount': membros.length,
    });
  }

  Future<void> _removeMembro(
      int index, List<Map<String, dynamic>> membros) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover membro'),
        content: Text(
            'Remover "${membros[index]['nome'] ?? ''}" deste grupo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = List<Map<String, dynamic>>.from(membros)..removeAt(index);
    await _groupRef.update({
      'membros': updated,
      'membrosCount': updated.length,
    });
  }

  // -- Encontros Tab --
  Widget _buildEncontrosTab() {
    return Column(
      children: [
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
            child: FilledButton.icon(
              onPressed: _addEncontro,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Registrar encontro'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                minimumSize: const Size(
                    double.infinity, ThemeCleanPremium.minTouchTarget),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _encontrosCol
                .orderBy('data', descending: true)
                .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 40, color: ThemeCleanPremium.error),
                      const SizedBox(height: 8),
                      Text('Erro ao carregar encontros',
                          style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant)),
                    ],
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note_rounded,
                          size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: ThemeCleanPremium.spaceSm),
                      Text('Nenhum encontro registrado',
                          style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: ThemeCleanPremium.spaceXs),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final data = d['data'];
                  String dataStr = '';
                  if (data is Timestamp) {
                    dataStr = DateFormat('dd/MM/yyyy').format(data.toDate());
                  }
                  final tema = (d['tema'] ?? '').toString();
                  final presentes = ((d['presentes'] as num?) ?? 0).toInt();
                  final notas = (d['notas'] ?? '').toString();

                  return Container(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                    decoration: BoxDecoration(
                      color: ThemeCleanPremium.cardBackground,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primaryLight
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                dataStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: ThemeCleanPremium.spaceSm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.success
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people_rounded,
                                      size: 14,
                                      color: ThemeCleanPremium.success),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$presentes',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeCleanPremium.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (widget.canWrite)
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18,
                                    color: ThemeCleanPremium.onSurfaceVariant),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Excluir encontro'),
                                      content: const Text(
                                          'Deseja excluir este encontro?'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancelar')),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  ThemeCleanPremium.error),
                                          child: const Text('Excluir'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await docs[i].reference.delete();
                                  }
                                },
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(
                                    ThemeCleanPremium.minTouchTarget,
                                    ThemeCleanPremium.minTouchTarget,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (tema.isNotEmpty) ...[
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                          Text(
                            tema,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                        ],
                        if (notas.isNotEmpty) ...[
                          const SizedBox(height: ThemeCleanPremium.spaceXs),
                          Text(
                            notas,
                            style: const TextStyle(
                              fontSize: 13,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addEncontro() async {
    DateTime selectedDate = DateTime.now();
    final temaCtrl = TextEditingController();
    final presentesCtrl = TextEditingController();
    final notasCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              ThemeCleanPremium.spaceLg,
              20,
              ThemeCleanPremium.spaceLg,
              MediaQuery.of(ctx).viewInsets.bottom + ThemeCleanPremium.spaceLg,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Novo Encontro',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setD(() => selectedDate = picked);
                    },
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data',
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      child: Text(
                          DateFormat('dd/MM/yyyy').format(selectedDate)),
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  TextField(
                    controller: temaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tema / Estudo',
                      prefixIcon: Icon(Icons.menu_book_rounded),
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  TextField(
                    controller: presentesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Presentes',
                      prefixIcon: Icon(Icons.people_rounded),
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  TextField(
                    controller: notasCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notas / Observações',
                      prefixIcon: Icon(Icons.notes_rounded),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceLg),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                          ),
                          child: const Text('Salvar'),
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
    );

    if (ok != true) return;

    await _encontrosCol.add({
      'data': Timestamp.fromDate(selectedDate),
      'tema': temaCtrl.text.trim(),
      'presentes': int.tryParse(presentesCtrl.text.trim()) ?? 0,
      'notas': notasCtrl.text.trim(),
      'createdAt': Timestamp.now(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _groupRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            appBar: AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !(snap.data?.exists ?? false)) {
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surfaceVariant,
            appBar: AppBar(
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Text(
                snap.hasError ? 'Erro ao carregar grupo' : 'Grupo não encontrado',
                style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
              ),
            ),
          );
        }

        final data = snap.data!.data() ?? {};
        final nome = (data['nome'] ?? '').toString();

        return Scaffold(
          backgroundColor: ThemeCleanPremium.surfaceVariant,
          appBar: AppBar(
            backgroundColor: ThemeCleanPremium.primary,
            foregroundColor: Colors.white,
            title: Text(nome),
            bottom: TabBar(
              controller: _tabCtrl,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(icon: Icon(Icons.info_outline_rounded), text: 'Info'),
                Tab(icon: Icon(Icons.people_rounded), text: 'Membros'),
                Tab(icon: Icon(Icons.event_note_rounded), text: 'Encontros'),
              ],
            ),
          ),
          body: SafeArea(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildInfoTab(data),
                _buildMembrosTab(data),
                _buildEncontrosTab(),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Detail info tile
// ---------------------------------------------------------------------------
class _DetailInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailInfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceXs),
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeCleanPremium.spaceMd,
        vertical: ThemeCleanPremium.spaceSm,
      ),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ThemeCleanPremium.primaryLight),
          const SizedBox(width: ThemeCleanPremium.spaceSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
