import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/finance_ofx_parser.dart';

class OfxMatchSuggestion {
  const OfxMatchSuggestion({
    required this.ofx,
    this.lancamentoId,
    this.lancamentoDescricao,
    this.confidence = 0,
    this.reason = '',
  });

  final OfxStatementTransaction ofx;
  final String? lancamentoId;
  final String? lancamentoDescricao;
  final int confidence;
  final String reason;

  bool get hasMatch => lancamentoId != null && confidence >= 50;
}

abstract final class FinanceOfxConciliationService {
  FinanceOfxConciliationService._();

  static const _amountTolerance = 0.02;
  static const _maxDayDelta = 5;

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      loadNaoConciliados(String tenantId) async {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    final loaded = await ChurchFinanceLoadService.loadLancamentos(
      seedTenantId: churchId,
      limit: 600,
      forceRefresh: true,
      forceServer: false,
    );
    return loaded.docs.where((d) {
      final data = d.data();
      if (financeInferTipo(data) == 'transferencia') return false;
      return data['conciliado'] != true;
    }).toList();
  }

  static List<OfxMatchSuggestion> suggestMatches({
    required List<OfxStatementTransaction> ofxRows,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> lancamentos,
  }) {
    final usedIds = <String>{};
    final out = <OfxMatchSuggestion>[];

    for (final ofx in ofxRows) {
      String? bestId;
      String? bestDesc;
      var bestScore = 0;
      var bestReason = '';

      for (final doc in lancamentos) {
        if (usedIds.contains(doc.id)) continue;
        final data = doc.data();
        final score = _scoreMatch(ofx, data);
        if (score > bestScore) {
          bestScore = score;
          bestId = doc.id;
          bestDesc = (data['descricao'] ?? data['categoria'] ?? doc.id)
              .toString();
          bestReason = _reasonFor(ofx, data, score);
        }
      }

      if (bestId != null && bestScore >= 50) usedIds.add(bestId);
      out.add(
        OfxMatchSuggestion(
          ofx: ofx,
          lancamentoId: bestScore >= 50 ? bestId : null,
          lancamentoDescricao: bestScore >= 50 ? bestDesc : null,
          confidence: bestScore,
          reason: bestReason,
        ),
      );
    }
    return out;
  }

  static int _scoreMatch(
    OfxStatementTransaction ofx,
    Map<String, dynamic> data,
  ) {
    final valor = financeParseValorBr(data['amount'] ?? data['valor']);
    if ((valor - ofx.absAmount).abs() > _amountTolerance) return 0;

    final dt = financeLancamentoDate(data);
    if (dt == null) return 20;

    final dayDelta = (DateTime(ofx.date.year, ofx.date.month, ofx.date.day)
            .difference(DateTime(dt.year, dt.month, dt.day))
            .inDays)
        .abs();
    if (dayDelta > _maxDayDelta) return 0;

    final tipoOk = ofx.isCredit
        ? financeIsEntrada(data)
        : financeIsSaida(data);
    if (!tipoOk) return 0;

    var score = 70;
    if (dayDelta == 0) {
      score += 25;
    } else if (dayDelta <= 2) {
      score += 15;
    } else {
      score += 5;
    }

    final ext = (data['extratoRef'] ?? '').toString().trim();
    if (ext.isNotEmpty && ext == ofx.fitId) score = 100;

    final memo = ofx.memo.toLowerCase();
    final desc = (data['descricao'] ?? '').toString().toLowerCase();
    if (memo.isNotEmpty &&
        desc.isNotEmpty &&
        (memo.contains(desc) || desc.contains(memo))) {
      score += 5;
    }
    return score.clamp(0, 100);
  }

  static String _reasonFor(
    OfxStatementTransaction ofx,
    Map<String, dynamic> data,
    int score,
  ) {
    if (score >= 95) return 'Valor, data e tipo coincidem';
    if (score >= 80) return 'Valor e data próximos';
    if (score >= 50) return 'Possível correspondência';
    return 'Sem lançamento compatível';
  }

  static bool financeIsEntrada(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('entrada') || t.contains('receita');
  }

  static bool financeIsSaida(Map<String, dynamic> data) {
    final t = financeInferTipo(data);
    return t.contains('saida') || t.contains('despesa');
  }

  static Future<int> applyMatches({
    required String tenantId,
    required List<OfxMatchSuggestion> accepted,
  }) async {
    if (accepted.isEmpty) return 0;
    final churchId = ChurchRepository.churchId(tenantId.trim());
    final fin = ChurchUiCollections.financeiro(churchId);
    final batch = fin.firestore.batch();
    var n = 0;

    for (final m in accepted) {
      final id = m.lancamentoId;
      if (id == null || id.isEmpty) continue;
      final ref = fin.doc(id);
      final patch = <String, dynamic>{
        'conciliado': true,
        'extratoRef': m.ofx.fitId,
        'ofxMemo': m.ofx.memo,
        'conciliadoEm': FieldValue.serverTimestamp(),
      };
      if (m.ofx.isCredit) {
        patch['recebimentoConfirmado'] = true;
        patch['pendenteConciliacaoRecorrencia'] = false;
      } else {
        patch['pagamentoConfirmado'] = true;
        patch['pendenteConciliacaoDespesaFixa'] = false;
      }
      batch.update(ref, patch);
      n++;
    }
    if (n > 0) await batch.commit();
    return n;
  }
}
