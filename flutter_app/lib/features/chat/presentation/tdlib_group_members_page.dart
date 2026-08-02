import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';

/// Participantes do grupo + membros do departamento sem telefone (visão líder).
class TdlibGroupMembersPage extends StatefulWidget {
  const TdlibGroupMembersPage({
    super.key,
    required this.chatId,
    required this.title,
    required this.churchId,
    this.departmentId = '',
    this.departmentName = '',
  });

  final int chatId;
  final String title;
  final String churchId;
  final String departmentId;
  final String departmentName;

  @override
  State<TdlibGroupMembersPage> createState() => _TdlibGroupMembersPageState();
}

class _TdlibGroupMembersPageState extends State<TdlibGroupMembersPage> {
  static const _accent = Color(0xFF0D9488);

  static String _phoneRegistrationMessage(String displayName) =>
      'Olá $displayName, cadastre seu telefone (mesmo do Telegram) no app Gestão YAHWEH para entrar no grupo do departamento.';

  Future<void> _requestMemberPhoneViaWhatsApp(MemberDirectoryEntry e) async {
    await YahwehWhatsAppService.openWithMessage(
      phoneDigits: e.telefone,
      message: _phoneRegistrationMessage(e.displayName),
    );
  }

  bool _loading = true;
  List<TdlibChatMember> _members = const [];
  List<MemberDirectoryEntry> _missingPhone = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _inDepartment(MemberDirectoryEntry e) {
    final name = widget.departmentName.trim().toLowerCase();
    final deptId = widget.departmentId.trim().toLowerCase();
    if (name.isEmpty && deptId.isEmpty) return true;
    final depts = e.departamentos
        .map((d) => d.trim().toLowerCase())
        .where((d) => d.isNotEmpty)
        .toList();
    return (name.isNotEmpty && depts.contains(name)) ||
        (deptId.isNotEmpty &&
            (depts.contains(deptId) ||
                e.departamentos.contains(widget.departmentId)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final members = await TdLibService.instance.getChatMembers(widget.chatId);
    final snap = MembersDirectorySnapshotService.peekMemory(widget.churchId);
    final missing = <MemberDirectoryEntry>[];
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      if (!_inDepartment(e)) continue;
      final phone = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      if (phone.length < 10) missing.add(e);
    }
    if (!mounted) return;
    setState(() {
      _members = members;
      _missingPhone = missing;
      _loading = false;
    });
  }

  MemberDirectoryEntry? _matchDirectory(TdlibChatMember m) {
    final snap = MembersDirectorySnapshotService.peekMemory(widget.churchId);
    final phone = (m.phoneDigits ?? '').replaceAll(RegExp(r'\D'), '');
    final name = m.displayName.trim().toLowerCase();
    for (final e in snap?.entries ?? const <MemberDirectoryEntry>[]) {
      final ep = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      if (phone.length >= 10 &&
          ep.length >= 8 &&
          ep.endsWith(phone.substring(phone.length - 8))) {
        return e;
      }
      if (e.displayName.trim().toLowerCase() == name) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: Text(
          'Participantes · ${widget.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Text(
                    '${_members.length} no grupo',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Ainda não foi possível listar os participantes.\n'
                        'Abra o grupo e tente atualizar.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._members.map((m) {
                      final dir = _matchDirectory(m);
                      final color =
                          m.isAdmin ? const Color(0xFF2563EB) : _accent;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: color.withValues(alpha: 0.25),
                              ),
                            ),
                            leading: dir != null
                                ? FotoMembroWidget(
                                    size: 44,
                                    tenantId: widget.churchId,
                                    memberId: dir.memberDocId,
                                    imageUrl:
                                        dir.photoThumbUrl ?? dir.photoUrl,
                                    memberData: dir.toMemberDataMap(),
                                    authUid: dir.authUid,
                                    cpfDigits: dir.cpfDigits,
                                    preferListThumbnail: true,
                                    imageCacheRevision:
                                        dir.fotoUrlCacheRevision,
                                  )
                                : CircleAvatar(
                                    backgroundColor:
                                        color.withValues(alpha: 0.15),
                                    child: Text(
                                      m.displayName.isEmpty
                                          ? '?'
                                          : m.displayName
                                              .substring(0, 1)
                                              .toUpperCase(),
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                            title: Text(
                              m.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              m.isAdmin
                                  ? 'Administrador'
                                  : (dir?.departamentos.isNotEmpty == true
                                      ? dir!.departamentos.take(2).join(' · ')
                                      : 'Participante'),
                            ),
                            trailing: m.isAdmin
                                ? Icon(Icons.shield_rounded, color: color)
                                : null,
                          ),
                        ),
                      );
                    }),
                  if (_missingPhone.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Sem telefone no cadastro (${_missingPhone.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estes membros estão no departamento, mas não entram no grupo automático até cadastrar o telefone (mesmo do Telegram).',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._missingPhone.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(color: Color(0xFFFCD34D)),
                            ),
                            leading: FotoMembroWidget(
                              size: 44,
                              tenantId: widget.churchId,
                              memberId: e.memberDocId,
                              imageUrl: e.photoThumbUrl ?? e.photoUrl,
                              memberData: e.toMemberDataMap(),
                              authUid: e.authUid,
                              cpfDigits: e.cpfDigits,
                              preferListThumbnail: true,
                              imageCacheRevision: e.fotoUrlCacheRevision,
                            ),
                            title: Text(
                              e.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle:
                                const Text('Cadastre o telefone em Membros'),
                            trailing: IconButton(
                              tooltip: 'Cobrar telefone',
                              icon: const Icon(
                                Icons.sms_rounded,
                                color: Color(0xFFB45309),
                              ),
                              onPressed: () =>
                                  unawaited(_requestMemberPhoneViaWhatsApp(e)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
