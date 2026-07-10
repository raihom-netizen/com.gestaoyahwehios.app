import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_save_service.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Outbox genérico — património, foto membro (sync silencioso após fila).
abstract final class ModuleMediaOutboxService {
  ModuleMediaOutboxService._();

  static const _prefsKey = 'module_media_outbox_v1';
  static bool _connectivityBound = false;

  static Future<void> registerPatrimonio({
    required String tenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required int startSlot,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
  }) async {
    await _register({
      'module': 'patrimonio',
      'tenantId': tenantId.trim(),
      'itemId': itemId.trim(),
      'isNewDoc': isNewDoc,
      'startSlot': startSlot,
      'existingPaths': existingPaths,
      'existingUrls': existingUrls,
      'corePayload': _jsonSafeMap(corePayload),
    });
  }

  static Future<void> registerMemberPhoto({
    required String tenantId,
    required String memberDocId,
    required Map<String, dynamic> memberData,
  }) async {
    await _register({
      'module': 'membro_foto',
      'tenantId': tenantId.trim(),
      'memberDocId': memberDocId.trim(),
      'memberData': memberData,
    });
  }

  static Future<void> registerFinanceComprovante({
    required String tenantId,
    required String lancamentoId,
    required String mimeType,
    String? fileName,
    int? referenceDateMs,
    String? previousStoragePath,
    String? previousDownloadUrl,
    bool alreadyCompressed = false,
  }) async {
    await _register({
      'module': 'finance_comprovante',
      'tenantId': tenantId.trim(),
      'lancamentoId': lancamentoId.trim(),
      'mimeType': mimeType,
      'fileName': fileName,
      'referenceDateMs': referenceDateMs,
      'previousStoragePath': previousStoragePath,
      'previousDownloadUrl': previousDownloadUrl,
      'alreadyCompressed': alreadyCompressed,
    });
  }

  static Future<void> _register(Map<String, dynamic> job) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final module = (job['module'] ?? '').toString();
    final tid = (job['tenantId'] ?? '').toString();
    final id = (job['itemId'] ?? job['memberDocId'] ?? job['lancamentoId'] ?? '')
        .toString();
    list.removeWhere(
      (e) =>
          (e['module'] ?? '').toString() == module &&
          (e['tenantId'] ?? '').toString() == tid &&
          ((e['itemId'] ?? e['memberDocId'] ?? e['lancamentoId'] ?? '')
              .toString() ==
              id),
    );
    list.add(job);
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static Future<void> clearPatrimonio({
    required String tenantId,
    required String itemId,
  }) async {
    await _clear(
      module: 'patrimonio',
      tenantId: tenantId,
      docId: itemId,
    );
    await MuralPostPendingMediaCache.remove(
      tenantId: tenantId,
      postId: 'patrimonio_$itemId',
    );
  }

  static Future<void> clearMemberPhoto({
    required String tenantId,
    required String memberDocId,
  }) async {
    await _clear(
      module: 'membro_foto',
      tenantId: tenantId,
      docId: memberDocId,
    );
    await MuralPostPendingMediaCache.remove(
      tenantId: tenantId,
      postId: 'membro_$memberDocId',
    );
  }

  static Future<void> clearFinanceComprovante({
    required String tenantId,
    required String lancamentoId,
  }) async {
    await _clear(
      module: 'finance_comprovante',
      tenantId: tenantId,
      docId: lancamentoId,
    );
    await MuralPostPendingMediaCache.remove(
      tenantId: tenantId,
      postId: 'finance_$lancamentoId',
    );
  }

