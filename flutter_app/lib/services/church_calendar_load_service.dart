import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Carga unificada do módulo Agenda — um intervalo, cache-first, paths `igrejas/{churchId}/…`.
class ChurchCalendarMonthLoadResult {
  const ChurchCalendarMonthLoadResult({
    required this.churchId,
    required this.agendaDocs,
    required this.eventosByDataEvento,
    this.muralEventos,
    required this.cultos,
    this.escalas,
    required this.eventTemplates,
    this.softError,
  });

  final String churchId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> agendaDocs;
  final QuerySnapshot<Map<String, dynamic>> eventosByDataEvento;
  final QuerySnapshot<Map<String, dynamic>>? muralEventos;
  final QuerySnapshot<Map<String, dynamic>> cultos;
  final QuerySnapshot<Map<String, dynamic>>? escalas;
  final QuerySnapshot<Map<String, dynamic>> eventTemplates;
  final String? softError;

  bool get hasAnyData =>
      agendaDocs.isNotEmpty ||
      eventosByDataEvento.docs.isNotEmpty ||
      (muralEventos?.docs.isNotEmpty ?? false) ||
      cultos.docs.isNotEmpty ||
      eventTemplates.docs.isNotEmpty;
}

/// Orquestra agenda + eventos + cultos + escalas + templates para o calendário.
abstract final class ChurchCalendarLoadService {
  ChurchCalendarLoadService._();

  static Duration get _queryCap => kIsWeb
      ? const Duration(seconds: 16)
      : ChurchPanelReadTimeouts.queryCap;

  static Future<ChurchCalendarMonthLoadResult> loadMonth({
    required String seedTenantId,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return ChurchCalendarMonthLoadResult(
        churchId: '',
        agendaDocs: const [],
        eventosByDataEvento: const MergedFirestoreQuerySnapshot([]),
        cultos: const MergedFirestoreQuerySnapshot([]),
        eventTemplates: const MergedFirestoreQuerySnapshot([]),
        softError: 'Igreja não identificada.',
      );
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    if (forceRefresh) {
      unawaited(ChurchAgendaLoadService.invalidate(churchId));
    }

    final start = Timestamp.fromDate(rangeStart);
    final end = Timestamp.fromDate(rangeEnd);
    String? softError;

    List<QueryDocumentSnapshot<Map<String, dynamic>>> agendaDocs = const [];
    try {
      final agenda = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchAgendaLoadService.loadByStartTimeRange(
          seedTenantId: churchId,
          start: start,
          end: end,
          forceRefresh: forceRefresh,
        ),
        maxAttempts: 4,
      ).timeout(_queryCap);
      agendaDocs = agenda.docs;
      softError ??= agenda.softError;
    } catch (e) {
      softError ??= _humanize(e);
      final ram = ChurchAgendaLoadService.peekAnyRam(
        churchId,
        start: start,
        end: end,
      );
      if (ram != null) agendaDocs = ram;
    }

    QuerySnapshot<Map<String, dynamic>> eventosByData =
        const MergedFirestoreQuerySnapshot([]);
    QuerySnapshot<Map<String, dynamic>>? muralEventos;
    QuerySnapshot<Map<String, dynamic>> cultosSnap =
        const MergedFirestoreQuerySnapshot([]);
    QuerySnapshot<Map<String, dynamic>>? escalasSnap;
    QuerySnapshot<Map<String, dynamic>> templatesSnap =
        const MergedFirestoreQuerySnapshot([]);

    Future<T> guard<T>(Future<T> future, void Function(Object) onErr) async {
      try {
        return await future.timeout(_queryCap);
      } catch (e) {
        onErr(e);
        if (T == QuerySnapshot<Map<String, dynamic>>) {
          return const MergedFirestoreQuerySnapshot([]) as T;
        }
        rethrow;
      }
    }

    // Web: 2 queries por vez — menos INTERNAL ASSERTION / timeout falso.
    if (kIsWeb) {
      muralEventos = await guard(
        ChurchTenantResilientReads.muralEventosByStartAtRange(
          churchId,
          start: start,
          end: end,
        ),
        (e) => softError ??= _humanize(e),
      );
      eventosByData = await guard(
        ChurchTenantResilientReads.eventosByDataEventoRange(
          churchId,
          start: start,
          end: end,
        ),
        (e) => softError ??= _humanize(e),
      );
      cultosSnap = await guard(
        ChurchTenantResilientReads.cultosByDateRange(
          churchId,
          start: start,
          end: end,
        ),
        (e) => softError ??= _humanize(e),
      );
      escalasSnap = await guard(
        ChurchTenantResilientReads.escalasByDateRange(
          churchId,
          start: start,
          end: end,
        ),
        (e) {},
      );
      templatesSnap = await guard(
        ChurchTenantResilientReads.eventTemplates(churchId),
        (e) {},
      ).timeout(const Duration(seconds: 8));
    } else {
      final parallel = await Future.wait<dynamic>([
        guard(
          ChurchTenantResilientReads.muralEventosByStartAtRange(
            churchId,
            start: start,
            end: end,
          ),
          (e) => softError ??= _humanize(e),
        ),
        guard(
          ChurchTenantResilientReads.eventosByDataEventoRange(
            churchId,
            start: start,
            end: end,
          ),
          (e) => softError ??= _humanize(e),
        ),
        guard(
          ChurchTenantResilientReads.cultosByDateRange(
            churchId,
            start: start,
            end: end,
          ),
          (e) => softError ??= _humanize(e),
        ),
        guard(
          ChurchTenantResilientReads.escalasByDateRange(
            churchId,
            start: start,
            end: end,
          ),
          (e) {},
        ),
        guard(
          ChurchTenantResilientReads.eventTemplates(churchId),
          (e) {},
        ).timeout(const Duration(seconds: 8)),
      ]);
      muralEventos = parallel[0] as QuerySnapshot<Map<String, dynamic>>?;
      eventosByData = parallel[1] as QuerySnapshot<Map<String, dynamic>>;
      cultosSnap = parallel[2] as QuerySnapshot<Map<String, dynamic>>;
      escalasSnap = parallel[3] as QuerySnapshot<Map<String, dynamic>>?;
      templatesSnap = parallel[4] as QuerySnapshot<Map<String, dynamic>>;
    }

    return ChurchCalendarMonthLoadResult(
      churchId: churchId,
      agendaDocs: agendaDocs,
      eventosByDataEvento: eventosByData,
      muralEventos: muralEventos,
      cultos: cultosSnap,
      escalas: escalasSnap,
      eventTemplates: templatesSnap,
      softError: softError,
    );
  }

  static String? _humanize(Object e) {
    if (e is TimeoutException) {
      return 'Tempo esgotado ao carregar a agenda. Verifique a conexão.';
    }
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 177)}…';
    return s;
  }
}
