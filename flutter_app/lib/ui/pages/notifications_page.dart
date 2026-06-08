import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/internal_notification_inbox_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_foreground_notification_snackbar.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

class NotificationsPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  const NotificationsPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final Future<List<String>> _deptFuture;
  late final String _cpfDigits;

  @override
  void initState() {
    super.initState();
    _cpfDigits = widget.cpf.replaceAll(RegExp(r'[^0-9]'), '');
    _deptFuture = _loadMemberDepartments();
  }

  bool get _isAdmin {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  CollectionReference<Map<String, dynamic>> get _members =>
                ChurchOperationalPaths.churchDoc(widget.tenantId)
          .collection('membros');

  CollectionReference<Map<String, dynamic>> get _notifications =>
                ChurchOperationalPaths.churchDoc(widget.tenantId)
          .collection('notificacoes');

  Future<List<String>> _loadMemberDepartments() async {
    if (_cpfDigits.isEmpty) return <String>[];
    try {
      final byId = await _members.doc(_cpfDigits).get(
            const GetOptions(source: Source.serverAndCache),
          );
      if (byId.exists) {
        return _deptList(byId.data());
      }
    } catch (_) {}
    try {
      final q = await _members
          .where('CPF', isEqualTo: _cpfDigits)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));
      if (q.docs.isNotEmpty) return _deptList(q.docs.first.data());
    } catch (_) {}
    return <String>[];
  }

  List<String> _deptList(Map<String, dynamic>? data) {
    final raw = data?['DEPARTAMENTOS'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _merge(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> a,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> b,
  ) {
    final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in a) {
      map[d.id] = d;
    }
    for (final d in b) {
      map[d.id] = d;
    }
    final out = map.values.toList();
    out.sort((x, y) {
      final dx = (x.data()['createdAt'] as Timestamp?)?.toDate();
      final dy = (y.data()['createdAt'] as Timestamp?)?.toDate();
      if (dx == null || dy == null) return 0;
      return dy.compareTo(dx);
    });
    return out;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _memberNotificationsStream {
    if (_cpfDigits.isEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _notifications
        .where('memberCpfs', arrayContains: _cpfDigits)
        .watchSafe();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: isMobile ? null : AppBar(title: const Text('Notificacoes')),
      body: SafeArea(
        child: _isAdmin ? _buildAdminBody() : _buildMemberBody(),
      ),
    );
  }

  Widget _buildAdminBody() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _notifications
          .orderBy('createdAt', descending: true)
          .limit(120)
          .watchSafe(),
      builder: (context, snap) {
        if (uid.isEmpty) {
          return _adminListFromSnap(snap);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: InternalNotificationInboxService.watch(uid),
          builder: (context, inboxSnap) {
            final tenantDocs = snap.data?.docs ?? [];
            final inboxDocs = inboxSnap.data?.docs ?? [];
            final merged = _mergeInbox(tenantDocs, inboxDocs);
            if (snap.hasError && inboxSnap.hasError) {
              return Center(
                child: Text(
                  'Erro ao carregar.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              );
            }
            if (merged.isEmpty &&
                snap.connectionState == ConnectionState.waiting &&
                inboxSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (merged.isEmpty) {
              return const Center(child: Text('Nenhuma notificacao.'));
            }
            return _buildList(merged);
          },
        );
      },
    );
  }

  Widget _adminListFromSnap(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
  ) {
    if (snap.hasError) {
      return Center(
        child: Text(
          'Erro ao carregar.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = snap.data?.docs ?? [];
    if (docs.isEmpty) {
      return const Center(child: Text('Nenhuma notificacao.'));
    }
    return _buildList(docs);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeInbox(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> tenant,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> personal,
  ) {
    final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final d in tenant) {
      map['t_${d.id}'] = d;
    }
    for (final d in personal) {
      map['p_${d.id}'] = d;
    }
    final out = map.values.toList();
    out.sort((x, y) {
      final dx = (x.data()['createdAt'] as Timestamp?)?.toDate();
      final dy = (y.data()['createdAt'] as Timestamp?)?.toDate();
      if (dx == null || dy == null) return 0;
      return dy.compareTo(dx);
    });
    return out;
  }

  Widget _buildMemberBody() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _memberNotificationsStream,
      builder: (context, memberSnap) {
        return FutureBuilder<List<String>>(
          future: _deptFuture,
          builder: (context, deptSnap) {
            Widget buildMerged(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
              if (uid.isEmpty) return _buildList(docs);
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: InternalNotificationInboxService.watch(uid, limit: 40),
                builder: (context, inboxSnap) {
                  final inbox = inboxSnap.data?.docs ?? [];
                  final merged = _mergeInbox(docs, inbox);
                  if (merged.isEmpty) {
                    return const Center(child: Text('Nenhuma notificacao.'));
                  }
                  return _buildList(merged);
                },
              );
            }

            final memberDocs =
                memberSnap.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final deptIds = deptSnap.data ?? <String>[];
            final deptReady = deptSnap.connectionState == ConnectionState.done;
            final canDeptStream =
                deptReady && deptIds.isNotEmpty && deptIds.length <= 10;

            if (!canDeptStream) {
              if (memberSnap.connectionState == ConnectionState.waiting &&
                  memberDocs.isEmpty &&
                  !deptReady) {
                return const Center(child: CircularProgressIndicator());
              }
              if (memberDocs.isEmpty) {
                if (!deptReady) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Center(child: Text('Nenhuma notificacao.'));
              }
              return buildMerged(memberDocs);
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _notifications
                  .where('departmentId', whereIn: deptIds)
                  .watchSafe(),
              builder: (context, deptStreamSnap) {
                if (memberSnap.hasError || deptStreamSnap.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                final deptDocs = deptStreamSnap.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final docs = _merge(memberDocs, deptDocs);
                if (docs.isEmpty &&
                    memberSnap.connectionState == ConnectionState.waiting &&
                    deptStreamSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (docs.isEmpty) {
                  return const Center(child: Text('Nenhuma notificacao.'));
                }
                return buildMerged(docs);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = docs[i].data();
        final title = (m['title'] ?? 'Notificação').toString();
        final body = (m['body'] ?? '').toString();
        final type = (m['type'] ?? '').toString();
        final module = _moduleFromType(type);
        final accent = gyModuleAccentColor(module);
        DateTime? dt;
        try {
          dt = (m['createdAt'] as Timestamp).toDate();
        } catch (_) {}
        final dateTxt = dt == null
            ? ''
            : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withValues(alpha: 0.22)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconForType(type), color: accent),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                if (dateTxt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${gyModuleLabel(module)} • $dateTxt',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _moduleFromType(String type) {
    switch (type) {
      case 'novo_aviso':
        return 'aviso';
      case 'novo_evento':
        return 'evento';
      case 'nova_escala':
      case 'escala_publicada':
        return 'escala';
      case 'aniversariantes_dia':
        return 'aniversario';
      case 'novo_membro':
        return 'membro';
      default:
        return 'generico';
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'novo_aviso':
        return Icons.campaign_rounded;
      case 'novo_evento':
        return Icons.event_rounded;
      case 'nova_escala':
      case 'escala_publicada':
        return Icons.calendar_month_rounded;
      case 'aniversariantes_dia':
        return Icons.cake_rounded;
      case 'novo_membro':
        return Icons.person_add_alt_1_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }
}
