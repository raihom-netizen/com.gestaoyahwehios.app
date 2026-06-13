import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_profile_variants_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageMediaUrlLooksLike,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isValidImageUrl,
        sanitizeImageUrl;

/// Fonte única — foto de perfil do membro (lista, chat, painel, carteirinha).
abstract final class MemberProfilePhotoResolver {
  MemberProfilePhotoResolver._();

  /// Referência para exibição: URL https, `gs://` ou path `igrejas/...`.
  static String? displayRef(
    Map<String, dynamic>? data, {
    bool preferThumb = false,
  }) {
    if (data == null || data.isEmpty) return null;

    if (preferThumb) {
      final thumbPath = MemberImageFields.photoThumbStoragePath(data);
      if (thumbPath != null && thumbPath.isNotEmpty) return thumbPath;
      final thumbUrl = MemberImageFields.photoThumbDownloadUrl(data);
      if (thumbUrl != null && thumbUrl.isNotEmpty) return thumbUrl;
    }

    // URL https no Firestore — prioridade sobre path desatualizado (docId ≠ authUid).
    final https = MemberImageFields.photoDownloadUrl(data);
    if (https != null && https.isNotEmpty) return https;

    if (preferThumb) {
      final list = MemberProfileVariantsService.listPhotoUrl(data);
      if (list != null && list.isNotEmpty) return list;
    }

    final storagePath = MemberImageFields.photoStoragePath(data);
    if (storagePath != null && storagePath.isNotEmpty) return storagePath;

    final full = MemberProfileVariantsService.profilePhotoUrl(data);
    if (full != null && full.isNotEmpty) return full;

    final mapUrl = imageUrlFromMap(data);
    return mapUrl.isEmpty ? null : mapUrl;
  }

  static bool hasPhotoRef(Map<String, dynamic>? data, {bool preferThumb = false}) {
    final r = displayRef(data, preferThumb: preferThumb);
    return r != null && isResolvableRef(r);
  }

  /// Aceita https, gs:// ou path Storage (não só URL http).
  static bool isResolvableRef(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return false;
    if (isValidImageUrl(sanitizeImageUrl(s))) return true;
    final low = s.toLowerCase();
    if (low.startsWith('gs://')) return true;
    return firebaseStorageMediaUrlLooksLike(s);
  }

  /// UID/pasta real no Storage — campos do doc + segmento em URL/path.
  static String? authUidFromData(
    Map<String, dynamic> data, {
    String? memberDocId,
  }) {
    for (final k in const [
      'authUid',
      'firebaseUid',
      'firebase_uid',
      'firebaseUserId',
      'userId',
      'user_id',
      'uid',
      'USUARIO_UID',
      'usuario_uid',
    ]) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }

    final stems = StorageMediaService.memberProfileFolderStemsFromFirestoreMap(
      data,
    );
    if (stems.isEmpty) return null;

    final docId = (memberDocId ?? '').trim();
    if (docId.isNotEmpty) {
      for (final stem in stems) {
        if (stem != docId) return stem;
      }
    }
    return stems.first;
  }

  /// Path canónico para tentativa de download quando o doc não tem path correto.
  static String canonicalPhotoPath({
    required String tenantId,
    required String memberDocId,
    Map<String, dynamic>? data,
    bool preferThumb = false,
  }) {
    final tid = tenantId.trim();
    final mid = memberDocId.trim();
    final ref = displayRef(data, preferThumb: preferThumb);
    if (ref != null) {
      final path = firebaseStorageObjectPathFromHttpUrl(ref) ??
          StorageMediaService.normalizeFirestoreStoragePath(ref);
      if (path != null && path.isNotEmpty) return path;
    }
    final folder = FirebaseStorageService.memberProfileStorageFolderId(
      mid,
      authUidFromData(data ?? const {}, memberDocId: mid),
    );
    if (preferThumb) {
      return ChurchStorageLayout.memberProfileThumbPathFlatWebpLegacy(tid, folder);
    }
    return ChurchStorageLayout.memberProfilePhotoPath(tid, folder);
  }
}
