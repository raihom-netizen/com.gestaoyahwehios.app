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
  dynamic get(Object field) => _data[field.toString()];

  @override
  dynamic operator [](Object field) => _data[field.toString()];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
