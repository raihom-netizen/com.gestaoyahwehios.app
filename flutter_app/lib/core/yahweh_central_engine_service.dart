import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/background_upload_worker.dart';
import 'package:gestao_yahweh/core/church_panel_modules_removed.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/yahweh_data_engine_fetcher.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';

/// Módulos do Gestão YAHWEH — **uma** porta de entrada para persistência offline-first.
enum YahwehCentralModule {
  financeiro('financeiro'),
  membros('membros'),
  transferencias('transferencias'),
  patrimonio('patrimonio'),
  avisos('avisos'),
  eventos('eventos'),
  pedidosOracao('pedidos_oracao'),
  aprovacoes('aprovacoes'),
  escalas('escalas'),
  certificados('certificados'),
  fornecedores('fornecedores'),
  chat('chats');

  const YahwehCentralModule(this.collectionSegment);
  final String collectionSegment;
}

/// Engine central **canónica** — roteia para serviços existentes (não duplica upload/Firestore).
///
/// **Proibido** neste ficheiro:
/// - `FirebaseFirestore.instance` / `FirebaseStorage.instance` directos
/// - Gravar `downloadURL` / caminhos locais no Firestore antes do Storage confirmar
/// - `syncStatus` + `localMediaPaths` genéricos (usar outboxes existentes)
///
/// **Pipeline mídia (online):** compressão → Storage (`igrejas/{churchId}/…`) → Firestore → UI
/// **Offline:** [TenantOfflineWrite] + [EcoFireResilientPublish] + [BackgroundUploadWorker]
abstract final class YahwehCentralEngineService {
  YahwehCentralEngineService._();

  /// Erros de rede/offline tratados como sucesso local (UI não bloqueia).
  static bool isOfflineQueuedSuccess(Object error) =>
      EcoFireResilientPublish.treatAsSilentSuccess(error);

  /// Módulo Avisos removido — publicação bloqueada.
  static Future<String> executeInstantSaveAviso({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    throw const ChurchPanelModuleRemovedException('Avisos');
  }

  /// Comprovante enfileirado (lançamento já gravado; preview via [MuralPostPendingMediaCache]).
  static Future<void> queueFinanceComprovante({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
  }) async {
    await EcoFireResilientPublish.queueFinanceComprovante(
      churchId: churchId,
      docRef: docRef,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      referenceDate: referenceDate,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
    );
    scheduleBackgroundSync(reason: 'finance_comprovante');
  }

  /// Alias — preferir [scheduleBackgroundSync].
  static void ensureBackgroundSync({String reason = 'central_engine'}) =>
      scheduleBackgroundSync(reason: reason);

  /// Arranque idempotente — filas Storage + outboxes (chamar no login/resume se necessário).
  static void scheduleBackgroundSync({String reason = 'central_engine'}) {
    YahwehMediaUploadPipeline.bindOnAppStart();
    BackgroundUploadWorker.scheduleDrain(reason: reason);
  }

  /// Compressão imagem padrão painel (1080 JPEG ~75%) — delega [YahwehMediaUploadPipeline].
  static Future<Uint8List> compressImageForModule({
    required YahwehCentralModule module,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) =>
      YahwehMediaUploadPipeline.compressImageBytes(
        module: _uploadModule(module),
        bytes: bytes,
        contentType: contentType,
      );

  static YahwehUploadModule _uploadModule(YahwehCentralModule m) => switch (m) {
        YahwehCentralModule.avisos => YahwehUploadModule.aviso,
        YahwehCentralModule.eventos => YahwehUploadModule.evento,
        YahwehCentralModule.chat => YahwehUploadModule.chat,
        _ => YahwehUploadModule.generic,
      };

  static DocumentReference<Map<String, dynamic>> docRef({
    required YahwehCentralModule module,
    required String churchId,
    required String docId,
  }) {
    final cid = ChurchRepository.churchId(churchId);
    return switch (module) {
      YahwehCentralModule.membros => ChurchUiCollections.membros(cid).doc(docId),
      YahwehCentralModule.financeiro =>
        ChurchUiCollections.financeiro(cid).doc(docId),
      YahwehCentralModule.patrimonio =>
        ChurchUiCollections.patrimonio(cid).doc(docId),
      YahwehCentralModule.avisos => ChurchUiCollections.avisos(cid).doc(docId),
      YahwehCentralModule.eventos => ChurchUiCollections.eventos(cid).doc(docId),
      YahwehCentralModule.pedidosOracao =>
        ChurchUiCollections.pedidosOracao(cid).doc(docId),
      YahwehCentralModule.certificados =>
        ChurchUiCollections.certificados(cid).doc(docId),
      YahwehCentralModule.transferencias =>
        ChurchUiCollections.transferencias(cid).doc(docId),
      YahwehCentralModule.fornecedores =>
        ChurchUiCollections.fornecedores(cid).doc(docId),
      YahwehCentralModule.escalas => ChurchUiCollections.escalas(cid).doc(docId),
      YahwehCentralModule.aprovacoes =>
        ChurchUiCollections.ref('aprovacoes', churchIdHint: cid).doc(docId),
      YahwehCentralModule.chat => ChurchUiCollections.chats(cid).doc(docId),
    };
  }

  /// Texto / metadados **sem mídia** — Firestore offline-first + fila Hive se sem rede.
  static Future<void> persistTextOnly({
    required YahwehCentralModule module,
    required String churchId,
    required String docId,
    required Map<String, dynamic> fields,
    bool merge = true,
  }) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) {
      throw StateError('churchId vazio — use ChurchRepository.churchId.');
    }
    final data = Map<String, dynamic>.from(fields);
    data.remove('localMediaPaths');
    data.remove('syncStatus');
    data['updatedAt'] = FieldValue.serverTimestamp();

    await TenantOfflineWrite.setDocument(
      ref: docRef(module: module, churchId: cid, docId: docId),
      data: data,
      merge: merge,
      module: OfflineModules.forCollection(module.collectionSegment),
      tenantId: cid,
    );
    EcoFireResilientPublish.scheduleSync(
      reason: 'central_text_${module.collectionSegment}',
    );
  }

