import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_hub_departments_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/pages/church_telegram_in_app_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Hub do chat — **Telegram embutido** (web.telegram.org dentro do app).
/// Departamentos da igreja = grupos Telegram (`telegramInviteUrl` no doc).
/// Paridade: Web + Android + iOS (mesmo módulo do shell).
class ChurchTelegramChatHubPage extends StatefulWidget {
  const ChurchTelegramChatHubPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf = '',
    this.permissions = const [],
    this.embeddedInShell = false,
    this.onShellBack,
  });

  final String tenantId;
  final String role;
  final String cpf;
  final List<String>? permissions;
  final bool embeddedInShell;
  final VoidCallback? onShellBack;

  @override
  State<ChurchTelegramChatHubPage> createState() =>
      _ChurchTelegramChatHubPageState();
}

class _ChurchTelegramChatHubPageState extends State<ChurchTelegramChatHubPage> {
  bool _loading = true;
  Object? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _depts = const [];

  String get _churchId => ChurchRepository.churchId(widget.tenantId.trim());

  bool get _canManageLinks => AppPermissions.canEditDepartments(
        widget.role,
        permissions: widget.permissions,
      );

  @override
  void initState() {
    super.initState();
    final peek = ChurchChatHubDepartmentsService.peekInstant(widget.tenantId);
    if (peek != null && peek.isNotEmpty) {
      _depts = peek;
      _loading = false;
    }
    ChurchPanelNavigationBridge.instance
        .registerChatOpenListener(_onPendingChatOpen);
    unawaited(_reload());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumePendingChatOpen());
    });
  }

  @override
  void dispose() {
    ChurchPanelNavigationBridge.instance
        .unregisterChatOpenListener(_onPendingChatOpen);
    super.dispose();
  }

  void _onPendingChatOpen() {
    unawaited(_consumePendingChatOpen());
  }

  Future<void> _consumePendingChatOpen() async {
    if (!mounted) return;
    final pending =
        ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
    if (pending == null) return;

    var phone = (pending.phoneDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10 && (pending.peerUid ?? '').isNotEmpty) {
      final snap =
          MembersDirectorySnapshotService.peekMemory(_churchId);
      final peer = (pending.peerUid ?? '').trim();
      for (final e in snap?.entries ?? const []) {
        if ((e.authUid ?? '').trim() == peer) {
          phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
          break;
        }
      }
    }
    final dm = ChurchTelegramLauncher.dmUrlFromPhone(phone);
    if (dm != null && mounted) {
      await ChurchTelegramInAppPage.open(
        context,
        urlOrHandle: dm,
        title: pending.displayName ?? 'Yahweh Chat',
        subtitle: 'Conversa no Yahweh Chat',
      );
      return;
    }
    // Sem telefone: abre o cliente Telegram (lista de chats).
    if (mounted) await _openTelegramHome();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    if (_depts.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await ChurchChatHubDepartmentsService.load(
        seedTenantId: widget.tenantId,
        forceServer: true,
      );
      if (!mounted) return;
      setState(() {
        _depts = r.docs;
        _loading = false;
        // Soft error só bloqueia UI se não houver lista local.
        _error = r.docs.isEmpty ? r.softError : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _openDeptTelegram(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final link = ChurchTelegramLauncher.inviteFromDeptData(data);
    if (link == null) {
      if (_canManageLinks) {
        await _editTelegramLink(doc);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Este departamento ainda não tem grupo de chat. Peça à gestão para colar o link de convite.',
          ),
        );
      }
      return;
    }
    await ChurchTelegramInAppPage.open(
      context,
      urlOrHandle: link,
      title: churchDepartmentNameFromDoc(doc),
      subtitle: 'Grupo do departamento · Yahweh Chat',
    );
  }

  Future<void> _openTelegramHome() async {
    await ChurchTelegramInAppPage.open(
      context,
      urlOrHandle: ChurchTelegramLauncher.kWebClientHome,
      title: 'Yahweh Chat',
      subtitle: 'Conversas, fotos, vídeos e arquivos',
    );
  }

  Future<void> _editTelegramLink(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final current =
        ChurchTelegramLauncher.inviteFromDeptData(doc.data()) ?? '';
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Text(
          'Yahweh Chat — ${churchDepartmentNameFromDoc(doc)}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Crie o grupo de chat (ou use um existente), copie o link de convite e cole abaixo. Fotos, vídeos e arquivos ficam no Yahweh Chat.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Link de convite do grupo',
                hintText: 'Cole o link de convite aqui',
                prefixIcon: const Icon(Icons.forum_rounded, color: Color(0xFF0D9488)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final raw = ctrl.text.trim();
    ctrl.dispose();
    final normalized = raw.isEmpty
        ? null
        : ChurchTelegramLauncher.normalizeInviteOrGroupUrl(raw);
    if (raw.isNotEmpty && normalized == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Link inválido. Cole o link de convite completo do grupo.',
          ),
        );
      }
      return;
    }
    try {
      await doc.reference.set(
        {
          if (normalized != null)
            'telegramInviteUrl': normalized
          else
            'telegramInviteUrl': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            normalized != null
                ? 'Grupo de chat ligado ao departamento.'
                : 'Link removido.',
          ),
        );
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    }
  }

  Future<void> _openMemberDmPicker() async {
    final tid = _churchId;
    final snap = MembersDirectorySnapshotService.peekMemory(tid);
    final entries = snap?.entries ?? const [];
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Lista de membros ainda a carregar. Abra Membros e volte.',
          ),
        );
      }
      return;
    }
    final qCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final q = filter.toLowerCase();
            final list = entries.where((e) {
              if (q.isEmpty) return true;
              return e.displayName.toLowerCase().contains(q);
            }).take(80).toList();
            return Container(
              height: MediaQuery.sizeOf(ctx).height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: TextField(
                      controller: qCtrl,
                      onChanged: (v) => setLocal(() => filter = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Buscar membro…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Abre conversa no Yahweh Chat (pelo telefone do cadastro).',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final phone = (e.telefone ?? '').toString();
                        final dm = ChurchTelegramLauncher.dmUrlFromPhone(phone);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                const Color(0xFF0D9488).withValues(alpha: 0.15),
                            child: const Icon(Icons.person_rounded,
                                color: Color(0xFF0D9488)),
                          ),
                          title: Text(
                            e.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            dm != null
                                ? 'Abrir no Yahweh Chat'
                                : 'Sem telefone no cadastro',
                            style: TextStyle(
                              fontSize: 12,
                              color: dm != null
                                  ? const Color(0xFF0D9488)
                                  : Colors.grey.shade600,
                            ),
                          ),
                          enabled: dm != null,
                          onTap: dm == null
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  await ChurchTelegramInAppPage.open(
                                    context,
                                    urlOrHandle: dm,
                                    title: e.displayName,
                                    subtitle: 'Conversa no Yahweh Chat',
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
        );
      },
    );
    qCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = kChurchShellNavEntries.length > 23
        ? kChurchShellNavEntries[23].accent
        : const Color(0xFF0D9488);

    final body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.08),
            const Color(0xFFF8FAFC),
          ],
        ),
      ),
      child: Column(
        children: [
          if (widget.embeddedInShell && widget.onShellBack != null)
            ChurchEmbeddedModuleBar(
              title: 'Yahweh Chat',
              icon: Icons.forum_rounded,
              accent: const Color(0xFF0D9488),
              onBack: widget.onShellBack!,
              subtitle: 'Motor Telegram · fotos, vídeos, áudios e arquivos',
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F766E),
                    Color(0xFF0D9488),
                    Color(0xFF14B8A6),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.forum_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yahweh Chat',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Motor Telegram real — mesma velocidade para mídia. '
                              'Na 1ª vez, entre com o número do seu Telegram.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _TgMediaChip(Icons.photo_camera_rounded, 'Fotos'),
                      _TgMediaChip(Icons.videocam_rounded, 'Vídeos'),
                      _TgMediaChip(Icons.mic_rounded, 'Áudios'),
                      _TgMediaChip(Icons.attach_file_rounded, 'Arquivos'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_openTelegramHome()),
                    icon: const Icon(Icons.forum_rounded, size: 18),
                    label: const Text('Abrir chat'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openMemberDmPicker,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: const Text('Privada'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Atualizar grupos',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Grupos por departamento',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ChurchPanelResilientLoadBanner(
                hasLocalData: _depts.isNotEmpty,
                isSyncing: false,
                errorTitle: 'Não foi possível atualizar os grupos',
                error: _error,
                onRetry: _reload,
              ),
            ),
          Expanded(
            child: _loading && _depts.isEmpty
                ? const ChurchPanelLoadingBody()
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _depts.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(24),
                            children: [
                              Icon(Icons.groups_outlined,
                                  size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum departamento ainda.\n'
                                'Crie departamentos e, como gestão, cole o link de convite do grupo Telegram em cada um (ícone de engrenagem).',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _depts.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final d = _depts[i];
                              final name = churchDepartmentNameFromDoc(d);
                              final link = ChurchTelegramLauncher
                                  .inviteFromDeptData(d.data());
                              final ready = link != null;
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => unawaited(_openDeptTelegram(d)),
                                  onLongPress: _canManageLinks
                                      ? () => unawaited(_editTelegramLink(d))
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: ready
                                            ? const Color(0xFF0D9488)
                                                .withValues(alpha: 0.35)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                      boxShadow:
                                          ThemeCleanPremium.softUiCardShadow,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0D9488)
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: const Icon(
                                            Icons.forum_rounded,
                                            color: Color(0xFF0D9488),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                ready
                                                    ? 'Grupo Telegram · fotos, vídeos e arquivos'
                                                    : (_canManageLinks
                                                        ? 'Toque para colar o link de convite Telegram'
                                                        : 'Aguardando link da gestão'),
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: ready
                                                      ? const Color(0xFF0D9488)
                                                      : Colors.grey.shade600,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_canManageLinks)
                                          IconButton(
                                            tooltip: 'Configurar link',
                                            onPressed: () =>
                                                unawaited(_editTelegramLink(d)),
                                            icon: Icon(
                                              Icons.settings_rounded,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: ready
                                              ? const Color(0xFF0D9488)
                                              : Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );

    if (widget.embeddedInShell) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yahweh Chat'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}

class _TgMediaChip extends StatelessWidget {
  const _TgMediaChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
