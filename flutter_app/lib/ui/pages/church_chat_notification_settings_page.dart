import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';

/// Personalização de alertas (foreground) por conta, DM, grupo e conversa — estilo Super Premium.
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
  String _globalMode = ChurchChatNotificationPrefs.alertModeSound;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _reloadGlobal();
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
      return 'Usa o modo global da conta (padrão WhatsApp).';
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
      tenantId: widget.tenantId,
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
      tenantId: widget.tenantId,
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
      tenantId: widget.tenantId,
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

  Widget _glassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _modeChips({
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Som'),
          selected: selected == ChurchChatNotificationPrefs.alertModeSound,
          onSelected: (_) =>
              onSelect(ChurchChatNotificationPrefs.alertModeSound),
        ),
        ChoiceChip(
          label: const Text('Vibrar'),
          selected: selected == ChurchChatNotificationPrefs.alertModeVibrate,
          onSelected: (_) =>
              onSelect(ChurchChatNotificationPrefs.alertModeVibrate),
        ),
        ChoiceChip(
          label: const Text('Silêncio'),
          selected: selected == ChurchChatNotificationPrefs.alertModeSilent,
          onSelected: (_) =>
              onSelect(ChurchChatNotificationPrefs.alertModeSilent),
        ),
      ],
    );
  }

  Widget _inheritDropdown({
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Modo',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          isDense: true,
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
                        'Super Premium · estilo WhatsApp — global, DM, grupo e por conversa',
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
                child: _glassCard(
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
                      _modeChips(
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
                stream: ChurchChatMemberPrefs.watch(widget.tenantId),
                builder: (context, prefSnap) {
                  final prefs = ChurchChatMemberPrefs.parse(prefSnap.data);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _glassCard(
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
                      _glassCard(
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          'Por conversa (${prefs.threadNotifModes.length}/'
                          '${ChurchChatMemberPrefs.maxThreadNotifOverrides})',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Pesquisar conversa ou grupo…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: ThemeCleanPremium.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('igrejas')
                            .doc(widget.tenantId)
                            .collection('chat_threads')
                            .where('participantUids', arrayContains: uid)
                            .snapshots(),
                        builder: (context, thSnap) {
                          if (thSnap.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Erro ao carregar conversas: ${thSnap.error}',
                                style: TextStyle(
                                  color: ThemeCleanPremium.error,
                                  fontWeight: FontWeight.w600,
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
                                    : 'Nenhum resultado para «$q».',
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
                              return Material(
                                color: ThemeCleanPremium.surface
                                    .withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.12),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    ov == null
                                        ? (isDept
                                            ? 'Segue grupo / global'
                                            : 'Segue DM / global')
                                        : 'Override: ${_modeLabel(ov)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: DropdownButton<String?>(
                                    value: ov,
                                    underline: const SizedBox.shrink(),
                                    isDense: true,
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
