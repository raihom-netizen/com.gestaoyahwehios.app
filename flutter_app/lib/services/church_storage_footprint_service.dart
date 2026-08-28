import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Um grupo de ficheiros (Imagens, Vídeos, PDFs…) e o que ocupa.
class ChurchStorageGroup {
  const ChurchStorageGroup({
    required this.label,
    required this.bytes,
    required this.files,
  });

  final String label;
  final int bytes;
  final int files;
}

/// Espaço real ocupado por uma igreja.
class ChurchStorageFootprint {
  const ChurchStorageFootprint({
    required this.tenantId,
    required this.totalBytes,
    required this.totalFiles,
    required this.firestoreDocs,
    required this.groups,
  });

  final String tenantId;
  final int totalBytes;
  final int totalFiles;
  final int firestoreDocs;
  final List<ChurchStorageGroup> groups;
}

/// Mede o que a igreja ocupa no Cloud Storage — bytes reais, não estimativa.
///
/// A `getChurchStorageUsage` antiga só contava documentos do Firestore e
/// multiplicava por 1 KB; não respondia «quanto de arquivo esta igreja tem».
abstract final class ChurchStorageFootprintService {
  ChurchStorageFootprintService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    app: firebaseDefaultApp,
    region: 'us-central1',
  );

  static Future<ChurchStorageFootprint> load(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) throw ArgumentError('tenantId vazio');
    final callable = _functions.httpsCallable(
      'getChurchStorageFootprint',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );
    final res = await callable.call<Map<String, dynamic>>({'tenantId': tid});
    final d = res.data;
    return ChurchStorageFootprint(
      tenantId: (d['tenantId'] ?? tid).toString(),
      totalBytes: int.tryParse('${d['totalBytes'] ?? 0}') ?? 0,
      totalFiles: int.tryParse('${d['totalFiles'] ?? 0}') ?? 0,
      firestoreDocs: int.tryParse('${d['firestoreDocs'] ?? 0}') ?? 0,
      groups: [
        for (final g in (d['groups'] as List? ?? const []))
          if (g is Map)
            ChurchStorageGroup(
              label: (g['label'] ?? '').toString(),
              bytes: int.tryParse('${g['bytes'] ?? 0}') ?? 0,
              files: int.tryParse('${g['files'] ?? 0}') ?? 0,
            ),
      ],
    );
  }
}
