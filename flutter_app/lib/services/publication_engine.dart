import 'dart:async' show unawaited;
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_state.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/church_tenant_write_log.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/church_data_service.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Tipos de conteúdo publicável — **único motor** (avisos, eventos, mural, feed público).
enum PublicationKind {
  aviso,
  evento,
  noticia,
  mural,
  feedPublico,
}

/// Fase da distribuição (Firestore já gravado — nunca cancelar publicação).
enum PublicationDistributionPhase {
  afterFirestoreSave,
  afterMediaFinalized,
}

/// Pedido de gravação Firestore (fase obrigatória).
class PublicationSaveRequest {
  const PublicationSaveRequest({
    required this.docRef,
    required this.tenantId,
    required this.kind,
    required this.payload,
    required this.isNewDoc,
    this.merge,
    this.publicSite = true,
    this.pendingPhotoCount = 0,
  });

  final DocumentReference<Map<String, dynamic>> docRef;
  final String tenantId;
  final PublicationKind kind;
  final Map<String, dynamic> payload;
  final bool isNewDoc;
  final bool? merge;
  final bool publicSite;
  final int pendingPhotoCount;

  String get postType => _postTypeFromKind(kind);

  static String _postTypeFromKind(PublicationKind k) {
    switch (k) {
      case PublicationKind.aviso:
      case PublicationKind.mural:
      case PublicationKind.feedPublico:
        return 'aviso';
      case PublicationKind.evento:
      case PublicationKind.noticia:
        return 'evento';
    }
  }

  bool get isEvento => postType == 'evento';
}

/// **Publication Engine** — aviso, evento, notícia, mural, feed público.
///
/// Ordem fixa após gravação Firestore (background; falha num passo **não** desfaz o post):
/// dashboard → painel → feed (streams locais) → site público → push (CF) → WhatsApp (opcional).
abstract final class PublicationEngine {
  PublicationEngine._();

  static const String statusProcessing = MuralFastPublishService.stateUploading;
  static const String statusPublished = MuralFastPublishService.statePublished;
  static const String statusFailed = MuralFastPublishService.stateFailed;
  static const String statusDraft = MuralFastPublishService.stateDraft;

  static const int kMaxPhotosAviso = 5;
  static const int kMaxPhotosEvento = kMaxEventFeedPhotosPerPost;
  static const int kMaxVideosEvento = 1;

  /// Legado — avisos (5 fotos).
  static const int kMaxPhotosPerPost = kMaxPhotosAviso;

  /// Eventos — 5 fotos / 1 vídeo.
  static const int kMaxPhotosPerEvento = kMaxPhotosEvento;
  static const int kMaxVideosPerPost = kMaxVideosEvento;

  static int maxPhotosForKind(PublicationKind kind) {
    switch (kind) {
      case PublicationKind.evento:
      case PublicationKind.noticia:
        return kMaxPhotosEvento;
      default:
        return kMaxPhotosAviso;
    }
  }

  static int maxVideosForKind(PublicationKind kind) {
    switch (kind) {
      case PublicationKind.evento:
      case PublicationKind.noticia:
        return kMaxVideosEvento;
      default:
        return 0;
    }
  }

  // —— Fase 1: Firestore (bloqueante; falha = publicação não concluída) ——

