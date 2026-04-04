import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Push segmentado (departamento / cargo / igreja), devocional diário (FCM agendado) e alerta de evasão (presenças).
class PastoralComunicacaoPage extends StatefulWidget {
  final String tenantId;
  final String role;

  const PastoralComunicacaoPage({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  State<PastoralComunicacaoPage> createState() => _PastoralComunicacaoPageState();
}

class _PastoralComunicacaoPageState extends State<PastoralComunicacaoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Pastoral & comunicação'),
              bottom: TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'Push', icon: Icon(Icons.campaign_rounded)),
                  Tab(text: 'Devocional', icon: Icon(Icons.wb_sunny_rounded)),
                  Tab(text: 'Evasão', icon: Icon(Icons.health_and_safety_rounded)),
                ],
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (isMobile)
              Material(
                color: ThemeCleanPremium.primary,
                child: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: ThemeCleanPremium.navSidebarAccent,
                  tabs: const [
                    Tab(text: 'Push'),
                    Tab(text: 'Devocional'),
                    Tab(text: 'Evasão'),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _PushSegmentadoTab(tenantId: widget.tenantId),
                  _DevocionalTab(tenantId: widget.tenantId),
                  _EvasaoTab(tenantId: widget.tenantId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PushSegmentadoTab extends StatefulWidget {
  final String tenantId;
  const _PushSegmentadoTab({required this.tenantId});

  @override
  State<_PushSegmentadoTab> createState() => _PushSegmentadoTabState();
}

class _PushSegmentadoTabState extends State<_PushSegmentadoTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _segment = 'broadcast';
  String? _deptId;
  String? _cargoName;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String get _topicPreview {
    final tid = widget.tenantId.trim();
    if (_segment == 'department' && (_deptId ?? '').isNotEmpty) {
      return 'dept_${_deptId!}';
    }
    if (_segment == 'cargo' && (_cargoName ?? '').trim().isNotEmpty) {
      return 'cargo_${FcmService.slugTopicPart(_cargoName!)}';
    }
    return 'igreja_$tid';
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e mensagem.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendSegmentedPush');
      await fn.call({
        'tenantId': widget.tenantId,
        'title': title,
        'body': body,
        'segment': _segment,
        if (_segment == 'department') 'departmentId': _deptId ?? '',
        if (_segment == 'cargo') 'cargoLabel': _cargoName ?? '',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Notificação enviada para o tópico.'),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Falha ao enviar.'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deptsRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('departamentos');
    final cargosRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('cargos');

    return ListView(
      padding: ThemeCleanPremium.pagePadding(context),
      children: [
        Text(
          'Avisos segmentados',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Os aparelhos precisam estar inscritos nos tópicos (departamento, cargo e igreja). '
          'Lembrete de escala e devocional usam o mesmo sistema.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tópico: $_topicPreview',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'broadcast', label: Text('Igreja'), icon: Icon(Icons.church_rounded)),
                  ButtonSegment(value: 'department', label: Text('Dept.'), icon: Icon(Icons.groups_rounded)),
                  ButtonSegment(value: 'cargo', label: Text('Cargo'), icon: Icon(Icons.work_rounded)),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
              if (_segment == 'department') ...[
                const SizedBox(height: 16),
                FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: deptsRef.get().then((s) {
                    final l = s.docs.toList()
                      ..sort(
                        (a, b) => churchDepartmentNameFromData(a.data(), docId: a.id)
                            .toLowerCase()
                            .compareTo(
                              churchDepartmentNameFromData(b.data(), docId: b.id).toLowerCase(),
                            ),
                      );
                    return l;
                  }),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ));
                    }
                    final docs = snap.data!;
                    return DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Departamento',
                        border: OutlineInputBorder(),
                      ),
                      value: _deptId != null && docs.any((d) => d.id == _deptId)
                          ? _deptId
                          : null,
                      items: docs
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.id,
                              child: Text(
                                churchDepartmentNameFromData(d.data(), docId: d.id),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _deptId = v),
                    );
                  },
                ),
              ],
              if (_segment == 'cargo') ...[
                const SizedBox(height: 16),
                FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: cargosRef.get().then((s) {
                    final l = s.docs.toList()
                      ..sort(
                        (a, b) => (a.data()['name'] ?? a.id)
                            .toString()
                            .toLowerCase()
                            .compareTo((b.data()['name'] ?? b.id).toString().toLowerCase()),
                      );
                    return l;
                  }),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ));
                    }
                    final docs = snap.data!;
                    return DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Cargo (como no cadastro)',
                        border: OutlineInputBorder(),
                      ),
                      value: _cargoName != null &&
                              docs.any((d) => (d.data()['name'] ?? '').toString() == _cargoName)
                          ? _cargoName
                          : null,
                      items: docs
                          .map(
                            (d) => DropdownMenuItem(
                              value: (d.data()['name'] ?? '').toString(),
                              child: Text(
                                (d.data()['name'] ?? d.id).toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _cargoName = v),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'O app inscreve o membro em cargo_${FcmService.slugTopicPart(_cargoName ?? 'exemplo')} conforme o campo CARGO da ficha.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mensagem',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_sending ? 'Enviando…' : 'Enviar notificação'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _infoCard(
          'Lembrete de escala',
          'Por volta das 8h15 (horário de Brasília), o sistema envia push no dia anterior '
          'à escala para quem tem FCM token e está em memberCpfs. Ajuste o horário do culto no cadastro da escala.',
        ),
        const SizedBox(height: 12),
        _infoCard(
          'Devocional',
          'Configure na aba ao lado. O envio ocorre no horário escolhido (uma vez por dia) para o tópico da igreja.',
        ),
      ],
    );
  }

  Widget _infoCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35)),
        ],
      ),
    );
  }
}

