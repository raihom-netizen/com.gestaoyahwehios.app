import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;

/// Personalização de alertas (foreground) por conta, DM, grupo, departamento, pessoa e conversa — estilo Super Premium.
class ChurchChatNotificationSettingsPage extends StatefulWidget {
  final String tenantId;

  const ChurchChatNotificationSettingsPage({
    super.key,
    required this.tenantId,
  });

  @override
  State<ChurchChatNotificationSettingsPage> createState() =>
      _ChurchChatNotificationSettingsPageState();
}

class _ChurchChatNotificationSettingsPageState
    extends State<ChurchChatNotificationSettingsPage> {
  final _searchCtrl = TextEditingController();
  /// 0 = departamento, 1 = pessoa (DM), 2 = conversa.
  int _sectionIndex = 2;
  String _globalMode = ChurchChatNotificationPrefs.alertModeSound;
  /// Alinhado ao hub do chat — evita `permission-denied` com tenant dos claims desatualizado.
  String _effectiveTenantId = '';

  @override
  void initState() {
    super.initState();
    _effectiveTenantId = widget.tenantId.trim();
    _searchCtrl.addListener(() => setState(() {}));
    _reloadGlobal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resolveEffectiveTenant());
    });
  }

  Future<void> _resolveEffectiveTenant() async {
    final u = FirebaseAuth.instance.currentUser?.uid;
    if (u == null || !mounted) {
      return;
    }
    final raw = widget.tenantId.trim();
    if (raw.isEmpty) {
      return;
    }
    try {
      final tid =
          await TenantResolverService.resolveEffectiveTenantIdPreferringUserBinding(
        raw,
        userUid: u,
      );
      if (mounted) {
        setState(() => _effectiveTenantId = tid.trim());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _effectiveTenantId = raw);
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reloadGlobal() async {
    final m = await ChurchChatNotificationPrefs.getChatAlertMode();
    if (mounted) setState(() => _globalMode = m);
  }

  static String _threadRowTitle(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    final data = doc.data();
    final type = (data['type'] ?? '').toString();
    if (type == 'department') {
      final t = (data['title'] ?? 'Grupo').toString().trim();
      return t.isEmpty ? 'Grupo' : t;
    }
    final peers = (data['participantUids'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    var peer = '';
    for (final p in peers) {
      if (p != myUid) {
        peer = p;
        break;
      }
    }
    final titles = data['titlesByUid'];
    var title = peer;
    if (titles is Map && titles[peer] != null) {
      title = titles[peer].toString();
    }
    final t = title.trim();
    return t.isNotEmpty ? t : (peer.isNotEmpty ? peer : 'Conversa');
  }

  /// Outro participante num thread `type == dm`; `null` se não for DM.
  static String? _dmPeerUid(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String myUid,
  ) {
    final data = doc.data();
    if ((data['type'] ?? '').toString().trim() != 'dm') return null;
    final peers =
        (data['participantUids'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
            [];
    for (final p in peers) {
      if (p != myUid) return p;
    }
    return null;
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case ChurchChatNotificationPrefs.alertModeVibrate:
        return 'Só vibrar';
      case ChurchChatNotificationPrefs.alertModeSilent:
        return 'Silencioso';
      default:
        return 'Som + vibrar';
    }
  }

  static String _inheritSubtitle(String? specific) {
    if (specific == null) {
      return 'Usa o modo global da conta (padrão do app).';
    }
    return 'Override: ${_modeLabel(specific)}';
  }

  Future<void> _setGlobal(String mode) async {
    await ChurchChatNotificationPrefs.setChatAlertMode(mode: mode);
    await _reloadGlobal();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Padrão global: ${_modeLabel(mode)}')),
    );
  }

  Future<void> _setDm(String? mode) async {
    await ChurchChatMemberPrefs.setDmNotificationStyle(
      tenantId: _tid,
      mode: mode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == null
              ? 'Mensagens diretas: seguem o global.'
              : 'Mensagens diretas: ${_modeLabel(mode)}',
        ),
      ),
    );
  }

  Future<void> _setGroup(String? mode) async {
    await ChurchChatMemberPrefs.setGroupNotificationStyle(
      tenantId: _tid,
      mode: mode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == null
              ? 'Grupos: seguem o global.'
              : 'Grupos: ${_modeLabel(mode)}',
        ),
      ),
    );
  }

  Future<void> _setThread(String threadId, String? mode) async {
    final ok = await ChurchChatMemberPrefs.setThreadNotificationOverride(
      tenantId: _tid,
      threadId: threadId,
      mode: mode,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Máximo de ${ChurchChatMemberPrefs.maxThreadNotifOverrides} conversas '
            'com alerta personalizado. Remova uma nas definições.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == null
              ? 'Esta conversa voltou ao padrão (DM/grupo/global).'
              : 'Esta conversa: ${_modeLabel(mode)}',
        ),
      ),
    );
  }

  Future<void> _setDepartmentAlert(String departmentId, String? mode) async {
    final ok = await ChurchChatMemberPrefs.setDepartmentAlertMode(
      tenantId: _tid,
      departmentId: departmentId,
      mode: mode,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Máximo de ${ChurchChatMemberPrefs.maxDepartmentAlertModes} departamentos '
            'com alerta próprio. Remova um na lista.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == null
              ? 'Departamento: segue grupo / global.'
              : 'Departamento: ${_modeLabel(mode)}',
        ),
      ),
    );
  }

  Future<void> _setDmPeerAlert(String peerUid, String? mode) async {
    final ok = await ChurchChatMemberPrefs.setDmPeerAlertMode(
      tenantId: _tid,
      peerUid: peerUid,
      mode: mode,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Máximo de ${ChurchChatMemberPrefs.maxDmPeerAlertModes} contactos '
            'com alerta próprio. Remova um na lista.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == null
              ? 'Este contacto: segue DM / global.'
              : 'Este contacto: ${_modeLabel(mode)}',
        ),
      ),
    );
  }

  /// Tenant efetivo (resolver + fallback ao passado no construtor).
  String get _tid {
    final t = _effectiveTenantId.trim();
    return t.isNotEmpty ? t : widget.tenantId.trim();
  }

  Widget _premiumCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
          width: 1.1,
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: child,
    );
  }

  Widget _premiumGlobalModeRow({
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    Widget segment({
      required String mode,
      required IconData icon,
      required String shortLabel,
    }) {
      final on = selected == mode;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelect(mode),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: on ? churchChatWhatsPremiumLinearGradient : null,
                  color: on ? null : ThemeCleanPremium.cardBackground,
                  border: Border.all(
                    color: on
                        ? Colors.white.withValues(alpha: 0.22)
                        : ThemeCleanPremium.primary.withValues(alpha: 0.38),
                    width: on ? 1.4 : 1.15,
                  ),
                  boxShadow: on
                      ? [
                          BoxShadow(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.32),
                            blurRadius: 16,
                            offset: const Offset(0, 7),
                          ),
                        ]
                      : ThemeCleanPremium.softUiCardShadow,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: on ? Colors.white : ThemeCleanPremium.primary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          letterSpacing: -0.2,
                          color: on ? Colors.white : ThemeCleanPremium.onSurface,
                        ),
                      ),
                      if (on) ...[
                        const SizedBox(height: 4),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        segment(
          mode: ChurchChatNotificationPrefs.alertModeSound,
          icon: Icons.volume_up_rounded,
          shortLabel: 'Som',
        ),
        segment(
          mode: ChurchChatNotificationPrefs.alertModeVibrate,
          icon: Icons.vibration_rounded,
          shortLabel: 'Vibrar',
        ),
        segment(
          mode: ChurchChatNotificationPrefs.alertModeSilent,
          icon: Icons.notifications_off_rounded,
          shortLabel: 'Silêncio',
        ),
      ],
    );
  }

  Widget _inheritDropdown({
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final r = BorderRadius.circular(14);
    final deco = InputDecoration(
      labelText: 'Modo',
      filled: true,
      fillColor: ThemeCleanPremium.cardBackground,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: ThemeCleanPremium.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      border: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.32),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(
          color: ThemeCleanPremium.primary,
          width: 2,
        ),
      ),
    );
    return InputDecorator(
      decoration: deco,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          isDense: true,
          icon: Icon(Icons.expand_more_rounded, color: ThemeCleanPremium.primary),
          dropdownColor: ThemeCleanPremium.cardBackground,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurface,
            fontSize: 14,
          ),
          items: const [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('Seguir conta (global)'),
            ),
            DropdownMenuItem(
              value: ChurchChatNotificationPrefs.alertModeSound,
              child: Text('Som + vibrar'),
            ),
            DropdownMenuItem(
              value: ChurchChatNotificationPrefs.alertModeVibrate,
              child: Text('Só vibrar'),
            ),
            DropdownMenuItem(
              value: ChurchChatNotificationPrefs.alertModeSilent,
              child: Text('Silencioso'),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _whatsappSectionTabsRow() {
    Widget chip(int index, String label, IconData icon) {
      final on = _sectionIndex == index;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _sectionIndex = index),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: on ? churchChatWhatsPremiumLinearGradient : null,
                  color: on ? null : ThemeCleanPremium.cardBackground,
                  border: Border.all(
                    color: on
                        ? Colors.white.withValues(alpha: 0.22)
                        : ThemeCleanPremium.primary.withValues(alpha: 0.32),
                    width: on ? 1.45 : 1.12,
                  ),
                  boxShadow: on
                      ? [
                          BoxShadow(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : ThemeCleanPremium.softUiCardShadow,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: on ? Colors.white : ThemeCleanPremium.primary,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: -0.2,
                          color: on
                              ? Colors.white
                              : ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          chip(0, 'Departamento', Icons.apartment_rounded),
          chip(1, 'Pessoa (DM)', Icons.person_pin_rounded),
          chip(2, 'Conversa', Icons.forum_rounded),
        ],
      ),
    );
  }

  String _searchHintForSection() {
    switch (_sectionIndex) {
      case 0:
        return 'Pesquisar departamento…';
      case 1:
        return 'Pesquisar pessoa…';
      default:
        return 'Pesquisar conversa ou grupo…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Inicie sessão para gerir alertas.')),
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 118,
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsetsDirectional.only(
                  start: 52,
                  bottom: 14,
                ),
                title: Text(
                  'Alertas do chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                background: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: churchChatWhatsPremiumLinearGradient,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 44),
                      child: Text(
                        'Alertas personalizados — global, DM, grupo, departamento, pessoa e conversa',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: _premiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Padrão global da conta',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Usado quando não há override por DM, grupo ou conversa.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _premiumGlobalModeRow(
                        selected: _globalMode,
                        onSelect: (m) => _setGlobal(m),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: ChurchChatMemberPrefs.watch(_tid),
                builder: (context, prefSnap) {
                  final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _premiumCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  color: ThemeCleanPremium.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Mensagens diretas',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _inheritSubtitle(prefs.dmNotificationStyle),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _inheritDropdown(
                              value: prefs.dmNotificationStyle,
                              onChanged: _setDm,
                            ),
                          ],
                        ),
                      ),
                      _premiumCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.groups_rounded,
                                  color: ThemeCleanPremium.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Grupos (departamentos)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _inheritSubtitle(prefs.groupNotificationStyle),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: ThemeCleanPremium.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _inheritDropdown(
                              value: prefs.groupNotificationStyle,
                              onChanged: _setGroup,
                            ),
                          ],
                        ),
                      ),
                      _whatsappSectionTabsRow(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          _sectionIndex == 0
                              ? 'Por departamento (${prefs.departmentAlertModes.length}/'
                                  '${ChurchChatMemberPrefs.maxDepartmentAlertModes})'
                              : _sectionIndex == 1
                                  ? 'Por pessoa — DMs (${prefs.dmPeerAlertModes.length}/'
                                      '${ChurchChatMemberPrefs.maxDmPeerAlertModes})'
                                  : 'Por conversa (${prefs.threadNotifModes.length}/'
                                      '${ChurchChatMemberPrefs.maxThreadNotifOverrides})',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: _searchHintForSection(),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: ThemeCleanPremium.primary,
                            ),
                            filled: true,
                            fillColor: ThemeCleanPremium.cardBackground,
                            hintStyle: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.28),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.28),
                                width: 1.15,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: ThemeCleanPremium.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_sectionIndex == 0)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('igrejas')
                              .doc(_tid)
                              .collection('departamentos')
                              .snapshots(),
                          builder: (context, dSnap) {
                            if (dSnap.hasError) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 28),
                                child: Text(
                                  'Erro ao carregar departamentos: ${dSnap.error}',
                                  style: TextStyle(
                                    color: ThemeCleanPremium.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }
                            if (!dSnap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            final q = _searchCtrl.text.trim().toLowerCase();
                            var ddocs = dSnap.data!.docs.toList();
                            ddocs.sort(
                              (a, b) => churchDepartmentNameFromDoc(a)
                                  .toLowerCase()
                                  .compareTo(
                                    churchDepartmentNameFromDoc(b)
                                        .toLowerCase(),
                                  ),
                            );
                            final dfiltered = q.isEmpty
                                ? ddocs
                                : ddocs.where((d) {
                                    final n = churchDepartmentNameFromDoc(d)
                                        .toLowerCase();
                                    return n.contains(q) ||
                                        d.id.toLowerCase().contains(q);
                                  }).toList();
                            if (dfiltered.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  q.isEmpty
                                      ? 'Sem departamentos.'
                                      : 'Nenhum resultado para "$q".',
                                  style: TextStyle(
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              itemCount: dfiltered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final doc = dfiltered[i];
                                final name = churchDepartmentNameFromDoc(doc);
                                final mode =
                                    prefs.departmentAlertMode(doc.id);
                                return Container(
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.cardBackground,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.22),
                                    ),
                                    boxShadow:
                                        ThemeCleanPremium.softUiCardShadow,
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.apartment_rounded,
                                        color: ThemeCleanPremium.primary,
                                        size: 22,
                                      ),
                                    ),
                                    title: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      mode == null
                                          ? 'Segue grupo / global'
                                          : 'Override: ${_modeLabel(mode)}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: ThemeCleanPremium
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Theme(
                                      data: Theme.of(context).copyWith(
                                        canvasColor:
                                            ThemeCleanPremium.cardBackground,
                                      ),
                                      child: DropdownButton<String?>(
                                        value: mode,
                                        underline: const SizedBox.shrink(),
                                        isDense: true,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        dropdownColor:
                                            ThemeCleanPremium.cardBackground,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: ThemeCleanPremium.onSurface,
                                        ),
                                        items: const [
                                          DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Padrão'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeSound,
                                            child: Text('Som'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeVibrate,
                                            child: Text('Vibrar'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeSilent,
                                            child: Text('Silêncio'),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            _setDepartmentAlert(doc.id, v),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        )
                      else
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: ChurchChatService.chatThreadsSnapshotsForUser(
                          _tid,
                          uid,
                        ),
                        builder: (context, thSnap) {
                          if (thSnap.hasError) {
                            final err = thSnap.error.toString();
                            final perm = err.contains('permission-denied');
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                              child: Material(
                                color: ThemeCleanPremium.cardBackground,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.security_rounded,
                                            color: ThemeCleanPremium.error,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              perm
                                                  ? 'Sem permissão para listar conversas nesta igreja.'
                                                  : 'Erro ao carregar conversas.',
                                              style: TextStyle(
                                                color: ThemeCleanPremium.error,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        perm
                                            ? 'Saia e volte a entrar no painel, ou peça ao gestor para '
                                                'publicar as regras Firestore mais recentes. '
                                                'Se continuar, confirme que está na igreja certa.'
                                            : err,
                                        style: TextStyle(
                                          color: ThemeCleanPremium.onSurface,
                                          fontWeight: FontWeight.w600,
                                          height: 1.4,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          if (!thSnap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final q = _searchCtrl.text.trim().toLowerCase();
                          final docs = thSnap.data!.docs.toList();

                          if (_sectionIndex == 1) {
                            final peerMap = <String, String>{};
                            for (final d in docs) {
                              final pid = _dmPeerUid(d, uid);
                              if (pid == null) continue;
                              peerMap.putIfAbsent(
                                pid,
                                () => _threadRowTitle(d, uid),
                              );
                            }
                            var entries = peerMap.entries.toList();
                            entries.sort(
                              (a, b) => a.value.toLowerCase().compareTo(
                                    b.value.toLowerCase(),
                                  ),
                            );
                            if (q.isNotEmpty) {
                              entries = entries.where((e) {
                                return e.key.toLowerCase().contains(q) ||
                                    e.value.toLowerCase().contains(q);
                              }).toList();
                            }
                            if (entries.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  q.isEmpty
                                      ? 'Sem mensagens diretas com contactos.'
                                      : 'Nenhum resultado para "$q".',
                                  style: TextStyle(
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              itemCount: entries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final e = entries[i];
                                final mode = prefs.dmPeerAlertMode(e.key);
                                return Container(
                                  decoration: BoxDecoration(
                                    color: ThemeCleanPremium.cardBackground,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.22),
                                    ),
                                    boxShadow:
                                        ThemeCleanPremium.softUiCardShadow,
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: ThemeCleanPremium.primary
                                          .withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: ThemeCleanPremium.primary,
                                        size: 22,
                                      ),
                                    ),
                                    title: Text(
                                      e.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                    ),
                                    subtitle: Text(
                                      mode == null
                                          ? 'Segue DM / global'
                                          : 'Override: ${_modeLabel(mode)}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: ThemeCleanPremium
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Theme(
                                      data: Theme.of(context).copyWith(
                                        canvasColor:
                                            ThemeCleanPremium.cardBackground,
                                      ),
                                      child: DropdownButton<String?>(
                                        value: mode,
                                        underline: const SizedBox.shrink(),
                                        isDense: true,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        dropdownColor:
                                            ThemeCleanPremium.cardBackground,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: ThemeCleanPremium.onSurface,
                                        ),
                                        items: const [
                                          DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('Padrão'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeSound,
                                            child: Text('Som'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeVibrate,
                                            child: Text('Vibrar'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChurchChatNotificationPrefs
                                                .alertModeSilent,
                                            child: Text('Silêncio'),
                                          ),
                                        ],
                                        onChanged: (v) =>
                                            _setDmPeerAlert(e.key, v),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }

                          docs.sort((a, b) => _threadRowTitle(a, uid)
                              .toLowerCase()
                              .compareTo(_threadRowTitle(b, uid).toLowerCase()));
                          final filtered = q.isEmpty
                              ? docs
                              : docs.where((d) {
                                  final t =
                                      _threadRowTitle(d, uid).toLowerCase();
                                  final id = d.id.toLowerCase();
                                  return t.contains(q) || id.contains(q);
                                }).toList();

                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                q.isEmpty
                                    ? 'Sem conversas.'
                                    : 'Nenhum resultado para "$q".',
                                style: TextStyle(
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final doc = filtered[i];
                              final title = _threadRowTitle(doc, uid);
                              final isDept = (doc.data()['type'] ?? '')
                                      .toString() ==
                                  'department';
                              final ov = prefs.threadNotifOverride(doc.id);
                              var deptId = (doc.data()['departmentId'] ?? '')
                                  .toString()
                                  .trim();
                              if (deptId.isEmpty &&
                                  doc.id.startsWith('dept_') &&
                                  doc.id.length > 5) {
                                deptId = doc.id.substring(5);
                              }
                              final deptMode = deptId.isNotEmpty
                                  ? prefs.departmentAlertMode(deptId)
                                  : null;
                              final peerUid = _dmPeerUid(doc, uid);
                              final peerMode = peerUid != null
                                  ? prefs.dmPeerAlertMode(peerUid)
                                  : null;
                              String convSubtitle() {
                                if (ov != null) {
                                  return 'Override: ${_modeLabel(ov)}';
                                }
                                if (isDept) {
                                  if (deptMode != null) {
                                    return 'Por departamento: ${_modeLabel(deptMode)}';
                                  }
                                  return 'Segue grupo / global';
                                }
                                if (peerMode != null) {
                                  return 'Por pessoa: ${_modeLabel(peerMode)}';
                                }
                                return 'Segue DM / global';
                              }

                              return Container(
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.cardBackground,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.22),
                                  ),
                                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.14),
                                    child: Icon(
                                      isDept
                                          ? Icons.tag_rounded
                                          : Icons.chat_bubble_rounded,
                                      color: ThemeCleanPremium.primary,
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    convSubtitle(),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: Theme(
                                    data: Theme.of(context).copyWith(
                                      canvasColor:
                                          ThemeCleanPremium.cardBackground,
                                    ),
                                    child: DropdownButton<String?>(
                                      value: ov,
                                      underline: const SizedBox.shrink(),
                                      isDense: true,
                                      borderRadius: BorderRadius.circular(12),
                                      dropdownColor:
                                          ThemeCleanPremium.cardBackground,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: ThemeCleanPremium.onSurface,
                                      ),
                                      items: const [
                                        DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('Padrão'),
                                        ),
                                        DropdownMenuItem(
                                          value: ChurchChatNotificationPrefs
                                              .alertModeSound,
                                          child: Text('Som'),
                                        ),
                                        DropdownMenuItem(
                                          value: ChurchChatNotificationPrefs
                                              .alertModeVibrate,
                                          child: Text('Vibrar'),
                                        ),
                                        DropdownMenuItem(
                                          value: ChurchChatNotificationPrefs
                                              .alertModeSilent,
                                          child: Text('Silêncio'),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          _setThread(doc.id, v),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
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
