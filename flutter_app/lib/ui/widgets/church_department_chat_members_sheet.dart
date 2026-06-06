import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/pages/church_chat_thread_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_department_avatar.dart';
import 'package:gestao_yahweh/ui/widgets/church_department_add_members_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show SafeCircleAvatarImage, imageUrlFromMap;
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Lista de membros do departamento + presença + DM (mesmo fluxo do hub do chat).
class ChurchDepartmentChatMembersSheet extends StatefulWidget {
  final BuildContext navigatorContext;
  final String tenantId;
  final String currentUid;
  final String departmentId;
  final String departmentName;
  final Map<String, dynamic>? departmentDocData;
  final String role;
  final String cpfDigits;
  final List<String>? permissions;

  const ChurchDepartmentChatMembersSheet({
    super.key,
    required this.navigatorContext,
    required this.tenantId,
    required this.currentUid,
    required this.departmentId,
    required this.departmentName,
    required this.departmentDocData,
    required this.role,
    required this.cpfDigits,
    this.permissions,
  });

  @override
  State<ChurchDepartmentChatMembersSheet> createState() =>
      _ChurchDepartmentChatMembersSheetState();
}

class _ChurchDepartmentChatMembersSheetState
    extends State<ChurchDepartmentChatMembersSheet> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = ChurchChatService.fetchActiveDepartmentMembers(
      tenantId: widget.tenantId,
      departmentId: widget.departmentId,
    );
  }

  void _reloadMembers() {
    setState(() {
      _membersFuture = ChurchChatService.fetchActiveDepartmentMembers(
        tenantId: widget.tenantId,
        departmentId: widget.departmentId,
      );
    });
  }

  Future<void> _openGroupChat(BuildContext sheetCtx) async {
    Navigator.of(sheetCtx).pop();
    if (!widget.navigatorContext.mounted) return;
    await Navigator.of(widget.navigatorContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: widget.tenantId,
          threadId: ChurchChatService.deptThreadId(widget.departmentId),
          title: widget.departmentName,
          isDepartment: true,
          departmentId: widget.departmentId,
          memberRole: widget.role,
          memberCpfDigits: widget.cpfDigits,
        ),
      ),
    );
  }

  Future<void> _openDm(
      BuildContext sheetCtx, String peerUid, String name) async {
    Navigator.of(sheetCtx).pop();
    await ChurchChatService.ensureDmThread(
      tenantId: widget.tenantId,
      uidA: widget.currentUid,
      uidB: peerUid,
      titleA: FirebaseAuth.instance.currentUser?.displayName ?? 'Eu',
      titleB: name,
    );
    final threadId =
        ChurchChatService.dmThreadId(widget.currentUid, peerUid);
    if (!widget.navigatorContext.mounted) return;
    await Navigator.of(widget.navigatorContext).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchChatThreadPage(
          tenantId: widget.tenantId,
          threadId: threadId,
          title: name,
          isDepartment: false,
          peerUid: peerUid,
          memberRole: widget.role,
          memberCpfDigits: widget.cpfDigits,
        ),
      ),
    );
  }

  Future<void> _onAddMembers(BuildContext sheetCtx) async {
    final ok = await showChurchDepartmentAddMembersSheet(
      sheetCtx,
      tenantId: widget.tenantId,
      departmentId: widget.departmentId,
      departmentName: widget.departmentName,
      role: widget.role,
      permissions: widget.permissions,
      departmentDocData: widget.departmentDocData,
      memberCpfDigits: widget.cpfDigits,
    );
    if (ok == true && mounted) _reloadMembers();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canEdit = AppPermissions.canManageDepartmentChatMembers(
      role: widget.role,
      permissions: widget.permissions,
      departmentData: widget.departmentDocData,
      memberCpfDigits: widget.cpfDigits,
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.74,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ThemeCleanPremium.surface,
                const Color(0xFFECFEFF).withValues(alpha: 0.65),
                const Color(0xFFF5F3FF).withValues(alpha: 0.5),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.onSurfaceVariant
                        .withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChurchChatDepartmentAvatar(
                      deptData: widget.departmentDocData,
                      fallbackName: widget.departmentName,
                      radius: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.departmentName,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              color: ThemeCleanPremium.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Membros com este departamento na ficha',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                          if (canEdit) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                onPressed: () => _onAddMembers(ctx),
                                icon: Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: ThemeCleanPremium.primary,
                                ),
                                label: Text(
                                  'Adicionar membros ao departamento',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: _membersFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nenhum membro ativo encontrado neste grupo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ThemeCleanPremium.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final d = doc.data();
                        final auth =
                            (d['authUid'] ?? d['firebaseUid'] ?? '')
                                .toString();
                        final nome = (d['NOME_COMPLETO'] ?? d['nome'] ?? '')
                            .toString()
                            .trim();
                        final label = nome.isEmpty
                            ? (auth.isNotEmpty ? auth : 'Membro')
                            : nome;
                        final canDm =
                            auth.isNotEmpty && auth != widget.currentUid;
                        final fotoUrl = imageUrlFromMap(d);
                        final dpr = MediaQuery.devicePixelRatioOf(context);
                        final mem = (48 * dpr).round().clamp(96, 220);
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: auth.isEmpty
                              ? CircleAvatar(
                                  backgroundColor: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.15),
                                  foregroundColor: ThemeCleanPremium.primary,
                                  child: Text(
                                    label.isNotEmpty
                                        ? label[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                )
                              : StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('igrejas')
                                      .doc(widget.tenantId)
                                      .collection('chat_presence')
                                      .doc(auth)
                                      .watchSafe(),
                                  builder: (context, ps) {
                                    final on = ChurchChatService
                                        .isOnlineFromSnapshot(ps.data);
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        SafeCircleAvatarImage(
                                          imageUrl: fotoUrl,
                                          radius: 22,
                                          memCacheSize: mem,
                                          fallbackIcon: Icons.person_rounded,
                                          fallbackColor:
                                              ThemeCleanPremium.primary,
                                          backgroundColor: ThemeCleanPremium
                                              .primary
                                              .withValues(alpha: 0.12),
                                        ),
                                        Positioned(
                                          right: -1,
                                          bottom: -1,
                                          child: Container(
                                            width: 13,
                                            height: 13,
                                            decoration: BoxDecoration(
                                              color: on
                                                  ? const Color(0xFF22C55E)
                                                  : const Color(0xFF9CA3AF),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                  color: Colors.white,
                                                  width: 2),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                          title: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: auth.isEmpty
                              ? Text(
                                  'Sem conta no app — convide a vincular o login',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('igrejas')
                                      .doc(widget.tenantId)
                                      .collection('chat_presence')
                                      .doc(auth)
                                      .watchSafe(),
                                  builder: (context, ps) {
                                    final on = ChurchChatService
                                        .isOnlineFromSnapshot(ps.data);
                                    return Text(
                                      on ? 'Online agora' : 'Offline',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: on
                                            ? const Color(0xFF15803D)
                                            : ThemeCleanPremium
                                                .onSurfaceVariant,
                                      ),
                                    );
                                  },
                                ),
                          trailing: canDm
                              ? IconButton(
                                  tooltip: 'Mensagem direta',
                                  icon: Icon(
                                    Icons.chat_rounded,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                  onPressed: () => _openDm(ctx, auth, label),
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: ThemeCleanPremium.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openGroupChat(ctx),
                    icon: const Icon(Icons.forum_rounded),
                    label: const Text(
                      'Abrir chat do grupo',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
