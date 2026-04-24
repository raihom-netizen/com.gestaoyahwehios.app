import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';
import 'package:gestao_yahweh/core/finance_tenant_settings.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/utils/finance_smart_input_text.dart';

/// Gera documentos `finance` a partir de linhas parseadas (Controle Total → tenant Yahweh).
abstract final class FinanceSmartBatchService {
  FinanceSmartBatchService._();

  static const int kMaxChunk = 400;

  static String _yahwehType(String parserType) {
    if (parserType == 'income') return 'entrada';
    return 'saida';
  }

  static Map<String, dynamic> lancamentoMapForRow({
    required BankNotificationParseResult row,
    required String contaId,
    required String contaNome,
    required String categoria,
    String? smartPasteBatchId,
    String source = 'smart_paste',
  }) {
    final v = row.valor ?? 0.0;
    if (v <= 0) {
      throw StateError('Valor inválido');
    }
    var desc = (row.descricao ?? '').toString();
    desc = FinanceSmartInputText.sanitize(desc);
    desc = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (desc.isEmpty) {
      throw StateError('Descrição vazia');
    }
    final t = _yahwehType(row.type);
    final when = row.data ?? DateTime.now();
    final ts = Timestamp.fromDate(
      DateTime(when.year, when.month, when.day, 12, 0, 0),
    );
    final out = <String, dynamic>{
      'type': t,
      'amount': v,
      'categoria': categoria.trim().isEmpty ? 'Importado' : categoria.trim(),
      'descricao': desc,
      'centroCusto': '',
      'extratoRef': '',
      'conciliado': false,
      'createdAt': ts,
      'recebimentoConfirmado': t == 'entrada',
      'pagamentoConfirmado': t == 'saida',
      'source': source,
      'parsedSnippet': row.rawSnippet,
    };
    if (smartPasteBatchId != null && smartPasteBatchId.isNotEmpty) {
      out['smartPasteBatchId'] = smartPasteBatchId;
    }
    if (t == 'entrada') {
      out['contaDestinoId'] = contaId;
      out['contaDestinoNome'] = contaNome;
    } else {
      out['contaOrigemId'] = contaId;
      out['contaOrigemNome'] = contaNome;
    }
    return out;
  }

  static Map<String, dynamic> _mapWithAprovacao({
    required Map<String, dynamic> base,
    required FinanceTenantSettings settings,
    String? panelRole,
  }) {
    if ((base['type'] ?? '') != 'saida') return base;
    final lim = settings.limiteAprovacaoDespesa;
    final valor = (base['amount'] is num)
        ? (base['amount'] as num).toDouble()
        : 0.0;
    final need = lim > 0 &&
        valor > lim &&
        AppPermissions.despesaFinanceiraExigeSegundaAprovacao(panelRole);
    return {...base, 'aprovacaoPendente': need};
  }

  static Future<int> writeRows({
    required CollectionReference<Map<String, dynamic>> financeCol,
    required List<BankNotificationParseResult> rows,
    required String contaId,
    required String contaNome,
    required String categoria,
    String? Function(BankNotificationParseResult row)? categoriaForRow,
    String? smartPasteBatchId,
    String source = 'smart_paste',
    String? panelRole,
    required FinanceTenantSettings settings,
  }) async {
    final valid = rows.where((r) => r.hasMinimumForConfirmation).toList();
    if (valid.isEmpty) return 0;

    var total = 0;
    for (var i = 0; i < valid.length; i += kMaxChunk) {
      final batch = FirebaseFirestore.instance.batch();
      for (final row in valid.skip(i).take(kMaxChunk)) {
        final catEfetiva = categoriaForRow != null
            ? (categoriaForRow(row) ?? categoria)
            : categoria;
        var map = lancamentoMapForRow(
          row: row,
          contaId: contaId,
          contaNome: contaNome,
          categoria: catEfetiva,
          smartPasteBatchId: smartPasteBatchId,
          source: source,
        );
        map = _mapWithAprovacao(
            base: map, settings: settings, panelRole: panelRole);
        batch.set(financeCol.doc(), map);
        total++;
      }
      await batch.commit();
    }
    return total;
  }
}
