import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';

/// Resultado do uso de armazenamento Firestore de uma igreja.
class ChurchStorageUsageResult {
  final Map<String, dynamic> usage;
  final Map<String, dynamic>? churchData;
  final bool usingLocalEstimate;

  const ChurchStorageUsageResult({
    required this.usage,
    this.churchData,
    this.usingLocalEstimate = false,
  });

  int get totalDocs {
    final fs = usage['firestore'];
    if (fs is! Map) return 0;
    return (fs['totalDocs'] as num?)?.toInt() ?? 0;
  }

  int get estimateBytes {
    final fs = usage['firestore'];
    if (fs is! Map) return 0;
    return (fs['estimateBytes'] as num?)?.toInt() ?? 0;
  }
}

/// Carrega uso Firestore por igreja — Cloud Function com fallback local resiliente.
abstract final class ChurchStorageUsageService {
  ChurchStorageUsageService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static const _sampleCollections = [
    'members',
    'membros',
    'noticias',
    'avisos',
    'usersIndex',
    'event_templates',
    'departamentos',
    'patrimonio',
    'cultos',
    'visitantes',
    'eventos',
    'pedidosOracao',
  ];

  static Future<ChurchStorageUsageResult> load(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      throw ArgumentError('tenantId vazio');
    }

    await MasterAdminFirestore.ensureReady();

    Map<String, dynamic>? usage;
    var localEstimate = false;

    try {
      final callable = _functions.httpsCallable(
        'getChurchStorageUsage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 22)),
      );
      final result = await FirestoreWebGuard.runWithWebRecovery(
        () => callable.call<Map<dynamic, dynamic>>({'tenantId': tid}),
      );
      usage = Map<String, dynamic>.from(result.data);
    } catch (_) {
      usage = await _loadLocalFirestoreEstimate(tid);
      localEstimate = true;
    }

    Map<String, dynamic>? churchData;
    try {
      final op = await ChurchOperationalPaths.resolveCached(tid.trim());
      churchData = await firestoreReadDocSafe(
        ChurchOperationalPaths.churchDoc(op),
      );
    } catch (_) {}

    return ChurchStorageUsageResult(
      usage: usage,
      churchData: churchData,
      usingLocalEstimate: localEstimate,
    );
  }

  static Future<Map<String, dynamic>> _loadLocalFirestoreEstimate(
    String tenantId,
  ) async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final ref = ChurchOperationalPaths.churchDoc(op);
    final counts = <String, int>{};
    var totalDocs = 0;
    var sampledCollections = 0;

    // As 12 coleções em PARALELO e por `count()` (RunAggregationQuery) em vez
    // de `.get()` sequencial. O `.get()` do SDK JS abre um alvo de listen por
    // chamada — 12 alvos por igreja, vezes N igrejas, era o que devolvia
    // «Sincronização com o servidor em curso» nesta tela e a deixava lenta.
    // A agregação não passa pelo watch stream e traz a contagem real.
    final resultados = await Future.wait(
      _sampleCollections.map((name) async {
        final col = ref.collection(name);
        try {
          final agg = await col.count().get().timeout(
            const Duration(seconds: 12),
          );
          return (nome: name, total: agg.count ?? 0, noLimite: false);
        } catch (_) {
          try {
            final docs = await firestoreListDocsSafe(
              col,
              limit: YahwehPerformanceV4.masterStorageEstimateSampleLimit,
            ).timeout(const Duration(seconds: 12));
            return (
              nome: name,
              total: docs.length,
              noLimite: docs.length >=
                  YahwehPerformanceV4.masterStorageEstimateSampleLimit,
            );
          } catch (_) {
            return (nome: name, total: 0, noLimite: false);
          }
        }
      }),
    );

    for (final r in resultados) {
      counts[r.nome] = r.total;
      totalDocs += r.total;
      if (r.noLimite) sampledCollections++;
    }

    final estimateBytes = totalDocs * 500;
    return {
      'firestore': {
        'docCounts': counts,
        'totalDocs': totalDocs,
        'estimateBytes': estimateBytes,
        'sampledCollections': sampledCollections,
      },
    };
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
