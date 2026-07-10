import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Exclusão canónica de mídia — Firestore primeiro (UI instantânea), Storage em background.
abstract final class ChurchCanonicalMediaDeleteService {
  ChurchCanonicalMediaDeleteService._();

  static void scheduleFeedPostDeleted({
    required String tenantId,
    required String postId,
    required bool isEvento,
    Map<String, dynamic>? data,
  }) {
    unawaited(
      purgeFeedPostDeleted(
        tenantId: tenantId,
        postId: postId,
        isEvento: isEvento,
        data: data,
      ),
    );
  }

  /// Limpeza Storage após exclusão Firestore — aguardar em deletes críticos.
  static Future<void> purgeFeedPostDeleted({
    required String tenantId,
    required String postId,
    required bool isEvento,
    Map<String, dynamic>? data,
  }) =>
      _purgeFeedPostMedia(
        tenantId: tenantId,
        postId: postId,
        isEvento: isEvento,
        data: data,
      );

  static Future<void> _purgeFeedPostMedia({
    required String tenantId,
    required String postId,
    required bool isEvento,
    Map<String, dynamic>? data,
  }) async {
    final tid = ChurchRepository.churchId(tenantId.trim());
    final pid = postId.trim();
    if (tid.isEmpty || pid.isEmpty) return;

    final refs = _collectFeedPostStorageRefs(tid, pid, isEvento, data);
    final seg = isEvento
        ? ChurchStorageLayout.kSegEventos
        : ChurchStorageLayout.kSegAvisos;
    final legacyFolder = '${ChurchStorageLayout.churchRoot(tid)}/$seg/$pid';

    await Future.wait([
      _deleteRefsParallel(refs),
      FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix(legacyFolder),
      if (isEvento)
        for (var s = 0; s < 2; s++)
          FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
            tenantId: tid,
            postDocId: pid,
            videoSlot: s,
          ),
    ]);
  }

  static List<String> _collectFeedPostStorageRefs(
    String tenantId,
    String postId,
    bool isEvento,
    Map<String, dynamic>? data,
  ) {
    final out = <String>{};
    void add(String? raw) {
      final t = (raw ?? '').trim();
      if (t.isNotEmpty) out.add(t);
    }

    if (data != null) {
      final path = eventNoticiaImageStoragePath(data);
      if (path != null) add(path);
      add(eventNoticiaThumbStoragePath(data));
      for (final u in eventNoticiaPhotoUrls(data)) {
        add(u);
      }
      for (final v in eventNoticiaVideosFromDoc(data)) {
        add(v['videoUrl']);
        add(v['thumbUrl']);
      }
      for (final k in const [
        'imageStoragePath',
        'image_storage_path',
        'coverStoragePath',
        'cover_storage_path',
        'photoStoragePath',
        'defaultImageStoragePath',
        'videoStoragePath',
        'video_storage_path',
        'thumbStoragePath',
        'thumb_storage_path',
        'storagePath',
        'storage_path',
      ]) {
        add(data[k]?.toString());
      }
      for (final k in const [
        'imageStoragePaths',
        'image_storage_paths',
        'photoStoragePaths',
        'storagePaths',
        'imageUrls',
        'imageUrl',
        'coverUrl',
        'capaUrl',
        'videoUrl',
        'thumbUrl',
      ]) {
        final raw = data[k];
        if (raw is List) {
          for (final e in raw) {
            add(e?.toString());
          }
        } else {
          add(raw?.toString());
        }
      }
      out.addAll(
        FirebaseStorageCleanupService.urlsFromVariantMap(data['imageVariants']),
      );
      out.addAll(
        FirebaseStorageCleanupService.storagePathsFromVariantMap(
          data['imageVariants'],
        ),
      );
    }

    for (var i = 0; i < 10; i++) {
      if (isEvento) {
        add(ChurchStorageLayout.eventPostPhotoPath(tenantId, postId, i));
        add(ChurchStorageLayout.eventPostPhotoPathLegacy(tenantId, postId, i));
      } else {
        add(ChurchStorageLayout.avisoPostPhotoPath(tenantId, postId, i));
        add(ChurchStorageLayout.avisoPostPhotoPathLegacy(tenantId, postId, i));
      }
    }

    return out.toList();
  }

  static void schedulePatrimonioItemDeleted({
    required String tenantId,
    required String itemId,
    Map<String, dynamic>? data,
  }) {
    unawaited(
      _purgePatrimonioItem(
        tenantId: tenantId,
        itemId: itemId,
        data: data,
      ),
    );
  }

  static Future<void> _purgePatrimonioItem({
    required String tenantId,
    required String itemId,
    Map<String, dynamic>? data,
  }) async {
    final tid = ChurchRepository.churchId(tenantId.trim());
    final iid = itemId.trim();
    if (tid.isEmpty || iid.isEmpty) return;

    final refs = <String>[];
    if (data != null) {
      refs.addAll(ChurchCanonicalMediaContract.patrimonioStoragePaths(data));
      refs.addAll(ChurchCanonicalMediaContract.patrimonioImageUrls(data));
      refs.addAll(
        FirebaseStorageCleanupService.urlsFromVariantMap(data['imageVariants']),
      );
      refs.addAll(
        FirebaseStorageCleanupService.urlsFromVariantMap(data['fotoVariants']),
      );
      refs.addAll(
        FirebaseStorageCleanupService.storagePathsFromVariantMap(
          data['imageVariants'],
        ),
      );
    }

    await Future.wait([
      _deleteRefsParallel(refs),
      FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix(
        ChurchStorageLayout.patrimonioItemFolderPrefix(tid, iid),
      ),
      for (var s = 0; s < ChurchCanonicalMediaContract.patrimonioMaxPhotos; s++)
        FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
          tenantId: tid,
          itemDocId: iid,
          slot: s,
        ),
    ]);
  }

  /// Remove slot de foto — limpa Firestore no ato e Storage em background.
  static void schedulePatrimonioSlotCleared({
    required String tenantId,
    required String itemId,
    required int slot,
    Map<String, dynamic>? existingData,
    DocumentReference<Map<String, dynamic>>? docRef,
  }) {
    final tid = ChurchRepository.churchId(tenantId.trim());
    final iid = itemId.trim();
    final idx = slot.clamp(0, ChurchCanonicalMediaContract.patrimonioMaxPhotos - 1);
    if (tid.isEmpty || iid.isEmpty) return;

    if (docRef != null) {
      final urls = List<String>.filled(
        ChurchCanonicalMediaContract.patrimonioMaxPhotos,
        '',
      );
      final paths = List<String>.filled(
        ChurchCanonicalMediaContract.patrimonioMaxPhotos,
        '',
      );
      if (existingData != null) {
        final eu = PatrimonioPhotoFields.urlsFromData(existingData);
        final ep = PatrimonioPhotoFields.pathsFromData(existingData);
        for (var i = 0; i < ChurchCanonicalMediaContract.patrimonioMaxPhotos; i++) {
          if (i < eu.length) urls[i] = eu[i];
          if (i < ep.length) paths[i] = ep[i];
        }
      }
      urls[idx] = '';
      paths[idx] = '';
      final patch = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      ChurchCanonicalMediaContract.patrimonioApplyIndexedSlots(
        patch,
        urls,
        paths,
      );
      unawaited(docRef.set(patch, SetOptions(merge: true)));
    }

    unawaited(
      FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
        tenantId: tid,
        itemDocId: iid,
        slot: idx,
      ),
    );
  }

  /// Lançamento excluído — limpa comprovante no Storage (doc Firestore já apagado).
  static void scheduleComprovanteArtifactsDeleted({
    required String tenantId,
    required String lancamentoId,
    required Map<String, dynamic> data,
  }) {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    if (churchId.isEmpty || lancamentoId.trim().isEmpty) return;
    if (!FinanceComprovanteAttachService.hasComprovanteInDoc(data)) return;

    unawaited(
      FinanceComprovantePublishService.deleteComprovanteArtifacts(
        tenantId: churchId,
        lancamentoId: lancamentoId.trim(),
        storagePath: (data['comprovanteStoragePath'] ?? '').toString(),
        downloadUrl: (data['comprovanteUrl'] ?? data['comprovanteLink'] ?? '')
            .toString(),
        referenceDate:
            FinanceComprovantePublishService.referenceDateFromMap(data),
        ext: _extFromComprovanteData(data),
      ),
    );
  }

  static String _extFromComprovanteData(Map<String, dynamic> data) {
    final mime = (data['comprovanteMimeType'] ?? '').toString().toLowerCase();
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('png')) return 'png';
    final name = (data['comprovanteFileName'] ?? '').toString().toLowerCase();
    if (name.endsWith('.pdf')) return 'pdf';
    if (name.endsWith('.png')) return 'png';
    return 'jpg';
  }

  static void scheduleChurchLogoRemoved({
    required String churchId,
    Map<String, dynamic>? tenantData,
    String? storagePath,
    String? downloadUrl,
    DocumentReference<Map<String, dynamic>>? churchDocRef,
  }) {
    final cid = ChurchRepository.churchId(churchId.trim());
    if (cid.isEmpty) return;

    if (churchDocRef != null) {
      unawaited(
        churchDocRef.set(
          ChurchCanonicalMediaContract.churchLogoClearFirestorePatch(),
          SetOptions(merge: true),
        ),
      );
    }

    unawaited(
      _purgeChurchLogo(
        churchId: cid,
        tenantData: tenantData,
        storagePath: storagePath,
        downloadUrl: downloadUrl,
      ),
    );
    ChurchBrandService.invalidate(churchId: cid);
  }

  /// Remove logo — Firestore + Storage (await strict, cadastro igreja).
  static Future<void> removeChurchLogoStrict({
    required String churchId,
    Map<String, dynamic>? tenantData,
    String? storagePath,
    String? downloadUrl,
  }) async {
    final cid = ChurchRepository.churchId(churchId.trim());
    if (cid.isEmpty) return;

    await runFirestorePublishWithRecovery(
      () => ChurchRepository.churchDoc(cid).set(
        ChurchCanonicalMediaContract.churchLogoClearFirestorePatch(),
        SetOptions(merge: true),
      ),
    );

    await _purgeChurchLogo(
      churchId: cid,
      tenantData: tenantData,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
    );
    ChurchBrandService.invalidate(churchId: cid);
  }

  static Future<void> _purgeChurchLogo({
    required String churchId,
    Map<String, dynamic>? tenantData,
    String? storagePath,
    String? downloadUrl,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;

    var path = (storagePath ?? '').trim();
    if (path.isEmpty) {
      path = ChurchBrandService.logoPathFromData(tenantData, churchId: cid) ?? '';
    }
    final url = (downloadUrl ?? '').trim();

    await Future.wait([
      _deleteChurchLogoPathWithVariants(path),
      FirebaseStorageCleanupService.deleteByUrlPathOrGs(url),
      FirebaseStorageCleanupService.deleteByUrlPathOrGs(
        ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(cid),
      ),
      FirebaseStorageCleanupService.deleteByUrlPathOrGs(
        ChurchStorageLayout.churchIdentityLogoPath(cid),
      ),
      FirebaseStorageCleanupService.deleteAllObjectsUnderPrefix(
        'igrejas/$cid/configuracoes',
      ),
    ]);
  }

  static Future<void> _deleteChurchLogoPathWithVariants(String storagePath) async {
    final p = storagePath.trim();
    if (p.isEmpty) return;
    await FirebaseStorageCleanupService.deleteByUrlPathOrGs(p);
    final lower = p.toLowerCase();
    if (!lower.endsWith('.jpg') &&
        !lower.endsWith('.jpeg') &&
        !lower.endsWith('.png') &&
        !lower.endsWith('.webp')) {
      return;
    }
    final dot = p.lastIndexOf('.');
    final base = dot < 0 ? p : p.substring(0, dot);
    await Future.wait([
      for (final suffix in const ['_thumb.jpg', '_card.jpg', '_full.jpg'])
        FirebaseStorageCleanupService.deleteByUrlPathOrGs('$base$suffix'),
    ]);
    final slash = p.lastIndexOf('/');
    if (slash >= 0 && dot > slash) {
      final dir = p.substring(0, slash);
      final fileBase = p.substring(slash + 1, dot);
      if (fileBase.isNotEmpty) {
        await FirebaseStorageCleanupService.deleteByUrlPathOrGs(
          '$dir/thumb_$fileBase.jpg',
        );
      }
    }
  }

  static void scheduleMemberProfilePhotoRemoved({
    required String tenantId,
    required String memberId,
    required Map<String, dynamic> memberData,
    DocumentReference<Map<String, dynamic>>? memberDocRef,
  }) {
    final tid = ChurchRepository.churchId(tenantId.trim());
    final mid = memberId.trim();
    if (tid.isEmpty || mid.isEmpty) return;

    if (memberDocRef != null) {
      unawaited(
        memberDocRef.set(
          ChurchCanonicalMediaContract.memberProfileClearFirestorePatch(),
          SetOptions(merge: true),
        ),
      );
    }

    unawaited(
      FirebaseStorageCleanupService.deleteMemberProfilePhotoArtifactsBeforeReplace(
        tenantId: tid,
        memberId: mid,
        data: memberData,
      ),
    );
  }

  static Future<void> _deleteRefsParallel(Iterable<String> refs) async {
    final items = refs
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (items.isEmpty) return;
    await Future.wait(
      items.map(FirebaseStorageCleanupService.deleteByUrlPathOrGs),
    );
  }
}