  /// Leitura cache-first — delega [YahwehDataEngineFetcher] (nunca tenant fixo).
  static Future<List<Map<String, dynamic>>> readModuleCacheFirst({
    required YahwehCentralModule module,
    required String churchIdHint,
    int limit = 20,
  }) =>
      YahwehDataEngineFetcher.readModuleCacheFirst(
        collectionName: module.collectionSegment,
        churchIdHint: churchIdHint,
        limitCount: limit,
      );

  /// Guia para o Cursor — serviço strict/outbox por módulo (não reinventar upload).
  static String moduleGuide(YahwehCentralModule module) => switch (module) {
        YahwehCentralModule.membros =>
          '${YahwehDataEngineFetcher.readGuide(module)} '
          'Foto: executeSingleProfileSave → MemberProfilePhotoSaveService (path fixo foto_perfil.jpg + v=cb revision). '
          'Offline: EcoFireResilientPublish.queueMemberPhotoPublish.',
        YahwehCentralModule.financeiro =>
          'Comprovante: FinanceComprovantePublishService (PDF/imagem sem recompressão PDF). '
          'Offline: EcoFireResilientPublish.queueFinanceComprovante + ModuleMediaOutboxService.',
        YahwehCentralModule.patrimonio =>
          'PatrimonioStrictPublishService + ModuleMediaOutboxService.registerPatrimonio.',
        YahwehCentralModule.avisos =>
          'AvisoStrictPublishService / AvisoPublishService + MuralPublishOutboxService. '
          'UI: EcofirePublishProgressUi.runInBackgroundNonBlocking.',
        YahwehCentralModule.eventos =>
          'EventoStrictPublishService + MuralPublishOutboxService. Vídeo ≤90s video/mp4.',
        YahwehCentralModule.chat =>
          'ChurchChatMediaSendService: Storage → URL https → Firestore (mediaUrl + storagePath).',
        YahwehCentralModule.certificados ||
        YahwehCentralModule.transferencias =>
          'PDF/binário directo — StorageService + path canónico certificados/ ou transferencias/. '
          'Ver extended_publish_verification_services.',
        YahwehCentralModule.pedidosOracao ||
        YahwehCentralModule.aprovacoes ||
        YahwehCentralModule.escalas ||
        YahwehCentralModule.fornecedores =>
          'Sem mídia obrigatória: YahwehCentralEngineService.persistTextOnly. '
          'Com anexo pontual: YahwehMediaUploadPipeline + TenantOfflineWrite.',
      };

