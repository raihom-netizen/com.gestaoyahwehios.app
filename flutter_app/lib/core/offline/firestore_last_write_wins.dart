import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Resolução de conflitos offline-first: **última gravação vence** (LWW).
///
/// Toda escrita inclui [updatedAt] com [FieldValue.serverTimestamp] para o
/// Firestore ordenar gravações concorrentes de forma consistente.
abstract final class FirestoreLastWriteWins {
  FirestoreLastWriteWins._();

  static const String updatedAtField = 'updatedAt';
  static const String clientWriteSeqField = 'clientWriteSeq';

  /// Carimbo LWW para `set` / `update` — não sobrescreve campos de criação.
  static Map<String, dynamic> stamp(
    Map<String, dynamic> data, {
    bool includeCreatedAt = false,
  }) {
    final out = Map<String, dynamic>.from(data);
    out[updatedAtField] = FieldValue.serverTimestamp();
    out[clientWriteSeqField] = DateTime.now().millisecondsSinceEpoch;
    if (includeCreatedAt && !out.containsKey('createdAt')) {
      out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }

  /// Mescla patch LWW (updates parciais).
  static Map<String, dynamic> stampUpdate(Map<String, dynamic> patch) =>
      stamp(patch);

  /// Tamanho de página padrão para listagens lazy (20).
  static int get listPageSize => YahwehPerformanceV4.defaultPageSize;
}
