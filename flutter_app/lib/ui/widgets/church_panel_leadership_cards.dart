import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_corpo_admin_roles.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/church_panel_leadership_load_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/pages/church_leader_contact_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';

const Color _kDeptLeadersAccent = Color(0xFF6366F1);
const Color _kCorpoAdminAccent = Color(0xFF10B981);

/// Cards do painel — líderes de departamento e corpo administrativo (cache-first + Chat/WhatsApp).
class ChurchPanelLeadershipCardSection extends StatefulWidget {
  const ChurchPanelLeadershipCardSection({
    super.key,
    required this.tenantId,
    required this.role,
    required this.viewerCpfDigits,
    required this.section,
    required this.onRetry,
    this.panelCache,
    this.membersDirectory,
    this.corpoAdminRoles,
  });

  final String tenantId;
  final String role;
  final String viewerCpfDigits;
  final ChurchPanelLeadershipSection section;
  final Future<void> Function() onRetry;
  final PanelDashboardSnapshot? panelCache;
  final MembersDirectorySnapshot? membersDirectory;
  final List<String>? corpoAdminRoles;

  @override
  State<ChurchPanelLeadershipCardSection> createState() =>
      _ChurchPanelLeadershipCardSectionState();
}

class _ChurchPanelLeadershipCardSectionState
    extends State<ChurchPanelLeadershipCardSection> {
  late List<ChurchPanelLeaderEntry> _cached;
  late Future<List<ChurchPanelLeaderEntry>> _future;
  bool _refreshing = false;

  Color get _accent => widget.section ==
          ChurchPanelLeadershipSection.departmentLeaders
      ? _kDeptLeadersAccent
      : _kCorpoAdminAccent;

  @override
  void initState() {
    super.initState();
    _cached = _readPanelCache();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ChurchPanelLeadershipCardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.section != widget.section ||
        oldWidget.panelCache != widget.panelCache ||
        oldWidget.membersDirectory != widget.membersDirectory) {
      _cached = _readPanelCache();
      _future = _load();
    }
  }

  List<ChurchPanelLeaderEntry> _readPanelCache() {
    final panel = widget.panelCache;
    if (panel == null) return const [];
    return ChurchPanelLeadershipLoadService.fromPanelSnapshot(
      panel: panel,
      section: widget.section,
    );
  }

  Future<List<ChurchPanelLeaderEntry>> _load() {
    return ChurchPanelLeadershipLoadService.load(
      seedTenantId: widget.tenantId,
      section: widget.section,
      panelHint: widget.panelCache,
      directoryHint: widget.membersDirectory,
      corpoAdminRoles:
          widget.corpoAdminRoles ?? ChurchCorpoAdminRoles.defaultRoleKeys,
    );
  }

  void _reload() {
    setState(() {
      _refreshing = true;
      _future = _load();
    });
    unawaited(widget.onRetry());
  }

  String get _emptyMessage {
    if (widget.section == ChurchPanelLeadershipSection.departmentLeaders) {
      return 'Nenhum departamento com líder cadastrado.';
    }
    return 'Nenhum membro com cargo administrativo cadastrado.';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChurchPanelLeaderEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done) {
          _refreshing = false;
        }

        final list = snap.hasData && (snap.data?.isNotEmpty ?? false)
            ? snap.data!
            : (_cached.isNotEmpty ? _cached : (snap.data ?? const []));

        if (list.isEmpty &&
            snap.connectionState == ConnectionState.waiting &&
            !_refreshing) {
          return _LeadershipPanelShell(
            accent: _accent,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          );
        }

        if (list.isEmpty && snap.hasError) {
          return _LeadershipPanelShell(
            accent: _accent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ChurchPanelErrorBody(
                title: widget.section ==
                        ChurchPanelLeadershipSection.departmentLeaders
                    ? 'Não foi possível carregar os líderes de departamento.'
                    : 'Não foi possível carregar o corpo administrativo.',
                onRetry: _reload,
              ),
            ),
          );
        }

        if (list.isEmpty) {
          return _LeadershipPanelShell(
            accent: _accent,
            child: ChurchWisdomModuleEmptyState(
              icon: widget.section ==
                      ChurchPanelLeadershipSection.departmentLeaders
                  ? Icons.leaderboard_rounded
                  : Icons.groups_rounded,
              title: _emptyMessage,
              accent: _accent,
            ),
          );
        }

        if (snap.hasData && snap.data!.isNotEmpty) {
          _cached = snap.data!;
        }

        _scheduleWarmup(context, list);

        return _LeadershipPanelShell(
          accent: _accent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < ThemeCleanPremium.breakpointMobile;
              final crossAxisCount = narrow ? 1 : 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_refreshing || snap.connectionState == ConnectionState.waiting)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _accent.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: narrow ? 1.08 : 1.02,
                    ),
                    itemBuilder: (context, index) {
                      return ChurchPanelLeaderAttentionCard(
                        entry: list[index],
                        tenantId: widget.tenantId,
                        role: widget.role,
                        viewerCpfDigits: widget.viewerCpfDigits,
                        accent: _accent,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _scheduleWarmup(
    BuildContext context,
    List<ChurchPanelLeaderEntry> list,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(
        ChurchGalleryPhotoWarmup.schedule(
          context: context,
          tenantId: widget.tenantId,
          members: list.map((e) {
            final data = e.memberData;
            final cpf = (data['CPF'] ?? data['cpf'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\D'), '');
            return ChurchGalleryMemberPhotoRef(
              memberDocId: e.memberDocId,
              memberData: data,
              cpfDigits: cpf.length == 11 ? cpf : null,
              authUid: MemberProfilePhotoResolver.authUidFromData(
                data,
                memberDocId: e.memberDocId,
              ),
            );
          }),
        ),
      );
    });
  }
}

class _LeadershipPanelShell extends StatelessWidget {
  const _LeadershipPanelShell({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return YahwehWisdomSectionCard(
      borderTint: accent,
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

/// Card WISDOMAPP — foto, cargo, Chat e WhatsApp.
class ChurchPanelLeaderWisdomCard extends StatelessWidget {
  const ChurchPanelLeaderWisdomCard({
    super.key,
    required this.entry,
    required this.tenantId,
    required this.role,
    required this.viewerCpfDigits,
    required this.accent,
    this.dense = false,
  });

  final ChurchPanelLeaderEntry entry;
  final String tenantId;
  final String role;
  final String viewerCpfDigits;
  final Color accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final data = entry.memberData;
    final nome = entry.displayName;
    final subtitle = entry.subtitleLine;
    final foto = MemberProfilePhotoResolver.displayRef(data, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(data, preferThumb: true);
    final avatarColor = avatarColorForMember(data, hasPhoto: hasFoto);
    final avatarSize = dense ? 48.0 : 52.0;
    final memPx = (avatarSize * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 240);
    final cpf = (data['CPF'] ?? data['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: FotoMembroWidget(
        imageUrl: foto,
        memberData: data,
        tenantId: tenantId,
        memberId: entry.memberDocId,
        cpfDigits: cpf.length == 11 ? cpf : null,
        authUid: MemberProfilePhotoResolver.authUidFromData(
          data,
          memberDocId: entry.memberDocId,
        ),
        size: avatarSize,
        memCacheWidth: memPx,
        memCacheHeight: memPx,
        imageCacheRevision: memberPhotoDisplayCacheRevision(data) ?? 0,
        preferListThumbnail: true,
        backgroundColor:
            avatarColor ?? accent.withValues(alpha: 0.12),
      ),
    );

    return ChurchWisdomModuleListCard(
      title: nome,
      subtitle: subtitle.isEmpty ? null : subtitle,
      accent: accent,
      dense: dense,
      leading: avatar,
      onTap: () => openChurchLeaderContactPage(
        context,
        memberData: data,
        departmentNames: entry.subtitles,
        funcoes: entry.roles,
        tenantId: tenantId,
        memberDocId: entry.memberDocId,
        memberRole: role,
        viewerCpfDigits: viewerCpfDigits,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          YahwehSuperPremiumActionButton.chat(
            compact: true,
            onPressed: () => ChurchMemberContactChat.tapYahwehChat(
              context: context,
              tenantId: tenantId,
              memberRole: role,
              viewerCpfDigits: viewerCpfDigits,
              memberData: data,
              displayName: nome,
              memberDocId: entry.memberDocId,
            ),
          ),
          const SizedBox(width: 6),
          YahwehSuperPremiumActionButton.whatsapp(
            compact: true,
            onPressed: () => ChurchMemberContactChat.tapWhatsApp(
              context: context,
              memberData: data,
              tenantId: tenantId,
              memberDocId: entry.memberDocId,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card em grelha estilo atenção pastoral — com foto, nome completo e atalhos.
class ChurchPanelLeaderAttentionCard extends StatelessWidget {
  const ChurchPanelLeaderAttentionCard({
    super.key,
    required this.entry,
    required this.tenantId,
    required this.role,
    required this.viewerCpfDigits,
    required this.accent,
  });

  final ChurchPanelLeaderEntry entry;
  final String tenantId;
  final String role;
  final String viewerCpfDigits;
  final Color accent;

  String _fullName(Map<String, dynamic> data) {
    for (final k in const ['NOME_COMPLETO', 'nome', 'name', 'NOME']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return entry.displayName.trim().isNotEmpty ? entry.displayName.trim() : 'Membro';
  }

  @override
  Widget build(BuildContext context) {
    final data = entry.memberData;
    final nome = _fullName(data);
    final subtitle = entry.subtitleLine;
    final foto = MemberProfilePhotoResolver.displayRef(data, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(data, preferThumb: true);
    final avatarColor = avatarColorForMember(data, hasPhoto: hasFoto);
    final cpf = (data['CPF'] ?? data['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final initial = nome.isNotEmpty ? nome[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
            ThemeCleanPremium.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FotoMembroWidget(
                  imageUrl: foto,
                  memberData: data,
                  tenantId: tenantId,
                  memberId: entry.memberDocId,
                  cpfDigits: cpf.length == 11 ? cpf : null,
                  authUid: MemberProfilePhotoResolver.authUidFromData(
                    data,
                    memberDocId: entry.memberDocId,
                  ),
                  size: 52,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
                  preferListThumbnail: true,
                  backgroundColor:
                      avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  fallbackChild: CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.15),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: -0.25,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (subtitle.trim().isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: YahwehSuperPremiumActionButton.chat(
                    compact: true,
                    onPressed: () => ChurchMemberContactChat.tapYahwehChat(
                      context: context,
                      tenantId: tenantId,
                      memberRole: role,
                      viewerCpfDigits: viewerCpfDigits,
                      memberData: data,
                      displayName: nome,
                      memberDocId: entry.memberDocId,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: YahwehSuperPremiumActionButton.whatsapp(
                    compact: true,
                    onPressed: () => ChurchMemberContactChat.tapWhatsApp(
                      context: context,
                      memberData: data,
                      tenantId: tenantId,
                      memberDocId: entry.memberDocId,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Legado — mantido para imports externos; delega ao card WISDOMAPP.
class ChurchPanelLeaderTile extends StatelessWidget {
  const ChurchPanelLeaderTile({
    super.key,
    required this.narrow,
    required this.entry,
    required this.tenantId,
    required this.role,
    required this.viewerCpfDigits,
  });

  final bool narrow;
  final ChurchPanelLeaderEntry entry;
  final String tenantId;
  final String role;
  final String viewerCpfDigits;

  @override
  Widget build(BuildContext context) {
    final accent = entry.roles.isNotEmpty
        ? _kCorpoAdminAccent
        : _kDeptLeadersAccent;
    return ChurchPanelLeaderWisdomCard(
      entry: entry,
      tenantId: tenantId,
      role: role,
      viewerCpfDigits: viewerCpfDigits,
      accent: accent,
      dense: narrow,
    );
  }
}

class ChurchPanelLeaderContactTile extends StatelessWidget {
  const ChurchPanelLeaderContactTile({
    super.key,
    required this.narrow,
    required this.nome,
    required this.subtitle,
    required this.avatar,
    required this.onTap,
    this.onChat,
    this.onWhatsApp,
  });

  final bool narrow;
  final String nome;
  final String subtitle;
  final Widget avatar;
  final VoidCallback onTap;
  final VoidCallback? onChat;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return ChurchWisdomModuleListCard(
      title: nome,
      subtitle: subtitle.trim().isEmpty ? null : subtitle,
      accent: ThemeCleanPremium.primary,
      dense: narrow,
      leading: avatar,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onChat != null)
            YahwehSuperPremiumActionButton.chat(
              compact: true,
              onPressed: onChat,
            ),
          if (onChat != null && onWhatsApp != null) const SizedBox(width: 6),
          if (onWhatsApp != null)
            YahwehSuperPremiumActionButton.whatsapp(
              compact: true,
              onPressed: onWhatsApp,
            ),
        ],
      ),
    );
  }
}