  /// Foto de perfil única — sobrescreve `igrejas/{id}/membros/{folder}/foto_perfil.jpg`
  /// e grava URL com `v=cb{revision}` + [fotoUrlCacheRevision] no Firestore.
  static Future<MemberProfilePhotoUpdateResult> executeSingleProfileSave({
    required String collectionId,
    required String docId,
    required String igrejaId,
    required Map<String, dynamic> payloadFields,
    required Uint8List photoBytes,
    Map<String, dynamic>? memberDataHint,
    void Function(String phaseLabel)? onPhase,
    bool scheduleBackground = false,
  }) async {
    if (collectionId.trim() != 'membros') {
      throw UnsupportedError(
        'executeSingleProfileSave: collectionId deve ser «membros». '
        'Logo: executeSingleLogoSave(...).',
      );
    }
    final cid = ChurchRepository.churchId(igrejaId);
    final md = Map<String, dynamic>.from(memberDataHint ?? payloadFields);
    final textOnly = Map<String, dynamic>.from(payloadFields)
      ..removeWhere(
        (k, _) => k.startsWith('foto') || k.startsWith('photo') || k == 'avatarUrl',
      );
    if (textOnly.isNotEmpty) {
      await persistTextOnly(
        module: YahwehCentralModule.membros,
        churchId: cid,
        docId: docId,
        fields: textOnly,
      );
    }
    final gateOk = await YahwehModuleMediaGate.prepareForPublishUpload(
      module: YahwehMediaModule.membros,
      logLabel: 'membro_foto',
    );
    if (!gateOk) {
      throw StateError('Firebase indisponível para enviar foto do membro.');
    }
    if (scheduleBackground) {
      MemberProfilePhotoUpdateService.scheduleBackgroundPhotoUpload(
        tenantId: cid,
        memberDocId: docId,
        memberData: md,
        rawBytes: photoBytes,
      );
      final rev = YahwehMediaCacheBust.freshRevisionMs();
      scheduleBackgroundSync(reason: 'membro_foto_bg');
      return MemberProfilePhotoUpdateResult(
        downloadUrl: '',
        storagePath: ChurchStorageLayout.memberProfilePhotoPath(cid, docId),
        cacheRevision: rev,
      );
    }
    final result = await MemberProfilePhotoUpdateService.uploadAndPatchMember(
      tenantId: cid,
      memberDocId: docId,
      memberData: md,
      rawBytes: photoBytes,
      onPhase: onPhase,
    );
    scheduleBackgroundSync(reason: 'membro_foto');
    return result;
  }

  /// Logo única — sobrescreve `igrejas/{id}/configuracoes/logo_igreja.png` (sem duplicar ficheiros).
  static Future<String> executeSingleLogoSave({
    required String igrejaId,
    required Uint8List logoPngBytes,
    void Function(double progress)? onProgress,
  }) async {
    final cid = ChurchRepository.churchId(igrejaId);
    if (cid.isEmpty) {
      throw StateError('churchId vazio — use ChurchRepository.churchId.');
    }
    final ok = await YahwehModuleMediaGate.prepareForPublishUpload(
      module: YahwehMediaModule.cadastro,
      logLabel: 'logo_igreja',
    );
    if (!ok) {
      throw StateError('Firebase indisponível para enviar logo da igreja.');
    }
    final path = ChurchStorageLayout.churchIdentityLogoPath(cid);
    final upload = await MediaUploadService.uploadBytesDetailed(
      storagePath: path,
      bytes: logoPngBytes,
      contentType: 'image/png',
      onProgress: onProgress,
    );
    await ChurchBrandService.persistLogoPath(
      churchId: cid,
      storagePath: upload.storagePath,
      downloadUrl: upload.downloadUrl,
      cacheRevision: YahwehMediaCacheBust.freshRevisionMs(),
    );
    scheduleBackgroundSync(reason: 'logo_igreja');
    return upload.storagePath;
  }
}
