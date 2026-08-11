import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

import 'finance_line_opening.dart';
import 'firestore_query_batched_collect.dart';

/// Web: intervalo do poll leve que substitui `.snapshots()` nas funções deste
/// arquivo — evita somar alvos de watch simultâneos no Financeiro
/// (`INTERNAL ASSERTION FAILED` / `WatchChangeAggregator`, SDK JS 12.x).
const Duration _kFinanceWebPollInterval = Duration(seconds: 180);

/// Poll leve genérico: 1ª leitura imediata (cache, se houver, depois servidor
/// via [query.get]), depois a cada [_kFinanceWebPollInterval] — usado no Web
/// no lugar de `query.snapshots()`.
Stream<QuerySnapshot<Map<String, dynamic>>> _pollQuery(
  Query<Map<String, dynamic>> query,
) async* {
  while (true) {
    try {
      yield await query.get();
    } catch (_) {}
    await Future<void>.delayed(_kFinanceWebPollInterval);
  }
}

/// Limite padrão para streams de pendentes (índice `status`+`date`).
const int kFinancePendingStreamLimit = 500;

/// [uid] aqui é o `churchId` — Financeiro é por igreja, não por login pessoal.
CollectionReference<Map<String, dynamic>> _transactionsCol(String uid) =>
    ChurchUiCollections.financeiro(uid.trim());

bool _docEffectiveInPeriod(
  Map<String, dynamic> d,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final effective = FinanceLineOpening.effectiveDateTimeFromMap(d);
  if (effective == null) return false;
  return !effective.isBefore(rangeStart) && !effective.isAfter(rangeEnd);
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeTransactionSnapshots(
  Iterable<QuerySnapshot<Map<String, dynamic>>> snaps,
) {
  final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final snap in snaps) {
    for (final doc in snap.docs) {
      byId[doc.id] = doc;
    }
  }
  final out = byId.values.toList()
    ..sort((a, b) {
      final ta = FinanceLineOpening.effectiveDateTimeFromMap(a.data()) ??
          (a.data()['date'] as Timestamp?)?.toDate();
      final tb = FinanceLineOpening.effectiveDateTimeFromMap(b.data()) ??
          (b.data()['date'] as Timestamp?)?.toDate();
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
  return out;
}

Query<Map<String, dynamic>> _periodFieldQuery(
  CollectionReference<Map<String, dynamic>> col,
  String field,
  DateTime rs,
  DateTime re,
) {
  return col
      .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(rs))
      .where(field, isLessThanOrEqualTo: Timestamp.fromDate(re))
      .orderBy(field, descending: false);
}

/// Lista mesclada (date + effectiveDate + paidAt no período).
/// Emite cache imediatamente e depois atualiza com snapshots — não espera os 3 listeners.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> financeTransactionsPeriodDocs({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final fsUid = uid.trim();
  if (fsUid.isEmpty) {
    return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value(
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
    );
  }

  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  final col = _transactionsCol(uid);

  final qDate = _periodFieldQuery(col, 'date', rs, re);
  final qEffective = _periodFieldQuery(col, 'effectiveDate', rs, re);
  final qPaidAt = _periodFieldQuery(col, 'paidAt', rs, re);

  return Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.multi(
    (controller) {
      QuerySnapshot<Map<String, dynamic>>? lastA;
      QuerySnapshot<Map<String, dynamic>>? lastB;
      QuerySnapshot<Map<String, dynamic>>? lastC;
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emitIfAny() {
        if (controller.isClosed) return;
        final snaps = <QuerySnapshot<Map<String, dynamic>>>[];
        if (lastA != null) snaps.add(lastA!);
        if (lastB != null) snaps.add(lastB!);
        if (lastC != null) snaps.add(lastC!);
        if (snaps.isEmpty) return;
        controller.add(_mergeTransactionSnapshots(snaps));
      }

      Future<void> emitCacheFirst() async {
        final cached = <QuerySnapshot<Map<String, dynamic>>>[];
        for (final q in [qDate, qEffective, qPaidAt]) {
          try {
            cached.add(await q.get(const GetOptions(source: Source.cache)));
          } catch (_) {}
        }
        if (cached.isNotEmpty && !controller.isClosed) {
          controller.add(_mergeTransactionSnapshots(cached));
        }
      }

      unawaited(emitCacheFirst().then((_) {
        if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
          subs
            ..add(_pollQuery(qDate).listen((s) {
              lastA = s;
              emitIfAny();
            }, onError: (_) => emitIfAny()))
            ..add(_pollQuery(qEffective).listen((s) {
              lastB = s;
              emitIfAny();
            }, onError: (_) => emitIfAny()))
            ..add(_pollQuery(qPaidAt).listen((s) {
              lastC = s;
              emitIfAny();
            }, onError: (_) => emitIfAny()));
          return;
        }
        subs
          ..add(qDate.snapshots(includeMetadataChanges: true).listen(
            (s) {
              lastA = s;
              emitIfAny();
            },
            onError: (_) => emitIfAny(),
          ))
          ..add(qEffective.snapshots(includeMetadataChanges: true).listen(
            (s) {
              lastB = s;
              emitIfAny();
            },
            onError: (_) => emitIfAny(),
          ))
          ..add(qPaidAt.snapshots(includeMetadataChanges: true).listen(
            (s) {
              lastC = s;
              emitIfAny();
            },
            onError: (_) => emitIfAny(),
          ));
      }));

      controller.onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    },
  );
}

