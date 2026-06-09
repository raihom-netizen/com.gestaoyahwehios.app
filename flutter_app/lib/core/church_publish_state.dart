import 'package:cloud_firestore/cloud_firestore.dart';

/// Estados de publicação — rascunho → upload → verificação → publicado.
abstract final class ChurchPublishState {
  ChurchPublishState._();

  static const String draft = 'draft';
  static const String rascunho = 'rascunho';
  static const String uploading = 'uploading';
  static const String verifying = 'verifying';
  static const String success = 'success';
  static const String published = 'published';
  static const String failed = 'failed';

  static const Set<String> inProgress = {
    draft,
    rascunho,
    uploading,
    verifying,
  };

  static bool isPublished(String? state) {
    final s = (state ?? '').trim().toLowerCase();
    return s == success || s == published;
  }

  static bool isDraft(String? state) {
    final s = (state ?? '').trim().toLowerCase();
    return s.isEmpty || inProgress.contains(s) || s == failed;
  }

  static Map<String, dynamic> draftPatch() => {
        'publishState': draft,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> uploadingPatch() => {
        'publishState': uploading,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> verifyingPatch() => {
        'publishState': verifying,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> successPatch() => {
        'publishState': success,
        'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> failedPatch({String? reason}) => {
        'publishState': failed,
        if (reason != null && reason.trim().isNotEmpty)
          'publishError': reason.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