class _DevocionalTab extends StatefulWidget {
  final String tenantId;
  const _DevocionalTab({required this.tenantId});

  @override
  State<_DevocionalTab> createState() => _DevocionalTabState();
}

class _DevocionalTabState extends State<_DevocionalTab> {
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  bool _enabled = false;
  int _hora = 7;
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _cfgRef => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('config')
      .doc('comunicacao');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await _cfgRef.get();
    final d = snap.data() ?? {};
    _tituloCtrl.text = (d['devocionalTitulo'] ?? 'Bom dia').toString();
    _textoCtrl.text = (d['devocionalTexto'] ?? '').toString();
    _refCtrl.text = (d['devocionalReferencia'] ?? '').toString();
    _enabled = d['devocionalEnabled'] == true;
    final h = d['devocionalHora'];
    if (h is int && h >= 0 && h <= 23) _hora = h;
    if (h is num) _hora = h.toInt().clamp(0, 23);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _cfgRef.set({
        'devocionalEnabled': _enabled,
        'devocionalTitulo': _tituloCtrl.text.trim().isEmpty ? 'Bom dia' : _tituloCtrl.text.trim(),
        'devocionalTexto': _textoCtrl.text.trim(),
        'devocionalReferencia': _refCtrl.text.trim(),
        'devocionalHora': _hora,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Devocional salvo. O Cloud Function envia no horário configurado.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: ThemeCleanPremium.pagePadding(context),
      children: [
        Text(
          'Devocional diário',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativar envio automático'),
                subtitle: const Text('Push para o tópico da igreja (igreja_ID), uma vez por dia.'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Hora (Brasília)',
                  border: OutlineInputBorder(),
                ),
                value: _hora,
                items: List.generate(
                  24,
                  (i) => DropdownMenuItem(value: i, child: Text('${i.toString().padLeft(2, '0')}:00')),
                ),
                onChanged: (v) => setState(() => _hora = v ?? 7),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tituloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título da notificação',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textoCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Mensagem / versículo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Referência bíblica (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EvasaoRow {
  final String memberId;
  final String nome;
  final int days;
  final DateTime? lastPresent;

  _EvasaoRow({
    required this.memberId,
    required this.nome,
    required this.days,
    this.lastPresent,
  });
}

class _EvasaoTab extends StatefulWidget {
  final String tenantId;
  const _EvasaoTab({required this.tenantId});

  @override
  State<_EvasaoTab> createState() => _EvasaoTabState();
}

class _EvasaoTabState extends State<_EvasaoTab> {
  static const int diasAlerta = 21;
  late Future<List<_EvasaoRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_EvasaoRow>> _load() async {
    final membros = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
        .get();

    final cultos = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('cultos')
        .orderBy('data', descending: true)
        .limit(40)
        .get();

    final lastPresent = <String, DateTime>{};

    for (final c in cultos.docs) {
      final raw = c.data()['data'];
      DateTime? cultoDate;
      if (raw is Timestamp) cultoDate = raw.toDate();
      if (cultoDate == null) continue;

      final pres = await c.reference.collection('presencas').where('presente', isEqualTo: true).get();
      for (final p in pres.docs) {
        final mid = (p.data()['membroId'] ?? p.id).toString();
        final prev = lastPresent[mid];
        if (prev == null || cultoDate.isAfter(prev)) {
          lastPresent[mid] = cultoDate;
        }
      }
    }

    final now = DateTime.now();
    final rows = <_EvasaoRow>[];
    for (final m in membros.docs) {
      final st = (m.data()['STATUS'] ?? m.data()['status'] ?? 'ativo').toString().toLowerCase();
      if (st.contains('inativ') || st.contains('reprov') || st.contains('pendente')) continue;
      final nome = (m.data()['NOME_COMPLETO'] ?? m.data()['nome'] ?? m.id).toString();
      final last = lastPresent[m.id];
      final days = last == null ? 9999 : now.difference(last).inDays;
      if (days >= diasAlerta) {
        rows.add(_EvasaoRow(memberId: m.id, nome: nome, days: days, lastPresent: last));
      }
    }
    rows.sort((a, b) => b.days.compareTo(a.days));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _future = _load());
        await _future;
      },
      child: FutureBuilder<List<_EvasaoRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              padding: ThemeCleanPremium.pagePadding(context),
              children: [
                Text('Erro: ${snap.error}', style: TextStyle(color: ThemeCleanPremium.error)),
              ],
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          return ListView(
            padding: ThemeCleanPremium.pagePadding(context),
            children: [
              Text(
                'Alerta de evasão',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 8),
              Text(
                'Com base em presenças registradas em cultos/eventos (últimos registros analisados). '
                'Quem não comparece há $diasAlerta dias ou mais aparece abaixo — útil para visita ou ligação.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Nenhum membro ativo nessa faixa de ausência (ou ainda não há presenças lançadas).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else
                ...rows.map((r) {
                  final sub = r.lastPresent == null
                      ? 'Sem presença registrada nos cultos consultados'
                      : 'Última presença: ${_fmt(r.lastPresent!)}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.orange.shade50,
                            child: Text(
                              '${r.days >= 9999 ? '—' : r.days}d',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                const SizedBox(height: 4),
                                Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  String _fmt(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}
