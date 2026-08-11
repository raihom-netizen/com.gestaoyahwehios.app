import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// Leitura Firestore via **REST puro** (`firestore.googleapis.com/v1 :runQuery`).
///
/// ⭐ MOTIVO: o SDK JS 12.17 (Web) tem um bug — cada `.get()` cria um alvo de
/// Listen temporário e, com o acúmulo, o `WatchChangeAggregator` estoura a
/// `INTERNAL ASSERTION` e **envenena o cliente** (todas as leituras passam a
/// voltar vazio/erro). Não há versão nova do `cloud_firestore` (6.8.0 é a
/// última) que corrija isso. O REST **não passa pelo watch stream** → zero
/// alvos → zero assertion, e **funciona mesmo com o cliente do SDK envenenado**.
///
/// Usado como caminho de leitura do Financeiro (contas + lançamentos) no Web.
const String _kProjectId = 'gestaoyahweh-21e23';

String get _restBase =>
    'https://firestore.googleapis.com/v1/projects/$_kProjectId/databases/(default)/documents';

/// Documento REST — compatível com o que o app já consome
/// (`doc.data()`, `doc.id`, `doc.reference`). Demais membros do
/// `QueryDocumentSnapshot` não são usados no Financeiro (roteados por
/// `noSuchMethod`).
class RestQueryDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  RestQueryDoc(this._id, this._data, this._ref);

  final String _id;
  final Map<String, dynamic> _data;
  final DocumentReference<Map<String, dynamic>> _ref;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;

  @override
  bool get exists => true;

  @override
  SnapshotMetadata get metadata => const RestSnapshotMetadata();

  @override
  dynamic get(Object field) => _data[field.toString()];

  @override
  dynamic operator [](Object field) => _data[field.toString()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Metadata neutra para snapshots REST — `isFromCache=false` (dado fresco do
/// servidor), `hasPendingWrites=false`. Evita NPE em callers que leem
/// `snapshot.metadata.isFromCache`.
class RestSnapshotMetadata implements SnapshotMetadata {
  const RestSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;
}

/// Documento único REST — compatível com `DocumentSnapshot`
/// (`.exists`, `.data()`, `.id`, `.reference`, `.get()`, `[]`). Demais membros
/// via `noSuchMethod`.
class RestDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  RestDocumentSnapshot(this._id, this._data, this._ref);

  final String _id;
  final Map<String, dynamic>? _data;
  final DocumentReference<Map<String, dynamic>> _ref;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;

  @override
  SnapshotMetadata get metadata => const RestSnapshotMetadata();

  @override
  dynamic get(Object field) => _data?[field.toString()];

  @override
  dynamic operator [](Object field) => _data?[field.toString()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Lê UM documento por REST e devolve como [DocumentSnapshot] (compatível com o
/// que os módulos consomem). `exists=false` se não existir.
Future<RestDocumentSnapshot> firestoreRestGetDocSnap(String docPath) async {
  final data = await firestoreRestGetDoc(docPath);
  final ref = FirebaseFirestore.instance.doc(docPath.trim());
  return RestDocumentSnapshot(ref.id, data, ref);
}

/// Converte um valor no formato REST do Firestore para o tipo Dart nativo
/// (Timestamp para datas — igual ao SDK).
dynamic _restValue(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'] as String?;
  if (v.containsKey('integerValue')) {
    return int.tryParse('${v['integerValue']}') ?? 0;
  }
  if (v.containsKey('doubleValue')) {
    return (v['doubleValue'] as num?)?.toDouble() ?? 0.0;
  }
  if (v.containsKey('booleanValue')) return v['booleanValue'] == true;
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('timestampValue')) {
    final dt = DateTime.tryParse('${v['timestampValue']}');
    return dt == null ? null : Timestamp.fromDate(dt);
  }
  if (v.containsKey('referenceValue')) {
    // Guarda só o path relativo (o app usa como string quando precisa).
    final full = '${v['referenceValue']}';
    final idx = full.indexOf('/documents/');
    return idx >= 0 ? full.substring(idx + '/documents/'.length) : full;
  }
  if (v.containsKey('geoPointValue')) return v['geoPointValue'];
  if (v.containsKey('mapValue')) {
    final fields =
        (v['mapValue'] as Map<String, dynamic>?)?['fields'] as Map<String, dynamic>?;
    return _restFields(fields);
  }
  if (v.containsKey('arrayValue')) {
    final values =
        (v['arrayValue'] as Map<String, dynamic>?)?['values'] as List<dynamic>?;
    if (values == null) return <dynamic>[];
    return values
        .map((e) => _restValue(e as Map<String, dynamic>))
        .toList();
  }
  return null;
}

Map<String, dynamic> _restFields(Map<String, dynamic>? fields) {
  final out = <String, dynamic>{};
  if (fields == null) return out;
  fields.forEach((k, v) {
    if (v is Map<String, dynamic>) out[k] = _restValue(v);
  });
  return out;
}

/// Filtro simples de campo (fieldFilter).
class RestFieldFilter {
  RestFieldFilter(this.field, this.op, this.value);

  /// `field == value` — converte o valor Dart para o formato REST.
  factory RestFieldFilter.equal(String field, dynamic value) =>
      RestFieldFilter(field, 'EQUAL', _toRestValue(value));

  /// `field >= value`.
  factory RestFieldFilter.greaterOrEqual(String field, dynamic value) =>
      RestFieldFilter(field, 'GREATER_THAN_OR_EQUAL', _toRestValue(value));

  /// `field <= value`.
  factory RestFieldFilter.lessOrEqual(String field, dynamic value) =>
      RestFieldFilter(field, 'LESS_THAN_OR_EQUAL', _toRestValue(value));

  final String field;
  final String op; // GREATER_THAN_OR_EQUAL, LESS_THAN_OR_EQUAL, EQUAL...
  final Map<String, dynamic> value; // já no formato REST (ex.: {timestampValue: ...})
  Map<String, dynamic> toJson() => {
        'fieldFilter': {
          'field': {'fieldPath': field},
          'op': op,
          'value': value,
        },
      };
}

Map<String, dynamic> restTimestamp(DateTime d) =>
    {'timestampValue': d.toUtc().toIso8601String()};

/// Converte um valor Dart para o formato REST do Firestore.
/// `FieldValue.serverTimestamp()` (e afins) viram timestamp do cliente (now) —
/// suficiente para createdAt/updatedAt via REST (sem transform).
Map<String, dynamic> _toRestValue(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is String) return {'stringValue': v};
  if (v is DateTime) {
    return {'timestampValue': v.toUtc().toIso8601String()};
  }
  if (v is Timestamp) {
    return {'timestampValue': v.toDate().toUtc().toIso8601String()};
  }
  if (v is FieldValue) {
    return {'timestampValue': DateTime.now().toUtc().toIso8601String()};
  }
  if (v is Map) {
    return {
      'mapValue': {
        'fields': {
          for (final e in v.entries) e.key.toString(): _toRestValue(e.value),
        },
      },
    };
  }
  if (v is Iterable) {
    return {
      'arrayValue': {'values': v.map(_toRestValue).toList()},
    };
  }
  return {'stringValue': v.toString()};
}

/// GRAVA (cria/sobrescreve) um documento por REST (`PATCH .../documents/{docPath}`).
/// PATCH sem updateMask escreve o doc inteiro (ideal para CRIAR). Não passa pelo
/// watch stream do SDK → funciona mesmo com o cliente envenenado pela assertion.
Future<void> firestoreRestSetDoc(
  String docPath,
  Map<String, dynamic> data,
) async {
  final path = docPath.trim();
  if (path.isEmpty) throw StateError('docPath vazio');
  final user = fa.FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('sem sessão');
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) throw StateError('sem token');
  final fields = <String, dynamic>{
    for (final e in data.entries) e.key: _toRestValue(e.value),
  };
  final uri = Uri.parse('$_restBase/$path');
  final resp = await http
      .patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fields': fields}),
      )
      .timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) {
    debugPrint('firestoreRestSetDoc ${resp.statusCode}: ${resp.body}');
    throw StateError('REST write ${resp.statusCode}');
  }
}

