import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/church_tenant_write_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/church_chat_firestore_map.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/tenant_offline_write.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';

/// Serviço **único** de gravação Firestore + Storage por igreja (`igrejas/{churchId}/…`).
///
/// Fluxo canónico (avisos, eventos, chat com mídia):
/// 1. Gravar documento no Firestore (stub ou dados finais)
/// 2. UI mostra sucesso / mensagem na thread
/// 3. Upload Storage em background
/// 4. `update` com URL(s) e estado `sent` / `published`
///
/// Aliases da spec do cliente:
/// - `eventos` → Firestore `noticias` (Storage continua `eventos/`)
/// - `chats` → coleção canónica `chats` (mensagens em `messages`)
final class ChurchDataService {
  ChurchDataService._();

  static final ChurchDataService instance = ChurchDataService._();

  FirebaseFirestore get firestore => firebaseDefaultFirestore;
  FirebaseStorage get storage => firebaseDefaultStorage;

  /// Coleção Firestore sob `igrejas/{id}/` (resolve aliases).
  static String resolveFirestoreCollection(String collection) {
    final c = collection.trim().toLowerCase();
    switch (c) {
      case 'eventos':
      case 'evento':
      case 'noticias':
      case 'noticia':
        return ChurchTenantPostsCollections.eventos;
      case 'chats':
      case 'chat':
      case 'chat_threads':
      case 'thread':
        return ChurchChatFirestoreMap.conversationsCollection;
      case 'avisos':
      case 'aviso':
        return ChurchTenantPostsCollections.avisos;
      default:
        return collection.trim();
    }
  }

  static CollectionReference<Map<String, dynamic>> tenantCollection(
    String churchId,
    String collection,
  ) {
    return firebaseDefaultFirestore
        .collection('igrejas')
        .doc(churchId.trim())
        .collection(resolveFirestoreCollection(collection));
  }

  static DocumentReference<Map<String, dynamic>> tenantDocument(
    String churchId,
    String collection,
    String documentId,
  ) =>
      tenantCollection(churchId, collection).doc(documentId.trim());

  static CollectionReference<Map<String, dynamic>> chatMessagesCol(
    String churchId,
    String chatId,
  ) =>
      tenantCollection(churchId, 'chats')
          .doc(chatId.trim())
          .collection(ChurchChatFirestoreMap.messagesSubcollection);

  static String _tenantIdFromRefPath(String path) =>
      OfflineModules.tenantIdFromPath(path);

