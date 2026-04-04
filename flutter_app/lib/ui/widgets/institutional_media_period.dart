import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Filtro por período (mídias institucionais / painel master).
enum InstitutionalMediaPeriod {
  all,
  last7,
  last30,
  last90,
  custom,
}

DateTime? institutionalMediaDateFromPath(String path) {
  final m = RegExp(r'/(\d{13})_').firstMatch(path.replaceAll('\\', '/'));
  if (m == null) return null;
  final ms = int.tryParse(m.group(1)!);
  if (ms == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

DateTime? institutionalMediaDateFromItem(
  Map<String, dynamic> item, {
  required String storagePath,
}) {
  final raw = item['uploadedAt'];
  if (raw is Timestamp) return raw.toDate();
  return institutionalMediaDateFromPath(storagePath);
}

bool institutionalMediaMatchesPeriod(
  DateTime? uploaded,
  InstitutionalMediaPeriod period,
  DateTime? customStart,
  DateTime? customEnd,
) {
  if (period == InstitutionalMediaPeriod.all) return true;
  if (uploaded == null) return false;
  final d = DateTime(uploaded.year, uploaded.month, uploaded.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case InstitutionalMediaPeriod.all:
      return true;
    case InstitutionalMediaPeriod.last7:
      return !d.isBefore(today.subtract(const Duration(days: 6)));
    case InstitutionalMediaPeriod.last30:
      return !d.isBefore(today.subtract(const Duration(days: 29)));
    case InstitutionalMediaPeriod.last90:
      return !d.isBefore(today.subtract(const Duration(days: 89)));
    case InstitutionalMediaPeriod.custom:
      if (customStart == null || customEnd == null) return true;
      final s =
          DateTime(customStart.year, customStart.month, customStart.day);
      final e = DateTime(customEnd.year, customEnd.month, customEnd.day);
      return !d.isBefore(s) && !d.isAfter(e);
  }
}

String institutionalMediaPeriodLabel(InstitutionalMediaPeriod p) {
  switch (p) {
    case InstitutionalMediaPeriod.all:
      return 'Todo o período';
    case InstitutionalMediaPeriod.last7:
      return 'Últimos 7 dias';
    case InstitutionalMediaPeriod.last30:
      return 'Últimos 30 dias';
    case InstitutionalMediaPeriod.last90:
      return 'Últimos 90 dias';
    case InstitutionalMediaPeriod.custom:
      return 'Personalizado';
  }
}

/// Controlo partilhado entre lista ordenada e grelha (painel master).
@immutable
class InstitutionalMediaAdminConfig {
  final InstitutionalMediaPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final bool selectionMode;
  final Set<String> selectedPaths;
  final void Function(String storagePath) onPathToggle;

  /// Lista normalizada de paths atualmente visíveis na grelha (período + filtro) — para «Selecionar todas».
  final void Function(List<String> normalizedPaths)? onVisiblePathsUpdated;

  const InstitutionalMediaAdminConfig({
    required this.period,
    required this.customStart,
    required this.customEnd,
    required this.selectionMode,
    required this.selectedPaths,
    required this.onPathToggle,
    this.onVisiblePathsUpdated,
  });
}