/// ATUALIZA campos de um documento por REST (`PATCH` com `updateMask`). Só toca
/// nos campos em [setFields] (grava) e [deleteFields] (remove) — os demais ficam
/// intactos. Não passa pelo watch stream do SDK.
Future<void> firestoreRestUpdateDoc(
  String docPath, {
  required Map<String, dynamic> setFields,
  List<String> deleteFields = const [],
}) async {
  final path = docPath.trim();
  if (path.isEmpty) throw StateError('docPath vazio');
  final user = fa.FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('sem sessão');
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) throw StateError('sem token');
  final maskPaths = <String>[...setFields.keys, ...deleteFields];
  final qp = maskPaths
      .map((f) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(f)}')
      .join('&');
  final uri = Uri.parse('$_restBase/$path?$qp');
  final fields = <String, dynamic>{
    for (final e in setFields.entries) e.key: _toRestValue(e.value),
  };
  final resp = await http
      .patch(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fields': fields}),
      )
      .timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200) {
    debugPrint('firestoreRestUpdateDoc ${resp.statusCode}: ${resp.body}');
    throw StateError('REST update ${resp.statusCode}');
  }
}

/// Lê UM documento por REST (`GET .../documents/{docPath}`). Retorna os campos
/// já convertidos, ou `null` se não existir. Não passa pelo watch stream do SDK
/// (não trava/assertion com o cliente envenenado).
Future<Map<String, dynamic>?> firestoreRestGetDoc(String docPath) async {
  final path = docPath.trim();
  if (path.isEmpty) return null;
  final user = fa.FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) return null;
  final uri = Uri.parse('$_restBase/$path');
  final resp = await http.get(
    uri,
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 12));
  if (resp.statusCode == 404) return null;
  if (resp.statusCode != 200) {
    debugPrint('firestoreRestGetDoc ${resp.statusCode}: ${resp.body}');
    throw StateError('REST ${resp.statusCode}');
  }
  final decoded = jsonDecode(resp.body);
  if (decoded is! Map<String, dynamic>) return null;
  return _restFields(decoded['fields'] as Map<String, dynamic>?);
}

