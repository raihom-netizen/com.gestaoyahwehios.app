import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Retenção seletiva de mídia do chat — remove ficheiros Storage > 90 dias.
///
/// Preserva: `preserveMedia`, threads oficiais/anúncio, avisos (`/avisos/` no path).
/// Mensagens de texto permanecem; só apaga bytes no Storage e limpa URLs na mensagem.
abstract final class ChurchChatStorageRetentionService {
  ChurchChatStorageRetentionService._();

  static const int retentionDays = 90;
  static const String _prefsKey = 'yahweh_chat_retention_last_run_v1';
  static const Duration _minInterval = Duration(hours: 20);

  static const _mediaTypes = <String>['image', 'video', 'audio', 'file'];

  /// Executa no máximo uma vez por ~20h por tenant (arranque/resume).
  static Future<void> maybeRunForTenant(String tenantId) async {
    if (kIsWeb) return;
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '${_prefsKey}_$tid';
    final lastMs = prefs.getInt(key) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (DateTime.now().difference(last) < _minInterval) return;

    try {
      final purged = await purgeExpiredMedia(
        tid,
        maxMessagesPerRun: 48,
        maxThreadsPerRun: 24,
      );
      if (purged > 0 && kDebugMode) {
        debugPrint('ChurchChatStorageRetention: $purged mídias antigas ($tid)');
      }
      await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ChurchChatStorageRetention.maybeRunForTenant: $e\n$st');
      }
    }
  }

  static bool _threadIsOfficial(Map<String, dynamic> threadData) {
    final t = (threadData['threadType'] ?? threadData['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (t == 'announcement' ||
        t == 'official' ||
        t == 'aviso' ||
        t == 'broadcast') {
      return true;
    }
    final title = (threadData['title'] ?? threadData['name'] ?? '')
        .toString()
        .toLowerCase();
    return title.contains('aviso oficial') || title.contains('comunicado oficial');
  }

  static bool _shouldPreserveMessage(Map<String, dynamic> data) {
    if (data['preserveMedia'] == true) return true;
    if (data['mediaPurged'] == true) return true;
    final path = (data['storagePath'] ?? '').toString();
    if (path.contains('/avisos/') || path.contains('/eventos/')) return true;
    return false;
  }

  /// Apaga Storage e marca mensagem sem URL (histórico textual mantido).
  static Future<int> purgeExpiredMedia(
    String tenantId, {
    int maxMessagesPerRun = 48,
    int maxThreadsPerRun = 24,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    final cutoffTs = Timestamp.fromDate(cutoff);
    final db = FirebaseFirestore.instance;
    final op = await ChurchOperationalPaths.resolveCached(tid.trim());
    final chatsSnap = await         ChurchOperationalPaths.churchDoc(op)
        .collection('chats')
        .orderBy('lastMessageAt', descending: true)
        .limit(maxThreadsPerRun)
        .get();

    var purged = 0;
    for (final thread in chatsSnap.docs) {
      if (purged >= maxMessagesPerRun) break;
      if (_threadIsOfficial(thread.data())) continue;

      QuerySnapshot<Map<String, dynamic>> msgs;
      try {
        msgs = await thread.reference
            .collection('messages')
            .where('createdAt', isLessThan: cutoffTs)
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
      } catch (_) {
        continue;
      }

      for (final msg in msgs.docs) {
        if (purged >= maxMessagesPerRun) break;
        final data = msg.data();
        if (_shouldPreserveMessage(data)) continue;
        final type = (data['type'] ?? 'text').toString();
        if (!_mediaTypes.contains(type)) continue;

        final url = (data['mediaUrl'] ?? '').toString().trim();
        final path = (data['storagePath'] ?? '').toString().trim();
        if (url.isEmpty && path.isEmpty) continue;

        final targets = <String>{};
        if (url.isNotEmpty) targets.add(url);
        if (path.isNotEmpty) targets.add(path);
        final thumb = (data['thumbUrl'] ?? data['posterUrl'] ?? '').toString();
        if (thumb.isNotEmpty) targets.add(thumb);

        await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(targets);

        try {
          await msg.reference.set(
            {
              'mediaUrl': FieldValue.delete(),
              'storagePath': FieldValue.delete(),
              'thumbUrl': FieldValue.delete(),
              'mediaPurged': true,
              'mediaPurgedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          purged++;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('ChurchChatStorageRetention msg ${msg.id}: $e');
          }
        }
      }
    }
    return purged;
  }
}