  static String _moduleFromRefPath(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) return OfflineModules.forCollection(parts[2]);
    return OfflineModules.tenant;
  }

  static void _logError(String tag, Object e, StackTrace s) {
    debugPrint(tag);
    debugPrint('$e');
    debugPrint('$s');
  }

  Future<void> ensureReadyForWrite() async {
    await ensureFirebaseCore(requireAuth: true);
  }

  /// Novo documento com ID automático (spec Controle Total).
  Future<String> createDocument({
    required String churchId,
    required String collection,
    required Map<String, dynamic> data,
    String? module,
  }) async {
    await ensureReadyForWrite();
    final ref = tenantCollection(churchId, collection).doc();
    final payload = FirestoreWriteGuard.stripHeavyFields(
      <String, dynamic>{
        ...data,
        'id': ref.id,
        'churchId': churchId.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    final path = ref.path;
    final mod = module ?? OfflineModules.forCollection(collection);
    ChurchTenantWriteLog.firestoreSetStart(path, module: mod);
    try {
      await TenantOfflineWrite.setDocument(
        ref: ref,
        data: payload,
        module: mod,
        tenantId: churchId,
      );
      ChurchTenantWriteLog.firestoreSetOk(path, module: mod);
      return ref.id;
    } catch (e, s) {
      ChurchTenantWriteLog.firestoreSetFail(path, e, stack: s, module: mod);
      _logError('CREATE DOCUMENT ERROR', e, s);
      rethrow;
    }
  }

  /// Grava numa referência já alocada (mural / chat com id fixo).
  Future<void> setTenantDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    bool merge = false,
    String? module,
  }) async {
    await ensureReadyForWrite();
    final payload = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(data),
    );
    final path = ref.path;
    final mod = module ?? _moduleFromRefPath(path);
    final tid = _tenantIdFromRefPath(path);
    ChurchTenantWriteLog.firestoreSetStart(path, module: mod);
    try {
      await TenantOfflineWrite.setDocument(
        ref: ref,
        data: payload,
        merge: merge,
        module: mod,
        tenantId: tid,
      );
      ChurchTenantWriteLog.firestoreSetOk(path, module: mod);
    } catch (e, s) {
      ChurchTenantWriteLog.firestoreSetFail(path, e, stack: s, module: mod);
      _logError('SET DOCUMENT ERROR', e, s);
      rethrow;
    }
  }

  Future<void> updateTenantDocument({
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> data,
    String? module,
  }) async {
    await ensureReadyForWrite();
    final payload = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(data),
    );
    payload['updatedAt'] = FieldValue.serverTimestamp();
    final path = ref.path;
    final mod = module ?? _moduleFromRefPath(path);
    final tid = _tenantIdFromRefPath(path);
    ChurchTenantWriteLog.firestoreUpdateStart(path, module: mod);
    try {
      await TenantOfflineWrite.updateDocument(
        ref: ref,
        data: payload,
        module: mod,
        tenantId: tid,
      );
      ChurchTenantWriteLog.firestoreUpdateOk(path, module: mod);
    } catch (e, s) {
      ChurchTenantWriteLog.firestoreUpdateFail(path, e, stack: s, module: mod);
      _logError('UPDATE DOCUMENT ERROR', e, s);
      rethrow;
    }
  }

  /// Atualiza URL de ficheiro (campo genérico + aliases do mural).
  Future<void> updateFileUrl({
    required String churchId,
    required String collection,
    required String documentId,
    required String fileUrl,
    String? module,
  }) async {
    final ref = tenantDocument(churchId, collection, documentId);
    await updateTenantDocument(
      ref: ref,
      data: <String, dynamic>{
        'fileUrl': fileUrl,
        'imageUrl': fileUrl,
        'imagemUrl': fileUrl,
        'defaultImageUrl': fileUrl,
      },
      module: module ?? collection,
    );
  }

  /// Upload genérico por bytes (web + mobile).
  Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    String? contentType,
    String? module,
    void Function(double progress)? onProgress,
  }) async {
    await ensureReadyForWrite();
    if (!kIsWeb) {
      try {
        await FastMediaPublishBootstrap.warmForFeedPublish()
            .timeout(const Duration(seconds: 20));
      } catch (e, s) {
        _logError('UPLOAD WARM ERROR', e, s);
      }
    }
    final path = storagePath.trim();
    ChurchTenantWriteLog.storageUploadStart(path, module: module);
    try {
      final ref = storage.ref(path);
      final meta = SettableMetadata(
        contentType: contentType ?? 'application/octet-stream',
      );
      final task = ref.putData(bytes, meta);
      if (onProgress != null) {
        task.snapshotEvents.listen((snap) {
          final total = snap.totalBytes;
          if (total > 0) {
            onProgress(snap.bytesTransferred / total);
          }
        });
      }
      await task;
      final url = await ref.getDownloadURL();
      ChurchTenantWriteLog.storageUploadOk(path, module: module);
      return url;
    } catch (e, s) {
      ChurchTenantWriteLog.storageUploadFail(path, e, stack: s, module: module);
      _logError('UPLOAD ERROR', e, s);
      rethrow;
    }
  }

  /// Upload a partir de ficheiro local (Android/iOS).
  Future<String> uploadFile({
    required String churchId,
    required String folder,
    required String documentId,
    required File file,
    String? module,
  }) async {
    await ensureReadyForWrite();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        'igrejas/${churchId.trim()}/${folder.trim()}/${documentId.trim()}/$ts';
    ChurchTenantWriteLog.storageUploadStart(storagePath, module: module);
    try {
      final ref = storage.ref(storagePath);
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();
      ChurchTenantWriteLog.storageUploadOk(storagePath, module: module);
      return url;
    } catch (e, s) {
      ChurchTenantWriteLog.storageUploadFail(
        storagePath,
        e,
        stack: s,
        module: module,
      );
      _logError('UPLOAD ERROR', e, s);
      rethrow;
    }
  }

  /// Chat — mensagem de imagem: stub Firestore (`sending`) antes do Storage.
  Future<DocumentReference<Map<String, dynamic>>> createChatImageMessageStub({
    required String churchId,
    required String chatId,
    required String senderId,
    Map<String, dynamic>? extra,
  }) async {
    await ensureReadyForWrite();
    final msgRef = chatMessagesCol(churchId, chatId).doc();
    final data = <String, dynamic>{
      'id': msgRef.id,
      'senderUid': senderId,
      'type': 'image',
      'deliveryStatus': 'sending',
      'createdAt': FieldValue.serverTimestamp(),
      if (extra != null) ...extra,
    };
    await setTenantDocument(ref: msgRef, data: data, module: 'chat_image_stub');
    return msgRef;
  }

  Future<void> finalizeChatImageMessage({
    required DocumentReference<Map<String, dynamic>> msgRef,
    required String fileUrl,
  }) async {
    await updateTenantDocument(
      ref: msgRef,
      data: <String, dynamic>{
        'status': 'sent',
        'deliveryStatus': 'sent',
        'fileUrl': fileUrl,
        'mediaUrl': fileUrl,
      },
      module: 'chat_image',
    );
  }

  /// Chat — texto directo no Firestore (sem Cloud Function).
  Future<String> sendChatTextMessage({
    required String churchId,
    required String chatId,
    required String senderId,
    required String text,
    Map<String, dynamic>? extra,
  }) async {
    await ensureReadyForWrite();
    final col = chatMessagesCol(churchId, chatId);
    final path = '${col.path}/(auto)';
    ChurchTenantWriteLog.firestoreSetStart(path, module: 'chat_text');
    try {
      final ref = await col.add(<String, dynamic>{
        'senderId': senderId,
        'senderUid': senderId,
        'text': text,
        'type': 'text',
        'status': 'sent',
        'deliveryStatus': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
        if (extra != null) ...extra,
      });
      ChurchTenantWriteLog.firestoreSetOk(ref.path, module: 'chat_text');
      return ref.id;
    } catch (e, s) {
      ChurchTenantWriteLog.firestoreSetFail(path, e, stack: s, module: 'chat_text');
      _logError('CHAT TEXT ERROR', e, s);
      rethrow;
    }
  }

  /// Path Storage canónico para chat (usa [ChurchStorageLayout]).
  static String chatMediaStoragePath({
    required String churchId,
    required String threadId,
    required String uid,
    required String kind,
    String? fileName,
    int? timestampMs,
  }) =>
      ChurchStorageLayout.buildChatMediaObjectPath(
        tenantId: churchId,
        threadId: threadId,
        kind: kind,
        uid: uid,
        timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
        fileName: fileName ?? 'media.webp',
      );
}