  static Future<String> saveFirestore(PublicationSaveRequest request) async {
    await ensureFirebaseCore(requireAuth: true);
    final patch = _buildFirestorePatch(request);
    final merge = request.merge ?? !request.isNewDoc;
    
    logFirebasePublishPhase(
      'firestore_save_start',
      '${request.postType} path=${request.docRef.path} tenant=${request.tenantId.trim()}',
    );
    try {
      await runFirestorePublishWithRecovery(
        () => ChurchDataService.instance.setTenantDocument(
          ref: request.docRef,
          data: patch,
          merge: merge,
          module: request.postType,
        ),
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'firestore_save_error',
        '${request.postType} path=${request.docRef.path}',
        error: e,
        stack: st,
      );
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
    if (request.kind == PublicationKind.aviso ||
        request.kind == PublicationKind.mural ||
        request.kind == PublicationKind.feedPublico) {
      try {
        await AvisosPublishVerificationService.verifyDocumentExists(
          request.docRef,
        );
      } catch (e, st) {
        AvisosPublishVerificationService.rememberLastError(e);
        ChurchPublishFlowLog.firestoreError(e, st);
        rethrow;
      }
    } else if (request.kind == PublicationKind.evento ||
        request.kind == PublicationKind.noticia) {
      try {
        await EventosPublishVerificationService.verifyDocumentExists(
          request.docRef,
        );
      } catch (e, st) {
        EventosPublishVerificationService.rememberLastError(e);
        ChurchPublishFlowLog.firestoreError(e, st);
        rethrow;
      }
    }
    FeedPublishPreflight.firestoreSaveOk(isEvento: request.isEvento);
    ChurchTenantWriteLog.publishStubCommitted(
      request.docRef.path,
      module: request.postType,
    );
    logFirebasePublishPhase(
      'firestore_save_ok',
      '${request.postType} path=${request.docRef.path}',
    );
    if (request.isEvento) {
      ChurchPublishFlowLog.eventoFirestoreOk();
    } else {
      ChurchPublishFlowLog.avisoFirestoreOk();
    }
    return request.docRef.id;
  }

  static Map<String, dynamic> _buildFirestorePatch(PublicationSaveRequest request) {
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(request.payload),
    );
    final hasPendingPhotos = request.pendingPhotoCount > 0;
    patch['publishState'] = hasPendingPhotos
        ? (request.isNewDoc
            ? EntityPublishStatus.creating
            : statusProcessing)
        : statusPublished;
    if (request.kind == PublicationKind.aviso ||
        request.kind == PublicationKind.mural ||
        request.kind == PublicationKind.feedPublico ||
        request.kind == PublicationKind.evento ||
        request.kind == PublicationKind.noticia) {
      patch['ativo'] = true;
      if (hasPendingPhotos) {
        patch['publicado'] = false;
        patch['status'] = 'processando';
      } else {
        patch['publicado'] = true;
        patch['status'] = 'publicado';
      }
    }
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: request.isNewDoc,
      pendingPhotoCount: request.pendingPhotoCount,
      clearPublishError: true,
    );
    patch['updatedAt'] = FieldValue.serverTimestamp();
    return patch;
  }

  /// Gravação síncrona final — sem fila, pendingImageCount ou publishState.
  static Future<String> saveStrictPublished({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required PublicationKind kind,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    void Function(double progress)? onProgress,
  }) async {
    await ensureFirebaseCore(requireAuth: true);
    final patch = _buildStrictFirestorePatch(payload, isNewDoc: isNewDoc);
    final request = PublicationSaveRequest(
      docRef: docRef,
      tenantId: tenantId,
      kind: kind,
      payload: patch,
      isNewDoc: isNewDoc,
    );
    
    logFirebasePublishPhase(
      'firestore_save_start',
      '${request.postType} strict path=${docRef.path} tenant=${tenantId.trim()}',
    );
    try {
      final collection = request.isEvento ? 'eventos' : 'avisos';
      await AdminFeedFirestoreBridge.upsertTenantDoc(
        churchId: tenantId.trim(),
        collection: collection,
        docId: docRef.id,
        data: patch,
        isNewDoc: isNewDoc,
        onProgress: onProgress,
        directWrite: () => runFirestorePublishWithRecovery(
          () => ChurchDataService.instance.setTenantDocument(
            ref: docRef,
            data: patch,
            merge: !isNewDoc,
            module: request.postType,
          ),
        ),
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'firestore_save_error',
        '${request.postType} strict path=${docRef.path}',
        error: e,
        stack: st,
      );
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
    FeedPublishPreflight.firestoreSaveOk(isEvento: request.isEvento);
    ChurchTenantWriteLog.publishStubCommitted(
      docRef.path,
      module: request.postType,
    );
    logFirebasePublishPhase(
      'firestore_save_ok',
      '${request.postType} strict path=${docRef.path}',
    );
    return docRef.id;
  }

  static Map<String, dynamic> _buildStrictFirestorePatch(
    Map<String, dynamic> payload, {
    required bool isNewDoc,
  }) {
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(payload),
    );
    patch['ativo'] = true;
    patch['publicado'] = true;
    patch['status'] = 'publicado';
    patch['publishState'] = ChurchPublishState.published;
    patch['publishedAt'] = FieldValue.serverTimestamp();
    patch['updatedAt'] = FieldValue.serverTimestamp();
    // Site público: query Firestore exige bool true (string "true" não entra).
    if (patch.containsKey('publicSite')) {
      final v = patch['publicSite'];
      patch['publicSite'] = v == true ||
          v == 1 ||
          (v is String && v.trim().toLowerCase() == 'true');
    }
    if (!isNewDoc) {
      patch['pendingImageCount'] = FieldValue.delete();
      patch['publishError'] = FieldValue.delete();
      patch['photoUploadState'] = FieldValue.delete();
    }
    return patch;
  }

  /// Distribuição pós-publicação — aguardada (painel, site, contadores).
  static Future<void> runDistributionAwait({
    required String tenantId,
    required PublicationKind kind,
    required String postId,
    required bool isNewDoc,
    required bool publicSite,
    PublicationDistributionPhase phase =
        PublicationDistributionPhase.afterMediaFinalized,
  }) =>
      _runDistribution(
        tenantId: tenantId.trim(),
        kind: kind,
        postId: postId,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
        phase: phase,
      );

  /// Grava Firestore e dispara distribuição em background (não bloqueia UI).
  static Future<String> publishFirestoreFirst({
    required PublicationSaveRequest request,
    PublicationDistributionPhase distributionPhase =
        PublicationDistributionPhase.afterFirestoreSave,
  }) async {
    final postId = await saveFirestore(request);
    scheduleDistribution(
      tenantId: request.tenantId,
      kind: request.kind,
      postId: postId,
      isNewDoc: request.isNewDoc,
      publicSite: request.publicSite,
      phase: distributionPhase,
    );
    return postId;
  }

  /// Publicação imediata sem fotos novas.
  static Future<String> publishNow({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required PublicationKind kind,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    bool publicSite = true,
  }) =>
      publishFirestoreFirst(
        request: PublicationSaveRequest(
          docRef: docRef,
          tenantId: tenantId,
          kind: kind,
          payload: payload,
          isNewDoc: isNewDoc,
          publicSite: publicSite,
        ),
      );

  /// Upload → Storage → Firestore (linear). Aviso/evento/notícia nunca usam stub Firestore-first.
  static Future<String> publishWithPhotosInBackground({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required PublicationKind kind,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    required int pendingPhotoCount,
    bool publicSite = true,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
  }) async {
    if (pendingPhotoCount <= 0) {
      return publishNow(
        docRef: docRef,
        tenantId: tenantId,
        kind: kind,
        payload: corePayload,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
      );
    }

    await FeedPublishPreflight.prepareForFirestoreSave();

    if (kind == PublicationKind.aviso) {
      return ChurchFeedLinearPublishService.publishAviso(
        docRef: docRef,
        tenantId: tenantId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingPhotoRefs: existingUrls,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        publicSite: publicSite,
      );
    }

    if (kind == PublicationKind.evento || kind == PublicationKind.noticia) {
      return ChurchFeedLinearPublishService.publishEvento(
        docRef: docRef,
        tenantId: tenantId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingPhotoRefs: existingUrls,
        startSlotIndex: startSlotIndex,
        newImagesBytes: newImagesBytes,
        newImagePaths: newImagePaths,
        publicSite: publicSite,
        hasVideo: hasVideo,
      );
    }

    final request = PublicationSaveRequest(
      docRef: docRef,
      tenantId: tenantId,
      kind: kind,
      payload: corePayload,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      pendingPhotoCount: pendingPhotoCount,
    );
    final postId = await publishFirestoreFirst(request: request);

    Future<void> onMediaDone() async {
      scheduleDistribution(
        tenantId: tenantId,
        kind: kind,
        postId: postId,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
        phase: PublicationDistributionPhase.afterMediaFinalized,
      );
    }

    ChurchTenantWriteLog.publishBackgroundStart(docRef.path, module: request.postType);
    ChurchPublishFlowLog.uploadStart('${request.postType} $postId');

    final postType = request.postType;

    // Web = Android = iOS: preferir bytes (igual Events/Avisos).
    final images = <Uint8List>[
      for (final b in (newImagesBytes ?? const <Uint8List>[]))
        if (b.isNotEmpty) b,
    ];
    if (images.isNotEmpty) {
      MuralFastPublishService.scheduleBackgroundImageFinalize(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        newImages: images,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: MuralPostMediaPayload.buildMediaFields,
        onPublished: onMediaDone,
      );
      return postId;
    }

    if (kIsWeb) {
      throw StateError('Não foi possível ler as fotos para enviar.');
    }

    // Legado: paths → bytes → mesmo finalize da Web (sem scheduleBackgroundImageFinalizeFromPaths).
    final paths = newImagePaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) {
      throw StateError('Não foi possível ler as fotos para enviar.');
    }
    final fromPaths = <Uint8List>[];
    for (final localPath in paths) {
      final f = File(localPath);
      if (!await f.exists()) continue;
      final raw = await f.readAsBytes();
      if (raw.isNotEmpty) fromPaths.add(raw);
    }
    if (fromPaths.isEmpty) {
      throw StateError('Não foi possível ler as fotos para enviar.');
    }
    MuralFastPublishService.scheduleBackgroundImageFinalize(
      docRef: docRef,
      tenantId: tenantId,
      postId: postId,
      postType: postType,
      newImages: fromPaths,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        bytes: bytes,
        slotIndex: slot,
        onProgress: report,
      ),
      buildMediaFields: MuralPostMediaPayload.buildMediaFields,
      onPublished: onMediaDone,
    );
    return postId;
  }

  /// Distribuição pós-publicação — **nunca** reverte o documento Firestore.
  static void scheduleDistribution({
    required String tenantId,
    required PublicationKind kind,
    required String postId,
    required bool isNewDoc,
    required bool publicSite,
    PublicationDistributionPhase phase =
        PublicationDistributionPhase.afterFirestoreSave,
  }) {
    unawaited(
      _runDistribution(
        tenantId: tenantId.trim(),
        kind: kind,
        postId: postId,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
        phase: phase,
      ),
    );
  }

  static Future<void> _runDistribution({
    required String tenantId,
    required PublicationKind kind,
    required String postId,
    required bool isNewDoc,
    required bool publicSite,
    required PublicationDistributionPhase phase,
  }) async {
    if (tenantId.isEmpty) return;
    ChurchPublishFlowLog.phase(
      'DISTRIBUTION_${phase.name}_${kind.name}_$postId',
    );

    await _distStep('dashboard', () async {
      if (!isNewDoc) return;
      await ChurchTenantDashboardDocService.mergeCounters(
        tenantId,
        avisosDelta: kind == PublicationKind.aviso ||
                kind == PublicationKind.mural ||
                kind == PublicationKind.feedPublico
            ? 1
            : null,
        eventosDelta: kind == PublicationKind.evento ||
                kind == PublicationKind.noticia
            ? 1
            : null,
      );
    });

    await _distStep('panel', () async {
      await PanelDashboardSnapshotService.warmFromCallableIfStale(tenantId);
    });

    await _distStep('feed', () async {
      // Feed/mural no app: streams Firestore + cache local — nada bloqueante extra.
    });

    await _distStep('public_site', () async {
      if (!publicSite) return;
      await ChurchPerformanceCacheService.warmPublicFeedCacheFromCallableIfStale(
        tenantId,
      );
    });

    await _distStep('push', () async {
      // Push FCM: Cloud Functions `pushNovoConteudo.ts` após write Firestore.
      // Cliente não envia push — evita duplicar e travar publicação.
    });

    await _distStep('whatsapp', () async {
      // WhatsApp automático: só se tenant tiver integração ativa (futuro).
      // Partilha manual: [church_noticia_share_sheet].
    });

    if (kind == PublicationKind.evento || kind == PublicationKind.noticia) {
      ChurchPublishFlowLog.moduleFinalOk(isEvento: true);
    } else {
      ChurchPublishFlowLog.moduleFinalOk(isEvento: false);
    }
  }

  static Future<void> _distStep(
    String name,
    Future<void> Function() action,
  ) async {
    try {
      ChurchPublishFlowLog.phase('DIST_$name');
      await action().timeout(const Duration(seconds: 50));
      ChurchPublishFlowLog.phase('DIST_${name}_OK');
    } catch (e, st) {
      ChurchPublishFlowLog.logCatch(e, st, label: 'DIST_$name');
    }
  }

  static PublicationKind kindFromPostType(String postType) {
    final t = postType.trim().toLowerCase();
    if (t == 'aviso') return PublicationKind.aviso;
    if (t == 'evento') return PublicationKind.evento;
    if (t == 'noticia') return PublicationKind.noticia;
    if (t == 'feed' || t == 'feed_publico') return PublicationKind.feedPublico;
    return PublicationKind.mural;
  }
}
