import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_display_name.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Folha para reencaminhar uma mensagem a outra conversa.
class ChurchChatForwardSheet extends StatelessWidget {
  const ChurchChatForwardSheet({
    super.key,
    required this.tenantId,
    required this.sourceThreadId,
    required this.messageId,
    required this.messageData,
  });

  final String tenantId;
  final String sourceThreadId;
  final String messageId;
  final Map<String, dynamic> messageData;

  static String threadRowTitle(
    Map<String, dynamic> data,
    String myUid,
    String threadId,
  ) {
    if (data['isDepartment'] == true) {
      final dept = (data['departmentName'] ?? data['title'] ?? '').toString().trim();
      if (dept.isNotEmpty) return dept;
      return 'Grupo';
    }
    final peers = (data['participantUids'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    final peer = peers.firstWhere((p) => p != myUid, orElse: () => '');
    final titles = data['titlesByUid'];
    String? fromThread;
    if (titles is Map && peer.isNotEmpty && titles[peer] != null) {
      fromThread = ChurchChatDisplayName.sanitize(titles[peer].toString());
    }
    return ChurchChatDisplayName.peerTitle(
      peerUid: peer,
      fromThreadTitle: fromThread,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sessão inválida.'),
        ),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Reencaminhar para',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Flexible(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChurchChatService.chatThreadsSnapshotsForUser(
                tenantId,
                uid,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = (snap.data?.docs ?? [])
                    .where((d) => d.id != sourceThreadId)
                    .toList();
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma outra conversa disponível.',
                      style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final title = threadRowTitle(data, uid, doc.id);
                    final preview =
                        (data['lastMessagePreview'] ?? '').toString();
                    return ListTile(
                      leading: Icon(
                        data['isDepartment'] == true
                            ? Icons.groups_rounded
                            : Icons.person_rounded,
                        color: ThemeCleanPremium.primary,
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: preview.isEmpty
                          ? null
                          : Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () async {
                        final block =
                            ChurchChatService.forwardBlockReason(messageData);
                        if (block != null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(block)),
                            );
                          }
                          return;
                        }
                        Navigator.pop(context);
                        final ok = await ChurchChatService.forwardMessageToThread(
                          tenantId: tenantId,
                          sourceThreadId: sourceThreadId,
                          targetThreadId: doc.id,
                          messageId: messageId,
                          messageData: messageData,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Mensagem reencaminhada.'
                                  : 'Não foi possível reencaminhar.',
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> show(
    BuildContext context, {
    required String tenantId,
    required String sourceThreadId,
    required String messageId,
    required Map<String, dynamic> messageData,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeCleanPremium.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => ChurchChatForwardSheet(
          tenantId: tenantId,
          sourceThreadId: sourceThreadId,
          messageId: messageId,
          messageData: messageData,
        ),
      ),
    );
  }
}
