import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';

/// Busca local primeiro → Firestore depois (pesquisa instantânea).
abstract final class YahwehLocalSearchService {
  YahwehLocalSearchService._();

  static String _norm(String raw) => raw.trim().toLowerCase();

  /// Membros: cache `_panel_cache/members_directory` + snapshot local.
  static Future<List<MemberDirectoryEntry>> searchMembersLocal({
    required String tenantId,
    required String query,
    int maxResults = 40,
  }) async {
    final q = _norm(query);
    if (q.isEmpty) return const [];

    final fromServer = await MembersDirectorySnapshotService.readOnce(tenantId);
    var entries = fromServer.entries;
    if (entries.isEmpty) {
      final snap = await YahwehLocalSnapshotStore.readJsonList(
        tenantId,
        'membros_search',
      );
      entries = snap
          .map(MemberDirectoryEntry.fromMap)
          .where((e) => e.memberDocId.isNotEmpty)
          .toList();
    }

    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final out = <MemberDirectoryEntry>[];
    for (final m in entries) {
      final name = _norm(m.displayName);
      final email = _norm(m.email ?? '');
      final cpf = (m.cpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
      final phone = _norm(m.telefone ?? '');
      final hit = name.contains(q) ||
          email.contains(q) ||
          phone.contains(q) ||
          (qDigits.length >= 3 && cpf.contains(qDigits));
      if (hit) out.add(m);
      if (out.length >= maxResults) break;
    }
    return out;
  }

  /// Avisos/eventos em snapshot JSON (site / painel).
  static Future<List<Map<String, dynamic>>> searchFeedLocal({
    required String tenantId,
    required String bucket,
    required String query,
    int maxResults = 30,
  }) async {
    final q = _norm(query);
    if (q.isEmpty) return const [];
    final items = await YahwehLocalSnapshotStore.readJsonList(tenantId, bucket);
    final out = <Map<String, dynamic>>[];
    for (final m in items) {
      final title = _norm((m['title'] ?? m['titulo'] ?? '').toString());
      final body = _norm((m['body'] ?? m['texto'] ?? m['description'] ?? '')
          .toString());
      if (title.contains(q) || body.contains(q)) {
        out.add(m);
        if (out.length >= maxResults) break;
      }
    }
    return out;
  }
}
