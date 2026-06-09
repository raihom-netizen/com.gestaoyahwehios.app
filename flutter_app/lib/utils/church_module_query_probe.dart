import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Probe temporário — `.get()` único com logs (Web/Android/iOS mesma query).
abstract final class ChurchModuleQueryProbe {
  ChurchModuleQueryProbe._();

  static void logSuccess({
    required String module,
    required String churchId,
    required String path,
    required int totalDocs,
  }) {
    debugPrint('CHURCH_MODULE_PROBE module=$module');
    debugPrint('CHURCH_ID=$churchId');
    debugPrint('PATH=$path');
    debugPrint('TOTAL_DOCS=$totalDocs');
  }

  static void logError({
    required String module,
    required String churchId,
    required String path,
    required Object error,
    StackTrace? stackTrace,
  }) {
    debugPrint('CHURCH_MODULE_PROBE module=$module');
    debugPrint('CHURCH_ID=$churchId');
    debugPrint('PATH=$path');
    debugPrint('TOTAL_DOCS=0');
    debugPrint('ERRO_FIRESTORE=$error');
    if (stackTrace != null) {
      debugPrint('STACKTRACE=$stackTrace');
    }
  }

  /// Leitura directa `igrejas/{churchId}/{subcollection}` — sem `snapshots()`.
  static Future<int> probeCollection({
    required String module,
    required String churchId,
    required String subcollection,
    int limit = 500,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) {
      logError(
        module: module,
        churchId: id,
        path: 'igrejas/{empty}/$subcollection',
        error: 'churchId vazio',
      );
      return 0;
    }
    final path = 'igrejas/$id/$subcollection';
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final query = ChurchOperationalPaths.churchDoc(id)
          .collection(subcollection)
          .limit(limit);
      final snap = kIsWeb
          ? await firestoreQueryGetReliable(query)
          : await query.get(const GetOptions(source: Source.serverAndCache));
      final total = snap.docs.length;
      logSuccess(module: module, churchId: id, path: path, totalDocs: total);
      return total;
    } catch (e, st) {
      logError(
        module: module,
        churchId: id,
        path: path,
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }
}