  static Future<void> _clear({
    required String module,
    required String tenantId,
    required String docId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere(
      (e) =>
          (e['module'] ?? '').toString() == module &&
          (e['tenantId'] ?? '').toString() == tenantId.trim() &&
          ((e['itemId'] ?? e['memberDocId'] ?? e['lancamentoId'] ?? '')
              .toString() ==
              docId.trim()),
    );
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static void bindConnectivityResume() {
    if (_connectivityBound) return;
    _connectivityBound = true;
    AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) unawaited(drainPendingJobs());
    });
  }

  static Future<void> drainPendingJobs() async {
    bindConnectivityResume();
    if (!AppConnectivityService.instance.isOnline) return;
    await runFirebaseBackgroundTask<void>(
      () async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final remaining = <Map<String, dynamic>>[];
        for (final m in list) {
          final attempts =
              (m['attemptCount'] is num ? (m['attemptCount'] as num).toInt() : 0);
          if (attempts >= 6) {
            remaining.add({...m, 'attemptCount': attempts});
            continue;
          }
          try {
            await _retryJob(m);
            // sucesso — não re-adiciona
          } catch (e) {
            if (kDebugMode) {
              debugPrint('ModuleMediaOutboxService retry: $e');
            }
            remaining.add({...m, 'attemptCount': attempts + 1});
          }
        }
        await prefs.setString(_prefsKey, jsonEncode(remaining));
      },
      debugLabel: 'module_media_outbox_drain',
    ).catchError((_) {});
  }

  static Future<void> _retryJob(Map<String, dynamic> m) async {
    final module = (m['module'] ?? '').toString();
    final tenantId = (m['tenantId'] ?? '').toString().trim();
    if (module == 'patrimonio') {
      final itemId = (m['itemId'] ?? '').toString().trim();
      final cacheKey = 'patrimonio_$itemId';
      final images = await MuralPostPendingMediaCache.get(
            tenantId: tenantId,
            postId: cacheKey,
          ) ??
          const [];
      final core = _restoreMap(
        Map<String, dynamic>.from(
          (m['corePayload'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
      );
      final docRef = PatrimonioPublishVerificationService.patrimonioDocRef(
        igrejaId: tenantId,
        itemId: itemId,
      );
      if (images.isEmpty) {
        await PatrimonioPublishService.repairFromStorage(
          churchId: tenantId,
          itemId: itemId,
          corePayload: core,
        );
      } else {
        await PatrimonioPublishService.publishLinear(
          igrejaId: tenantId,
          itemId: itemId,
          docRef: docRef,
          corePayload: core,
          isNewDoc: m['isNewDoc'] == true,
          newImages: images,
          startSlot: (m['startSlot'] is num ? (m['startSlot'] as num).toInt() : 0),
          existingPaths: ((m['existingPaths'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
          existingUrls: ((m['existingUrls'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
        );
      }
      await clearPatrimonio(tenantId: tenantId, itemId: itemId);
      return;
    }
    if (module == 'membro_foto') {
      final memberDocId = (m['memberDocId'] ?? '').toString().trim();
      final cacheKey = 'membro_$memberDocId';
      final images = await MuralPostPendingMediaCache.get(
            tenantId: tenantId,
            postId: cacheKey,
          ) ??
          const [];
      if (images.isEmpty) {
        throw StateError('bytes membro em falta no cache');
      }
      final memberData = Map<String, dynamic>.from(
        (m['memberData'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      await MemberProfilePhotoSaveService.saveInternal(
        tenantId: tenantId,
        memberDocId: memberDocId,
        memberData: memberData,
        rawBytes: images.first,
      );
      await clearMemberPhoto(tenantId: tenantId, memberDocId: memberDocId);
      return;
    }
    if (module == 'finance_comprovante') {
      final lancamentoId = (m['lancamentoId'] ?? '').toString().trim();
      final cacheKey = 'finance_$lancamentoId';
      final images = await MuralPostPendingMediaCache.get(
            tenantId: tenantId,
            postId: cacheKey,
          ) ??
          const [];
      if (images.isEmpty) {
        throw StateError('bytes comprovante em falta no cache');
      }
      final refDateMs = m['referenceDateMs'];
      DateTime? refDate;
      if (refDateMs is num) {
        refDate = DateTime.fromMillisecondsSinceEpoch(refDateMs.toInt());
      }
      final docRef = ChurchUiCollections.financeiro(tenantId).doc(lancamentoId);
      final alreadyCompressed = m['alreadyCompressed'] == true;
      await FinanceComprovantePublishService.uploadComprovanteNow(
        tenantId: tenantId,
        docRef: docRef,
        rawBytes: images.first,
        mimeType: (m['mimeType'] ?? 'image/jpeg').toString(),
        fileName: (m['fileName'] ?? '').toString().trim().isEmpty
            ? null
            : (m['fileName'] ?? '').toString(),
        referenceDate: refDate,
        previousStoragePath: (m['previousStoragePath'] ?? '').toString(),
        previousDownloadUrl: (m['previousDownloadUrl'] ?? '').toString(),
        // Bytes vindos do picker já optimizados — nunca recomprimir no drain.
        alreadyCompressed: alreadyCompressed,
      );
      await clearFinanceComprovante(
        tenantId: tenantId,
        lancamentoId: lancamentoId,
      );
    }
  }

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final e in source.entries) {
      final v = e.value;
      if (v == null) {
        out[e.key] = null;
      } else if (v is Timestamp) {
        out[e.key] = {'_tsMs': v.millisecondsSinceEpoch};
      } else if (v is FieldValue) {
        continue;
      } else if (v is Map) {
        out[e.key] = _jsonSafeMap(v.cast<String, dynamic>());
      } else if (v is List) {
        out[e.key] = v.map((x) {
          if (x is Timestamp) return {'_tsMs': x.millisecondsSinceEpoch};
          if (x is Map) return _jsonSafeMap(x.cast<String, dynamic>());
          return x;
        }).toList();
      } else {
        out[e.key] = v;
      }
    }
    return out;
  }

  static Map<String, dynamic> _restoreMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    for (final e in source.entries) {
      final v = e.value;
      if (v is Map && v.containsKey('_tsMs')) {
        final ms = v['_tsMs'];
        if (ms is num) {
          out[e.key] = Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
        }
      } else if (v is Map) {
        out[e.key] = _restoreMap(v.cast<String, dynamic>());
      } else if (v is List) {
        out[e.key] = v.map((x) {
          if (x is Map && x.containsKey('_tsMs')) {
            final ms = x['_tsMs'];
            if (ms is num) {
              return Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
            }
          }
          if (x is Map) return _restoreMap(x.cast<String, dynamic>());
          return x;
        }).toList();
      } else {
        out[e.key] = v;
      }
    }
    return out;
  }
}
