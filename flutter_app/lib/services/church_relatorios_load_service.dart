import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_certificados_load_service.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Carga canónica — Relatórios (membros, eventos, financeiro, patrimônio).
///
/// Sempre `igrejas/{churchId}/…` via serviços existentes; evita directory parcial
/// e queries `where` lentas na Web.
abstract final class ChurchRelatoriosLoadService {
  ChurchRelatoriosLoadService._();

  static const int kMembrosLimit = ChurchCertificadosLoadService.kAllMembersLimit;
  static const int kEventosLimit = ChurchEventosLoadService.kGalleryLimit;
  static const int kFinanceLimit = 500;
  static const int kPatrimonioLimit = 200;

  static final Map<String, ({List<Map<String, dynamic>> rows, DateTime at})>
      _membrosRam = {};
  static final Map<String, ({List<Map<String, dynamic>> rows, DateTime at})>
      _eventosRam = {};

  static const Duration _ramTtl = Duration(minutes: 15);

  static String _churchId(String hint) => ChurchRepository.churchId(hint.trim());

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static Future<void> _ensureWeb() async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
  }

  static Future<T> _withRecovery<T>(Future<T> Function() op) async {
    await _ensureWeb();
    return op().timeout(ChurchPanelReadTimeouts.queryCap);
  }

  static void invalidateMembros(String churchIdHint) {
    final id = _churchId(churchIdHint);
    if (id.isEmpty) return;
    _membrosRam.remove(id);
    ChurchCertificadosLoadService.invalidate(id);
  }

  static void invalidateEventos(String churchIdHint) {
    _eventosRam.remove(_churchId(churchIdHint));
  }

  static void invalidateAll(String churchIdHint) {
    invalidateMembros(churchIdHint);
    invalidateEventos(churchIdHint);
  }

  static List<Map<String, dynamic>>? _peekMembrosRam(String churchId) {
    final hit = _membrosRam[churchId];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _membrosRam.remove(churchId);
      return null;
    }
    return hit.rows;
  }

  static List<Map<String, dynamic>> _docsToRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) =>
      docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList(growable: false);

  /// Lista completa de membros — coleção `membros` (não só directory parcial).
  static Future<List<Map<String, dynamic>>> loadMembrosRows({
    required String churchIdHint,
    int limit = kMembrosLimit,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    if (!forceRefresh) {
      final ram = _peekMembrosRam(churchId);
      if (ram != null && ram.isNotEmpty) return ram;
    } else {
      invalidateMembros(churchId);
    }

    return _withRecovery(() async {
      try {
        final callable = _functions.httpsCallable(
          'getRelatoriosBundle',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
        final res = await callable.call<Map<dynamic, dynamic>>({
          'tenantId': churchId,
          'modules': const ['membros'],
          'membrosLimit': limit,
        });
        final list = res.data['membros'];
        if (list is List && list.isNotEmpty) {
          final rows = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((m) =>
                  (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
              .toList(growable: false);
          if (rows.isNotEmpty) {
            _membrosRam[churchId] = (rows: rows, at: DateTime.now());
            return rows;
          }
        }
      } catch (e, st) {
        debugPrint('ChurchRelatoriosLoadService cloud membros: $e\n$st');
      }

      final result = await ChurchCertificadosLoadService.load(
        seedTenantId: churchId,
        forceRefresh: forceRefresh,
      );
      if (result.docs.isNotEmpty) {
        final rows = _docsToRows(result.docs);
        _membrosRam[churchId] = (rows: rows, at: DateTime.now());
        return rows;
      }

      try {
        final dir = await MembersDirectorySnapshotService.warmFromCallable(
          tenantId: churchId,
        );
        if (dir.hasEntries) {
          final rows = dir.entries
              .map((e) => {...e.toMemberDataMap(), 'id': e.memberDocId})
              .toList(growable: false);
          if (rows.isNotEmpty) {
            _membrosRam[churchId] = (rows: rows, at: DateTime.now());
            return rows;
          }
        }
      } catch (e, st) {
        debugPrint('ChurchRelatoriosLoadService directory: $e\n$st');
      }

      return const [];
    });
  }

  static DateTime? _eventStartAt(Map<String, dynamic> data) {
    for (final key in ['startAt', 'dataEvento', 'data', 'createdAt']) {
      final raw = data[key];
      if (raw is Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
    }
    return null;
  }

  static bool _isEventoDoc(Map<String, dynamic> data) {
    final t = (data['type'] ?? data['tipo'] ?? data['kind'] ?? '')
        .toString()
        .toLowerCase();
    if (t.isEmpty) return true;
    return t.contains('evento') || t == 'event';
  }

  /// Eventos no período — filtro de datas no cliente (sem índice composto na Web).
  static Future<List<Map<String, dynamic>>> loadEventosForPeriod({
    required String churchIdHint,
    required DateTime inicio,
    required DateTime fim,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    final startDay = DateTime(inicio.year, inicio.month, inicio.day);
    final endDay = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);

    return _withRecovery(() async {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

      try {
        final callable = _functions.httpsCallable(
          'getRelatoriosBundle',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
        final res = await callable.call<Map<dynamic, dynamic>>({
          'tenantId': churchId,
          'modules': const ['eventos'],
          'eventosLimit': kEventosLimit,
        });
        final list = res.data['eventos'];
        if (list is List && list.isNotEmpty) {
          docs = list.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            final id = (m['id'] ?? '').toString();
            m.remove('id');
            return _RelatoriosSyntheticDoc(id: id, data: m);
          }).toList();
        } else {
          docs = const [];
        }
      } catch (e, st) {
        debugPrint('ChurchRelatoriosLoadService cloud eventos: $e\n$st');
        docs = const [];
      }

      if (docs.isEmpty) {
        final result = await ChurchEventosLoadService.loadGallery(
          seedTenantId: churchId,
          forceRefresh: forceRefresh,
        );
        docs = result.docs;
      }

      final out = <Map<String, dynamic>>[];
      for (final d in docs) {
        final data = d.data();
        if (!_isEventoDoc(data)) continue;
        final dt = _eventStartAt(data);
        if (dt == null) continue;
        if (dt.isBefore(startDay) || dt.isAfter(endDay)) continue;
        final rsvp = (data['rsvp'] as List?) ?? [];
        final likes = (data['likes'] as List?) ?? [];
        out.add({
          'id': d.id,
          'title': (data['title'] ?? data['titulo'] ?? 'Evento').toString(),
          'date': dt,
          'rsvpCount': rsvp.length,
          'likesCount': likes.length,
          'location': (data['location'] ?? data['local'] ?? '').toString(),
        });
      }
      out.sort(
        (a, b) =>
            (a['date'] as DateTime).compareTo(b['date'] as DateTime),
      );
      return out;
    });
  }

  static Future<List<Map<String, dynamic>>> loadFinanceRows({
    required String churchIdHint,
    required DateTime inicio,
    required DateTime fim,
    int limit = kFinanceLimit,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    return _withRecovery(() async {
      try {
        final callable = _functions.httpsCallable(
          'getRelatoriosBundle',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
        final res = await callable.call<Map<dynamic, dynamic>>({
          'tenantId': churchId,
          'modules': const ['finance'],
          'financeLimit': limit,
        });
        final list = res.data['finance'];
        if (list is List && list.isNotEmpty) {
          return list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((row) {
                final dt = _financeDate(row);
                if (dt == null) return true;
                return !dt.isBefore(inicio) &&
                    !dt.isAfter(
                      DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999),
                    );
              })
              .toList(growable: false);
        }
      } catch (e, st) {
        debugPrint('ChurchRelatoriosLoadService cloud finance: $e\n$st');
      }

      final result = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: churchId,
        limit: limit,
        forceRefresh: forceRefresh,
      );
      return result.docs
          .map(_normalizeFinanceRow)
          .where((row) {
            final dt = _financeDate(row);
            if (dt == null) return true;
            return !dt.isBefore(inicio) &&
                !dt.isAfter(
                  DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999),
                );
          })
          .toList(growable: false);
    });
  }

  static DateTime? _financeDate(Map<String, dynamic> m) {
    final raw = m['createdAt'] ?? m['data'] ?? m['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int && raw > 0) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadPatrimonioDocs({
    required String churchIdHint,
    int limit = kPatrimonioLimit,
    bool forceRefresh = false,
  }) async {
    final churchId = _churchId(churchIdHint);
    if (churchId.isEmpty) return const [];

    return _withRecovery(() async {
      try {
        final callable = _functions.httpsCallable(
          'getRelatoriosBundle',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
        );
        final res = await callable.call<Map<dynamic, dynamic>>({
          'tenantId': churchId,
          'modules': const ['patrimonio'],
          'patrimonioLimit': limit,
        });
        final list = res.data['patrimonio'];
        if (list is List && list.isNotEmpty) {
          return list.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            final id = (m['id'] ?? '').toString();
            m.remove('id');
            return _RelatoriosSyntheticDoc(id: id, data: m);
          }).toList();
        }
      } catch (e, st) {
        debugPrint('ChurchRelatoriosLoadService cloud patrimonio: $e\n$st');
      }

      final result = await ChurchPatrimonioLoadService.loadAll(
        seedTenantId: churchId,
        limit: limit,
        forceRefresh: forceRefresh,
      );
      return result.docs;
    });
  }

  static Map<String, dynamic> _normalizeFinanceRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    final dataWithId = {...m, 'id': doc.id};
    final dt = financeLancamentoDate(m);
    final valor = financeParseValorBr(m['amount'] ?? m['valor']);
    final tipo = financeInferTipo(dataWithId);
    return {
      'id': doc.id,
      'createdAtMs': dt?.millisecondsSinceEpoch ?? 0,
      'createdAt': m['createdAt'] ?? m['data'],
      'tipo': tipo,
      'type': m['type'] ?? m['tipo'],
      'amount': valor,
      'categoria': (m['categoria'] ?? '').toString(),
      'descricao': (m['descricao'] ?? m['anotacoes'] ?? '').toString(),
      'valor': valor,
      'contaOrigemId': (m['contaOrigemId'] ?? '').toString(),
      'contaDestinoId': (m['contaDestinoId'] ?? '').toString(),
      'pago': m['pago'] == true,
      'statusPagamento':
          (m['statusPagamento'] ?? m['status'] ?? '').toString(),
      'comprovanteUrl': (m['comprovanteUrl'] ?? '').toString(),
      'recebimentoConfirmado': m['recebimentoConfirmado'],
      'pagamentoConfirmado': m['pagamentoConfirmado'],
      'fornecedorId': (m['fornecedorId'] ?? '').toString(),
      'fornecedorNome': (m['fornecedorNome'] ?? '').toString(),
    };
  }
}

// ignore: subtype_of_sealed_class
class _RelatoriosSyntheticDoc
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _RelatoriosSyntheticDoc({required this.id, required Map<String, dynamic> data})
      : _data = data;

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  bool get exists => true;

  @override
  SnapshotMetadata get metadata => const _RelSynMeta();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('synthetic');
}

class _RelSynMeta implements SnapshotMetadata {
  const _RelSynMeta();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => false;
}
