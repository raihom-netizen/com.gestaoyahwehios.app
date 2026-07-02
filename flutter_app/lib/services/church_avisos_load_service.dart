import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Leitura de avisos activos — painel, carrossel e site público.
abstract final class ChurchAvisosLoadService {
  ChurchAvisosLoadService._();

  static const int kPanelCarouselLimit = 12;
  static const int kModuleListLimit = 40;

  static String _churchId(String hint) => ChurchRepository.churchId(hint.trim());

  static List<ChurchAvisoItem> _mapDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required DateTime now,
  }) {
    return docs
        .map(ChurchAvisoItem.fromDoc)
        .where((a) => ChurchAvisosService.isActive(a, now: now))
        .toList();
  }

  static Future<List<ChurchAvisoItem>> loadActive({
    required String churchIdHint,
    int limit = kPanelCarouselLimit,
  }) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    await ChurchAvisosService.purgeExpired(churchIdHint: churchId);

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final now = DateTime.now();
    final snap = await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchUiCollections.avisos(churchId)
          .where('publicado', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(),
      maxAttempts: 4,
    );

    return _mapDocs(snap.docs, now: now);
  }

  static Stream<List<ChurchAvisoItem>> watchActive({
    required String churchIdHint,
    int limit = kPanelCarouselLimit,
  }) {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) {
      return Stream.value(const []);
    }

    if (kIsWeb && FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
      return Stream<List<ChurchAvisoItem>>.multi((controller) async {
        Timer? timer;
        Future<void> emit() async {
          if (controller.isClosed) return;
          try {
            controller.add(
              await loadActive(churchIdHint: churchId, limit: limit),
            );
          } catch (_) {}
        }

        await emit();
        timer = Timer.periodic(const Duration(seconds: 45), (_) => emit());
        controller.onCancel = () => timer?.cancel();
      });
    }

    final now = DateTime.now();
    return ChurchUiCollections.avisos(churchId)
        .where('publicado', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => _mapDocs(snap.docs, now: now));
  }
}
