import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';
import 'package:intl/intl.dart';

InputDecoration _pastoralInputDecoration(
  String label, {
  IconData? icon,
  int maxLines = 1,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
  );
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: maxLines > 1,
    prefixIcon: icon != null ? Icon(icon, size: 22) : null,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide:
          BorderSide(color: ThemeCleanPremium.primary.withValues(alpha: 0.85), width: 1.5),
    ),
  );
}

/// Filtro de data no histórico (push / devocional).
enum _PastoralDateFilterKind { none, day, month, range }

EdgeInsets _pastoralFullBleedPadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final hx = w >= 1400 ? 32.0 : (w >= 1000 ? 26.0 : (w >= 600 ? 20.0 : 14.0));
  return EdgeInsets.fromLTRB(hx, 12, hx, 28);
}

/// Barra de pesquisa + chips de período (evita duplicar UI entre abas).
class _PastoralHistoryFilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String searchHint;
  final _PastoralDateFilterKind kind;
  final ValueChanged<_PastoralDateFilterKind> onKindChanged;
  final VoidCallback onPickDay;
  final VoidCallback onPickMonth;
  final VoidCallback onPickRange;
  final String daySummary;
  final String monthSummary;
  final String rangeSummary;

  const _PastoralHistoryFilterBar({
    required this.searchCtrl,
    required this.searchHint,
    required this.kind,
    required this.onKindChanged,
    required this.onPickDay,
    required this.onPickMonth,
    required this.onPickRange,
    required this.daySummary,
    required this.monthSummary,
    required this.rangeSummary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.surface,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: searchCtrl,
            style: TextStyle(
              color: ThemeCleanPremium.onSurface,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: searchHint,
              hintStyle: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
              prefixIcon: Icon(Icons.search_rounded, color: ThemeCleanPremium.primary),
              filled: true,
              fillColor: ThemeCleanPremium.cardBackground,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                borderSide: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Período',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: kind == _PastoralDateFilterKind.none,
                onSelected: (_) => onKindChanged(_PastoralDateFilterKind.none),
                selectedColor: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kind == _PastoralDateFilterKind.none
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurface,
                ),
              ),
              ChoiceChip(
                label: Text(daySummary),
                selected: kind == _PastoralDateFilterKind.day,
                onSelected: (_) {
                  onKindChanged(_PastoralDateFilterKind.day);
                  onPickDay();
                },
                selectedColor: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kind == _PastoralDateFilterKind.day
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurface,
                ),
              ),
              ChoiceChip(
                label: Text(monthSummary),
                selected: kind == _PastoralDateFilterKind.month,
                onSelected: (_) {
                  onKindChanged(_PastoralDateFilterKind.month);
                  onPickMonth();
                },
                selectedColor: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kind == _PastoralDateFilterKind.month
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurface,
                ),
              ),
              ChoiceChip(
                label: Text(rangeSummary),
                selected: kind == _PastoralDateFilterKind.range,
                onSelected: (_) {
                  onKindChanged(_PastoralDateFilterKind.range);
                  onPickRange();
                },
                selectedColor: ThemeCleanPremium.primary.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: kind == _PastoralDateFilterKind.range
                      ? ThemeCleanPremium.primary
                      : ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Abas do cabeçalho — mesmo visual “pill” do Patrimônio ([ChurchPanelPillTabBar]).
class PastoralModuleTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;

  const PastoralModuleTabBar({super.key, required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ChurchPanelPillTabBar(
      controller: controller,
      tabs: const [
        Tab(text: 'Push'),
        Tab(text: 'Devocional'),
        Tab(text: 'Evasão'),
      ],
    );
  }
}

/// Fundo do painel premium por aba (conteúdo montado sob [IndexedStack], não [TabBarView]).
class _PastoralTabSurface extends StatelessWidget {
  final Widget child;

  const _PastoralTabSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ThemeCleanPremium.churchPanelBodyGradient,
      ),
      child: child,
    );
  }
}

