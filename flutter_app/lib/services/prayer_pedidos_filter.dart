import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/prayer_orando_membros_denorm.dart';

/// Período rápido para filtros do módulo Pedidos de Oração.
enum PrayerPeriodPreset {
  all,
  week,
  month,
  year,
  custom,
}

/// Filtro compartilhado — painel analítico e limpeza em lote.
class PrayerPedidosFilter {
  const PrayerPedidosFilter({
    this.period = PrayerPeriodPreset.all,
    this.customStart,
    this.customEnd,
    this.categoria,
    this.respondida,
    this.autorUid,
    this.intercessorUid,
    this.memberAuthUids,
    this.searchText = '',
  });

  final PrayerPeriodPreset period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final String? categoria;
  final bool? respondida;
  final String? autorUid;
  final String? intercessorUid;

  /// UIDs (auth) de membros de um departamento — pré-resolvido na UI.
  final Set<String>? memberAuthUids;
  final String searchText;

  PrayerPedidosFilter copyWith({
    PrayerPeriodPreset? period,
    DateTime? customStart,
    DateTime? customEnd,
    String? categoria,
    bool? respondida,
    String? autorUid,
    String? intercessorUid,
    Set<String>? memberAuthUids,
    String? searchText,
    bool clearCategoria = false,
    bool clearAutor = false,
    bool clearIntercessor = false,
    bool clearDepartment = false,
    bool clearRespondida = false,
  }) {
    return PrayerPedidosFilter(
      period: period ?? this.period,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      categoria: clearCategoria ? null : (categoria ?? this.categoria),
      respondida:
          clearRespondida ? null : (respondida ?? this.respondida),
      autorUid: clearAutor ? null : (autorUid ?? this.autorUid),
      intercessorUid:
          clearIntercessor ? null : (intercessorUid ?? this.intercessorUid),
      memberAuthUids:
          clearDepartment ? null : (memberAuthUids ?? this.memberAuthUids),
      searchText: searchText ?? this.searchText,
    );
  }

