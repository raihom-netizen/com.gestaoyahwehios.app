import 'package:cloud_firestore/cloud_firestore.dart';

/// Impede gravação acidental de payloads pesados no Firestore (base64 de mídia).
abstract final class FirestoreWriteGuard {
  FirestoreWriteGuard._();

  static const int _maxStringLen = 12000;

  static bool _looksLikeEmbeddedMedia(String s) {
    final t = s.trim().toLowerCase();
    if (t.startsWith('data:image/') && t.contains(';base64,')) return true;
    if (t.length < 5000) return false;
    if (t.startsWith('/9j/') || t.startsWith('ivbor')) return true;
    return false;
  }

  /// Remove chaves com strings enormes / base64 de imagem.
  static Map<String, dynamic> stripHeavyFields(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value is String) {
        if (value.length > _maxStringLen || _looksLikeEmbeddedMedia(value)) {
          return;
        }
        out[key] = value;
      } else if (value is Map) {
        out[key] = stripHeavyFields(Map<String, dynamic>.from(value));
      } else if (value is List) {
        out[key] = value;
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  /// Metadados de publicação (avisos/eventos). Em `set`/`add` **sem** merge, não usar
  /// [FieldValue.delete] — Firestore rejeita com `invalid-argument` (ex.: `publishError`).
  static void applyMuralPublishMetaPatch(
    Map<String, dynamic> patch, {
    required bool isNewDoc,
    int? pendingPhotoCount,
    bool clearPendingImageCount = false,
    bool clearPublishError = false,
  }) {
    if (pendingPhotoCount != null && pendingPhotoCount > 0) {
      patch['pendingImageCount'] = pendingPhotoCount;
    } else if (!isNewDoc && clearPendingImageCount) {
      patch['pendingImageCount'] = FieldValue.delete();
    }
    if (!isNewDoc && clearPublishError) {
      patch['publishError'] = FieldValue.delete();
    }
  }
}
