/// Escrita em lote que funciona nas DUAS plataformas.
///
/// ⭐ MOTIVO: no Web o `WriteBatch` do SDK cai na INTERNAL ASSERTION do SDK JS
/// 12.x e a gravação falha (foi o que partiu «vincular membros» em
/// Departamentos). O `FirestoreWebGuard.runWithWebRecovery` NÃO cura isso — só
/// repete a operação, e o Departamentos já o usava quando falhou. O caminho que
/// cura é o REST `:commit`, que não passa pelo watch stream.
///
/// - **Web:** converte tudo para [RestWrite] e envia por `firestoreRestCommit`
///   (atómico, com transforms reais do servidor).
/// - **Mobile/desktop:** usa o `WriteBatch` nativo, como sempre.
///
/// ## Porquê [YahwehFv] em vez de `FieldValue`
/// No Web o `FieldValue` do SDK é um objeto JS **opaco**: não há como ler se é
/// `arrayUnion`, `increment` ou `serverTimestamp` para montar o payload REST.
/// Por isso os lotes usam [YahwehFv], que é inspecionável e que se converte em
/// `FieldValue` quando corre no nativo.
///
/// ```dart
/// final b = YahwehBatch();
/// b.set(docRef, {'nome': 'Ana', 'updatedAt': YahwehFv.serverTimestamp});
/// b.update(deptRef, {'total': YahwehFv.increment(1)});
/// b.deleteDoc(oldRef);
/// await b.commit();
/// ```
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/utils/firestore_rest_read.dart'
    show firestoreRestCommit, RestWrite;

enum YahwehFvType {
  serverTimestamp,
  deleteField,
  increment,
  arrayUnion,
  arrayRemove,
}

/// Sentinela de transform — equivalente ao `FieldValue`, mas legível no Web.
class YahwehFv {
  const YahwehFv._(this.type, this.value);

  final YahwehFvType type;
  final dynamic value;

  /// Hora do servidor (`FieldValue.serverTimestamp()`).
  static const YahwehFv serverTimestamp = YahwehFv._(
    YahwehFvType.serverTimestamp,
    null,
  );

  /// Remove o campo (`FieldValue.delete()`).
  static const YahwehFv deleteField = YahwehFv._(
    YahwehFvType.deleteField,
    null,
  );

  /// Soma/subtrai (`FieldValue.increment`).
  static YahwehFv increment(num v) => YahwehFv._(YahwehFvType.increment, v);

  /// Acrescenta ao array sem duplicar (`FieldValue.arrayUnion`).
  static YahwehFv arrayUnion(List<dynamic> v) =>
      YahwehFv._(YahwehFvType.arrayUnion, List<dynamic>.from(v));

  /// Remove do array (`FieldValue.arrayRemove`).
  static YahwehFv arrayRemove(List<dynamic> v) =>
      YahwehFv._(YahwehFvType.arrayRemove, List<dynamic>.from(v));

  /// Equivalente nativo, usado fora do Web.
  FieldValue toSdk() {
    switch (type) {
      case YahwehFvType.serverTimestamp:
        return FieldValue.serverTimestamp();
      case YahwehFvType.deleteField:
        return FieldValue.delete();
      case YahwehFvType.increment:
        return FieldValue.increment(value as num);
      case YahwehFvType.arrayUnion:
        return FieldValue.arrayUnion(value as List<dynamic>);
      case YahwehFvType.arrayRemove:
        return FieldValue.arrayRemove(value as List<dynamic>);
    }
  }
}

class _Op {
  _Op.write(this.ref, this.data, {required this.merge}) : isDelete = false;
  _Op.delete(this.ref) : data = const {}, merge = true, isDelete = true;

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  final bool merge;
  final bool isDelete;
}

class YahwehBatch {
  final List<_Op> _ops = [];

  /// Limite do Firestore por lote (vale para o batch nativo e para o `:commit`).
  static const int maxWritesPerCommit = 400;

  bool get isEmpty => _ops.isEmpty;
  int get length => _ops.length;

  /// Grava/mescla o documento.
  void set(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data, {
    bool merge = true,
  }) => _ops.add(_Op.write(ref, data, merge: merge));

  /// Atualiza campos existentes (equivale a `set(..., merge: true)` aqui).
  void update(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) => _ops.add(_Op.write(ref, data, merge: true));

  /// Apaga o documento.
  void deleteDoc(DocumentReference<Map<String, dynamic>> ref) =>
      _ops.add(_Op.delete(ref));

  /// Converte um op para o formato REST, separando os transforms.
  static RestWrite _toRestWrite(_Op op) {
    if (op.isDelete) return RestWrite.delete(op.ref.path);

    final plain = <String, dynamic>{};
    final union = <String, List<dynamic>>{};
    final remove = <String, List<dynamic>>{};
    final inc = <String, num>{};
    final stamps = <String>[];
    final dels = <String>[];

    for (final e in op.data.entries) {
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
      if (v is FieldValue) {
        // Guarda-costas: `FieldValue` do SDK é opaco no Web e seria gravado
        // como lixo. Melhor falhar alto do que corromper dados em silêncio.
        throw StateError(
          'YahwehBatch: use YahwehFv em vez de FieldValue no campo "${e.key}" '
          '(${op.ref.path}). O FieldValue do SDK não é legível no Web.',
        );
      }
      plain[e.key] = v;
    }

    return RestWrite.update(
      op.ref.path,
      setFields: plain,
      arrayUnion: union,
      arrayRemove: remove,
      increment: inc,
      serverTimestamp: stamps,
      deleteFields: dels,
    );
  }

  /// Aplica o lote. Divide em pedaços de [maxWritesPerCommit].
  Future<void> commit() async {
    if (_ops.isEmpty) return;

    for (var i = 0; i < _ops.length; i += maxWritesPerCommit) {
      final slice = _ops.sublist(
        i,
        (i + maxWritesPerCommit).clamp(0, _ops.length),
      );

      if (kIsWeb) {
        await firestoreRestCommit(slice.map(_toRestWrite).toList());
        continue;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final op in slice) {
        if (op.isDelete) {
          batch.delete(op.ref);
          continue;
        }
        final data = <String, dynamic>{
          for (final e in op.data.entries)
            e.key: e.value is YahwehFv
                ? (e.value as YahwehFv).toSdk()
                : e.value,
        };
        batch.set(op.ref, data, SetOptions(merge: op.merge));
      }
      await batch.commit();
    }
    _ops.clear();
  }
}
