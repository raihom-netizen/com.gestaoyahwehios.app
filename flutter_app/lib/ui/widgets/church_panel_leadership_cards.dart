import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_corpo_admin_roles.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/church_panel_leadership_load_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/pages/church_leader_contact_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';

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
  late Future<List<ChurchPanelLeaderEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ChurchPanelLeadershipCardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.section != widget.section ||
        oldWidget.panelCache != widget.panelCache ||
        oldWidget.membersDirectory != widget.membersDirectory) {
      _future = _load();
    }
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
    setState(() => _future = _load());
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
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _PanelLeadershipLoadError(
              message: widget.section ==
                      ChurchPanelLeadershipSection.departmentLeaders
                  ? 'Não foi possível carregar os líderes de departamento.'
                  : 'Não foi possível carregar o corpo administrativo.',
              onRetry: _reload,
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _emptyMessage,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          );
        }
        _scheduleWarmup(context, list);
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                constraints.maxWidth < ThemeCleanPremium.breakpointMobile;
            final tiles = <Widget>[];
            for (final entry in list) {
              tiles.add(
                _SafeLeaderTile(
                  builder: () => ChurchPanelLeaderTile(
                    narrow: narrow,
                    entry: entry,
                    tenantId: widget.tenantId,
                    role: widget.role,
                    viewerCpfDigits: widget.viewerCpfDigits,
                  ),
                ),
              );
            }
            return _layoutPremiumLeaderGallery(narrow: narrow, tiles: tiles);
          },
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

class _SafeLeaderTile extends StatelessWidget {
  const _SafeLeaderTile({required this.builder});

  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    try {
      return builder();
    } catch (e, st) {
      debugPrint('Painel liderança tile: $e\n$st');
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          border: Border.all(color: const Color(0xFFE2E8F4)),
        ),
        child: Text(
          'Não foi possível exibir este perfil.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
      );
    }
  }
}

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
    final data = entry.memberData;
    final nome = entry.displayName;
    final subtitle = entry.subtitleLine;
    final foto = MemberProfilePhotoResolver.displayRef(data, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(data, preferThumb: true);
    final avatarColor = avatarColorForMember(data, hasPhoto: hasFoto);
    final avatarSize = narrow ? 52.0 : 72.0;
    final memPx = (avatarSize * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 280);
    final cpf = (data['CPF'] ?? data['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final avatarWidget = FotoMembroWidget(
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
          avatarColor ?? ThemeCleanPremium.primary.withValues(alpha: 0.1),
    );

    return ChurchPanelLeaderContactTile(
      narrow: narrow,
      nome: nome,
      subtitle: subtitle,
      avatar: avatarWidget,
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
      onChat: () => ChurchMemberContactChat.openChatIgrejaUnawaited(
        context: context,
        tenantId: tenantId,
        memberRole: role,
        viewerCpfDigits: viewerCpfDigits,
        memberData: data,
        displayName: nome,
        memberDocId: entry.memberDocId,
      ),
      onWhatsApp: () => unawaited(
        YahwehWhatsAppService.openForMember(
          context,
          data,
          tenantId: tenantId,
          memberDocId: entry.memberDocId,
        ),
      ),
    );
  }
}

/// Cartão premium — avatar, nome, Chat e WhatsApp.
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

  static Widget _ringAvatar(Widget inner, double diameter) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [ThemeCleanPremium.primary, ThemeCleanPremium.primaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: ColoredBox(color: Colors.white, child: inner),
        ),
      ),
    );
  }

  BoxDecoration get _shellDecoration => BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            ThemeCleanPremium.primary.withValues(alpha: 0.045),
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E8F4)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      );

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: narrow ? 15 : 14,
      letterSpacing: 0.2,
      color: ThemeCleanPremium.onSurface,
    );
    final subStyle = TextStyle(
      fontSize: narrow ? 12.5 : 12,
      height: 1.25,
      color: ThemeCleanPremium.onSurfaceVariant,
    );

    Widget contactButtons() {
      if (onChat == null && onWhatsApp == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: narrow ? 10 : 12),
        child: Row(
          children: [
            if (onChat != null)
              Expanded(
                child: YahwehSuperPremiumActionButton.chat(
                  compact: true,
                  label: 'Chat',
                  onPressed: onChat,
                ),
              ),
            if (onChat != null && onWhatsApp != null) const SizedBox(width: 6),
            if (onWhatsApp != null)
              Expanded(
                child: YahwehSuperPremiumActionButton.whatsapp(
                  compact: true,
                  label: 'WhatsApp',
                  onPressed: onWhatsApp,
                ),
              ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: narrow ? 12 : 14,
        ),
        decoration: _shellDecoration,
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onTap,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ringAvatar(avatar, 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle,
                              ),
                              if (subtitle.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: subStyle,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: ThemeCleanPremium.primary
                              .withValues(alpha: 0.55),
                        ),
                      ],
                    ),
                  ),
                  contactButtons(),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onTap,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ringAvatar(avatar, 72),
                        const SizedBox(height: 12),
                        Text(
                          nome,
                          style: nameStyle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: subStyle,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  contactButtons(),
                ],
              ),
      ),
    );
  }
}

class _PanelLeadershipLoadError extends StatelessWidget {
  const _PanelLeadershipLoadError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.cloud_off_rounded,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.88),
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(
                  foregroundColor: ThemeCleanPremium.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _layoutPremiumLeaderGallery({
  required bool narrow,
  required List<Widget> tiles,
}) {
  if (narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          tiles[i],
        ],
      ],
    );
  }
  return Wrap(
    spacing: 14,
    runSpacing: 14,
    children: tiles.map((w) => SizedBox(width: 160, child: w)).toList(),
  );
}