/// Coleta mesclada (date + effectiveDate) — evita perder lançamentos migrados do legado.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> financePeriodMergedDocumentsCollect({
  required String uid,
  required DateTime from,
  required DateTime to,
  String statusFilter = 'all',
  String typeFilter = 'all',
  String? financeAccountId,
  int pageSize = 400,
  int maxDocuments = 8000,
}) async {
  final id = uid.trim();
  if (id.isEmpty) return const [];
  final f = DateTime(from.year, from.month, from.day);
  final t = DateTime(to.year, to.month, to.day, 23, 59, 59);
  final col = ChurchUiCollections.financeiro(id);

  Query<Map<String, dynamic>> base(String field) {
    // Igualdades antes do intervalo (índices compostos Firestore).
    Query<Map<String, dynamic>> q = col;
    if (statusFilter == 'pending') {
      q = q.where('status', isEqualTo: 'pending');
    } else if (statusFilter == 'paid') {
      q = q.where('status', isEqualTo: 'paid');
    }
    if (typeFilter == 'income') {
      q = q.where('type', isEqualTo: 'income');
    } else if (typeFilter == 'expense') {
      q = q.where('type', isEqualTo: 'expense');
    }
    final acc = financeAccountId?.trim();
    if (acc != null && acc.isNotEmpty) {
      q = q.where('financeAccountId', isEqualTo: acc);
    }
    return q
        .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(f))
        .where(field, isLessThanOrEqualTo: Timestamp.fromDate(t))
        .orderBy(field, descending: false);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safeCollect(
    Query<Map<String, dynamic>> q,
  ) async {
    try {
      final server = await firestoreQueryCollectDocumentsBatched(
        q,
        pageSize: pageSize,
        maxDocuments: maxDocuments,
      );
      if (server.isNotEmpty) return server;
    } catch (_) {}
    try {
      return await _collectQueryFromCache(q, maxDocuments: maxDocuments);
    } catch (_) {
      return [];
    }
  }

  final byDate = await safeCollect(base('date'));
  final byEff = await safeCollect(base('effectiveDate'));
  final byPaidAt = await safeCollect(base('paidAt'));

  final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
  for (final d in [...byDate, ...byEff, ...byPaidAt]) {
    merged[d.id] = d;
  }

  final rs = f;
  final re = t;
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  for (final doc in merged.values) {
    final d = doc.data();
    if (statusFilter != 'all' && (d['status'] ?? 'paid').toString() != statusFilter) {
      continue;
    }
    if (typeFilter == 'income' && (d['type'] ?? 'expense').toString() != 'income') continue;
    if (typeFilter == 'expense' && (d['type'] ?? 'expense').toString() != 'expense') continue;
    if (!_docEffectiveInPeriod(d, rs, re)) continue;
    out.add(doc);
  }
  out.sort((a, b) {
    final da = FinanceLineOpening.effectiveDateTimeFromMap(a.data()) ??
        (a.data()['date'] as Timestamp?)?.toDate();
    final db = FinanceLineOpening.effectiveDateTimeFromMap(b.data()) ??
        (b.data()['date'] as Timestamp?)?.toDate();
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return out;
}

/// Coleta paginada só do cache local — lista completa offline (Android/iOS).
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _collectQueryFromCache(
  Query<Map<String, dynamic>> baseQuery, {
  int maxDocuments = 8000,
  int pageSize = 400,
}) async {
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  while (out.length < maxDocuments) {
    var q = baseQuery.limit(pageSize);
    if (cursor != null) {
      q = q.startAfterDocument(cursor);
    }
    final snap = await q.get(const GetOptions(source: Source.cache));
    if (snap.docs.isEmpty) break;
    out.addAll(snap.docs);
    if (snap.docs.length < pageSize) break;
    cursor = snap.docs.last;
  }
  return out;
}

/// Streams de transações com [includeMetadataChanges] para refletir gravações
/// locais (offline/cache) na hora nos saldos do painel e gráficos.

/// **Evitar** em produção: carrega a coleção inteira. Preferir
/// [financeTransactionsRangedSnapshots], [financeTransactionsPeriodDocs] ou
/// [financeTransactionsPendingSnapshots].
Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsOrderedSnapshots({
  required String uid,
}) {
  final query = _transactionsCol(uid).orderBy('date', descending: false);
  if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
    return _pollQuery(query);
  }
  return query.snapshots(includeMetadataChanges: true);
}

/// Pendentes — índice `status`+`date`; filtra [type] em memória (igual Financeiro).
Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsPendingSnapshots({
  required String uid,
  required String type,
  int limit = kFinancePendingStreamLimit,
}) {
  assert(type == 'income' || type == 'expense');
  final fsUid = uid.trim();
  if (fsUid.isEmpty) {
    return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
  }
  final query = ChurchUiCollections.financeiro(fsUid)
      .where('status', isEqualTo: 'pending')
      .orderBy('date', descending: false)
      .limit(limit);

  return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((controller) {
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;

    Future<void> emitCache() async {
      try {
        final cached = await query.get(const GetOptions(source: Source.cache));
        if (!controller.isClosed) {
          controller.add(_filterPendingByType(cached, type));
        }
      } catch (_) {}
    }

    unawaited(emitCache().then((_) {
      final source = FirestoreWebGuard.disableLiveSnapshotsOnWeb
          ? _pollQuery(query)
          : query.snapshots(includeMetadataChanges: true);
      sub = source.listen(
        (snap) => controller.add(_filterPendingByType(snap, type)),
        onError: controller.addError,
      );
    }));
    controller.onCancel = () => sub?.cancel();
  });
}

/// Filtra tipo em memória — painel/financeiro só leem [docs].
QuerySnapshot<Map<String, dynamic>> _filterPendingByType(
  QuerySnapshot<Map<String, dynamic>> snap,
  String type,
) {
  final docs = snap.docs.where((d) {
    return (d.data()['type'] ?? 'expense').toString() == type;
  }).toList();
  if (docs.length == snap.docs.length) return snap;
  return _FilteredQuerySnapshot(snap, docs);
}

class _FilteredQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _FilteredQuerySnapshot(this._source, this._docs);

  final QuerySnapshot<Map<String, dynamic>> _source;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges =>
      _source.docChanges
          .where((c) => _docs.any((d) => d.id == c.doc.id))
          .toList();

  @override
  SnapshotMetadata get metadata => _source.metadata;

  @override
  int get size => _docs.length;
}

Stream<QuerySnapshot<Map<String, dynamic>>> financeTransactionsRangedSnapshots({
  required String uid,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  final query = _transactionsCol(uid)
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(rs))
      .where('date', isLessThanOrEqualTo: Timestamp.fromDate(re))
      .orderBy('date', descending: false);

  return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((controller) {
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    unawaited(() async {
      try {
        final cached = await query.get(const GetOptions(source: Source.cache));
        if (!controller.isClosed) controller.add(cached);
      } catch (_) {}
      final source = FirestoreWebGuard.disableLiveSnapshotsOnWeb
          ? _pollQuery(query)
          : query.snapshots(includeMetadataChanges: true);
      sub = source.listen(
        controller.add,
        onError: controller.addError,
      );
    }());
    controller.onCancel = () => sub?.cancel();
  });
}
