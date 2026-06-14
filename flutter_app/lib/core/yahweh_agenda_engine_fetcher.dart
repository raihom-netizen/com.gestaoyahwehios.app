import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/agenda_firestore_fields.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';

/// Leitura **Agenda** — `igrejas/{churchId}/agenda` via [ChurchAgendaLoadService].
abstract final class YahwehAgendaEngineFetcher {
  YahwehAgendaEngineFetcher._();

  static const String pilotChurchIdHint =
      'igreja_o_brasil_para_cristo_jardim_goiano';

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  static Map<String, dynamic> docToMap(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] = doc.id;
    data['_displayTitle'] =
        AgendaFirestoreFields.displayTitle(data, docId: doc.id);
    data['_startTimestamp'] = AgendaFirestoreFields.parseTimestamp(data);
    data['_isActive'] = ChurchModuleFirestoreListRead.isActiveRecord(data);
    return data;
  }

  static List<Map<String, dynamic>> docsToMaps(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool activeOnly = true,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final m = docToMap(doc);
      if (activeOnly && m['_isActive'] != true) continue;
      final ts = m['_startTimestamp'];
      if (ts is Timestamp && rangeStart != null && rangeEnd != null) {
        final dt = ts.toDate();
        if (dt.isBefore(rangeStart) || dt.isAfter(rangeEnd)) continue;
      }
      out.add(m);
    }
    out.sort((a, b) {
      final ta = a['_startTimestamp'];
      final tb = b['_startTimestamp'];
      if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
      if (ta is Timestamp) return -1;
      if (tb is Timestamp) return 1;
      return (a['_displayTitle'] ?? '')
          .toString()
          .compareTo((b['_displayTitle'] ?? '').toString());
    });
    return out;
  }

  static Future<List<Map<String, dynamic>>> fetchAgenda({
    required String churchIdHint,
    bool activeOnly = true,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    if (rangeStart != null && rangeEnd != null) {
      final result = await ChurchAgendaLoadService.loadByStartTimeRange(
        seedTenantId: churchId,
        start: Timestamp.fromDate(rangeStart),
        end: Timestamp.fromDate(rangeEnd),
        forceRefresh: forceRefresh,
        forceServer: forceServer,
      );
      return docsToMaps(
        result.docs,
        activeOnly: activeOnly,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    }

    final result = await ChurchAgendaLoadService.loadAll(
      seedTenantId: churchId,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    return docsToMaps(result.docs, activeOnly: activeOnly);
  }

  static Stream<List<Map<String, dynamic>>> watchAgenda({
    required String churchIdHint,
    bool activeOnly = true,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async* {
    Future<List<Map<String, dynamic>>> loadOnce() => fetchAgenda(
          churchIdHint: churchIdHint,
          activeOnly: activeOnly,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );

    yield await loadOnce();

    if (kIsWeb) {
      yield* Stream.periodic(const Duration(seconds: 45))
          .asyncMap((_) => loadOnce());
      return;
    }

    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return;

    yield* ChurchUiCollections.agenda(churchId)
        .limit(ChurchAgendaLoadService.plainFallbackLimit)
        .snapshots()
        .asyncMap((_) => loadOnce());
  }
}
