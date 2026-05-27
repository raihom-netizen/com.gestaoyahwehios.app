import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

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
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros');

  CollectionReference<Map<String, dynamic>> get _notifications =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
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
        .snapshots();
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _notifications
          .orderBy('createdAt', descending: true)
          .limit(120)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhuma notificacao.'));
        }
        return _buildList(docs);
      },
    );
  }

  Widget _buildMemberBody() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _memberNotificationsStream,
      builder: (context, memberSnap) {
        return FutureBuilder<List<String>>(
          future: _deptFuture,
          builder: (context, deptSnap) {
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
              return _buildList(memberDocs);
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _notifications
                  .where('departmentId', whereIn: deptIds)
                  .snapshots(),
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
                return _buildList(docs);
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
        final title = (m['title'] ?? 'Notificacao').toString();
        final body = (m['body'] ?? '').toString();
        DateTime? dt;
        try {
          dt = (m['createdAt'] as Timestamp).toDate();
        } catch (_) {}
        final dateTxt = dt == null
            ? ''
            : '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                [body, dateTxt].where((e) => e.isNotEmpty).join(' • ')),
          ),
        );
      },
    );
  }
}
