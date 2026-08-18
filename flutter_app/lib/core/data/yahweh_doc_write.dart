import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart'
    show firestoreRestCommit, firestoreRestDeleteDoc, RestWrite;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

/// Escrita de UM documento à prova do SDK web envenenado.
///
/// O Firestore JS 12.x derruba o cliente inteiro com
/// `INTERNAL ASSERTION FAILED: Unexpected state` (WatchChangeAggregator /
/// PersistentListenStream). Depois disso **qualquer** `set/update/delete` do
/// SDK falha em silêncio — e o módulo parece "não grava", "não exclui",
/// "não edita". Aqui a Web grava pelo `:commit` REST, que não passa pelo
/// watch stream; mobile/desktop seguem o SDK com recuperação.
///
/// ## Sentinelas
/// Use [YahwehFv] (`serverTimestamp`, `deleteField`, `increment`,
/// `arrayUnion`, `arrayRemove`) — são traduzidos para os *transforms* REST
/// corretos. Um `FieldValue` **cru** do SDK é opaco na Web e viraria lixo no
/// documento; nesse caso esta classe **não usa REST**: cai no SDK, que é o
/// comportamento antigo (nunca corrompe dados).
abstract final class YahwehDocWrite {
  YahwehDocWrite._();

  /// `true` se o payload tem algum `FieldValue` cru (não-[YahwehFv]).
  static bool _hasRawFieldValue(Object? v) {
    if (v is YahwehFv) return false;
    if (v is FieldValue) return true;
    if (v is Map) return v.values.any(_hasRawFieldValue);
    if (v is Iterable) return v.any(_hasRawFieldValue);
    return false;
  }

  /// Converte [YahwehFv] em `FieldValue` para o caminho SDK.
  static Map<String, dynamic> _toSdkPayload(Map<String, dynamic> data) {
    Object? conv(Object? v) {
      if (v is YahwehFv) return v.toSdk();
      if (v is Map) {
        return <String, dynamic>{
          for (final e in v.entries) e.key.toString(): conv(e.value),
        };
      }
      if (v is Iterable && v is! String) return v.map(conv).toList();
      return v;
    }

    return <String, dynamic>{
      for (final e in data.entries) e.key: conv(e.value),
    };
  }

  static RestWrite _restWrite(String path, Map<String, dynamic> data) {
    final plain = <String, dynamic>{};
    final union = <String, List<dynamic>>{};
    final remove = <String, List<dynamic>>{};
    final inc = <String, num>{};
    final stamps = <String>[];
    final dels = <String>[];

    for (final e in data.entries) {
      final v = e.value;
      if (v is YahwehFv) {
        switch (v.type) {
          case YahwehFvType.serverTimestamp:
            stamps.add(e.key);
          case YahwehFvType.deleteField:
            dels.add(e.key);
          case YahwehFvType.increment:
            inc[e.key] = v.value as num;
          case YahwehFvType.arrayUnion:
            union[e.key] = v.value as List<dynamic>;
          case YahwehFvType.arrayRemove:
            remove[e.key] = v.value as List<dynamic>;
        }
        continue;
      }
      plain[e.key] = v;
    }

    return RestWrite.update(
      path,
      setFields: plain,
      arrayUnion: union,
      arrayRemove: remove,
      increment: inc,
      serverTimestamp: stamps,
      deleteFields: dels,
    );
  }

  /// `set(..., merge: true)` por omissão — o padrão do sistema.
  static Future<void> set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    if (kIsWeb && !_hasRawFieldValue(data)) {
      try {
        await firestoreRestCommit([_restWrite(ref.path, data)]);
        return;
      } catch (_) {
        // Cai no SDK (offline / falha de rede no REST).
      }
    }
    final payload = _toSdkPayload(data);
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.set(payload, SetOptions(merge: merge)),
      maxAttempts: 3,
    );
  }

  static Future<void> update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    if (kIsWeb && !_hasRawFieldValue(data)) {
      try {
        await firestoreRestCommit([_restWrite(ref.path, data)]);
        return;
      } catch (_) {}
    }
    final payload = _toSdkPayload(data);
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.update(payload),
      maxAttempts: 3,
    );
  }

  static Future<void> delete(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    if (kIsWeb) {
      try {
        await firestoreRestDeleteDoc(ref.path);
        return;
      } catch (_) {}
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.delete(),
      maxAttempts: 3,
    );
  }

  /// `collection.add(...)` — id gerado no cliente e gravação pelo caminho seguro.
  static Future<DocumentReference<Map<String, dynamic>>> add(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data,
  ) async {
    final ref = col.doc();
    await set(ref, data, merge: false);
    return ref;
  }
}
