import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

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

  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static final _db = FirebaseFirestore.instance;

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
      final snap = await MasterAdminFirestore.document(
        ChurchOperationalPaths.churchDoc(op),
        cacheKey: 'storage_church_$tid',
      );
      churchData = snap.data();
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

    for (final name in _sampleCollections) {
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => ref
              .collection(name)
              .limit(YahwehPerformanceV4.masterStorageEstimateSampleLimit)
              .get()
              .timeout(const Duration(seconds: 12)),
        );
        final c = snap.docs.length;
        final atCap =
            c >= YahwehPerformanceV4.masterStorageEstimateSampleLimit;
        counts[name] = c;
        if (atCap) sampledCollections++;
        totalDocs += c;
      } catch (_) {
        counts[name] = 0;
      }
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
