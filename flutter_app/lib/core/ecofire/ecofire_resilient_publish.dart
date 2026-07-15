import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/background_upload_worker.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_outbound_pending.dart';
import 'package:gestao_yahweh/services/module_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/services/patrimonio_photo_fields.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/offline_payload_codec.dart';
import 'package:gestao_yahweh/core/offline/offline_write_operations.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';
import 'package:gestao_yahweh/core/offline/firestore_last_write_wins.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/sync_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Publicação resiliente — online rápido; offline/rede fraca → fila silenciosa + sync automático.
abstract final class EcoFireResilientPublish {
  EcoFireResilientPublish._();

  /// Erro tratado como sucesso local — UI não mostra SnackBar vermelho.
  static bool isQueuedSuccess(Object e) =>
      e is ResilientPublishQueuedException;

  /// Deve enfileirar em background (sem bloquear o utilizador).
  ///
  /// Offline real → sempre. Online: só erros de rede transitórios explícitos
  /// (nunca `internal`/assert — chat: bolha sumia → «Sem mensagens ainda»).
  static bool shouldQueueSilently(Object error) {
    if (error is ResilientPublishQueuedException) return true;
    if (!AppConnectivityService.instance.isOnline) return true;

    if (FirestoreWebGuard.isInternalAssertionError(error)) return false;

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'network-request-failed':
          return true;
        case 'deadline-exceeded':
        case 'resource-exhausted':
        case 'aborted':
        case 'cancelled':
        case 'internal':
          return false;
      }
    }

    final low = error.toString().toLowerCase();
    if (low.contains('offline') ||
        low.contains('sem conexão') ||
        low.contains('sem ligacao') ||
        low.contains('client is offline') ||
        low.contains('network-request-failed') ||
        low.contains('failed to fetch') ||
        low.contains('socketexception')) {
      return true;
    }
    if (low.contains('timeout') ||
        low.contains('tempo esgotado') ||
        low.contains('deadline') ||
        low.contains('internal assertion')) {
      return false;
    }

    return false;
  }

  /// Avisos/eventos — também enfileira após falha de bootstrap (já com retry).
  static bool shouldQueueFeedPublish(Object error) {
    if (shouldQueueSilently(error)) return true;
    if (isFirebaseNoAppError(error)) return true;
    if (error is TimeoutException) return !AppConnectivityService.instance.isOnline;
    return false;
  }

  /// Bootstrap — offline passa; online tenta init + refresh token antes de falhar.
  static Future<void> prepareForPublish({String logLabel = 'resilient'}) async {
    if (!AppConnectivityService.instance.isOnline) return;
    try {
      await EcoFirePublishBootstrap.ensureHard(logLabel: logLabel, strict: true);
      return;
    } catch (e) {
      if (shouldQueueSilently(e)) return;
      rethrow;
    }
  }

  /// Agenda sync global (chat, mural, storage, Hive).
  static void scheduleSync({String reason = 'resilient_queue'}) {
    BackgroundUploadWorker.scheduleDrain(reason: reason);
  }

  /// Avisos / eventos — cache fotos + outbox + Firestore local offline.
  static Future<void> queueFeedPublish({
    required String churchId,
    required String docId,
    required String postType,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? bytesList,
    List<String>? localPaths,
  }) async {
    final tid = churchId.trim();
    final pid = docId.trim();
    if (bytesList != null && bytesList.isNotEmpty) {
      await MuralPostPendingMediaCache.put(
        tenantId: tid,
        postId: pid,
        images: bytesList,
      );
    }
    final paths = localPaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    await MuralPublishOutboxService.registerJob(
      tenantId: tid,
      postId: pid,
      postType: postType,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      localPaths: paths.isEmpty ? null : paths,
    );

    final localPayload = Map<String, dynamic>.from(corePayload);
    localPayload['ativo'] = true;
    localPayload['publicado'] = true;
    localPayload['status'] = 'publicado';
    localPayload['publishState'] = MuralFastPublishService.stateUploading;
    localPayload['photoUploadState'] = EntityPublishStatus.uploading;

    await TenantOfflineWrite.setDocument(
      ref: docRef,
      data: localPayload,
      merge: !isNewDoc,
      module: postType == 'evento' ? 'eventos' : 'avisos',
      tenantId: tid,
    );

    if (kDebugMode) {
      debugPrint('EcoFireResilientPublish: feed enfileirado $postType/$pid');
    }
  }

  /// Chat — outbox local + bytes/path (sync silencioso).
  static Future<void> queueChatMedia({
    required String tenantId,
    required String threadId,
    required ChurchChatOutboundPending pending,
    List<int>? bytes,
    String? localPath,
  }) async {
    Uint8List? u8;
    if (bytes != null && bytes.isNotEmpty) {
      u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    } else if (pending.previewBytes != null && pending.previewBytes!.isNotEmpty) {
      u8 = pending.previewBytes;
    }
    await ChurchChatMediaOutboxService.registerJob(
      tenantId: tenantId,
      threadId: threadId,
      localId: pending.localId,
      kind: pending.kind,
      fileName: pending.fileName,
      mime: pending.mime,
      firestoreMessageId: pending.firestoreMessageId,
      storagePath: pending.storagePath,
      localPath: localPath ?? pending.localPath,
      bytes: u8,
    );
    if (kDebugMode) {
      debugPrint(
        'EcoFireResilientPublish: chat enfileirado ${pending.localId}',
      );
    }
  }

  /// Património — cache fotos + outbox + Firestore local offline.
  static Future<void> queuePatrimonioPublish({
    required String churchId,
    required String itemId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    Map<int, Uint8List> uploadsBySlot = const {},
    List<String> indexedSlotUrls = const [],
    List<String> indexedSlotPaths = const [],
    List<Uint8List> newImages = const [],
    int startSlot = 0,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
  }) async {
    final tid = churchId.trim();
    final iid = itemId.trim();
    final queuedImages = uploadsBySlot.isNotEmpty
        ? (uploadsBySlot.keys.toList()..sort())
            .map((s) => uploadsBySlot[s]!)
            .toList(growable: false)
        : newImages;
    final queuedStartSlot = uploadsBySlot.isNotEmpty
        ? uploadsBySlot.keys.reduce((a, b) => a < b ? a : b)
        : startSlot;
    final queuedExistingUrls = indexedSlotUrls.length >=
            PatrimonioPhotoFields.maxPhotos
        ? indexedSlotUrls
        : existingUrls;
    final queuedExistingPaths = indexedSlotPaths.length >=
            PatrimonioPhotoFields.maxPhotos
        ? indexedSlotPaths
        : existingPaths;
    if (queuedImages.isNotEmpty) {
      await MuralPostPendingMediaCache.put(
        tenantId: tid,
        postId: 'patrimonio_$iid',
        images: queuedImages,
      );
    }
    await ModuleMediaOutboxService.registerPatrimonio(
      tenantId: tid,
      itemId: iid,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      startSlot: queuedStartSlot,
      existingPaths: queuedExistingPaths,
      existingUrls: queuedExistingUrls,
    );
    final localPayload = Map<String, dynamic>.from(corePayload);
    localPayload['ativo'] = true;
    localPayload[EntityPublishStatus.photoUploadStateField] = 'pending_sync';
    localPayload['publishState'] = 'pending_sync';

    await TenantOfflineWrite.setDocument(
      ref: docRef,
      data: localPayload,
      merge: !isNewDoc,
      module: 'patrimonio',
      tenantId: tid,
    );
    if (kDebugMode) {
      debugPrint('EcoFireResilientPublish: património enfileirado $iid');
    }
  }

  /// Financeiro — lançamento na fila Hive (+ comprovante opcional em outbox).
  static Future<void> queueFinanceLancamento({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> payload,
    required bool isEdit,
    Uint8List? comprovanteBytes,
    String? comprovanteMime,
    String? comprovanteFileName,
    DateTime? referenceDate,
  }) async {
    final tid = churchId.trim();
    final stamped = FirestoreLastWriteWins.stamp(
      FirestoreWriteGuard.stripHeavyFields(Map<String, dynamic>.from(payload)),
      includeCreatedAt: !isEdit,
    );
    stamped['publishState'] = 'pending_sync';
    if (comprovanteBytes != null && comprovanteBytes.isNotEmpty) {
      stamped[FinanceComprovantePublishService.comprovanteUploadStateField] =
          EntityPublishStatus.uploading;
      await MuralPostPendingMediaCache.put(
        tenantId: tid,
        postId: 'finance_${docRef.id}',
        images: [comprovanteBytes],
      );
      await ModuleMediaOutboxService.registerFinanceComprovante(
        tenantId: tid,
        lancamentoId: docRef.id,
        mimeType: comprovanteMime ?? 'image/jpeg',
        fileName: comprovanteFileName,
        referenceDateMs: referenceDate?.millisecondsSinceEpoch,
        alreadyCompressed: true,
      );
    }

    await SyncEngine.enqueue(
      SyncTask(
        id:
            'finance_${isEdit ? 'update' : 'set'}_${docRef.path.hashCode}_${DateTime.now().microsecondsSinceEpoch}',
        module: OfflineModules.financeiro,
        tenantId: tid,
        operation:
            isEdit ? OfflineWriteOperations.update : OfflineWriteOperations.set,
        payload: {
          'path': docRef.path,
          'data': OfflinePayloadCodec.encodeMap(stamped),
          'merge': isEdit,
        },
      ),
    );
    SyncService.notifyUserActionSaved();
    if (kDebugMode) {
      debugPrint('EcoFireResilientPublish: financeiro enfileirado ${docRef.id}');
    }
  }

  /// Financeiro — só comprovante pendente (lançamento já gravado).
  static Future<void> queueFinanceComprovante({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
    bool alreadyCompressed = true,
  }) async {
    final tid = churchId.trim();

    // Web online: fila Hive/SharedPreferences perde bytes — upload imediato.
    if (kIsWeb && AppConnectivityService.instance.isOnline) {
      try {
        await FinanceComprovantePublishService.uploadComprovanteNow(
          tenantId: tid,
          docRef: docRef,
          rawBytes: bytes,
          mimeType: mimeType,
          fileName: fileName,
          referenceDate: referenceDate,
          previousStoragePath: previousStoragePath,
          previousDownloadUrl: previousDownloadUrl,
          alreadyCompressed: alreadyCompressed,
        );
        scheduleSync(reason: 'finance_comprovante_web_direct');
        return;
      } catch (e, st) {
        debugPrint(
          'EcoFireResilientPublish: web comprovante direct falhou: $e\n$st',
        );
        rethrow;
      }
    }

    await MuralPostPendingMediaCache.put(
      tenantId: tid,
      postId: 'finance_${docRef.id}',
      images: [bytes],
    );
    await ModuleMediaOutboxService.registerFinanceComprovante(
      tenantId: tid,
      lancamentoId: docRef.id,
      mimeType: mimeType,
      fileName: fileName,
      referenceDateMs: referenceDate?.millisecondsSinceEpoch,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
      alreadyCompressed: alreadyCompressed,
    );
    await SyncEngine.enqueue(
      SyncTask(
        id:
            'finance_comp_state_${docRef.path.hashCode}_${DateTime.now().microsecondsSinceEpoch}',
        module: OfflineModules.financeiro,
        tenantId: tid,
        operation: OfflineWriteOperations.update,
        payload: {
          'path': docRef.path,
          'data': OfflinePayloadCodec.encodeMap({
            FinanceComprovantePublishService.comprovanteUploadStateField:
                EntityPublishStatus.uploading,
            'hasComprovante': false,
          }),
        },
      ),
    );
    if (kDebugMode) {
      debugPrint(
        'EcoFireResilientPublish: comprovante financeiro enfileirado ${docRef.id}',
      );
    }
  }

  /// Foto perfil membro — cache + outbox + Firestore local.
  static Future<void> queueMemberPhotoPublish({
    required String churchId,
    required String memberDocId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Map<String, dynamic> memberData,
    required Uint8List rawBytes,
  }) async {
    final tid = churchId.trim();
    final mid = memberDocId.trim();
    await MuralPostPendingMediaCache.put(
      tenantId: tid,
      postId: 'membro_$mid',
      images: [rawBytes],
    );
    await ModuleMediaOutboxService.registerMemberPhoto(
      tenantId: tid,
      memberDocId: mid,
      memberData: memberData,
    );
    final local = Map<String, dynamic>.from(memberData);
    local['photoUploadState'] = EntityPublishStatus.uploading;
    local['publishState'] = 'pending_sync';
    local['ativo'] = true;
    await TenantOfflineWrite.setDocument(
      ref: docRef,
      data: local,
      merge: true,
      module: 'membros',
      tenantId: tid,
    );
    if (kDebugMode) {
      debugPrint('EcoFireResilientPublish: foto membro enfileirada $mid');
    }
  }

  /// UI — tratar erro recuperável como sucesso local (fecha editor sem SnackBar).
  static bool treatAsSilentSuccess(Object error) => shouldQueueSilently(error);

  static Future<void> queueStorageFile({
    required String storagePath,
    required String localFilePath,
    required String contentType,
  }) async {
    await StorageUploadPersistenceService.enqueueFileJob(
      storagePath: storagePath,
      localFilePath: localFilePath,
      contentType: contentType,
    );
  }

  /// Executa [action]; falha recuperável → [onQueue] + devolve [optimisticResult].
  static Future<T> runOrQueue<T>({
    required String logLabel,
    required Future<T> Function() action,
    required Future<void> Function() onQueue,
    required T optimisticResult,
  }) async {
    try {
      await prepareForPublish(logLabel: logLabel);
      if (!AppConnectivityService.instance.isOnline) {
        await onQueue();
        scheduleSync(reason: '${logLabel}_offline');
        return optimisticResult;
      }
      return await action();
    } catch (e) {
      if (!shouldQueueSilently(e)) rethrow;
      try {
        await onQueue();
      } catch (qe, st) {
        if (kDebugMode) debugPrint('EcoFireResilientPublish.onQueue: $qe\n$st');
      }
      scheduleSync(reason: '${logLabel}_queued');
      return optimisticResult;
    }
  }

  /// Refresh token silencioso antes do drain (BackgroundUploadWorker).
  static Future<void> refreshSessionForDrain() async {
    if (!AppConnectivityService.instance.isOnline) return;
    try {
      if (!FirebaseBootstrapService.isReady()) {
        await FirebaseBootstrapService.ensureInitializedOnce();
      }
      await FirebaseAuthTokenGuard.refreshIfStale();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) return;
    } catch (_) {}
    try {
      await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: true);
    } catch (_) {}
  }
}

/// Sinaliza à UI que o conteúdo foi aceite localmente e sync segue em background.
final class ResilientPublishQueuedException implements Exception {
  ResilientPublishQueuedException([this.detail = 'queued']);

  final String detail;

  @override
  String toString() => 'ResilientPublishQueuedException($detail)';
}
