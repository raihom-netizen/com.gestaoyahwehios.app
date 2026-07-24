import 'dart:async' show StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_hub_departments_service.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/pages/church_telegram_in_app_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';

/// Yahweh Chat — motor **TDLib** (Telegram Database Library).
///
/// - Sessão isolada por igreja (DB local `tdlib/{churchId}`).
/// - Departamentos e membros vêm do Firestore desta igreja.
/// - Após 1º login OTP no aparelho, reabre automático (sem colar link).
/// - Web: mesma UI; conversas abrem no cliente Telegram embutido (sem paste).
class ChurchYahwehTdlibHubPage extends StatefulWidget {
  const ChurchYahwehTdlibHubPage({
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
  State<ChurchYahwehTdlibHubPage> createState() =>
      _ChurchYahwehTdlibHubPageState();
}

class _ChurchYahwehTdlibHubPageState extends State<ChurchYahwehTdlibHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  StreamSubscription<TdlibAuthSnapshot>? _authSub;
  StreamSubscription<List<TdlibChatPreview>>? _chatsSub;

  TdlibAuthSnapshot _auth = TdlibAuthSnapshot.idle;
  List<TdlibChatPreview> _chats = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _depts = const [];
  bool _loadingDepts = true;
  Object? _deptError;

  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '+55');
  bool _authBusy = false;
  String? _authLocalError;
  String? _myPhoneDigits;
  bool _autoPhoneTried = false;

  String get _churchId => ChurchRepository.churchId(widget.tenantId.trim());

  bool get _canManageLinks => AppPermissions.canEditDepartments(
        widget.role,
        permissions: widget.permissions,
      );

