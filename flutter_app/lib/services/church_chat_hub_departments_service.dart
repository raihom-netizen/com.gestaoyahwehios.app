import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Grupos do Chat Igreja = subcoleção `igrejas/{churchId}/departamentos`.
abstract final class ChurchChatHubDepartmentsService {
  ChurchChatHubDepartmentsService._();

  static String _churchId(String seed) =>
      ChurchRepository.churchId(seed.trim());

  /// RAM / memória Firestore — 1.º frame ao abrir aba Grupos.
  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peekInstant(
    String seedTenantId,
  ) {
    final id = _churchId(seedTenantId);
    if (id.isEmpty) return null;
    final ram = ChurchDepartmentsLoadService.peekRam(id);
    if (ram != null && ram.isNotEmpty) return ram;
    final mem = FirestoreReadResilience.peekLastGoodQuery(
      ChurchDepartmentsLoadService.cacheKey(id),
    );
    return mem != null && mem.docs.isNotEmpty ? mem.docs : null;
  }

  /// Carga canónica — mesma API do módulo Departamentos (Hive + retry web).
  /// Devolve [ChurchDepartmentsLoadResult] com [softError] quando a rede falha.
  static Future<ChurchDepartmentsLoadResult> load({
    required String seedTenantId,
    bool forceServer = false,
  }) async {
    final id = _churchId(seedTenantId);
    if (id.isEmpty) {
      return const ChurchDepartmentsLoadResult(
        churchId: '',
        docs: [],
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    // Cache/Hive primeiro — não bloqueia em ensurePanelReadReady.
    if (!forceServer) {
      final instant = peekInstant(seedTenantId);
      if (instant != null && instant.isNotEmpty) {
        unawaited(() async {
          try {
            if (kIsWeb) {
              await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
            }
            final refreshed = await ChurchDepartmentsLoadService.load(
              seedTenantId: id,
              forceRefresh: true,
              forceServer: false,
            );
            if (refreshed.docs.isNotEmpty) {
              await ChurchDepartmentsLoadService.persistAfterLoad(refreshed);
            }
          } catch (_) {}
        }());
        return ChurchDepartmentsLoadResult(
          churchId: id,
          docs: instant,
          readSource: 'peek_instant',
        );
      }
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final result = await ChurchDepartmentsLoadService.load(
      seedTenantId: id,
      forceRefresh: forceServer,
      forceServer: forceServer,
    ).timeout(
      ChurchPanelReadTimeouts.queryCap,
      onTimeout: () => ChurchDepartmentsLoadResult(
        churchId: id,
        docs: const [],
        readSource: 'timeout',
        softError: 'Tempo esgotado ao carregar grupos dos departamentos.',
      ),
    );

    if (result.docs.isNotEmpty) {
      await ChurchDepartmentsLoadService.persistAfterLoad(result);
    }
    return result;
  }

  /// Compat: só docs (preferir [load] para softError).
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadDocs({
    required String seedTenantId,
    bool forceServer = false,
  }) async {
    final result = await load(
      seedTenantId: seedTenantId,
      forceServer: forceServer,
    );
    return result.docs;
  }
}
