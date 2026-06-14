import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/receitas_recorrentes_geracao_service.dart';

/// Id determinístico do lançamento gerado por despesa fixa + competência.
String idLancamentoDespesaFixa(String despesaFixaId, String competencia) =>
    'desp_${despesaFixaId}_$competencia';

int _diaNaCompetencia(int diaVencimento, DateTime monthStart) {
  final last = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  final d = diaVencimento > 0 ? diaVencimento : 1;
  return d > last ? last : d;
}

/// Gera lançamentos de despesa **pendentes de pagamento** (idempotente).
Future<int> gerarDespesasFixasPendentes(String tenantId) async {
  final churchId = ChurchRepository.churchId(tenantId.trim());
  final fixSnap = await ChurchTenantResilientReads.despesasFixas(churchId);
  final fin = ChurchUiCollections.financeiro(churchId);
  final now = DateTime.now();
  final mesAtual = DateTime(now.year, now.month, 1);
  var criados = 0;

  for (final fd in fixSnap.docs) {
    final m = fd.data();
    if (m['ativo'] == false) continue;

    final valor = m['valor'];
    final v = valor is num ? valor.toDouble() : double.tryParse('$valor') ?? 0;
    if (v <= 0) continue;

    final categoria = (m['categoria'] ?? 'Outros').toString().trim();
    final descricao = (m['descricao'] ?? categoria).toString().trim();
    final diaVenc = (m['diaVencimento'] is int)
        ? m['diaVencimento'] as int
        : int.tryParse('${m['diaVencimento']}') ?? 10;
    final vinculoTipo = (m['vinculoTipo'] ?? 'nenhum').toString();

    DateTime? di;
    DateTime? df;
    final ti = m['dataInicio'];
    if (ti is Timestamp) di = ti.toDate();
    final tf = m['dataFim'];
    if (tf is Timestamp) df = tf.toDate();
    if (di == null) continue;

    final totalParcelas = (m['totalParcelas'] is int)
        ? m['totalParcelas'] as int?
        : int.tryParse('${m['totalParcelas']}');
    final aPartir = (m['aPartirDaParcela'] is int)
        ? m['aPartirDaParcela'] as int?
        : int.tryParse('${m['aPartirDaParcela']}');

    final inicioM = DateTime(di.year, di.month, 1);
    DateTime fimLoop;
    if (df == null) {
      fimLoop = mesAtual;
    } else {
      final dfM = DateTime(df.year, df.month, 1);
      fimLoop = dfM.isAfter(mesAtual) ? mesAtual : dfM;
    }
    if (inicioM.isAfter(fimLoop)) continue;

    var parcelIndex = 0;
    var cursor = inicioM;
    while (!cursor.isAfter(fimLoop)) {
      parcelIndex++;
      final comp = competenciaFinanceira(cursor);
      final docId = idLancamentoDespesaFixa(fd.id, comp);
      final ref = fin.doc(docId);
      final exist = await ref.get();

      final skipParcela = totalParcelas != null &&
          totalParcelas > 0 &&
          (aPartir != null && aPartir > 0
              ? parcelIndex < aPartir || parcelIndex > totalParcelas
              : parcelIndex > totalParcelas);

      if (!exist.exists && !skipParcela) {
        final dia = _diaNaCompetencia(diaVenc, cursor);
        final dataLanc =
            DateTime(cursor.year, cursor.month, dia, 12, 0, 0);
        final labelMes =
            '${cursor.month.toString().padLeft(2, '0')}/${cursor.year}';
        final titular = (m['titularNome'] ??
                m['fornecedorNome'] ??
                m['membroNome'] ??
                '')
            .toString()
            .trim();

        final base = <String, dynamic>{
          'type': 'saida',
          'amount': v,
          'categoria': categoria,
          'descricao': '$descricao ($labelMes) · fixa',
          'pagamentoConfirmado': false,
          'pendenteConciliacaoDespesaFixa': true,
          'despesaFixaId': fd.id,
          'competencia': comp,
          'vinculoTipo': vinculoTipo,
          'date': Timestamp.fromDate(dataLanc),
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (titular.isNotEmpty) base['titularNome'] = titular;
        if (vinculoTipo == 'membro') {
          final mid = (m['membroId'] ?? '').toString().trim();
          if (mid.isNotEmpty) {
            base['membroId'] = mid;
            base['memberDocId'] = mid;
          }
          final mn = (m['membroNome'] ?? '').toString().trim();
          if (mn.isNotEmpty) base['membroNome'] = mn;
        } else if (vinculoTipo == 'fornecedor') {
          final fid = (m['fornecedorId'] ?? '').toString().trim();
          if (fid.isNotEmpty) base['fornecedorId'] = fid;
          final fn = (m['fornecedorNome'] ?? '').toString().trim();
          if (fn.isNotEmpty) base['fornecedorNome'] = fn;
        }
        await ref.set(base);
        criados++;
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }
  return criados;
}