  bool get _tdlibReady =>
      TdLibService.instance.isSupported &&
      _auth.phase == TdlibAuthPhase.ready;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final peek = ChurchChatHubDepartmentsService.peekInstant(widget.tenantId);
    if (peek != null && peek.isNotEmpty) {
      _depts = peek;
      _loadingDepts = false;
    }
    ChurchPanelNavigationBridge.instance
        .registerChatOpenListener(_onPendingChatOpen);
    unawaited(_boot());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumePendingChatOpen());
    });
  }

  Future<void> _boot() async {
    await _resolveMyPhone();
    await _reloadDepts();
    final svc = TdLibService.instance;
    _authSub = svc.authorizationStateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _auth = snap);
      if (snap.phase == TdlibAuthPhase.waitPhoneNumber) {
        unawaited(_tryAutoPhone());
      }
      if (snap.phase == TdlibAuthPhase.ready) {
        unawaited(svc.refreshChats());
      }
    });
    _chatsSub = svc.chatsStream.listen((list) {
      if (!mounted) return;
      setState(() => _chats = list);
    });
    if (svc.isSupported) {
      await svc.init(churchId: _churchId);
      if (mounted) setState(() => _auth = svc.currentAuth);
    } else if (mounted) {
      setState(() => _auth = TdlibAuthSnapshot.unsupported);
    }
  }

  Future<void> _resolveMyPhone() async {
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || _churchId.isEmpty) return;
    try {
      final hit = await ChurchUiMemberPhone.resolve(
        tenantId: _churchId,
        authUid: uid,
      );
      if (!mounted) return;
      if (hit != null && hit.length >= 10) {
        setState(() {
          _myPhoneDigits = hit;
          _phoneCtrl.text = hit.startsWith('55') ? '+$hit' : '+55$hit';
        });
      }
    } catch (_) {}
  }

  Future<void> _tryAutoPhone() async {
    if (_autoPhoneTried || _authBusy) return;
    final phone = _phoneCtrl.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 12) return;
    _autoPhoneTried = true;
    await _runAuth(() => TdLibService.instance.sendPhoneNumber(phone));
  }

  Future<void> _reloadDepts() async {
    if (!mounted) return;
    if (_depts.isEmpty) {
      setState(() {
        _loadingDepts = true;
        _deptError = null;
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
        _loadingDepts = false;
        _deptError = r.docs.isEmpty ? r.softError : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDepts = false;
        _deptError = e;
      });
    }
  }

  void _onPendingChatOpen() => unawaited(_consumePendingChatOpen());

  Future<void> _consumePendingChatOpen() async {
    if (!mounted) return;
    final pending =
        ChurchPanelNavigationBridge.instance.consumePendingChatThreadOpen();
    if (pending == null) return;
    var phone = (pending.phoneDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10 && (pending.peerUid ?? '').isNotEmpty) {
      final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
      final peer = (pending.peerUid ?? '').trim();
      for (final e in snap?.entries ?? const []) {
        if ((e.authUid ?? '').trim() == peer) {
          phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
          break;
        }
      }
    }
    if (phone.length >= 10) {
      await _openMemberDm(
        phone: phone,
        title: pending.displayName ?? 'Conversa',
      );
    }
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _authBusy = true;
      _authLocalError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _authLocalError = e.toString());
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _openMemberDm({
    required String phone,
    required String title,
  }) async {
    if (_tdlibReady) {
      try {
        final chatId =
            await TdLibService.instance.openPrivateChatByPhone(phone);
        if (!mounted) return;
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(
            builder: (_) => ChurchYahwehTdlibThreadPage(
              chatId: chatId,
              title: title,
            ),
          ),
        );
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
              'Não foi possível abrir no TDLib: $e',
            ),
          );
        }
      }
    }
    // Web / fallback: cliente Telegram embutido pelo telefone (sem paste).
    final dm = ChurchTelegramLauncher.dmUrlFromPhone(phone);
    if (dm == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Cadastre o telefone do membro (mesmo do Telegram).',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await ChurchTelegramInAppPage.open(
      context,
      urlOrHandle: dm,
      title: title,
      subtitle: 'Motor Telegram · conversa privada',
    );
  }

  Future<void> _openDept(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final name = churchDepartmentNameFromDoc(doc);
    final invite = ChurchTelegramLauncher.inviteFromDeptData(data);
    final storedChatId = int.tryParse(
      (data['telegramChatId'] ?? data['tdlibChatId'] ?? '').toString(),
    );

    if (_tdlibReady) {
      try {
        int chatId;
        if (storedChatId != null && storedChatId != 0) {
          chatId = storedChatId;
          await TdLibService.instance.loadChatHistory(chatId);
        } else if (invite != null) {
          chatId = await TdLibService.instance.joinByInviteLink(invite);
          unawaited(doc.reference.set({
            'telegramChatId': chatId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)));
        } else if (_canManageLinks) {
          chatId = await _ensureDeptTelegramGroup(doc);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Gestão ainda não ligou o grupo deste departamento.',
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(
            builder: (_) => ChurchYahwehTdlibThreadPage(
              chatId: chatId,
              title: name,
            ),
          ),
        );
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Grupo: $e'),
          );
        }
      }
    }

    if (invite == null) {
      if (_canManageLinks) {
        await _editInvite(doc);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Peça à gestão para ligar o grupo do departamento (1 vez).',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await ChurchTelegramInAppPage.open(
      context,
      urlOrHandle: invite,
      title: name,
      subtitle: 'Grupo do departamento · Yahweh Chat',
    );
  }

  /// Gestão: cria o supergrupo no Telegram (integração TDLib) e grava o id.
  Future<int> _ensureDeptTelegramGroup(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final name = churchDepartmentNameFromDoc(doc);
    final created = await TdLibService.instance.createDepartmentSupergroup(
      title: 'Yahweh · $name',
      description: 'Grupo do departamento $name (Gestão Yahweh)',
    );
    final payload = <String, dynamic>{
      'telegramChatId': created.chatId,
      'tdlibChatId': created.chatId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (created.inviteLink != null && created.inviteLink!.isNotEmpty) {
      payload['telegramInviteUrl'] = created.inviteLink;
    }
    await doc.reference.set(payload, SetOptions(merge: true));

    final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
    final deptId = doc.id;
    final nameLc = name.toLowerCase();
    var invited = 0;
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      final depts = e.departamentos.map((d) => d.toLowerCase()).toList();
      final inDept = depts.contains(nameLc) ||
          depts.contains(deptId.toLowerCase()) ||
          e.departamentos.contains(deptId);
      if (!inDept) continue;
      final phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      if (phone.length < 10) continue;
      final ok = await TdLibService.instance
          .addChatMemberByPhone(created.chatId, phone);
      if (ok) invited++;
    }
    if (mounted && invited > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Grupo criado. $invited membro(s) convidado(s) no Telegram.',
        ),
      );
    }
    await _reloadDepts();
    return created.chatId;
  }

  Future<void> _editInvite(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final current =
        ChurchTelegramLauncher.inviteFromDeptData(doc.data()) ?? '';
    final hasTdlib = _tdlibReady;

    if (hasTdlib) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          title: Text('Grupo · ${churchDepartmentNameFromDoc(doc)}'),
          content: const Text(
            'Crie o grupo automático com sua integração TDLib '
            '(recomendado) ou cole um link já existente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'paste'),
              child: const Text('Colar link'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'create'),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Criar automático'),
            ),
          ],
        ),
      );
      if (choice == 'create') {
        try {
          final chatId = await _ensureDeptTelegramGroup(doc);
          if (!mounted) return;
          await Navigator.of(context, rootNavigator: true).push<void>(
            MaterialPageRoute(
              builder: (_) => ChurchYahwehTdlibThreadPage(
                chatId: chatId,
                title: churchDepartmentNameFromDoc(doc),
              ),
            ),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar('Falha ao criar grupo: $e'),
            );
          }
        }
        return;
      }
      if (choice != 'paste') return;
    }

    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Text('Grupo · ${churchDepartmentNameFromDoc(doc)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cole o link de convite do grupo Telegram deste departamento '
              '(opcional se já criar automático no app).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Link de convite',
                hintText: 'https://t.me/+…',
              ),
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
    final normalized =
        ChurchTelegramLauncher.normalizeInviteOrGroupUrl(ctrl.text.trim());
    ctrl.dispose();
    if (normalized == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Link inválido.'),
        );
      }
      return;
    }
    await doc.reference.set({
      'telegramInviteUrl': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _reloadDepts();
  }

  @override
  void dispose() {
    ChurchPanelNavigationBridge.instance
        .unregisterChatOpenListener(_onPendingChatOpen);
    _authSub?.cancel();
    _chatsSub?.cancel();
    _tabs.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF0D9488);
    final body = Column(
      children: [
        if (widget.embeddedInShell && widget.onShellBack != null)
          ChurchEmbeddedModuleBar(
            title: YahwehContactButtonLabels.yahwehChat,
            icon: Icons.forum_rounded,
            accent: accent,
            onBack: widget.onShellBack!,
            subtitle: 'Motor TDLib · por igreja',
          ),
        _buildHero(accent),
        if (!_tdlibReady && TdLibService.instance.isSupported)
          _buildAuthCard(accent)
        else if (!TdLibService.instance.isSupported)
          _buildWebHint(accent),
        TabBar(
          controller: _tabs,
          labelColor: accent,
          indicatorColor: accent,
          tabs: const [
            Tab(text: 'Conversas'),
            Tab(text: 'Grupos'),
            Tab(text: 'Contatos'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildChatsTab(accent),
              _buildDeptsTab(accent),
              _buildContactsTab(accent),
            ],
          ),
        ),
      ],
    );

    if (widget.embeddedInShell) return ColoredBox(color: const Color(0xFFF8FAFC), child: body);
    return Scaffold(
      appBar: AppBar(
        title: const Text(YahwehContactButtonLabels.yahwehChat),
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildHero(Color accent) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [accent, Color.lerp(accent, const Color(0xFF134E4A), 0.35)!],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yahweh Chat',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            TdLibService.instance.isSupported
                ? (_tdlibReady
                    ? 'Motor TDLib ativo · esta igreja isolada · fotos, vídeos, áudios e arquivos'
                    : 'Usando sua integração Telegram (api_id/hash). Telefone do cadastro entra sozinho; só o código SMS na 1ª vez neste aparelho.')
                : 'Web: conversas pelo Telegram embutido. No Android/iOS o motor TDLib nativo fica completo.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _MediaChip(Icons.photo_camera_rounded, 'Fotos'),
              _MediaChip(Icons.videocam_rounded, 'Vídeos'),
              _MediaChip(Icons.mic_rounded, 'Áudios'),
              _MediaChip(Icons.attach_file_rounded, 'Arquivos'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebHint(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: const ListTile(
          leading: Icon(Icons.info_outline_rounded, color: Color(0xFF0D9488)),
          title: Text(
            'Na web o chat abre no Telegram embutido. No app Android/iOS usa TDLib nativo (sua integração).',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(Color accent) {
    final phase = _auth.phase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _auth.message ?? 'Autorização Telegram',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (_myPhoneDigits != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Telefone do cadastro: +$_myPhoneDigits (preenchido automático)',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
              if (_authLocalError != null) ...[
                const SizedBox(height: 8),
                Text(_authLocalError!,
                    style: const TextStyle(color: ThemeCleanPremium.error)),
              ],
              const SizedBox(height: 10),
              if (phase == TdlibAuthPhase.waitPhoneNumber ||
                  phase == TdlibAuthPhase.error) ...[
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone Telegram',
                    hintText: '+5562…',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                            () => TdLibService.instance
                                .sendPhoneNumber(_phoneCtrl.text),
                          ),
                  child: Text(_authBusy ? 'Enviando…' : 'Continuar'),
                ),
              ],
              if (phase == TdlibAuthPhase.waitCode) ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Código SMS',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                            () =>
                                TdLibService.instance.sendCode(_codeCtrl.text),
                          ),
                  child: Text(_authBusy ? 'Validando…' : 'Confirmar código'),
                ),
              ],
              if (phase == TdlibAuthPhase.waitPassword) ...[
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha 2FA',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _authBusy
                      ? null
                      : () => _runAuth(
                            () => TdLibService.instance
                                .sendPassword(_passwordCtrl.text),
                          ),
                  child: Text(_authBusy ? 'Validando…' : 'Entrar'),
                ),
              ],
              if (phase == TdlibAuthPhase.initializing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatsTab(Color accent) {
    if (!_tdlibReady) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.forum_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            TdLibService.instance.isSupported
                ? 'Conecte o motor TDLib acima (código SMS só na 1ª vez neste aparelho).'
                : 'Use as abas Grupos e Contatos — na web o Telegram embutido abre direto.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      );
    }
    if (_chats.isEmpty) {
      return const Center(child: Text('Nenhuma conversa ainda.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = _chats[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: accent.withValues(alpha: 0.2)),
            ),
            leading: CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.15),
              child: Icon(Icons.chat_bubble_rounded, color: accent),
            ),
            title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(c.lastMessagePreview ?? 'Abrir conversa'),
            trailing: c.unreadCount > 0
                ? CircleAvatar(
                    radius: 12,
                    backgroundColor: accent,
                    child: Text(
                      '${c.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => ChurchYahwehTdlibThreadPage(
                    chatId: c.id,
                    title: c.title,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDeptsTab(Color accent) {
    if (_loadingDepts && _depts.isEmpty) {
      return const ChurchPanelLoadingBody();
    }
    if (_deptError != null && _depts.isEmpty) {
      return ChurchPanelResilientLoadBanner(
        hasLocalData: false,
        isSyncing: false,
        errorTitle: 'Não foi possível carregar departamentos',
        error: _deptError,
        onRetry: _reloadDepts,
      );
    }
    if (_depts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum departamento nesta igreja.\nCrie em Departamentos — cada igreja fica separada.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reloadDepts,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _depts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = _depts[i];
          final ready = ChurchTelegramLauncher.inviteFromDeptData(d.data()) !=
                  null ||
              (d.data()['telegramChatId'] ?? '').toString().trim().isNotEmpty;
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: ready
                      ? accent.withValues(alpha: 0.35)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.12),
                child: Icon(Icons.groups_rounded, color: accent),
              ),
              title: Text(
                churchDepartmentNameFromDoc(d),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                ready
                    ? 'Abrir grupo (TDLib / Telegram)'
                    : (_canManageLinks
                        ? 'Toque: cria grupo automático (sem colar link)'
                        : 'Aguardando gestão'),
              ),
              trailing: _canManageLinks
                  ? IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => unawaited(_editInvite(d)),
                    )
                  : Icon(Icons.chevron_right_rounded, color: accent),
              onTap: () => unawaited(_openDept(d)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContactsTab(Color accent) {
    final snap = MembersDirectorySnapshotService.peekMemory(_churchId);
    final entries = snap?.entries ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Lista de membros desta igreja ainda a carregar.\nAbra Membros e volte — cada igreja fica separada.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length.clamp(0, 200),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        final phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
        final ok = phone.length >= 10;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: accent.withValues(alpha: 0.18)),
            ),
            leading: CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(Icons.person_rounded, color: accent),
            ),
            title: Text(
              e.displayName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              ok ? 'Abrir privada (Telegram)' : 'Sem telefone no cadastro',
            ),
            enabled: ok,
            trailing: Icon(
              Icons.chat_bubble_outline_rounded,
              color: ok ? accent : Colors.grey,
            ),
            onTap: !ok
                ? null
                : () => unawaited(
                      _openMemberDm(phone: phone, title: e.displayName),
                    ),
          ),
        );
      },
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip(this.icon, this.label);
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
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolve telefone do membro logado nesta igreja.
abstract final class ChurchUiMemberPhone {
  ChurchUiMemberPhone._();

  static Future<String?> resolve({
    required String tenantId,
    required String authUid,
  }) async {
    final snap = MembersDirectorySnapshotService.peekMemory(tenantId);
    for (final e in snap?.entries ?? const []) {
      if ((e.authUid ?? '').trim() == authUid) {
        final p = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
        if (p.length >= 10) return p;
      }
    }
    try {
      final doc = await ChurchRepository.churchDoc(tenantId)
          .collection('membros')
          .doc(authUid)
          .get();
      if (doc.exists) {
        final p = ChurchMemberContactChat.phoneDigitsFromMember(doc.data()!);
        if (p.length >= 10) return p;
      }
    } catch (_) {}
    return null;
  }
}

/// Thread TDLib — texto + anexo (foto/vídeo/arquivo).
class ChurchYahwehTdlibThreadPage extends StatefulWidget {
  const ChurchYahwehTdlibThreadPage({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<ChurchYahwehTdlibThreadPage> createState() =>
      _ChurchYahwehTdlibThreadPageState();
}

class _ChurchYahwehTdlibThreadPageState
    extends State<ChurchYahwehTdlibThreadPage> {
  final _textCtrl = TextEditingController();
  StreamSubscription<List<TdlibMessageItem>>? _sub;
  List<TdlibMessageItem> _messages = const [];
  bool _sending = false;

  static const _accent = Color(0xFF0D9488);

  @override
  void initState() {
    super.initState();
    _sub = TdLibService.instance.messagesStream.listen((list) {
      if (!mounted) return;
      setState(() => _messages = list);
    });
    unawaited(TdLibService.instance.loadChatHistory(widget.chatId));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final t = _textCtrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await TdLibService.instance.sendTextMessage(widget.chatId, t);
      _textCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Falha ao enviar: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSend() async {
    final result = await YahwehFilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    final name = result!.files.single.name.toLowerCase();
    var kind = 'document';
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic')) {
      kind = 'photo';
    } else if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.mkv')) {
      kind = 'video';
    } else if (name.endsWith('.ogg') ||
        name.endsWith('.m4a') ||
        name.endsWith('.mp3')) {
      kind = 'voice';
    }
    setState(() => _sending = true);
    try {
      await TdLibService.instance.sendLocalFile(
        widget.chatId,
        path,
        kind: kind,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Falha no anexo: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(
              'Motor TDLib · Telegram',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final mine = m.isOutgoing;
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                    ),
                    decoration: BoxDecoration(
                      color: mine ? _accent : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      m.preview,
                      style: const TextStyle(color: Colors.white, height: 1.35),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _pickAndSend,
                    icon: const Icon(Icons.attach_file_rounded,
                        color: Colors.white70),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Mensagem',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45)),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: _accent,
                    child: IconButton(
                      onPressed: _sending ? null : _sendText,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
