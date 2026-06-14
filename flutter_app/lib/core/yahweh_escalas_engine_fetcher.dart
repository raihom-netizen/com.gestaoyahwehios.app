import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/escala_firestore_fields.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_schedules_load_service.dart';

/// Motor de leitura **Escalas** — `igrejas/{churchId}/escalas` via [ChurchSchedulesLoadService].
///
/// **Proibido:** tenant hardcoded, `FirebaseFirestore.instance` directo nas telas.
abstract final class YahwehEscalasEngineFetcher {
  YahwehEscalasEngineFetcher._();

  /// Referência aceite — **não** usar em runtime fixo; só documentação/DEBUG.
  static const String pilotChurchIdHint =
      'igreja_o_brasil_para_cristo_jardim_goiano';

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  static DateTime? parseEscalaDate(Map<String, dynamic> data) =>
      EscalaFirestoreFields.parseDate(data);

  static String displayTitle(Map<String, dynamic> data) {
    for (final k in ['title', 'culto', 'evento', 'nome', 'name']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return 'Culto / Escala';
  }

  static String displayMinisterio(Map<String, dynamic> data) {
    for (final k in ['ministerio', 'ministério', 'departmentName', 'departamento']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return 'Sem ministério';
  }

  static String displayDateLabel(Map<String, dynamic> data) {
    final explicit = (data['dataExibicao'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final dt = parseEscalaDate(data);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  static List<String> volunteerLabels(Map<String, dynamic> data) {
    final raw = data['voluntarios'] ?? data['memberCpfs'] ?? data['membros'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, dynamic> docToMap(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] = doc.id;
    final dt = parseEscalaDate(data);
    if (dt != null) {
      data['_parsedDateMs'] = dt.millisecondsSinceEpoch;
    }
    return data;
  }

  static List<Map<String, dynamic>> docsToMaps(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.map(docToMap).toList(growable: false);

  static Future<List<Map<String, dynamic>>> fetchEscalas({
    required String churchIdHint,
    int limit = ChurchSchedulesLoadService.kEscalasDefaultLimit,
    bool forceRefresh = false,
    bool forceServer = false,
  }) async {
    final result = await ChurchSchedulesLoadService.loadEscalas(
      seedTenantId: resolveChurchId(churchIdHint),
      limit: limit,
      forceRefresh: forceRefresh,
      forceServer: forceServer,
    );
    return docsToMaps(result.docs);
  }

  static Future<List<Map<String, dynamic>>> fetchEscalasForMember({
    required String churchIdHint,
    required String cpfDigits,
    int limit = ChurchSchedulesLoadService.kEscalasDefaultLimit,
    bool forceRefresh = false,
  }) async {
    final result = await ChurchSchedulesLoadService.loadEscalasForMember(
      seedTenantId: resolveChurchId(churchIdHint),
      cpfDigits: cpfDigits,
      limit: limit,
      forceRefresh: forceRefresh,
    );
    return docsToMaps(result.docs);
  }

  static Stream<List<Map<String, dynamic>>> watchEscalas({
    required String churchIdHint,
    int limit = ChurchSchedulesLoadService.kEscalasDefaultLimit,
  }) async* {
    Future<List<Map<String, dynamic>>> loadOnce() => fetchEscalas(
          churchIdHint: churchIdHint,
          limit: limit,
        );

    yield await loadOnce();

    if (kIsWeb) {
      yield* Stream.periodic(const Duration(seconds: 45))
          .asyncMap((_) => loadOnce());
      return;
    }

    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) return;

    yield* ChurchUiCollections.escalas(churchId)
        .limit(limit)
        .snapshots()
        .asyncMap((_) => loadOnce());
  }
}
