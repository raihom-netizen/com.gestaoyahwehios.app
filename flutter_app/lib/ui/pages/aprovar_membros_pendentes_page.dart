import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';
import 'package:intl/intl.dart';

class AprovarMembrosPendentesPage extends StatefulWidget {
  final String tenantId;
  final String gestorRole;
  /// No [IgrejaCleanShell] o [ModuleHeaderPremium] já traz título e voltar — evita AppBar azul alto duplicado.
  final bool embeddedInShell;

  const AprovarMembrosPendentesPage({
    super.key,
    required this.tenantId,
    required this.gestorRole,
    this.embeddedInShell = false,
  });

  @override
  State<AprovarMembrosPendentesPage> createState() =>
      _AprovarMembrosPendentesPageState();
}

class _AprovarMembrosPendentesPageState extends State<AprovarMembrosPendentesPage>
    with SingleTickerProviderStateMixin {
  late final CollectionReference<Map<String, dynamic>> _membersCol;
  final Set<String> _selecionados = {};
  Map<String, String>? _tenantLinkageCache;
  int _pendentesStreamKey = 0;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _membersCol = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros');
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _getTenantLinkage() async {
    if (_tenantLinkageCache != null) return _tenantLinkageCache!;
    final snap =
        await FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).get();
    final d = snap.data();
    final id = snap.id;
    final alias = (d?['alias'] ?? d?['slug'] ?? id).toString().trim();
    final slug = (d?['slug'] ?? d?['alias'] ?? id).toString().trim();
    _tenantLinkageCache = {
      'alias': alias.isEmpty ? id : alias,
      'slug': slug.isEmpty ? id : slug,
    };
    return _tenantLinkageCache!;
  }

  Future<void> _editarStatus(String id, String newStatus) async {
    final linkage = await _getTenantLinkage();
    await _membersCol.doc(id).update({
      'alias': linkage['alias'],
      'slug': linkage['slug'],
      'tenantId': widget.tenantId,
      'status': newStatus,
      'STATUS': newStatus,
      if (newStatus == 'ativo') 'aprovadoEm': FieldValue.serverTimestamp(),
      if (newStatus == 'reprovado') 'reprovadoEm': FieldValue.serverTimestamp(),
    });
    if (newStatus == 'ativo') {
      try {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('setMemberApproved')
            .call({'tenantId': widget.tenantId, 'memberId': id});
      } catch (_) {}
    }
    setState(() => _selecionados.remove(id));
  }

  Future<void> _batchAction(String newStatus) async {
    if (_selecionados.isEmpty) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final linkage = await _getTenantLinkage();
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selecionados) {
      batch.update(_membersCol.doc(id), {
        'alias': linkage['alias'],
        'slug': linkage['slug'],
        'tenantId': widget.tenantId,
        'status': newStatus,
        'STATUS': newStatus,
        if (newStatus == 'ativo') 'aprovadoEm': FieldValue.serverTimestamp(),
        if (newStatus == 'reprovado') 'reprovadoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (newStatus == 'ativo') {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      for (final id in _selecionados) {
        try {
          await functions
              .httpsCallable('setMemberApproved')
              .call({'tenantId': widget.tenantId, 'memberId': id});
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar(
          '${_selecionados.length} membro(s) ${newStatus == 'ativo' ? 'aprovado(s)' : 'reprovado(s)'}.'));
      setState(() => _selecionados.clear());
    }
  }

  Future<void> _aprovarTodos(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (docs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Aprovar todos'),
        content: Text('Deseja aprovar os ${docs.length} membro(s) pendente(s)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar todos')),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    final linkage = await _getTenantLinkage();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in docs) {
      batch.update(_membersCol.doc(d.id), {
        'alias': linkage['alias'],
        'slug': linkage['slug'],
        'tenantId': widget.tenantId,
        'status': 'ativo',
        'STATUS': 'ativo',
        'aprovadoEm': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    for (final d in docs) {
      try {
        await functions
            .httpsCallable('setMemberApproved')
            .call({'tenantId': widget.tenantId, 'memberId': d.id});
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('${docs.length} membro(s) aprovado(s)!'));
      setState(() => _selecionados.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    if (!AppPermissions.canEditDepartments(widget.gestorRole)) {
      return const Scaffold(body: Center(child: Text('Acesso restrito.')));
    }
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: null,
      body: SafeArea(
        top: !widget.embeddedInShell,
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPremiumTabsStrip(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildPendentesTab(isMobile),
                  _ApprovalHistoryPanel(membersCol: _membersCol),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Faixa compacta (gradiente + sombra) — substitui AppBar+TabBar que ocupava ~¼ da tela.
  Widget _buildPremiumTabsStrip() {
    final pad = ThemeCleanPremium.pagePadding(context);
    final topGap = widget.embeddedInShell ? 2.0 : 6.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad.left, topGap, pad.right, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ThemeCleanPremium.primary,
              Color.lerp(ThemeCleanPremium.primary, const Color(0xFF1D4ED8), 0.35)!,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            ...ThemeCleanPremium.softUiCardShadow,
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            if (!widget.embeddedInShell)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                tooltip: 'Voltar',
                onPressed: () => Navigator.maybePop(context),
                style: IconButton.styleFrom(
                  minimumSize: const Size(
                    ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _premiumSegTab(
                      label: 'Pendentes',
                      icon: Icons.pending_actions_rounded,
                      selected: _tabCtrl.index == 0,
                      onTap: () => _tabCtrl.animateTo(0),
                    ),
                  ),
                  Expanded(
                    child: _premiumSegTab(
                      label: 'Histórico',
                      icon: Icons.history_rounded,
                      selected: _tabCtrl.index == 1,
                      onTap: () => _tabCtrl.animateTo(1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumSegTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.white.withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendentesTab(bool isMobile) {
    return Column(
      children: [
        if (_selecionados.isNotEmpty)
          Container(
            color: ThemeCleanPremium.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('${_selecionados.length} selecionado(s)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                  onPressed: () => _batchAction('ativo'),
                  tooltip: 'Aprovar',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                  onPressed: () => _batchAction('reprovado'),
                  tooltip: 'Reprovar',
                  style: IconButton.styleFrom(
                      minimumSize: const Size(
                          ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            key: ValueKey('pendentes_$_pendentesStreamKey'),
            stream: _membersCol.where('status', isEqualTo: 'pendente').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: ThemeCleanPremium.pagePadding(context),
                  child: ChurchPanelErrorBody(
                    title: 'Não foi possível carregar os membros pendentes',
                    error: snap.error,
                    onRetry: () => setState(() => _pendentesStreamKey++),
                  ),
                );
              }
              final docs = snap.data?.docs ?? [];
              final isLoading =
                  snap.connectionState == ConnectionState.waiting && !snap.hasData;
              if (isLoading) {
                return const ChurchPanelLoadingBody();
              }
              if (docs.isEmpty) {
                return CustomScrollView(
                  primary: false,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _PremiumEmptyPendentes(onOpenHistorico: () => _tabCtrl.animateTo(1)),
                    ),
                  ],
                );
              }
              return ListView(
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: ThemeCleanPremium.pagePadding(context),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            ThemeCleanPremium.success,
                            Color.lerp(ThemeCleanPremium.success, Colors.white, 0.15)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: [
                          BoxShadow(
                            color: ThemeCleanPremium.success.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          onTap: () => _aprovarTodos(docs),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  'Aprovar todos (${docs.length})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(docs.length, (i) {
                    final d = docs[i];
                    final data = d.data();
                    final nome =
                        (data['NOME_COMPLETO'] ?? data['nome'] ?? 'Membro').toString();
                    final email = (data['EMAIL'] ?? data['email'] ?? '').toString();
                    final foto = _photoUrlFromData(data);
                    final hasFoto = foto.isNotEmpty;
                    final sel = _selecionados.contains(d.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            ThemeCleanPremium.primary.withValues(alpha: 0.03),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(
                          color: sel
                              ? ThemeCleanPremium.primary.withValues(alpha: 0.35)
                              : const Color(0xFFE8EEF4),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          onTap: () => setState(() {
                            if (sel) {
                              _selecionados.remove(d.id);
                            } else {
                              _selecionados.add(d.id);
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: sel,
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _selecionados.add(d.id);
                                    } else {
                                      _selecionados.remove(d.id);
                                    }
                                  }),
                                ),
                                const SizedBox(width: 8),
                                ClipOval(
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: hasFoto
                                        ? SafeNetworkImage(
                                            imageUrl: foto,
                                            fit: BoxFit.cover,
                                            placeholder: _avatarPlaceholder(nome),
                                            errorWidget: _avatarPlaceholder(nome),
                                          )
                                        : _avatarPlaceholder(nome),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                      Text(nome,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 14)),
                                      if (email.isNotEmpty)
                                        Text(email,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600)),
                                    ])),
                                IconButton(
                                  icon: const Icon(Icons.check_rounded,
                                      color: ThemeCleanPremium.success),
                                  onPressed: () => _editarStatus(d.id, 'ativo'),
                                  tooltip: 'Aprovar',
                                  style: IconButton.styleFrom(
                                      minimumSize: const Size(
                                          ThemeCleanPremium.minTouchTarget,
                                          ThemeCleanPremium.minTouchTarget)),
                                ),
                                IconButton(
                                  icon: Icon(Icons.close_rounded, color: Colors.red.shade400),
                                  onPressed: () => _editarStatus(d.id, 'reprovado'),
                                  tooltip: 'Reprovar',
                                  style: IconButton.styleFrom(
                                      minimumSize: const Size(
                                          ThemeCleanPremium.minTouchTarget,
                                          ThemeCleanPremium.minTouchTarget)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _avatarPlaceholder(String nome) {
    return Container(
      color: Colors.grey.shade400,
      alignment: Alignment.center,
      child: Text(
        nome.isNotEmpty ? nome[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }

  static String _photoUrlFromData(Map<String, dynamic> data) => imageUrlFromMap(data);
}

// ── Empty state premium ─────────────────────────────────────────────────────

class _PremiumEmptyPendentes extends StatelessWidget {
  final VoidCallback onOpenHistorico;

  const _PremiumEmptyPendentes({required this.onOpenHistorico});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  ThemeCleanPremium.success.withValues(alpha: 0.2),
                  ThemeCleanPremium.success.withValues(alpha: 0.05),
                ],
              ),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Icon(Icons.check_circle_rounded, size: 72, color: ThemeCleanPremium.success),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhum membro pendente!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ThemeCleanPremium.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Todos os cadastros foram aprovados ou não há solicitações.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.35, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onOpenHistorico,
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Ver histórico e gráficos'),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Histórico + filtros + gráficos ──────────────────────────────────────────

enum _HistoryPreset { mesAtual, trimestre, ultimos90, ano, periodo }

class _ApprovalHistoryPanel extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> membersCol;

  const _ApprovalHistoryPanel({required this.membersCol});

  @override
  State<_ApprovalHistoryPanel> createState() => _ApprovalHistoryPanelState();
}

class _ApprovalHistoryPanelState extends State<_ApprovalHistoryPanel> {
  _HistoryPreset _preset = _HistoryPreset.mesAtual;
  int _yearFilter = DateTime.now().year;
  DateTime? _customStart;
  DateTime? _customEnd;
  int _loadKey = 0;
  late final TextEditingController _periodoInicioCtrl;
  late final TextEditingController _periodoFimCtrl;

  @override
  void initState() {
    super.initState();
    _periodoInicioCtrl = TextEditingController();
    _periodoFimCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _periodoInicioCtrl.dispose();
    _periodoFimCtrl.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _effectiveRange {
    final now = DateTime.now();
    switch (_preset) {
      case _HistoryPreset.mesAtual:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      case _HistoryPreset.trimestre:
        final sm = ((now.month - 1) ~/ 3) * 3 + 1;
        return (
          DateTime(now.year, sm, 1),
          DateTime(now.year, sm + 3, 0, 23, 59, 59),
        );
      case _HistoryPreset.ultimos90:
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (end.subtract(const Duration(days: 90)), end);
      case _HistoryPreset.ano:
        return (
          DateTime(_yearFilter, 1, 1),
          DateTime(_yearFilter, 12, 31, 23, 59, 59),
        );
      case _HistoryPreset.periodo:
        final a = _customStart ?? now.subtract(const Duration(days: 30));
        final b = _customEnd ?? now;
        var start = DateTime(a.year, a.month, a.day);
        var end = DateTime(b.year, b.month, b.day, 23, 59, 59);
        if (start.isAfter(end)) {
          final t = start;
          start = DateTime(end.year, end.month, end.day);
          end = DateTime(t.year, t.month, t.day, 23, 59, 59);
        }
        return (start, end);
    }
  }

  Future<_HistoryData> _loadHistorico() async {
    final range = _effectiveRange;
    final t0 = Timestamp.fromDate(range.$1);
    final t1 = Timestamp.fromDate(range.$2);

    final approved = await widget.membersCol
        .where('status', isEqualTo: 'ativo')
        .where('aprovadoEm', isGreaterThanOrEqualTo: t0)
        .where('aprovadoEm', isLessThanOrEqualTo: t1)
        .orderBy('aprovadoEm', descending: true)
        .limit(800)
        .get();

    final rejected = await widget.membersCol
        .where('status', isEqualTo: 'reprovado')
        .where('reprovadoEm', isGreaterThanOrEqualTo: t0)
        .where('reprovadoEm', isLessThanOrEqualTo: t1)
        .orderBy('reprovadoEm', descending: true)
        .limit(800)
        .get();

    return _HistoryData.fromSnapshots(range.$1, range.$2, approved, rejected);
  }

  void _selecionarPresetPeriodo() {
    if (_preset == _HistoryPreset.periodo) return;
    final r = _effectiveRange;
    setState(() {
      _preset = _HistoryPreset.periodo;
      _customStart = DateTime(r.$1.year, r.$1.month, r.$1.day);
      _customEnd = DateTime(r.$2.year, r.$2.month, r.$2.day);
      _periodoInicioCtrl.text = formatBrDateDdMmYyyy(_customStart!);
      _periodoFimCtrl.text = formatBrDateDdMmYyyy(
        DateTime(_customEnd!.year, _customEnd!.month, _customEnd!.day),
      );
      _loadKey++;
    });
  }

  void _aplicarPeriodoDigitado() {
    final di = parseBrDateDdMmYyyy(_periodoInicioCtrl.text);
    final df = parseBrDateDdMmYyyy(_periodoFimCtrl.text);
    if (di == null || df == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Use datas válidas no formato DD/MM/AAAA (ex.: 01/01/2026).',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
          ),
        ),
      );
      return;
    }
    var start = DateTime(di.year, di.month, di.day);
    var endDay = DateTime(df.year, df.month, df.day);
    if (start.isAfter(endDay)) {
      final t = start;
      start = endDay;
      endDay = t;
    }
    setState(() {
      _preset = _HistoryPreset.periodo;
      _customStart = start;
      _customEnd = endDay;
      _periodoInicioCtrl.text = formatBrDateDdMmYyyy(start);
      _periodoFimCtrl.text = formatBrDateDdMmYyyy(endDay);
      _loadKey++;
    });
  }

  Future<void> _abrirCalendarioPeriodo() async {
    final now = DateTime.now();
    final initialEnd = _customEnd ?? now;
    final initialStart = _customStart ?? now.subtract(const Duration(days: 30));
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
              ),
            ),
            colorScheme: ColorScheme.light(
              primary: ThemeCleanPremium.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: ThemeCleanPremium.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _preset = _HistoryPreset.periodo;
      _customStart = range.start;
      _customEnd = range.end;
      _periodoInicioCtrl.text = formatBrDateDdMmYyyy(
        DateTime(range.start.year, range.start.month, range.start.day),
      );
      _periodoFimCtrl.text = formatBrDateDdMmYyyy(
        DateTime(range.end.year, range.end.month, range.end.day),
      );
      _loadKey++;
    });
  }

  String _presetBadgeLabel() {
    switch (_preset) {
      case _HistoryPreset.mesAtual:
        return 'Mês atual';
      case _HistoryPreset.trimestre:
        return 'Trimestre';
      case _HistoryPreset.ultimos90:
        return '90 dias';
      case _HistoryPreset.ano:
        return 'Ano $_yearFilter';
      case _HistoryPreset.periodo:
        return 'Personalizado';
    }
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        ThemeCleanPremium.primary,
                        Color.lerp(
                                ThemeCleanPremium.primary,
                                const Color(0xFF1D4ED8),
                                0.35) ??
                            ThemeCleanPremium.primary,
                      ],
                    )
                  : null,
              color: selected ? null : Colors.white,
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.35)
                    : const Color(0xFFE2E8F4),
                width: selected ? 1.2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? Colors.white : ThemeCleanPremium.primary,
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.15,
                    color:
                        selected ? Colors.white : ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _effectiveRange;
    final periodoLabel =
        '${DateFormat('dd/MM/yyyy').format(range.$1)} — ${DateFormat('dd/MM/yyyy').format(range.$2)}';

    return FutureBuilder<_HistoryData>(
      key: ValueKey(_loadKey),
      future: _loadHistorico(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: ThemeCleanPremium.pagePadding(context),
            child: ChurchPanelErrorBody(
              title: 'Não foi possível carregar o histórico',
              error: snap.error,
              onRetry: () => setState(() => _loadKey++),
            ),
          );
        }
        if (!snap.hasData) {
          return const ChurchPanelLoadingBody();
        }
        final data = snap.data!;

        return Padding(
          padding: ThemeCleanPremium.pagePadding(context).copyWith(bottom: 32),
          child: CustomScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      ThemeCleanPremium.primary.withValues(alpha: 0.06),
                      const Color(0xFFF8FAFC),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    ...ThemeCleanPremium.softUiCardShadow,
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                ThemeCleanPremium.primary.withValues(alpha: 0.14),
                                ThemeCleanPremium.primary.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(Icons.date_range_rounded,
                              color: ThemeCleanPremium.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Filtros por período',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  letterSpacing: -0.35,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Linha do tempo, gráficos e totais seguem o intervalo abaixo.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            ThemeCleanPremium.primary.withValues(alpha: 0.07),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.07),
                            blurRadius: 16,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.event_available_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Período ativo',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  periodoLabel,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              _presetBadgeLabel(),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: ThemeCleanPremium.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      children: [
                        _filterChip(
                          label: 'Mês atual',
                          selected: _preset == _HistoryPreset.mesAtual,
                          icon: Icons.calendar_month_rounded,
                          onTap: () => setState(() {
                            _preset = _HistoryPreset.mesAtual;
                            _loadKey++;
                          }),
                        ),
                        _filterChip(
                          label: 'Trimestre',
                          selected: _preset == _HistoryPreset.trimestre,
                          icon: Icons.date_range_rounded,
                          onTap: () => setState(() {
                            _preset = _HistoryPreset.trimestre;
                            _loadKey++;
                          }),
                        ),
                        _filterChip(
                          label: '90 dias',
                          selected: _preset == _HistoryPreset.ultimos90,
                          icon: Icons.timelapse_rounded,
                          onTap: () => setState(() {
                            _preset = _HistoryPreset.ultimos90;
                            _loadKey++;
                          }),
                        ),
                        _filterChip(
                          label: 'Ano',
                          selected: _preset == _HistoryPreset.ano,
                          icon: Icons.calendar_view_month_rounded,
                          onTap: () => setState(() {
                            _preset = _HistoryPreset.ano;
                            _yearFilter = DateTime.now().year;
                            _loadKey++;
                          }),
                        ),
                        _filterChip(
                          label: 'Período…',
                          selected: _preset == _HistoryPreset.periodo,
                          icon: Icons.edit_calendar_rounded,
                          onTap: _selecionarPresetPeriodo,
                        ),
                      ],
                    ),
                    if (_preset == _HistoryPreset.ano) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F4)),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_view_month_rounded,
                                color: ThemeCleanPremium.primary, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              'Ano civil',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F4)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _yearFilter,
                                      items: List.generate(6, (i) {
                                        final y = DateTime.now().year - i;
                                        return DropdownMenuItem(
                                            value: y, child: Text('$y'));
                                      }),
                                      onChanged: (y) {
                                        if (y == null) return;
                                        setState(() {
                                          _yearFilter = y;
                                          _preset = _HistoryPreset.ano;
                                          _loadKey++;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_preset == _HistoryPreset.periodo) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              ThemeCleanPremium.primary.withValues(alpha: 0.1),
                              Colors.white,
                              const Color(0xFFF8FAFC),
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          border: Border.all(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Icon(Icons.draw_rounded,
                                      color: ThemeCleanPremium.primary, size: 22),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Intervalo personalizado',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Digite as datas ou escolha no calendário. O resumo acima atualiza ao aplicar.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _abrirCalendarioPeriodo,
                                icon: Icon(Icons.calendar_month_rounded,
                                    size: 20,
                                    color: ThemeCleanPremium.primary),
                                label: Text(
                                  'Escolher no calendário',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ThemeCleanPremium.primary,
                                  side: BorderSide(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.45),
                                    width: 1.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, c) {
                                final narrow = c.maxWidth < 420;
                                final fieldDec = InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  labelText: 'Data inicial',
                                  hintText: 'DD/MM/AAAA',
                                  prefixIcon: Icon(Icons.flag_outlined,
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.85),
                                      size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: ThemeCleanPremium.primary,
                                      width: 1.6,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                );
                                final fieldDecFim = fieldDec.copyWith(
                                  labelText: 'Data final',
                                  prefixIcon: Icon(Icons.flag_rounded,
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.85),
                                      size: 20),
                                );
                                final inicio = TextField(
                                  controller: _periodoInicioCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    BrDateDdMmYyyyInputFormatter(),
                                  ],
                                  decoration: fieldDec,
                                  onSubmitted: (_) => _aplicarPeriodoDigitado(),
                                );
                                final fim = TextField(
                                  controller: _periodoFimCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    BrDateDdMmYyyyInputFormatter(),
                                  ],
                                  decoration: fieldDecFim,
                                  onSubmitted: (_) => _aplicarPeriodoDigitado(),
                                );
                                Widget connector({required bool vertical}) {
                                  final icon = Icon(
                                    vertical
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_forward_rounded,
                                    size: 20,
                                    color: ThemeCleanPremium.primary,
                                  );
                                  return Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.08),
                                      border: Border.all(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: icon,
                                  );
                                }
                                if (narrow) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      inicio,
                                      const SizedBox(height: 10),
                                      Center(child: connector(vertical: true)),
                                      const SizedBox(height: 10),
                                      fim,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(child: inicio),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      child: connector(vertical: false),
                                    ),
                                    Expanded(child: fim),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Formato DD/MM/AAAA com máscara. Enter em qualquer campo também aplica.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _aplicarPeriodoDigitado,
                                borderRadius: BorderRadius.circular(14),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        ThemeCleanPremium.primary,
                                        Color.lerp(
                                                ThemeCleanPremium.primary,
                                                const Color(0xFF1E40AF),
                                                0.25) ??
                                            ThemeCleanPremium.primary,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 18,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.check_circle_rounded,
                                            color: Colors.white, size: 22),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Aplicar período',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15.5,
                                            letterSpacing: -0.1,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: ThemeCleanPremium.spaceMd)),
            SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryPremiumCard(
                      icon: Icons.verified_rounded,
                      title: 'Aprovados',
                      value: '${data.aprovados}',
                      color: ThemeCleanPremium.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryPremiumCard(
                      icon: Icons.cancel_outlined,
                      title: 'Reprovados',
                      value: '${data.reprovados}',
                      color: ThemeCleanPremium.error,
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: ThemeCleanPremium.spaceMd)),
            if (data.totalEventos > 0) ...[
              SliverToBoxAdapter(child: _PieDistribuicao(data: data)),
              SliverToBoxAdapter(child: SizedBox(height: ThemeCleanPremium.spaceMd)),
              SliverToBoxAdapter(child: _BarMensalChart(data: data)),
              SliverToBoxAdapter(child: SizedBox(height: ThemeCleanPremium.spaceMd)),
            ],
            SliverToBoxAdapter(
              child: Row(
                children: [
                  Icon(Icons.list_alt_rounded, color: ThemeCleanPremium.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Linha do tempo (${data.events.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            if (data.events.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(color: const Color(0xFFE8EEF4)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Sem registros neste período',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Aprovações e reprovações passam a aparecer aqui quando os campos aprovadoEm / reprovadoEm forem gravados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.35),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final e = data.events[i];
                    return _HistoricoTile(event: e);
                  },
                  childCount: data.events.length,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryData {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int aprovados;
  final int reprovados;
  final List<_HistoryEvent> events;
  final List<String> monthKeysOrdered;
  final Map<String, int> aprovadosPorMes;
  final Map<String, int> reprovadosPorMes;

  _HistoryData({
    required this.rangeStart,
    required this.rangeEnd,
    required this.aprovados,
    required this.reprovados,
    required this.events,
    required this.monthKeysOrdered,
    required this.aprovadosPorMes,
    required this.reprovadosPorMes,
  });

  int get totalEventos => aprovados + reprovados;

  static _HistoryData fromSnapshots(
    DateTime rangeStart,
    DateTime rangeEnd,
    QuerySnapshot<Map<String, dynamic>> approvedSnap,
    QuerySnapshot<Map<String, dynamic>> rejectedSnap,
  ) {
    final events = <_HistoryEvent>[];
    final aprovadosPorMes = <String, int>{};
    final reprovadosPorMes = <String, int>{};

    String monthKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

    for (final d in approvedSnap.docs) {
      final m = d.data();
      final ts = m['aprovadoEm'];
      DateTime? when;
      if (ts is Timestamp) when = ts.toDate();
      if (when == null) continue;
      final mk = monthKey(when);
      aprovadosPorMes[mk] = (aprovadosPorMes[mk] ?? 0) + 1;
      final nome = (m['NOME_COMPLETO'] ?? m['nome'] ?? 'Membro').toString();
      events.add(_HistoryEvent(
        when: when,
        nome: nome,
        aprovado: true,
        docId: d.id,
      ));
    }

    for (final d in rejectedSnap.docs) {
      final m = d.data();
      final ts = m['reprovadoEm'];
      DateTime? when;
      if (ts is Timestamp) when = ts.toDate();
      if (when == null) continue;
      final mk = monthKey(when);
      reprovadosPorMes[mk] = (reprovadosPorMes[mk] ?? 0) + 1;
      final nome = (m['NOME_COMPLETO'] ?? m['nome'] ?? 'Membro').toString();
      events.add(_HistoryEvent(
        when: when,
        nome: nome,
        aprovado: false,
        docId: d.id,
      ));
    }

    events.sort((a, b) => b.when.compareTo(a.when));

    final monthSet = <String>{...aprovadosPorMes.keys, ...reprovadosPorMes.keys};
    var cursor = DateTime(rangeStart.year, rangeStart.month, 1);
    final endM = DateTime(rangeEnd.year, rangeEnd.month, 1);
    while (!cursor.isAfter(endM)) {
      final k =
          '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}';
      monthSet.add(k);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    final monthKeysOrdered = monthSet.toList()..sort();

    return _HistoryData(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      aprovados: approvedSnap.docs.length,
      reprovados: rejectedSnap.docs.length,
      events: events,
      monthKeysOrdered: monthKeysOrdered,
      aprovadosPorMes: aprovadosPorMes,
      reprovadosPorMes: reprovadosPorMes,
    );
  }
}

class _HistoryEvent {
  final DateTime when;
  final String nome;
  final bool aprovado;
  final String docId;

  _HistoryEvent({
    required this.when,
    required this.nome,
    required this.aprovado,
    required this.docId,
  });
}

class _SummaryPremiumCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _SummaryPremiumCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE8EEF4)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _PieDistribuicao extends StatelessWidget {
  final _HistoryData data;

  const _PieDistribuicao({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.aprovados + data.reprovados;
    if (total == 0) return const SizedBox.shrink();

    final sections = <PieChartSectionData>[];
    if (data.aprovados > 0) {
      final pct = (data.aprovados / total * 100);
      sections.add(PieChartSectionData(
        value: data.aprovados.toDouble(),
        title: '${pct.toStringAsFixed(0)}%',
        color: ThemeCleanPremium.success,
        radius: 54,
        titleStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
      ));
    }
    if (data.reprovados > 0) {
      final pct = (data.reprovados / total * 100);
      sections.add(PieChartSectionData(
        value: data.reprovados.toDouble(),
        title: '${pct.toStringAsFixed(0)}%',
        color: ThemeCleanPremium.error,
        radius: 54,
        titleStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribuição no período',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Aprovados vs reprovados',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 36,
                      sections: sections,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _legendRow(ThemeCleanPremium.success, 'Aprovados', data.aprovados),
                      const SizedBox(height: 10),
                      _legendRow(ThemeCleanPremium.error, 'Reprovados', data.reprovados),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color c, String label, int n) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label ($n)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _BarMensalChart extends StatelessWidget {
  final _HistoryData data;

  const _BarMensalChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.monthKeysOrdered.isEmpty) return const SizedBox.shrink();

    final groups = <BarChartGroupData>[];
    double maxY = 1;
    for (var i = 0; i < data.monthKeysOrdered.length; i++) {
      final k = data.monthKeysOrdered[i];
      final a = data.aprovadosPorMes[k] ?? 0;
      final r = data.reprovadosPorMes[k] ?? 0;
      if (a > maxY) maxY = a.toDouble();
      if (r > maxY) maxY = r.toDouble();
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: a.toDouble(),
            color: ThemeCleanPremium.success,
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          BarChartRodData(
            toY: r.toDouble(),
            color: ThemeCleanPremium.error,
            width: 10,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
        barsSpace: 4,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Por mês',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Barras verdes: aprovados · vermelhas: reprovados',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY + 2,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= data.monthKeysOrdered.length) {
                          return const SizedBox.shrink();
                        }
                        final parts = data.monthKeysOrdered[i].split('-');
                        if (parts.length != 2) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${parts[1]}/${parts[0].substring(2)}',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble() && value >= 0) {
                          return Text('${value.toInt()}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: groups,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoricoTile extends StatelessWidget {
  final _HistoryEvent event;

  const _HistoricoTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final cor = event.aprovado ? ThemeCleanPremium.success : ThemeCleanPremium.error;
    final rotulo = event.aprovado ? 'Aprovado' : 'Reprovado';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              event.aprovado ? Icons.verified_rounded : Icons.highlight_off_rounded,
              color: cor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.nome,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$rotulo · ${DateFormat('dd/MM/yyyy HH:mm').format(event.when)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
