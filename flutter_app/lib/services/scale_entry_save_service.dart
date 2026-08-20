import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:gestao_yahweh/utils/connectivity_offline.dart';
import 'package:gestao_yahweh/utils/firestore_user_doc_id.dart';
import 'package:gestao_yahweh/utils/module_write_guard.dart';
import 'scales_entries_hub.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Item para gravação em lote na coleção `scales`.
class ScaleEntryWriteItem {
  const ScaleEntryWriteItem({
    required this.ref,
    required this.data,
    this.isUpdate = false,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  final bool isUpdate;
}

class ScaleEntrySaveResult {
  const ScaleEntrySaveResult({required this.docIds});

  final List<String> docIds;
}

/// Persistência offline-first de lançamentos em Escalas (paridade com Financeiro).
class ScaleEntrySaveService {
  ScaleEntrySaveService._();

  static const Duration _kLocalWait = Duration(milliseconds: 2200);

  static CollectionReference<Map<String, dynamic>> scalesCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(uid))
          .collection('scales');

  static Future<bool> isOffline() async {
    try {
      return isConnectivityOffline(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  static String offlineSuffix(bool offline) => offline
      ? ' Guardado no aparelho; sincroniza quando houver internet.'
      : '';

  /// Aceita na fila local do Firestore e retorna — não espera o servidor.
  static Future<ScaleEntrySaveResult> commitBatch({
    required List<ScaleEntryWriteItem> items,
    Duration localWait = _kLocalWait,
    String? notifyUid,
    DateTime? notifyMonth,
  }) async {
    if (items.isEmpty) return const ScaleEntrySaveResult(docIds: []);
    if (notifyUid != null && notifyUid.isNotEmpty) {
      await ModuleWriteGuard.ensureReady(notifyUid);
    }

    final ids = <String>[];
    const batchLimit = 450;

    for (var i = 0; i < items.length; i += batchLimit) {
      final slice = items.skip(i).take(batchLimit).toList();
      for (final item in slice) {
        ids.add(item.ref.id);
      }
      await _commitOrEnqueuePerDoc(slice, localWait);
    }

    if (notifyUid != null && notifyUid.isNotEmpty) {
      ScalesEntriesHub.notifyMutated(uid: notifyUid, month: notifyMonth);
    }

    return ScaleEntrySaveResult(docIds: ids);
  }

  static Future<void> _commitOrEnqueuePerDoc(
    List<ScaleEntryWriteItem> slice,
    Duration localWait,
  ) async {
    final batch = YahwehBatch();
    for (final item in slice) {
      if (item.isUpdate) {
        batch.update(item.ref, item.data);
      } else {
        batch.set(item.ref, item.data);
      }
    }
    try {
      await batch.commit().timeout(localWait);
      return;
    } on TimeoutException {
      // Fila local — continua gravação assíncrona.
    } catch (_) {}

    for (final item in slice) {
      try {
        final op = item.isUpdate
            ? YahwehDocWrite.update(item.ref, item.data)
            : YahwehDocWrite.set(item.ref, item.data, merge: false);
        await op.timeout(localWait);
      } on TimeoutException {
        unawaited(
          item.isUpdate ? YahwehDocWrite.update(item.ref, item.data) : YahwehDocWrite.set(item.ref, item.data, merge: false),
        );
      } catch (_) {
        unawaited(
          item.isUpdate ? YahwehDocWrite.update(item.ref, item.data) : YahwehDocWrite.set(item.ref, item.data, merge: false),
        );
      }
    }
  }

  /// Grava um único doc (criação) — retorna a referência com ID estável.
  static Future<DocumentReference<Map<String, dynamic>>> setNewEntry({
    required String uid,
    required Map<String, dynamic> data,
    Duration localWait = _kLocalWait,
    DateTime? notifyMonth,
    DocumentReference<Map<String, dynamic>>? ref,
  }) async {
    final userDocId = await ModuleWriteGuard.ensureReady(uid);
    if (userDocId.isEmpty) {
      throw StateError(ModuleWriteGuard.kSessionNotReadyMessage);
    }
    final docRef = ref ?? scalesCol(userDocId).doc();
    final payload = Map<String, dynamic>.from(data)
      ..putIfAbsent('createdAt', () => YahwehFv.serverTimestamp)
      ..['updatedAt'] = YahwehFv.serverTimestamp;
    await _commitOrEnqueuePerDoc(
      [ScaleEntryWriteItem(ref: docRef, data: payload)],
      localWait,
    );
    ScalesEntriesHub.notifyMutated(uid: userDocId, month: notifyMonth);
    return docRef;
  }
}
