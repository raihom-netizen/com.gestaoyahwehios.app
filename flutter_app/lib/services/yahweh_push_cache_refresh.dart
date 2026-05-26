import 'dart:async' show unawaited;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_local_snapshot_store.dart';

/// Push silencioso / data-only — aquece cache antes do utilizador abrir o ecrã.
abstract final class YahwehPushCacheRefresh {
  YahwehPushCacheRefresh._();

  static bool _looksSilentData(RemoteMessage message) {
    final d = message.data;
    if (d.isEmpty) return false;
    final silent = (d['silent'] ?? d['content_available'] ?? '').toString();
    if (silent == '1' || silent.toLowerCase() == 'true') return true;
    return d.containsKey('cacheRefresh') || d.containsKey('warmCache');
  }

  static String? _tenantId(RemoteMessage message) {
    final d = message.data;
    final tid = (d['tenantId'] ?? d['tenant_id'] ?? d['igrejaId'] ?? '')
        .toString()
        .trim();
    return tid.isEmpty ? null : tid;
  }

  /// Chamar em [FirebaseMessaging.onMessage] (app em foreground/background visível).
  static void handleMessage(RemoteMessage message) {
    if (!_looksSilentData(message) && message.notification != null) {
      // Notificação visível: ainda podemos aquecer cache de chat se for tipo chat.
      final type = (message.data['type'] ?? '').toString().toLowerCase();
      if (type != 'chat' && type != 'message') return;
    } else if (!_looksSilentData(message)) {
      return;
    }
    final tid = _tenantId(message);
    if (tid == null) return;
    unawaited(_warm(tid, message.data));
  }

  static Future<void> _warm(
    String tenantId,
    Map<String, dynamic> data,
  ) async {
    final kind = (data['cacheRefresh'] ?? data['type'] ?? 'all')
        .toString()
        .toLowerCase();
    try {
      if (kind.contains('chat') || kind == 'all') {
        // Threads recentes ficam no cache Firestore offline após qualquer leitura.
      }
      if (kind.contains('member') || kind == 'all') {
        await MembersDirectorySnapshotService.warmFromCallableIfStale(tenantId);
        final dir = await MembersDirectorySnapshotService.readOnce(tenantId);
        if (dir.entries.isNotEmpty) {
          await YahwehLocalSnapshotStore.saveJsonList(
            tenantId,
            'membros_search',
            dir.entries.map(_memberEntryToMap).toList(),
          );
        }
      }
      if (kind.contains('aviso') ||
          kind.contains('feed') ||
          kind.contains('event') ||
          kind == 'all') {
        final feed =
            await ChurchPerformanceCacheService.readPublicFeedOnce(tenantId);
        if (feed.isNotEmpty) {
          await YahwehLocalSnapshotStore.saveJsonList(
            tenantId,
            'public_feed',
            feed,
          );
        }
      }
    } catch (_) {}
  }

  static Map<String, dynamic> _memberEntryToMap(MemberDirectoryEntry e) {
    return {
      'memberDocId': e.memberDocId,
      'displayName': e.displayName,
      if (e.photoUrl != null) 'photoUrl': e.photoUrl,
      'fotoUrlCacheRevision': e.fotoUrlCacheRevision,
      if (e.authUid != null) 'authUid': e.authUid,
      if (e.cpfDigits != null) 'cpfDigits': e.cpfDigits,
      if (e.email != null) 'email': e.email,
      if (e.telefone != null) 'telefone': e.telefone,
      'status': e.status,
      if (e.funcao != null) 'funcao': e.funcao,
      'funcoes': e.funcoes,
      'departamentos': e.departamentos,
      if (e.genero != null) 'genero': e.genero,
      if (e.createdAt != null) 'createdAt': e.createdAt,
      if (e.updatedAt != null) 'updatedAt': e.updatedAt,
    };
  }
}
