import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

class AttendancePage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cpf;
  const AttendancePage({
    super.key,
    required this.tenantId,
    required this.role,
    required this.cpf,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  static const _tipos = ['Todos', 'Culto', 'Célula', 'Evento', 'Reunião'];
  String _tipoFiltro = 'Todos';

  late Future<QuerySnapshot<Map<String, dynamic>>> _resumoFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _chartFuture;
  late Future<QuerySnapshot<Map<String, dynamic>>> _cultosListFuture;

  @override
  void initState() {
    super.initState();
    _refreshPresencaData();
  }

  void _refreshPresencaData() {
    final now = DateTime.now();
    final mesInicio = DateTime(now.year, now.month);
    final mesFim = DateTime(now.year, now.month + 1);
    setState(() {
      _resumoFuture = _cultos
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(mesInicio))
          .where('data', isLessThan: Timestamp.fromDate(mesFim))
          .get();
      _chartFuture = _cultos.orderBy('data', descending: true).limit(8).get();
      Query<Map<String, dynamic>> q = _cultos.orderBy('data', descending: true);
      if (_tipoFiltro != 'Todos') q = q.where('tipo', isEqualTo: _tipoFiltro);
      _cultosListFuture = q.get();
    });
  }

  bool get _canManage {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  CollectionReference<Map<String, dynamic>> get _cultos =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('cultos');

  CollectionReference<Map<String, dynamic>> get _members =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      appBar: isMobile
          ? null
          : AppBar(title: const Text('Controle de Presença')),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showCriarCultoDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo Evento'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _refreshPresencaData();
            await _cultosListFuture;
          },
          child: ListView(
            padding: ThemeCleanPremium.pagePadding(context),
            children: [
              if (isMobile) ...[
                Text(
                  'Controle de Presença',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                      ),
                ),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
              ],
              _buildResumoCard(),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              _buildChartCard(),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
              _buildFiltros(),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _buildCultosList(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Resumo Card ────────────────────────────────────────────────────────────
  Widget _buildResumoCard() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _resumoFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorCard('Erro ao carregar resumo');
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _shimmerCard(height: 130);
        }
        final docs = snap.data?.docs ?? [];
        final totalMes = docs.length;

        return FutureBuilder<_ResumoData>(
          future: _calcResumo(docs),
          builder: (context, resumoSnap) {
            final resumo = resumoSnap.data ?? _ResumoData(0, 0, null);
            return Container(
              decoration: BoxDecoration(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.primaryLight.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                        child: Icon(Icons.insights_rounded, color: ThemeCleanPremium.primaryLight, size: 22),
                      ),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      Text(
                        'Resumo do Mês',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ThemeCleanPremium.onSurface,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  Row(
                    children: [
                      _statTile(
                        context,
                        icon: Icons.event_rounded,
                        label: 'Eventos',
                        value: '$totalMes',
                        color: ThemeCleanPremium.primary,
                      ),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      _statTile(
                        context,
                        icon: Icons.people_rounded,
                        label: 'Média',
                        value: resumo.media > 0
                            ? '${resumo.media.toStringAsFixed(0)}%'
                            : '—',
                        color: ThemeCleanPremium.success,
                      ),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      _statTile(
                        context,
                        icon: Icons.calendar_today_rounded,
                        label: 'Último',
                        value: resumo.ultimoCulto ?? '—',
                        color: ThemeCleanPremium.primaryLight,
                        small: true,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool small = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ThemeCleanPremium.spaceSm,
          vertical: ThemeCleanPremium.spaceMd,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: small ? 13 : 18,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: ThemeCleanPremium.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<_ResumoData> _calcResumo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (docs.isEmpty) return _ResumoData(0, 0, null);

    double totalPercent = 0;
    int counted = 0;
    String? ultimoNome;

    final totalMembers = await _members.count().get();
    final membersCount = totalMembers.count ?? 1;

    for (final doc in docs) {
      final presSnap = await _cultos
          .doc(doc.id)
          .collection('presencas')
          .where('presente', isEqualTo: true)
          .count()
          .get();
      final presentes = presSnap.count ?? 0;
      if (membersCount > 0) {
        totalPercent += (presentes / membersCount) * 100;
        counted++;
      }
    }

    final sorted = List.of(docs)
      ..sort((a, b) {
        final da = (a.data()['data'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final db = (b.data()['data'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return db.compareTo(da);
      });
    ultimoNome = sorted.first.data()['nome']?.toString();

    final media = counted > 0 ? totalPercent / counted : 0.0;
    return _ResumoData(media, counted, ultimoNome);
  }

  // ─── Chart Card ─────────────────────────────────────────────────────────────
  Widget _buildChartCard() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _chartFuture,
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return _shimmerCard(height: 170);
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Presenças por Evento',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.onSurface,
                    ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              _ChartBars(cultos: _cultos, docs: docs.reversed.toList()),
            ],
          ),
        );
      },
    );
  }

  // ─── Filtros ────────────────────────────────────────────────────────────────
  Widget _buildFiltros() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tipos.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: ThemeCleanPremium.spaceXs),
        itemBuilder: (context, i) {
          final t = _tipos[i];
          final selected = t == _tipoFiltro;
          return ChoiceChip(
            label: Text(t),
            selected: selected,
            onSelected: (_) => setState(() {
              _tipoFiltro = t;
              Query<Map<String, dynamic>> q = _cultos.orderBy('data', descending: true);
              if (_tipoFiltro != 'Todos') q = q.where('tipo', isEqualTo: _tipoFiltro);
              _cultosListFuture = q.get();
            }),
            selectedColor: ThemeCleanPremium.primary,
            labelStyle: TextStyle(
              color: selected ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            backgroundColor: ThemeCleanPremium.cardBackground,
            side: BorderSide(
              color: selected
                  ? ThemeCleanPremium.primary
                  : Colors.grey.shade300,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            ),
          );
        },
      ),
    );
  }

  // ─── Lista de Cultos ────────────────────────────────────────────────────────
  Widget _buildCultosList() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _cultosListFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorCard('Erro ao carregar eventos: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Column(
            children: List.generate(3, (_) => Padding(
              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: _shimmerCard(height: 90),
            )),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState();

        return Column(
          children: docs.map((doc) => _buildCultoCard(doc)).toList(),
        );
      },
    );
  }

  Widget _buildCultoCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final nome = d['nome']?.toString() ?? 'Sem nome';
    final tipo = d['tipo']?.toString() ?? '';
    final data = (d['data'] as Timestamp?)?.toDate();
    final dataStr = data != null
        ? DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(data)
        : '—';
    final horaStr = data != null ? DateFormat.Hm('pt_BR').format(data) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      child: StreamBuilder<AggregateQuerySnapshot>(
        stream: _cultos
            .doc(doc.id)
            .collection('presencas')
            .where('presente', isEqualTo: true)
            .count()
            .get()
            .asStream(),
        builder: (context, countSnap) {
          final presentes = countSnap.data?.count ?? 0;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              onTap: () => _openPresenca(doc),
              onLongPress: _canManage ? () => _showCultoOptions(doc) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _tipoColor(tipo).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      child: Icon(_tipoIcon(tipo), color: _tipoColor(tipo), size: 22),
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
                              fontSize: 15,
                              color: ThemeCleanPremium.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            horaStr.isNotEmpty ? '$dataStr • $horaStr' : dataStr,
                            style: const TextStyle(
                              fontSize: 12,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceXs),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _tipoBadge(tipo),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_rounded, size: 14, color: ThemeCleanPremium.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '$presentes',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 64,
            color: ThemeCleanPremium.onSurfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Text(
            'Nenhum evento encontrado',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceXs),
          Text(
            _canManage
                ? 'Toque no botão + para criar um evento'
                : 'Nenhum evento cadastrado ainda',
            style: TextStyle(
              fontSize: 13,
              color: ThemeCleanPremium.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Criar Culto Dialog ─────────────────────────────────────────────────────
  Future<void> _showCriarCultoDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    if (!_canManage) return;
    final editing = doc != null;
    final existing = doc?.data() ?? {};

    final nomeCtrl = TextEditingController(text: existing['nome']?.toString() ?? '');
    String tipo = existing['tipo']?.toString() ?? 'Culto';
    DateTime selectedDate = (existing['data'] as Timestamp?)?.toDate() ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            ),
            title: Text(editing ? 'Editar Evento' : 'Novo Evento'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome do evento',
                        hintText: 'Ex: Culto de Domingo',
                        prefixIcon: Icon(Icons.church_rounded),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    DropdownButtonFormField<String>(
                      value: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                      items: ['Culto', 'Célula', 'Evento', 'Reunião']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => tipo = v ?? tipo),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_rounded),
                      title: Text(
                        DateFormat("dd 'de' MMMM 'de' yyyy", 'pt_BR')
                            .format(selectedDate),
                      ),
                      subtitle: const Text('Data'),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: Text(selectedTime.format(ctx)),
                      subtitle: const Text('Horário'),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx, true);
                },
                child: Text(editing ? 'Salvar' : 'Criar'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;

    final combinedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    final payload = {
      'nome': nomeCtrl.text.trim(),
      'tipo': tipo,
      'data': Timestamp.fromDate(combinedDate),
    };

    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (editing) {
      await doc!.reference.update(payload);
    } else {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await _cultos.add(payload);
    }

    if (mounted) {
      _refreshPresencaData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editing ? 'Evento atualizado' : 'Evento criado com sucesso', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    }
  }

  // ─── Opções do Culto (long press) ──────────────────────────────────────────
  void _showCultoOptions(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Editar evento'),
              minTileHeight: ThemeCleanPremium.minTouchTarget,
              onTap: () {
                Navigator.pop(ctx);
                _showCriarCultoDialog(doc: doc);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded, color: ThemeCleanPremium.error),
              title: Text('Excluir evento', style: TextStyle(color: ThemeCleanPremium.error)),
              minTileHeight: ThemeCleanPremium.minTouchTarget,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteCulto(doc);
              },
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCulto(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Excluir evento?'),
        content: const Text('Todas as presenças registradas serão perdidas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await doc.reference.delete();
    if (mounted) {
      _refreshPresencaData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evento excluído', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    }
  }

  // ─── Tela de Presença ──────────────────────────────────────────────────────
  void _openPresenca(QueryDocumentSnapshot<Map<String, dynamic>> cultoDoc) {
    final cultoData = cultoDoc.data();
    final cultoNome = cultoData['nome']?.toString() ?? 'Evento';
    final cultoDate = (cultoData['data'] as Timestamp?)?.toDate();
    final subtitle = cultoDate != null
        ? DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(cultoDate)
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (ctx, scrollCtrl) => _PresencaSheet(
          scrollController: scrollCtrl,
          cultoId: cultoDoc.id,
          cultoNome: cultoNome,
          cultoSubtitle: subtitle,
          tenantId: widget.tenantId,
          canManage: _canManage,
        ),
      ),
    );
  }

  // ─── Helpers visuais ───────────────────────────────────────────────────────
  Color _tipoColor(String tipo) {
    switch (tipo) {
      case 'Culto':
        return ThemeCleanPremium.primary;
      case 'Célula':
        return const Color(0xFF7C3AED);
      case 'Evento':
        return const Color(0xFFEA580C);
      case 'Reunião':
        return const Color(0xFF0891B2);
      default:
        return ThemeCleanPremium.primaryLight;
    }
  }

  IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'Culto':
        return Icons.church_rounded;
      case 'Célula':
        return Icons.groups_rounded;
      case 'Evento':
        return Icons.celebration_rounded;
      case 'Reunião':
        return Icons.handshake_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  Widget _tipoBadge(String tipo) {
    final color = _tipoColor(tipo);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tipo.isNotEmpty ? tipo : 'Outro',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _errorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: ThemeCleanPremium.error),
          const SizedBox(width: ThemeCleanPremium.spaceSm),
          Expanded(
            child: Text(msg,
                style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _shimmerCard({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

// ─── Resumo Model ───────────────────────────────────────────────────────────
class _ResumoData {
  final double media;
  final int totalCounted;
  final String? ultimoCulto;
  _ResumoData(this.media, this.totalCounted, this.ultimoCulto);
}

// ─── Chart Bars Widget ──────────────────────────────────────────────────────
class _ChartBars extends StatelessWidget {
  final CollectionReference<Map<String, dynamic>> cultos;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _ChartBars({required this.cultos, required this.docs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: docs.map((doc) {
          final nome = doc.data()['nome']?.toString() ?? '';
          final label = nome.length > 8 ? '${nome.substring(0, 8)}…' : nome;
          return Expanded(
            child: FutureBuilder<AggregateQuerySnapshot>(
              future: cultos
                  .doc(doc.id)
                  .collection('presencas')
                  .where('presente', isEqualTo: true)
                  .count()
                  .get(),
              builder: (context, snap) {
                final count = snap.data?.count ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: count > 0 ? (count.clamp(1, 50) * 1.6) + 8 : 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              ThemeCleanPremium.primary,
                              ThemeCleanPremium.primaryLight,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 9,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Presença Bottom Sheet ──────────────────────────────────────────────────
class _PresencaSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String cultoId;
  final String cultoNome;
  final String cultoSubtitle;
  final String tenantId;
  final bool canManage;

  const _PresencaSheet({
    required this.scrollController,
    required this.cultoId,
    required this.cultoNome,
    required this.cultoSubtitle,
    required this.tenantId,
    required this.canManage,
  });

  @override
  State<_PresencaSheet> createState() => _PresencaSheetState();
}

class _PresencaSheetState extends State<_PresencaSheet> {
  String _search = '';
  final Map<String, bool> _presencas = {};
  final Map<String, String> _nomes = {};
  bool _loaded = false;
  bool _saving = false;
  int _totalMembers = 0;

  CollectionReference<Map<String, dynamic>> get _presencasRef =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('cultos')
          .doc(widget.cultoId)
          .collection('presencas');

  CollectionReference<Map<String, dynamic>> get _members =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final membersSnap = await _members.orderBy('NOME_COMPLETO').get();
    final presSnap = await _presencasRef.get();

    final presMap = <String, bool>{};
    for (final p in presSnap.docs) {
      presMap[p.data()['membroId']?.toString() ?? p.id] =
          p.data()['presente'] == true;
    }

    final nomes = <String, String>{};
    final presencas = <String, bool>{};
    for (final m in membersSnap.docs) {
      final nome = (m.data()['NOME_COMPLETO'] ?? m.data()['nome'] ?? m.data()['name'] ?? '').toString();
      if (nome.isEmpty) continue;
      nomes[m.id] = nome;
      presencas[m.id] = presMap[m.id] ?? false;
    }

    if (mounted) {
      setState(() {
        _nomes.addAll(nomes);
        _presencas.addAll(presencas);
        _totalMembers = nomes.length;
        _loaded = true;
      });
    }
  }

  int get _presentCount => _presencas.values.where((v) => v).length;

  List<MapEntry<String, String>> get _filtered {
    final q = _search.toLowerCase();
    final entries = _nomes.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    if (q.isEmpty) return entries;
    return entries.where((e) => e.value.toLowerCase().contains(q)).toList();
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final batch = FirebaseFirestore.instance.batch();

    for (final entry in _presencas.entries) {
      final docRef = _presencasRef.doc(entry.key);
      batch.set(docRef, {
        'membroId': entry.key,
        'membroNome': _nomes[entry.key] ?? '',
        'presente': entry.value,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presenças salvas com sucesso', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    }
  }

  void _marcarTodos(bool value) {
    setState(() {
      for (final key in _presencas.keys) {
        _presencas[key] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeCleanPremium.spaceLg,
            ThemeCleanPremium.spaceSm,
            ThemeCleanPremium.spaceLg,
            0,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cultoNome,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (widget.cultoSubtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              widget.cultoSubtitle,
                              style: const TextStyle(
                                fontSize: 13,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.canManage)
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveAll,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Salvar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeCleanPremium.spaceSm,
                  vertical: ThemeCleanPremium.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: ThemeCleanPremium.success),
                    const SizedBox(width: 6),
                    Text(
                      '$_presentCount de $_totalMembers presentes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: ThemeCleanPremium.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceSm),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar membro...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceSm,
                    vertical: ThemeCleanPremium.spaceSm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceXs),
              if (widget.canManage)
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _marcarTodos(true),
                      icon: const Icon(Icons.check_box_rounded, size: 18),
                      label: const Text('Marcar Todos'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceXs),
                    TextButton.icon(
                      onPressed: () => _marcarTodos(false),
                      icon: const Icon(Icons.check_box_outline_blank_rounded, size: 18),
                      label: const Text('Desmarcar Todos'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget,
                          ThemeCleanPremium.minTouchTarget,
                        ),
                      ),
                    ),
                  ],
                ),
              const Divider(),
            ],
          ),
        ),
        if (!_loaded)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      _search.isNotEmpty
                          ? 'Nenhum membro encontrado'
                          : 'Nenhum membro cadastrado',
                      style: const TextStyle(
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceLg,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final entry = _filtered[i];
                      final presente = _presencas[entry.key] ?? false;
                      final initials = entry.value
                          .split(' ')
                          .where((w) => w.isNotEmpty)
                          .take(2)
                          .map((w) => w[0].toUpperCase())
                          .join();

                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: ThemeCleanPremium.spaceXs,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd,
                            ),
                            onTap: widget.canManage
                                ? () {
                                    setState(() {
                                      _presencas[entry.key] = !presente;
                                    });
                                  }
                                : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: ThemeCleanPremium.spaceSm,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: presente
                                    ? ThemeCleanPremium.success.withOpacity(0.06)
                                    : ThemeCleanPremium.cardBackground,
                                borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd,
                                ),
                                border: Border.all(
                                  color: presente
                                      ? ThemeCleanPremium.success.withOpacity(0.2)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: presente
                                        ? ThemeCleanPremium.success.withOpacity(0.15)
                                        : ThemeCleanPremium.primary.withOpacity(0.08),
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: presente
                                            ? ThemeCleanPremium.success
                                            : ThemeCleanPremium.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: ThemeCleanPremium.spaceSm),
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: ThemeCleanPremium.minTouchTarget,
                                    height: ThemeCleanPremium.minTouchTarget,
                                    child: Checkbox(
                                      value: presente,
                                      onChanged: widget.canManage
                                          ? (v) {
                                              setState(() {
                                                _presencas[entry.key] =
                                                    v ?? false;
                                              });
                                            }
                                          : null,
                                      activeColor: ThemeCleanPremium.success,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