  (DateTime?, DateTime?) resolveRange({DateTime? now}) {
    final ref = now ?? DateTime.now();
    switch (period) {
      case PrayerPeriodPreset.all:
        return (null, null);
      case PrayerPeriodPreset.week:
        final start = ref.subtract(Duration(days: ref.weekday - 1));
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(ref.year, ref.month, ref.day, 23, 59, 59, 999),
        );
      case PrayerPeriodPreset.month:
        return (
          DateTime(ref.year, ref.month, 1),
          DateTime(ref.year, ref.month + 1, 0, 23, 59, 59, 999),
        );
      case PrayerPeriodPreset.year:
        return (
          DateTime(ref.year, 1, 1),
          DateTime(ref.year, 12, 31, 23, 59, 59, 999),
        );
      case PrayerPeriodPreset.custom:
        return (customStart, customEnd);
    }
  }

  static DateTime? _createdAt(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static List<String> _orandoUids(Map<String, dynamic> data) {
    final membros = PrayerOrandoMembrosDenorm.parseList(data['orandoMembros']);
    if (membros.isNotEmpty) {
      return PrayerOrandoMembrosDenorm.uidsFromMembros(membros);
    }
    final raw = data['orandoUids'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  bool matches(Map<String, dynamic> data, {String docId = ''}) {
    final (start, end) = resolveRange();
    if (start != null || end != null) {
      final created = _createdAt(data);
      if (created == null) return false;
      if (start != null && created.isBefore(start)) return false;
      if (end != null && created.isAfter(end)) return false;
    }

    if (categoria != null && categoria!.isNotEmpty) {
      if ((data['categoria'] ?? 'Outro').toString() != categoria) {
        return false;
      }
    }

    if (respondida != null) {
      final r = data['respondida'] == true;
      if (r != respondida) return false;
    }

    if (autorUid != null && autorUid!.isNotEmpty) {
      if ((data['autorUid'] ?? '').toString().trim() != autorUid) {
        return false;
      }
    }

    if (intercessorUid != null && intercessorUid!.isNotEmpty) {
      if (!_orandoUids(data).contains(intercessorUid)) return false;
    }

    if (memberAuthUids != null && memberAuthUids!.isNotEmpty) {
      final autor = (data['autorUid'] ?? '').toString().trim();
      final orando = _orandoUids(data);
      final hitAutor = autor.isNotEmpty && memberAuthUids!.contains(autor);
      final hitOrando = orando.any(memberAuthUids!.contains);
      if (!hitAutor && !hitOrando) return false;
    }

    final q = searchText.trim().toLowerCase();
    if (q.isNotEmpty) {
      final texto = (data['texto'] ?? '').toString().toLowerCase();
      final autorNome = (data['autorNome'] ?? '').toString().toLowerCase();
      final cat = (data['categoria'] ?? '').toString().toLowerCase();
      if (!texto.contains(q) &&
          !autorNome.contains(q) &&
          !cat.contains(q) &&
          !docId.toLowerCase().contains(q)) {
        return false;
      }
    }

    return true;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> applyToDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs.where((d) => matches(d.data(), docId: d.id)).toList();
}

/// Estatísticas agregadas para gráficos e PDF.
class PrayerPedidosAnalyticsSnapshot {
  const PrayerPedidosAnalyticsSnapshot({
    required this.total,
    required this.abertos,
    required this.respondidos,
    required this.totalIntercessoes,
    required this.porCategoria,
    required this.topIntercessores,
    required this.porMes,
    required this.filteredDocIds,
  });

  final int total;
  final int abertos;
  final int respondidos;
  final int totalIntercessoes;
  final Map<String, int> porCategoria;
  final List<MapEntry<String, int>> topIntercessores;
  final Map<String, int> porMes;
  final List<String> filteredDocIds;

  static PrayerPedidosAnalyticsSnapshot compute(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    PrayerPedidosFilter filter,
  ) {
    final filtered = filter.applyToDocs(docs);
    var abertos = 0;
    var respondidos = 0;
    var totalIntercessoes = 0;
    final porCategoria = <String, int>{};
    final intercessorCounts = <String, int>{};
    final porMes = <String, int>{};

    for (final d in filtered) {
      final data = d.data();
      final respondida = data['respondida'] == true;
      if (respondida) {
        respondidos++;
      } else {
        abertos++;
      }

      final cat = (data['categoria'] ?? 'Outro').toString();
      porCategoria[cat] = (porCategoria[cat] ?? 0) + 1;

      final membros = PrayerOrandoMembrosDenorm.parseList(data['orandoMembros']);
      final uids = membros.isNotEmpty
          ? PrayerOrandoMembrosDenorm.uidsFromMembros(membros)
          : List<String>.from(data['orandoUids'] ?? []);
      totalIntercessoes += membros.isNotEmpty ? membros.length : uids.length;

      for (final m in membros) {
        final uid = (m['uid'] ?? '').toString();
        if (uid.isEmpty) continue;
        final label = (m['nome'] ?? 'Membro').toString();
        intercessorCounts[label] = (intercessorCounts[label] ?? 0) + 1;
      }
      if (membros.isEmpty) {
        for (final uid in uids) {
          intercessorCounts[uid] = (intercessorCounts[uid] ?? 0) + 1;
        }
      }

      final created = PrayerPedidosFilter._createdAt(data);
      if (created != null) {
        final key =
            '${created.year}-${created.month.toString().padLeft(2, '0')}';
        porMes[key] = (porMes[key] ?? 0) + 1;
      }
    }

    final top = intercessorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PrayerPedidosAnalyticsSnapshot(
      total: filtered.length,
      abertos: abertos,
      respondidos: respondidos,
      totalIntercessoes: totalIntercessoes,
      porCategoria: porCategoria,
      topIntercessores: top.take(8).toList(),
      porMes: porMes,
      filteredDocIds: filtered.map((d) => d.id).toList(),
    );
  }
}