/// EXCLUI um documento por REST (`DELETE .../documents/{docPath}`). Não passa
/// pelo watch stream do SDK (não trava/assertion com o cliente envenenado).
Future<void> firestoreRestDeleteDoc(String docPath) async {
  final path = docPath.trim();
  if (path.isEmpty) throw StateError('docPath vazio');
  final user = fa.FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('sem sessão');
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) throw StateError('sem token');
  final uri = Uri.parse('$_restBase/$path');
  final resp = await http.delete(
    uri,
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 20));
  if (resp.statusCode != 200 && resp.statusCode != 404) {
    debugPrint('firestoreRestDeleteDoc ${resp.statusCode}: ${resp.body}');
    throw StateError('REST delete ${resp.statusCode}');
  }
}

/// Executa um `runQuery` REST numa subcoleção e devolve os documentos.
///
/// [collectionPath] = caminho completo até a coleção (ex.:
/// `igrejas/{churchId}/financeiro`). O parent do runQuery é tudo menos o último
/// segmento; `collectionId` é o último.
Future<List<RestQueryDoc>> firestoreRestCollect({
  required String collectionPath,
  List<RestFieldFilter> filters = const [],
  String? orderByField,
  bool descending = false,
  int? limit,
}) async {
  final path = collectionPath.trim();
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return const [];
  final collectionId = segments.removeLast();
  final parentRel = segments.join('/');

  final user = fa.FirebaseAuth.instance.currentUser;
  if (user == null) return const [];
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) return const [];

  final structuredQuery = <String, dynamic>{
    'from': [
      {'collectionId': collectionId},
    ],
  };
  if (filters.length == 1) {
    structuredQuery['where'] = filters.first.toJson();
  } else if (filters.length > 1) {
    structuredQuery['where'] = {
      'compositeFilter': {
        'op': 'AND',
        'filters': filters.map((f) => f.toJson()).toList(),
      },
    };
  }
  if (orderByField != null && orderByField.isNotEmpty) {
    structuredQuery['orderBy'] = [
      {
        'field': {'fieldPath': orderByField},
        'direction': descending ? 'DESCENDING' : 'ASCENDING',
      },
    ];
  }
  if (limit != null && limit > 0) structuredQuery['limit'] = limit;

  final uri = Uri.parse(
    '$_restBase${parentRel.isEmpty ? '' : '/$parentRel'}:runQuery',
  );
  final resp = await http
      .post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'structuredQuery': structuredQuery}),
      )
      .timeout(const Duration(seconds: 20));

  if (resp.statusCode != 200) {
    debugPrint('firestoreRestCollect ${resp.statusCode}: ${resp.body}');
    throw StateError('REST ${resp.statusCode}');
  }

  final decoded = jsonDecode(resp.body);
  if (decoded is! List) return const [];
  final db = FirebaseFirestore.instance;
  final out = <RestQueryDoc>[];
  for (final row in decoded) {
    if (row is! Map<String, dynamic>) continue;
    final doc = row['document'];
    if (doc is! Map<String, dynamic>) continue; // linhas de "readTime" sem doc
    final name = '${doc['name'] ?? ''}';
    final id = name.isEmpty ? '' : name.split('/').last;
    if (id.isEmpty) continue;
    final data = _restFields(doc['fields'] as Map<String, dynamic>?);
    final ref = db.doc('$collectionPath/$id');
    out.add(RestQueryDoc(id, data, ref));
  }
  return out;
}