/// Push segmentado (departamento / cargo / igreja), devocional diário (FCM agendado) e alerta de evasão (presenças).
class PastoralComunicacaoPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Dentro de [IgrejaCleanShell]: evita [SafeArea] superior extra entre o cartão do módulo e as abas.
  final bool embeddedInShell;

  const PastoralComunicacaoPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<PastoralComunicacaoPage> createState() => _PastoralComunicacaoPageState();
}

class _PastoralComunicacaoPageState extends State<PastoralComunicacaoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  /// Abas já montadas (lazy): evita [TabBarView]/PageView no Web — faixa cinza + gesto horizontal
  /// a competir com [ListView]; Devocional/Evasão só sob demanda.
  final Set<int> _tabsBuilt = {0};

  /// Mesmo ID canónico que Departamentos (`resolveChurchDocIdPreferringNonEmptyDepartments`):
  /// evita ler `pastoral_*` / `departamentos` no doc errado (slug vs doc irmão _sistema/_bpc).
  String _resolvedChurchDocId = '';

  void _onTabChanged() {
    if (!mounted) return;
    final i = _tab.index;
    if (!_tabsBuilt.contains(i)) {
      setState(() => _tabsBuilt.add(i));
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_onTabChanged);
    _resolveChurchDocId();
  }

  Future<void> _resolveChurchDocId() async {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return;
    try {
      final id = await TenantResolverService
          .resolveChurchDocIdPreferringNonEmptyDepartments(seed);
      if (!mounted) return;
      setState(() => _resolvedChurchDocId = id.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvedChurchDocId = seed);
    }
  }

  String get _effectiveChurchId {
    final r = _resolvedChurchDocId.trim();
    return r.isNotEmpty ? r : widget.tenantId.trim();
  }

  @override
  void didUpdateWidget(covariant PastoralComunicacaoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _resolvedChurchDocId = '';
      _tabsBuilt
        ..clear()
        ..add(0);
      _resolveChurchDocId();
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _showPastoralModuleHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: ThemeCleanPremium.primary),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pastoral & comunicação',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Push: envie avisos segmentados (igreja, departamentos, cargos ou membros) com FCM.\n\n'
            'Devocional: mensagem diária agendada para os dispositivos.\n\n'
            'Evasão: alertas com base em padrões de presença.\n\n'
            'O layout segue o mesmo padrão visual dos demais módulos do painel.',
            style: TextStyle(height: 1.4, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final iconBtnStyle = IconButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: ThemeCleanPremium.primary,
      elevation: 2,
      shadowColor: Colors.black26,
      minimumSize: const Size(
        ThemeCleanPremium.minTouchTarget,
        ThemeCleanPremium.minTouchTarget,
      ),
    );
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile
          ? null
          : AppBar(
              elevation: 0,
              title: const Text(
                'Pastoral & comunicação',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              bottom: PastoralModuleTabBar(controller: _tab),
              actions: [
                IconButton(
                  icon: Icon(Icons.help_outline_rounded,
                      color: ThemeCleanPremium.primary),
                  tooltip: 'Ajuda do módulo',
                  onPressed: () => _showPastoralModuleHelp(context),
                  style: iconBtnStyle,
                ),
              ],
            ),
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMobile)
              Container(
                color: ThemeCleanPremium.primary,
                child: PastoralModuleTabBar(controller: _tab),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ThemeCleanPremium.churchPanelBodyGradient,
                ),
                child: AnimatedBuilder(
                  animation: _tab,
                  builder: (context, _) {
                    final tid = _effectiveChurchId;
                    // StackFit.loose: expand força filhos a preencher altura; com SingleChildScrollView
                    // no Web/desktop pode sobrar faixa “cinza” (gradiente do painel) sob o histórico.
                    return IndexedStack(
                      index: _tab.index,
                      children: [
                        _PastoralTabSurface(
                          child: _PushSegmentadoTab(
                            key: ValueKey<String>('pastoral_push_$tid'),
                            tenantId: tid,
                          ),
                        ),
                        _PastoralTabSurface(
                          child: _tabsBuilt.contains(1)
                              ? _DevocionalTab(
                                  key: ValueKey<String>('pastoral_dev_$tid'),
                                  tenantId: tid,
                                )
                              : const SizedBox.shrink(),
                        ),
                        _PastoralTabSurface(
                          child: _tabsBuilt.contains(2)
                              ? _EvasaoTab(
                                  key: ValueKey<String>('pastoral_evasao_$tid'),
                                  tenantId: tid,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    );
                  },
                ),
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
  const _PushSegmentadoTab({super.key, required this.tenantId});

  @override
  State<_PushSegmentadoTab> createState() => _PushSegmentadoTabState();
}

class _PushSegmentadoTabState extends State<_PushSegmentadoTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _segment = 'broadcast';
  final Set<String> _selectedDeptIds = {};
  final Set<String> _selectedCargoLabels = {};
  final Set<String> _selectedMemberIds = {};
  bool _useMessageExpiry = false;
  DateTime? _expiresAt;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String get _topicPreview {
    final tid = widget.tenantId.trim();
    if (_segment == 'member') {
      if (_selectedMemberIds.isEmpty) return 'direto_membro_(selecione)';
      if (_selectedMemberIds.length == 1) {
        return 'direto_membro_${_selectedMemberIds.first}';
      }
      return 'direto_${_selectedMemberIds.length}_membros';
    }
    if (_segment == 'department') {
      if (_selectedDeptIds.isEmpty) return 'dept_(selecione)';
      if (_selectedDeptIds.length == 1) return 'dept_${_selectedDeptIds.first}';
      return '${_selectedDeptIds.length}_departamentos';
    }
    if (_segment == 'cargo') {
      if (_selectedCargoLabels.isEmpty) return 'cargo_(selecione)';
      if (_selectedCargoLabels.length == 1) {
        return 'cargo_${FcmService.slugTopicPart(_selectedCargoLabels.first)}';
      }
      return '${_selectedCargoLabels.length}_cargos';
    }
    return 'igreja_$tid';
  }

  Future<Set<String>?> _openMultiSelectSheet({
    required String title,
    required String searchHint,
    required List<({String id, String label})> items,
    required Set<String> initial,
  }) {
    return showModalBottomSheet<Set<String>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PastoralMultiPickSheet(
        title: title,
        searchHint: searchHint,
        items: items,
        initialSelected: initial,
      ),
    );
  }

  Future<void> _pickExpiryDateTime() async {
    final now = DateTime.now();
    final base = _expiresAt ?? now.add(const Duration(days: 7));
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null || !mounted) return;
    setState(() {
      _expiresAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Widget _segmentPickCard({
    required IconData icon,
    required String summary,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF8FAFC),
            ThemeCleanPremium.primary.withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.checklist_rounded, size: 20),
            label: Text(buttonLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeCleanPremium.primary,
              side: BorderSide(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
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
    if (_segment == 'member' && _selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um membro.')),
      );
      return;
    }
    if (_segment == 'department' && _selectedDeptIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um departamento.')),
      );
      return;
    }
    if (_segment == 'cargo' && _selectedCargoLabels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um cargo.')),
      );
      return;
    }
    if (_useMessageExpiry) {
      final exp = _expiresAt;
      if (exp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Defina data e hora de validade ou desative a opção.')),
        );
        return;
      }
      if (!exp.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A validade deve ser no futuro.')),
        );
        return;
      }
    }
    setState(() => _sending = true);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendSegmentedPush');
      final payload = <String, dynamic>{
        'tenantId': widget.tenantId,
        'title': title,
        'body': body,
        'segment': _segment,
        if (_segment == 'department' && _selectedDeptIds.isNotEmpty)
          'departmentIds': _selectedDeptIds.toList(),
        if (_segment == 'cargo' && _selectedCargoLabels.isNotEmpty)
          'cargoLabels': _selectedCargoLabels.toList(),
        if (_segment == 'member' && _selectedMemberIds.isNotEmpty)
          'memberDocIds': _selectedMemberIds.toList(),
      };
      if (_useMessageExpiry && _expiresAt != null) {
        payload['expiresAtMillis'] = _expiresAt!.millisecondsSinceEpoch;
      }
      await fn.call(payload);
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

    return SingleChildScrollView(
      padding: _pastoralFullBleedPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.14),
                    ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.22),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Icon(Icons.campaign_rounded,
                  color: ThemeCleanPremium.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Push pastoral',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Notificações por tópico (igreja, departamento, cargo ou membro). '
                    'Escala e devocional usam o mesmo motor FCM.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hub_rounded,
                        size: 18, color: ThemeCleanPremium.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tópico atual: $_topicPreview',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.primary,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 420;
                  final seg = SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'broadcast', label: Text('Igreja'), icon: Icon(Icons.church_rounded)),
                      ButtonSegment(value: 'department', label: Text('Dept.'), icon: Icon(Icons.groups_rounded)),
                      ButtonSegment(value: 'cargo', label: Text('Cargo'), icon: Icon(Icons.work_rounded)),
                      ButtonSegment(value: 'member', label: Text('Membro'), icon: Icon(Icons.person_rounded)),
                    ],
                    selected: {_segment},
                    onSelectionChanged: (s) => setState(() {
                      _segment = s.first;
                      _selectedDeptIds.clear();
                      _selectedCargoLabels.clear();
                      _selectedMemberIds.clear();
                    }),
                  );
                  if (!narrow) return seg;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: seg,
                  );
                },
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
                    final items = docs
                        .map(
                          (d) => (
                            id: d.id,
                            label: churchDepartmentNameFromData(d.data(), docId: d.id),
                          ),
                        )
                        .toList();
                    final summary = _selectedDeptIds.isEmpty
                        ? 'Nenhum departamento selecionado'
                        : '${_selectedDeptIds.length} departamento(s) selecionado(s)';
                    return _segmentPickCard(
                      icon: Icons.groups_rounded,
                      summary: summary,
                      buttonLabel: 'Escolher departamentos',
                      onTap: () async {
                        final r = await _openMultiSelectSheet(
                          title: 'Departamentos',
                          searchHint: 'Filtrar por nome…',
                          items: items,
                          initial: Set<String>.from(_selectedDeptIds),
                        );
                        if (r != null && mounted) {
                          setState(() {
                            _selectedDeptIds
                              ..clear()
                              ..addAll(r);
                          });
                        }
                      },
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
                    final items = <({String id, String label})>[];
                    for (final d in docs) {
                      final name = (d.data()['name'] ?? d.id).toString().trim();
                      if (name.isEmpty) continue;
                      items.add((id: name, label: name));
                    }
                    final summary = _selectedCargoLabels.isEmpty
                        ? 'Nenhum cargo selecionado'
                        : '${_selectedCargoLabels.length} cargo(s) selecionado(s)';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _segmentPickCard(
                          icon: Icons.work_outline_rounded,
                          summary: summary,
                          buttonLabel: 'Escolher cargos',
                          onTap: () async {
                            final r = await _openMultiSelectSheet(
                              title: 'Cargos',
                              searchHint: 'Filtrar cargo…',
                              items: items,
                              initial: Set<String>.from(_selectedCargoLabels),
                            );
                            if (r != null && mounted) {
                              setState(() {
                                _selectedCargoLabels
                                  ..clear()
                                  ..addAll(r);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'O app inscreve o membro nos tópicos cargo_* conforme o campo CARGO da ficha.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    );
                  },
                ),
              ],
              if (_segment == 'member') ...[
                const SizedBox(height: 16),
                FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: FirebaseFirestore.instance
                      .collection('igrejas')
                      .doc(widget.tenantId)
                      .collection('membros')
                      .limit(500)
                      .get()
                      .then((s) {
                    final l = s.docs.toList()
                      ..sort((a, b) {
                        final na = (a.data()['NOME_COMPLETO'] ?? a.data()['nome'] ?? a.id)
                            .toString()
                            .toLowerCase();
                        final nb = (b.data()['NOME_COMPLETO'] ?? b.data()['nome'] ?? b.id)
                            .toString()
                            .toLowerCase();
                        return na.compareTo(nb);
                      });
                    return l;
                  }),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final docs = snap.data!;
                    final items = docs
                        .map(
                          (d) => (
                            id: d.id,
                            label: (d.data()['NOME_COMPLETO'] ?? d.data()['nome'] ?? d.id)
                                .toString(),
                          ),
                        )
                        .toList();
                    final summary = _selectedMemberIds.isEmpty
                        ? 'Nenhum membro selecionado'
                        : '${_selectedMemberIds.length} membro(s) selecionado(s)';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _segmentPickCard(
                          icon: Icons.person_search_rounded,
                          summary: summary,
                          buttonLabel: 'Escolher membros',
                          onTap: () async {
                            final r = await _openMultiSelectSheet(
                              title: 'Membros',
                              searchHint: 'Filtrar por nome…',
                              items: items,
                              initial: Set<String>.from(_selectedMemberIds),
                            );
                            if (r != null && mounted) {
                              setState(() {
                                _selectedMemberIds
                                  ..clear()
                                  ..addAll(r);
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Envio direto aos aparelhos (FCM). Exige CPF na ficha e app com login.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: _pastoralInputDecoration(
                  'Título',
                  icon: Icons.title_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: _pastoralInputDecoration(
                  'Mensagem',
                  icon: Icons.chat_bubble_outline_rounded,
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Validade no painel do membro',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _useMessageExpiry && _expiresAt != null
                      ? 'Oculta após: ${DateFormat("dd/MM/yyyy HH:mm").format(_expiresAt!)}'
                      : 'Opcional — após data/hora, a mensagem some da caixa de entrada.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                value: _useMessageExpiry,
                onChanged: (v) => setState(() {
                  _useMessageExpiry = v;
                  if (v && _expiresAt == null) {
                    _expiresAt = DateTime.now().add(const Duration(days: 7));
                  }
                }),
              ),
              if (_useMessageExpiry) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _pickExpiryDateTime,
                    icon: const Icon(Icons.event_rounded, size: 20),
                    label: Text(
                      _expiresAt == null
                          ? 'Definir data e hora'
                          : 'Alterar data e hora',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _sending ? 'Enviando…' : 'Enviar notificação',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
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
      ),
    );
  }

  Widget _infoCard(String title, String body) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: -0.2,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: pesquisa + multi-seleção; Voltar/Cancelar descartam; Confirmar aplica.
class _PastoralMultiPickSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final List<({String id, String label})> items;
  final Set<String> initialSelected;

  const _PastoralMultiPickSheet({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.initialSelected,
  });

  @override
  State<_PastoralMultiPickSheet> createState() => _PastoralMultiPickSheetState();
}

class _PastoralMultiPickSheetState extends State<_PastoralMultiPickSheet> {
  late Set<String> _sel;
  final _search = TextEditingController();
  String _q = '';

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

  List<({String id, String label})> get _filtered {
    if (_q.isEmpty) return widget.items;
    return widget.items
        .where((e) => e.label.toLowerCase().contains(_q))
        .toList();
  }

  void _popCancel() => Navigator.pop<Set<String>?>(context, null);

  void _popConfirm() => Navigator.pop<Set<String>?>(context, Set<String>.from(_sel));

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height * 0.88;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: h.clamp(320, 900),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Voltar',
                        onPressed: _popCancel,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            letterSpacing: -0.3,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _popCancel,
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        '${_sel.length} selecionado(s)',
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
                            'Nenhum resultado',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final e = _filtered[i];
                            final on = _sel.contains(e.id);
                            return CheckboxListTile(
                              value: on,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _sel.add(e.id);
                                  } else {
                                    _sel.remove(e.id);
                                  }
                                });
                              },
                              title: Text(
                                e.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _popCancel,
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _popConfirm,
                            child: const Text('Confirmar seleção'),
                          ),
                        ),
                      ],
                    ),
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

class _DevocionalTab extends StatefulWidget {
  final String tenantId;
  const _DevocionalTab({super.key, required this.tenantId});

  @override
  State<_DevocionalTab> createState() => _DevocionalTabState();
}

class _DevocionalTabState extends State<_DevocionalTab> {
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _devHistorySearchCtrl = TextEditingController();
  final ScrollController _devScrollCtrl = ScrollController();
  bool _enabled = false;
  int _hora = 7;
  bool _loading = true;
  bool _saving = false;
  String? _busyDevEnvioId;
  _PastoralDateFilterKind _devDateKind = _PastoralDateFilterKind.none;
  DateTime? _devFilterDay;
  int _devFilterMonth = DateTime.now().month;
  int _devFilterYear = DateTime.now().year;
  DateTime? _devRangeStart;
  DateTime? _devRangeEnd;

  DocumentReference<Map<String, dynamic>> get _cfgRef => FirebaseFirestore.instance
      .collection('igrejas')
      .doc(widget.tenantId)
      .collection('config')
      .doc('comunicacao');

  @override
  void initState() {
    super.initState();
    _devHistorySearchCtrl.addListener(() => setState(() {}));
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
    _devHistorySearchCtrl.dispose();
    _devScrollCtrl.dispose();
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDevDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _devFilterDay ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null && mounted) setState(() => _devFilterDay = d);
  }

  Future<void> _pickDevMonth() async {
    var m = _devFilterMonth;
    var y = _devFilterYear;
    final anchorYear = DateTime.now().year;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Filtrar por mês'),
        content: StatefulBuilder(
          builder: (context, setLocal) {
            return Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Mês'),
                    value: m,
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                    ),
                    onChanged: (v) => setLocal(() => m = v ?? m),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(labelText: 'Ano'),
                    value: y,
                    items: List.generate(
                      8,
                      (i) {
                        final yy = anchorYear - i;
                        return DropdownMenuItem(value: yy, child: Text('$yy'));
                      },
                    ),
                    onChanged: (v) => setLocal(() => y = v ?? y),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _devFilterMonth = m;
        _devFilterYear = y;
      });
    }
  }

  Future<void> _pickDevRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _devRangeStart != null && _devRangeEnd != null
          ? DateTimeRange(start: _devRangeStart!, end: _devRangeEnd!)
          : null,
    );
    if (range != null && mounted) {
      setState(() {
        _devRangeStart = range.start;
        _devRangeEnd = range.end;
      });
    }
  }

  bool _devDocPassesFilters(Map<String, dynamic> data) {
    final q = _devHistorySearchCtrl.text.trim().toLowerCase();
    final titulo = (data['titulo'] ?? '').toString().toLowerCase();
    final texto = (data['texto'] ?? '').toString().toLowerCase();
    final ref = (data['referencia'] ?? '').toString().toLowerCase();
    if (q.isNotEmpty &&
        !titulo.contains(q) &&
        !texto.contains(q) &&
        !ref.contains(q)) {
      return false;
    }
    final ts = data['sentAt'];
    if (_devDateKind == _PastoralDateFilterKind.none) return true;
    if (ts is! Timestamp) return false;
    final d = ts.toDate();
    final dd = DateTime(d.year, d.month, d.day);
    switch (_devDateKind) {
      case _PastoralDateFilterKind.none:
        return true;
      case _PastoralDateFilterKind.day:
        final p = _devFilterDay;
        if (p == null) return true;
        return dd.year == p.year && dd.month == p.month && dd.day == p.day;
      case _PastoralDateFilterKind.month:
        return d.year == _devFilterYear && d.month == _devFilterMonth;
      case _PastoralDateFilterKind.range:
        final a = _devRangeStart;
        final b = _devRangeEnd;
        if (a == null || b == null) return true;
        final start = DateTime(a.year, a.month, a.day);
        final end = DateTime(b.year, b.month, b.day);
        return !dd.isBefore(start) && !dd.isAfter(end);
    }
  }

  String get _devDayChipLabel {
    if (_devFilterDay == null) return 'Dia';
    return DateFormat('dd/MM/yyyy').format(_devFilterDay!);
  }

  String get _devMonthChipLabel =>
      'Mês ${DateFormat('MM/yyyy').format(DateTime(_devFilterYear, _devFilterMonth))}';

  String get _devRangeChipLabel {
    if (_devRangeStart == null || _devRangeEnd == null) return 'Período';
    return '${DateFormat('dd/MM/yy').format(_devRangeStart!)}–${DateFormat('dd/MM/yy').format(_devRangeEnd!)}';
  }

  Future<void> _resendDevotional(String envioId) async {
    setState(() => _busyDevEnvioId = envioId);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('resendDevotionalEnvio');
      await fn.call({'tenantId': widget.tenantId, 'envioId': envioId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Devocional reenviado para o tópico da igreja.'),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Falha ao reenviar.'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDevEnvioId = null);
    }
  }

  Future<void> _deleteDevotionalEntry(String envioId) async {
    setState(() => _busyDevEnvioId = envioId);
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deleteDevotionalEnvio');
      await fn.call({'tenantId': widget.tenantId, 'envioId': envioId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Registro removido do histórico.'),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Falha ao excluir.'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyDevEnvioId = null);
    }
  }

  Future<void> _confirmDeleteDevotional(String envioId, String titulo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir do histórico?'),
        content: Text(
          'Remover "$titulo" da lista? Isso não altera o texto atual do devocional automático.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _deleteDevotionalEntry(envioId);
  }

  void _loadDevotionalIntoForm(Map<String, dynamic> data) {
    _tituloCtrl.text = (data['titulo'] ?? 'Bom dia').toString();
    _textoCtrl.text = (data['texto'] ?? '').toString();
    _refCtrl.text = (data['referencia'] ?? '').toString();
    setState(() {});
    if (_devScrollCtrl.hasClients) {
      _devScrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar(
        'Texto carregado no formulário — ajuste e salve.',
      ),
    );
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ThemeCleanPremium.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A carregar configuração…',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      controller: _devScrollCtrl,
      padding: _pastoralFullBleedPadding(context),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.withValues(alpha: 0.35),
                    ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.28),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Icon(Icons.wb_sunny_rounded,
                  color: Colors.amber.shade900, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Devocional diário',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Uma notificação por dia no horário escolhido (Brasília), para o tópico da igreja. '
                    'O histórico registra cada envio automático feito pela nuvem.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Ativar envio automático',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Push para o tópico da igreja (igreja_ID), uma vez por dia.',
                ),
                value: _enabled,
                activeThumbColor: ThemeCleanPremium.primary,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: _pastoralInputDecoration(
                  'Hora (Brasília)',
                  icon: Icons.schedule_rounded,
                ),
                // ignore: deprecated_member_use — valor controlado pelo estado (_hora).
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
                textCapitalization: TextCapitalization.sentences,
                decoration: _pastoralInputDecoration(
                  'Título da notificação',
                  icon: Icons.title_rounded,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textoCtrl,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _pastoralInputDecoration(
                  'Mensagem / versículo',
                  icon: Icons.menu_book_rounded,
                  maxLines: 5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _refCtrl,
                decoration: _pastoralInputDecoration(
                  'Referência bíblica (opcional)',
                  icon: Icons.bookmark_outline_rounded,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text(
                  'Salvar',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Icon(Icons.history_edu_rounded,
                        color: ThemeCleanPremium.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Histórico de envios (devocional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: ThemeCleanPremium.onSurface,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cada disparo automático gera um registro. Editar carrega no formulário; reenviar manda push de novo; excluir só apaga o registro.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: ThemeCleanPremium.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PastoralHistoryFilterBar(
                searchCtrl: _devHistorySearchCtrl,
                searchHint: 'Buscar por título, texto ou referência…',
                kind: _devDateKind,
                onKindChanged: (k) => setState(() => _devDateKind = k),
                onPickDay: _pickDevDay,
                onPickMonth: _pickDevMonth,
                onPickRange: _pickDevRange,
                daySummary: _devDayChipLabel,
                monthSummary: _devMonthChipLabel,
                rangeSummary: _devRangeChipLabel,
              ),
              const SizedBox(height: 14),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey<String>('dev_hist_${widget.tenantId}'),
                stream: FirebaseFirestore.instance
                    .collection('igrejas')
                    .doc(widget.tenantId)
                    .collection('devocional_envios')
                    .limit(200)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Não foi possível carregar o histórico: ${snap.error}',
                        style: TextStyle(color: ThemeCleanPremium.error, fontWeight: FontWeight.w600),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final raw = snap.data!.docs.toList();
                  raw.sort((a, b) {
                    final ta = a.data()['sentAt'];
                    final tb = b.data()['sentAt'];
                    if (ta is Timestamp && tb is Timestamp) {
                      return tb.compareTo(ta);
                    }
                    if (ta is Timestamp) return -1;
                    if (tb is Timestamp) return 1;
                    return b.id.compareTo(a.id);
                  });
                  if (raw.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.surface,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_outlined,
                              size: 40,
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.35)),
                          const SizedBox(height: 10),
                          Text(
                            'Ainda não há envios registrados',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Após o deploy das funções, cada envio automático (horário de Brasília) aparece aqui. '
                            'Registros antigos não são recriados automaticamente.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final docs = raw
                      .where((d) => _devDocPassesFilters(d.data()))
                      .take(80)
                      .toList();
                  if (docs.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.surface,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        border: Border.all(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.filter_alt_off_rounded,
                              size: 38,
                              color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhum resultado para os filtros',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final d = docs[index];
                      final data = d.data();
                      final titulo = (data['titulo'] ?? 'Bom dia').toString();
                      final texto = (data['texto'] ?? '').toString();
                      final ref = (data['referencia'] ?? '').toString();
                      final busy = _busyDevEnvioId == d.id;
                      final ts = data['sentAt'];
                      String when = '';
                      if (ts is Timestamp) {
                        when = DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
                      }
                      final rc = (data['resendCount'] ?? 0) is int
                          ? data['resendCount'] as int
                          : int.tryParse('${data['resendCount']}') ?? 0;
                      final daySp = (data['daySp'] ?? '').toString();
                      return Material(
                        color: ThemeCleanPremium.surface,
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                            border: Border.all(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                            ),
                            boxShadow: ThemeCleanPremium.softUiCardShadow,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  titulo.isEmpty ? 'Bom dia' : titulo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                                if (texto.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    texto,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (ref.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    ref,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ThemeCleanPremium.primary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    if (when.isNotEmpty)
                                      Chip(
                                        label: Text(when,
                                            style: const TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w700)),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (daySp.isNotEmpty)
                                      Chip(
                                        label: Text('Dia $daySp',
                                            style: const TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w700)),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (rc > 0)
                                      Text(
                                        'Reenvios: $rc',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: ThemeCleanPremium.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => _loadDevotionalIntoForm(data),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text('Editar'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: busy ? null : () => _resendDevotional(d.id),
                                      icon: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.send_rounded, size: 18),
                                      label: const Text('Reenviar'),
                                    ),
                                    TextButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => _confirmDeleteDevotional(d.id, titulo),
                                      icon: Icon(Icons.delete_outline_rounded,
                                          size: 18, color: ThemeCleanPremium.error),
                                      label: Text('Excluir',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: ThemeCleanPremium.error)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
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
  const _EvasaoTab({super.key, required this.tenantId});

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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _pastoralFullBleedPadding(context),
              children: [
                Text('Erro: ${snap.error}', style: TextStyle(color: ThemeCleanPremium.error)),
              ],
            );
          }
          if (!snap.hasData) {
            final h = MediaQuery.sizeOf(context).height;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _pastoralFullBleedPadding(context),
              children: [
                SizedBox(height: (h * 0.18).clamp(72.0, 220.0)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: ThemeCleanPremium.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'A analisar presenças…',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          final rows = snap.data!;
          return ListView(
            padding: _pastoralFullBleedPadding(context),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Icon(Icons.health_and_safety_rounded,
                        color: Colors.orange.shade800, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alerta de evasão',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Com base em presenças em cultos (últimos registros analisados). '
                          'Ausência de $diasAlerta dias ou mais — útil para visita ou contacto.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (rows.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 44, color: Colors.green.withValues(alpha: 0.45)),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum alerta neste momento',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Não há membros ativos nesta faixa de ausência, ou ainda não há presenças registradas em cultos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
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
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.orange.shade50,
                            child: Text(
                              '${r.days >= 9999 ? '—' : r.days}d',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sub,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                    height: 1.3,
                                  ),
                                ),
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
