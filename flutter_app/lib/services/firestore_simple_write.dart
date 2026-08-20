import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';

/// Escritas Firestore simples (padrão Controle Total): merge + timestamps do servidor.
abstract final class FirestoreSimpleWrite {
  FirestoreSimpleWrite._();

  static Map<String, dynamic> withServerTimestamps(
    Map<String, dynamic> data, {
    bool onCreate = false,
  }) {
    final out = Map<String, dynamic>.from(data);
    out['updatedAt'] = YahwehFv.serverTimestamp;
    if (onCreate) {
      out['createdAt'] = YahwehFv.serverTimestamp;
    }
    return out;
  }

  static Future<void> setMerge(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    await ref.set(
      withServerTimestamps(data),
      SetOptions(merge: true),
    );
  }

  static Future<void> update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    await YahwehDocWrite.update(ref, withServerTimestamps(data));
  }

  static Future<void> add(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, dynamic> data,
  ) async {
    await col.add(withServerTimestamps(data, onCreate: true));
  }
}
