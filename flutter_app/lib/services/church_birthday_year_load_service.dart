import 'dart:async' show TimeoutException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_birthday_query_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Entrada leve para a vista «Aniversariantes do ano».
class ChurchBirthdayYearEntry {
  const ChurchBirthdayYearEntry({
    required this.memberDocId,
    required this.memberData,
    required this.birthDate,
  });

  final String memberDocId;
  final Map<String, dynamic> memberData;
  final DateTime birthDate;

  int get month => birthDate.month;
  int get day => birthDate.day;

  String get displayName =>
      (memberData['NOME_COMPLETO'] ??
              memberData['nome'] ??
              memberData['name'] ??
              '')
          .toString()
          .trim();

  String get firstName {
    final full = displayName;
    if (full.isEmpty) return '?';
    return full.split(RegExp(r'\s+')).first;
  }
}

/// Carga rápida — directory `_panel_cache` → scan único `membrosRecent` (sem 12 queries).
abstract final class ChurchBirthdayYearLoadService {
  ChurchBirthdayYearLoadService._();

  static const Duration loadTimeout = Duration(seconds: 22);
  static const int scanLimit = 600;

  static Future<List<ChurchBirthdayYearEntry>> load({
    required String seedTenantId,
    MembersDirectorySnapshot? directoryHint,
  }) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) return const [];

    return loadTimeoutGuard(
      _loadInternal(churchId, directoryHint: directoryHint),
    );
  }

  static Future<List<ChurchBirthdayYearEntry>> loadTimeoutGuard(
    Future<List<ChurchBirthdayYearEntry>> future,
  ) {
    return future.timeout(
      loadTimeout,
      onTimeout: () => throw TimeoutException(
        'Tempo esgotado ao carregar aniversariantes. Toque em atualizar.',
      ),
    );
  }

  static Future<List<ChurchBirthdayYearEntry>> _loadInternal(
    String churchId, {
    MembersDirectorySnapshot? directoryHint,
  }) async {
    final byId = <String, ChurchBirthdayYearEntry>{};

    void absorb(String docId, Map<String, dynamic> data) {
      final dt = birthDateFromMemberData(data);
      if (dt == null) return;
      byId[docId] = ChurchBirthdayYearEntry(
        memberDocId: docId,
        memberData: data,
        birthDate: DateTime(2000, dt.month, dt.day),
      );
    }

    final directory = await _resolveDirectory(churchId, directoryHint);
    if (directory != null) {
      for (final e in directory.entries) {
        absorb(e.memberDocId, e.toMemberDataMap());
      }
    }

    if (_needsFullRoster(directory, byId.length)) {
      final yearDocs = await ChurchBirthdayQueryService.fetchYearAllMonths(
        tenantId: churchId,
        perMonthLimit: 80,
      );
      for (final doc in yearDocs) {
        absorb(doc.id, doc.data());
      }

      if (byId.length < 8) {
        final snap = await ChurchTenantResilientReads.membrosRecent(
          churchId,
          limit: scanLimit,
        );
        for (final doc in snap.docs) {
          absorb(doc.id, doc.data());
        }
      }
    }

    final list = byId.values.toList()
      ..sort((a, b) {
        final cm = a.month.compareTo(b.month);
        return cm != 0 ? cm : a.day.compareTo(b.day);
      });
    return list;
  }

  /// Directory pode ter muitos membros mas poucas `DATA_NASCIMENTO` — força roster.
  static bool _needsFullRoster(
    MembersDirectorySnapshot? directory,
    int birthdayCount,
  ) {
    if (birthdayCount < 8) return true;
    if (directory == null || !directory.hasEntries) return true;
    final total = directory.entries.length;
    if (total <= 0) return true;
    final minExpected = (total * 0.2).ceil().clamp(3, 999);
    return birthdayCount < minExpected;
  }

  static Future<MembersDirectorySnapshot?> _resolveDirectory(
    String churchId,
    MembersDirectorySnapshot? hint,
  ) async {
    if (hint != null && hint.hasEntries) return hint;
    final peek = MembersDirectorySnapshotService.peekMemory(churchId);
    if (peek != null && peek.hasEntries) return peek;
    final read = await MembersDirectorySnapshotService.readOnce(churchId);
    if (read.hasEntries) return read;
    return MembersDirectorySnapshotService.warmFromCallableIfStale(churchId);
  }

  /// Agrupa por mês (1–12) e, dentro de cada mês, por dia.
  static Map<int, Map<int, List<ChurchBirthdayYearEntry>>> groupByMonthAndDay(
    List<ChurchBirthdayYearEntry> entries,
  ) {
    final out = <int, Map<int, List<ChurchBirthdayYearEntry>>>{};
    for (var m = 1; m <= 12; m++) {
      out[m] = {};
    }
    for (final e in entries) {
      out[e.month]!.putIfAbsent(e.day, () => []).add(e);
    }
    for (final days in out.values) {
      for (final list in days.values) {
        list.sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      }
    }
    return out;
  }
}
