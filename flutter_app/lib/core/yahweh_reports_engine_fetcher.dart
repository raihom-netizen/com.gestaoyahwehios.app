import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Consolidação de dados para **Relatórios** — sempre `igrejas/{churchId}/…`.
///
/// Delega leitura a [ChurchFinanceLoadService], [ChurchPatrimonioLoadService] e
/// cache de membros; **nunca** hardcode de tenant nem `FirebaseFirestore.instance`.
abstract final class YahwehReportsEngineFetcher {
  YahwehReportsEngineFetcher._();

  static const int kFinanceReportLimit = 500;
  static const int kPatrimonioReportLimit = 200;
  static const int kMembrosReportLimit = 800;

  /// Sem fallback fixo de tenant — usar sempre o churchId da sessão.
  static const String pilotChurchIdHint = '';

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  static Future<void> _ensureWebReady() async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
  }

  static Future<T> _withWebRecovery<T>(Future<T> Function() op) async {
    await _ensureWebReady();
    if (kIsWeb) {
      return FirestoreWebGuard.runWithWebRecovery(op, maxAttempts: 4);
    }
    return op();
  }

  static bool _inPeriod(DateTime? dt, DateTime inicio, DateTime fim) {
    if (dt == null) return true;
    final inicioDay = DateTime(inicio.year, inicio.month, inicio.day);
    final fimEnd = DateTime(fim.year, fim.month, fim.day, 23, 59, 59, 999);
    return !dt.isBefore(inicioDay) && !dt.isAfter(fimEnd);
  }

  /// Normaliza doc `igrejas/{id}/finance` → mapa do relatório financeiro.
  static Map<String, dynamic> normalizeFinanceRow(
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
      'tipo': tipo,
      'type': m['type'] ?? m['tipo'],
      'amount': valor,
      'categoria': (m['categoria'] ?? '').toString(),
      'descricao': (m['descricao'] ?? m['anotacoes'] ?? '').toString(),
      'valor': valor,
      'contaOrigemId': (m['contaOrigemId'] ?? '').toString(),
      'contaDestinoId': (m['contaDestinoId'] ?? '').toString(),
      'pago': m['pago'] == true,
      'statusPagamento': (m['statusPagamento'] ?? m['status'] ?? '').toString(),
      'comprovanteUrl': (m['comprovanteUrl'] ?? '').toString(),
      'recebimentoConfirmado': m['recebimentoConfirmado'],
      'pagamentoConfirmado': m['pagamentoConfirmado'],
      'fornecedorId': (m['fornecedorId'] ?? '').toString(),
      'fornecedorNome': (m['fornecedorNome'] ?? '').toString(),
    };
  }

  /// Lançamentos do período — filtro de datas **no cliente** (evita índice composto Web).
  static Future<List<Map<String, dynamic>>> fetchFinanceRowsForPeriod({
    required String churchIdHint,
    required DateTime inicio,
    required DateTime fim,
    int limit = kFinanceReportLimit,
    bool forceRefresh = false,
  }) =>
      _withWebRecovery(() async {
        final churchId = resolveChurchId(churchIdHint);
        if (churchId.isEmpty) return const [];

        final result = await ChurchFinanceLoadService.loadLancamentos(
          seedTenantId: churchId,
          limit: limit,
          forceRefresh: forceRefresh,
        );

        return result.docs
            .map(normalizeFinanceRow)
            .where(
              (row) => _inPeriod(
                financeLancamentoDate(row),
                inicio,
                fim,
              ),
            )
            .toList(growable: false);
      });

  static Map<String, double> aggregateFinanceTotals(
    Iterable<Map<String, dynamic>> rows,
  ) {
    var entradas = 0.0;
    var saidas = 0.0;
    for (final m in rows) {
      final tipo = (m['tipo'] ?? '').toString().toLowerCase();
      final valor = financeParseValorBr(m['valor'] ?? m['amount']);
      if (tipo == 'transferencia') continue;
      if (tipo.contains('entrada') || tipo.contains('receita')) {
        entradas += valor;
      } else if (tipo.contains('saida') || tipo.contains('despesa')) {
        saidas += valor;
      }
    }
    return {
      'entradas': entradas,
      'saidas': saidas,
      'saldo': entradas - saidas,
    };
  }

  /// Totais financeiros reactivos — re-emite quando `finance` muda (cards/gráficos).
  static Stream<Map<String, double>> watchFinanceTotals({
    required String churchIdHint,
    required DateTime inicio,
    required DateTime fim,
    int limit = kFinanceReportLimit,
  }) async* {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      yield const {'entradas': 0.0, 'saidas': 0.0, 'saldo': 0.0};
      return;
    }

    await _ensureWebReady();

    Future<Map<String, double>> loadOnce() async {
      final rows = await fetchFinanceRowsForPeriod(
        churchIdHint: churchId,
        inicio: inicio,
        fim: fim,
        limit: limit,
      );
      return aggregateFinanceTotals(rows);
    }

    yield await loadOnce();

    if (kIsWeb) {
      yield* Stream.periodic(const Duration(seconds: 45))
          .asyncMap((_) => loadOnce());
      return;
    }

    yield* ChurchUiCollections.financeiro(churchId)
        .limit(limit)
        .snapshots()
        .asyncMap((_) => loadOnce());
  }

  static Future<List<Map<String, dynamic>>> fetchMembrosRows({
    required String churchIdHint,
    int limit = kMembrosReportLimit,
  }) =>
      _withWebRecovery(() async {
        final churchId = resolveChurchId(churchIdHint);
        if (churchId.isEmpty) return const [];

        try {
          final dir = await MembersDirectorySnapshotService.readOnce(churchId);
          if (dir.hasEntries) {
            final out = <Map<String, dynamic>>[];
            for (final e in dir.entries) {
              if (out.length >= limit) break;
              out.add({...e.toMemberDataMap(), 'id': e.memberDocId});
            }
            if (out.isNotEmpty) return out;
          }
        } catch (_) {}

        final snap =
            await ChurchTenantResilientReads.membrosRecent(churchId, limit: limit);
        return snap.docs
            .map((d) => {...d.data(), 'id': d.id})
            .toList(growable: false);
      });

  static Future<Map<String, int>> loadMembrosStats({
    required String churchIdHint,
    int limit = kMembrosReportLimit,
  }) async {
    final rows = await fetchMembrosRows(
      churchIdHint: churchIdHint,
      limit: limit,
    );
    var active = 0;
    for (final m in rows) {
      if (ChurchModuleFirestoreListRead.isActiveRecord(m)) active++;
    }
    return {
      'totalActive': active,
      'total': rows.length,
    };
  }

  static Stream<Map<String, int>> watchMembrosStats({
    required String churchIdHint,
    int limit = kMembrosReportLimit,
  }) async* {
    yield await loadMembrosStats(churchIdHint: churchIdHint, limit: limit);
    yield* Stream.periodic(const Duration(seconds: 60)).asyncMap(
      (_) => loadMembrosStats(churchIdHint: churchIdHint, limit: limit),
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchPatrimonioDocs({
    required String churchIdHint,
    int limit = kPatrimonioReportLimit,
    bool forceRefresh = false,
  }) =>
      _withWebRecovery(() async {
        final churchId = resolveChurchId(churchIdHint);
        if (churchId.isEmpty) return const [];

        final result = await ChurchPatrimonioLoadService.loadAll(
          seedTenantId: churchId,
          limit: limit,
          forceRefresh: forceRefresh,
        );
        return result.docs;
      });

  static Future<Map<String, dynamic>> loadPatrimonioStats({
    required String churchIdHint,
    int limit = kPatrimonioReportLimit,
  }) async {
    final docs = await fetchPatrimonioDocs(
      churchIdHint: churchIdHint,
      limit: limit,
    );
    var count = 0;
    var total = 0.0;
    for (final d in docs) {
      if (!ChurchModuleFirestoreListRead.isActiveRecord(d.data())) continue;
      count++;
      total += financeParseValorBr(d.data()['valor'] ?? d.data()['value']);
    }
    return {
      'quantidadeItens': count,
      'investimentoTotal': total,
    };
  }

  static Stream<Map<String, dynamic>> watchPatrimonioStats({
    required String churchIdHint,
    int limit = kPatrimonioReportLimit,
  }) async* {
    yield await loadPatrimonioStats(churchIdHint: churchIdHint, limit: limit);
    yield* Stream.periodic(const Duration(seconds: 60)).asyncMap(
      (_) => loadPatrimonioStats(churchIdHint: churchIdHint, limit: limit),
    );
  }
}
