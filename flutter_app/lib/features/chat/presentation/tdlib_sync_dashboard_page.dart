import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_chat_local_prefs.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart';

/// Painel rápido para o pastor: sync Telegram × cadastro da igreja.
class TdlibSyncDashboardPage extends StatefulWidget {
  const TdlibSyncDashboardPage({
    super.key,
    required this.churchId,
    required this.departments,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> departments;

  @override
  State<TdlibSyncDashboardPage> createState() => _TdlibSyncDashboardPageState();
}

class _TdlibSyncDashboardPageState extends State<TdlibSyncDashboardPage> {
  static const _accent = Color(0xFF0D9488);
  String? _lastSync;

  @override
  void initState() {
    super.initState();
    TdlibChatLocalPrefs.getLastSyncAt(widget.churchId).then((v) {
      if (mounted) setState(() => _lastSync = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = MembersDirectorySnapshotService.peekMemory(widget.churchId);
    final entries = snap?.entries ?? const <MemberDirectoryEntry>[];
    var withPhone = 0;
    var withoutPhone = 0;
    for (final e in entries) {
      final p = (e.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      if (p.length >= 10) {
        withPhone++;
      } else {
        withoutPhone++;
      }
    }
    var ready = 0;
    for (final d in widget.departments) {
      final id = (d.data()['telegramChatId'] ?? d.data()['tdlibChatId'] ?? '')
          .toString()
          .trim();
      if (id.isNotEmpty) ready++;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('Sync Telegram · Igreja'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _card(
            title: 'Grupos de departamento',
            value: '$ready / ${widget.departments.length}',
            subtitle: 'já ligados ao Telegram',
            color: _accent,
          ),
          const SizedBox(height: 10),
          _card(
            title: 'Membros com telefone',
            value: '$withPhone / ${entries.length}',
            subtitle: 'podem entrar no grupo automático',
            color: const Color(0xFF16A34A),
          ),
          const SizedBox(height: 10),
          _card(
            title: 'Sem telefone',
            value: '$withoutPhone',
            subtitle: 'cadastre em Membros (mesmo do Telegram)',
            color: const Color(0xFFB45309),
          ),
          const SizedBox(height: 16),
          Text(
            _lastSync == null || _lastSync!.isEmpty
                ? 'Último sync: ainda não registado'
                : 'Último sync: ${_lastSync!.replaceFirst('T', ' ').split('.').first}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 18),
          const Text(
            'Departamentos',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...widget.departments.map((d) {
            final name = churchDepartmentNameFromDoc(d);
            final chatReady =
                (d.data()['telegramChatId'] ?? d.data()['tdlibChatId'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty;
            final inDept = entries.where((e) {
              final n = name.trim().toLowerCase();
              final id = d.id.trim().toLowerCase();
              final depts = e.departamentos.map((x) => x.trim().toLowerCase());
              return depts.contains(n) ||
                  depts.contains(id) ||
                  e.departamentos.contains(d.id);
            }).toList();
            final phones = inDept
                .where(
                  (e) =>
                      (e.telefone ?? '').replaceAll(RegExp(r'\D'), '').length >=
                      10,
                )
                .length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    chatReady
                        ? '$phones/${inDept.length} com telefone · grupo OK'
                        : '$phones/${inDept.length} com telefone · abre automático',
                  ),
                  trailing: Icon(
                    chatReady
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_empty_rounded,
                    color: chatReady ? const Color(0xFF16A34A) : Colors.orange,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
