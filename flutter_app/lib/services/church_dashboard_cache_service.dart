import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_repository.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Leitura instantânea — `igrejas/{churchId}/_dashboard_cache/main` (1 read no painel).
class ChurchDashboardCacheSnapshot {
  const ChurchDashboardCacheSnapshot({
    required this.totalMembros,
    required this.ativos,
    required this.visitantes,
    required this.saldo,
    this.homens = 0,
    this.mulheres = 0,
    this.criancas = 0,
    this.eventos = 0,
    this.avisos = 0,
    this.updatedAt,
  });

  final int totalMembros;
  final int ativos;
  final int visitantes;
  final double saldo;
  final int homens;
  final int mulheres;
  final int criancas;
  final int eventos;
  final int avisos;
  final DateTime? updatedAt;

  bool get hasData =>
      totalMembros > 0 ||
      ativos > 0 ||
      visitantes > 0 ||
      saldo != 0 ||
      homens > 0 ||
      mulheres > 0 ||
      criancas > 0 ||
      eventos > 0 ||
      avisos > 0;

  factory ChurchDashboardCacheSnapshot.fromMap(Map<String, dynamic> raw) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    double f(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
    DateTime? at;
    final ts = raw['updatedAt'];
    if (ts is Timestamp) at = ts.toDate();
    return ChurchDashboardCacheSnapshot(
      totalMembros: n(raw['totalMembros'] ?? raw['membros'] ?? raw['membersTotalCount']),
      ativos: n(raw['ativos'] ?? raw['activeMembersCount']),
      visitantes: n(raw['visitantes'] ?? raw['newVisitorsCount']),
      saldo: f(raw['saldo'] ?? raw['saldoAtual'] ?? raw['saldo_atual']),
      homens: n(raw['homens']),
      mulheres: n(raw['mulheres']),
      criancas: n(raw['criancas']),
      eventos: n(raw['eventos']),
      avisos: n(raw['avisos']),
      updatedAt: at,
    );
  }
}

abstract final class ChurchDashboardCacheService {
  ChurchDashboardCacheService._();

  static DocumentReference<Map<String, dynamic>> mainDoc([String? churchIdHint]) =>
      ChurchRepository.churchDoc(churchIdHint)
          .collection('_dashboard_cache')
          .doc('main');

  static Future<ChurchDashboardCacheSnapshot?> load({
    String? churchIdHint,
  }) async {
    final id = ChurchRepository.churchId(churchIdHint);
    if (id.isEmpty) return null;
    try {
      final snap = await FirestoreReadResilience.getDocument(
        mainDoc(id),
        cacheKey: 'dashboard_cache_main_$id',
        attemptTimeout: ChurchRepository.panelQueryTimeout,
      );
      if (!snap.exists || snap.data() == null) return null;
      return ChurchDashboardCacheSnapshot.fromMap(snap.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Stream nativo — painel atualiza KPIs sem recalcular no cliente.
  static Stream<ChurchDashboardCacheSnapshot?> watch({
    String? churchIdHint,
  }) {
    final id = ChurchRepository.churchId(churchIdHint);
    if (id.isEmpty) {
      return Stream<ChurchDashboardCacheSnapshot?>.value(null);
    }
    return FirestoreStreamUtils.documentWatchBootstrap(mainDoc(id)).map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ChurchDashboardCacheSnapshot.fromMap(snap.data()!);
    });
  }
}
