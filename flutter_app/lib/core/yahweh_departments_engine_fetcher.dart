import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromData;

/// Leitura **Departamentos** — `igrejas/{churchId}/departamentos` via [ChurchDepartmentsLoadService].
abstract final class YahwehDepartmentsEngineFetcher {
  YahwehDepartmentsEngineFetcher._();

  static const String pilotChurchIdHint = '';

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  static Map<String, dynamic> docToMap(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] = doc.id;
    data['_displayName'] = churchDepartmentNameFromData(data, docId: doc.id);
    data['_isActive'] = ChurchModuleFirestoreListRead.isActiveRecord(data);
    return data;
  }

  static List<Map<String, dynamic>> docsToMaps(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool activeOnly = false,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final m = docToMap(doc);
      if (activeOnly && m['_isActive'] != true) continue;
      out.add(m);
    }
    out.sort((a, b) => (a['_displayName'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['_displayName'] ?? '').toString().toLowerCase()));
    return out;
  }

  static Future<List<Map<String, dynamic>>> fetchDepartamentos({
    required String churchIdHint,
    bool activeOnly = false,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final result = await ChurchDepartmentsLoadService.load(
      seedTenantId: resolveChurchId(churchIdHint),
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    return docsToMaps(result.docs, activeOnly: activeOnly);
  }

  static Stream<List<Map<String, dynamic>>> watchDepartamentos({
    required String churchIdHint,
    bool activeOnly = false,
  }) async* {
    Future<List<Map<String, dynamic>>> loadOnce() => fetchDepartamentos(
          churchIdHint: churchIdHint,
          activeOnly: activeOnly,
        );

    yield await loadOnce();

    if (kIsWeb) {
      yield* Stream.periodic(const Duration(seconds: 45))
          .asyncMap((_) => loadOnce());
      return;
    }

    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return;

    yield* ChurchUiCollections.departamentos(churchId)
        .limit(ChurchDepartmentsLoadService.kLimit)
        .snapshots()
        .asyncMap((_) => loadOnce());
  }
}
