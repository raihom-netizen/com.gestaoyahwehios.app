import 'package:cloud_firestore/cloud_firestore.dart';

/// Competência no formato `yyyy-MM`.
String competenciaFinanceira(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Id determinístico do lançamento financeiro gerado pela recorrência + mês.
String idLancamentoRecorrencia(String receitaRecorrenteId, String competencia) =>
    'rec_${receitaRecorrenteId}_$competencia';

/// Gera lançamentos de receita **pendentes de conciliação** no caixa (um por competência).
/// Idempotente: documento fixo em `finance` por recorrência + `yyyy-MM`.
///
/// Só gera competências entre o mês de [dataInicio] e o **mês atual** (sem meses futuros).
Future<int> gerarReceitasRecorrentesPendentes(String tenantId) async {
  final db = FirebaseFirestore.instance;
  final ig = db.collection('igrejas').doc(tenantId);
  final recSnap = await ig.collection('receitas_recorrentes').get();
  final fin = ig.collection('finance');
  final now = DateTime.now();
  final mesAtual = DateTime(now.year, now.month, 1);
  var criados = 0;

  for (final rd in recSnap.docs) {
    final m = rd.data();
    if (m['ativo'] == false) continue;
    final vinculoTipo = (m['vinculoTipo'] ?? 'membro').toString();
    final isFornecedor = vinculoTipo == 'fornecedor';
    final memberDocId = (m['memberDocId'] ?? '').toString().trim();
    final memberNome = (m['memberNome'] ?? '').toString().trim();
    final memberTelefone = (m['memberTelefone'] ?? '').toString().trim();
    final fornecedorId = (m['fornecedorId'] ?? '').toString().trim();
    final fornecedorNome = (m['fornecedorNome'] ?? '').toString().trim();
    if (isFornecedor) {
      if (fornecedorId.isEmpty) continue;
    } else {
      if (memberDocId.isEmpty) continue;
    }
    final valor = (m['valor'] ?? 0);
    final v = valor is num ? valor.toDouble() : double.tryParse('$valor') ?? 0;
    if (v <= 0) continue;
    final categoria = (m['categoria'] ?? 'Dízimos').toString().trim();
    final contaDestinoId = (m['contaDestinoId'] ?? '').toString().trim();
    final contaDestinoNome = (m['contaDestinoNome'] ?? '').toString().trim();

    DateTime? di;
    DateTime? df;
    final ti = m['dataInicio'];
    if (ti is Timestamp) di = ti.toDate();
    final tf = m['dataFim'];
    if (tf is Timestamp) df = tf.toDate();
    final indeterminado = m['indeterminado'] == true;

    if (di == null) continue;

    final inicioM = DateTime(di.year, di.month, 1);

    DateTime fimLoop;
    if (indeterminado || df == null) {
      fimLoop = mesAtual;
    } else {
      final dfM = DateTime(df.year, df.month, 1);
      fimLoop = dfM.isAfter(mesAtual) ? mesAtual : dfM;
    }
    if (inicioM.isAfter(fimLoop)) continue;

    var cursor = inicioM;
    while (!cursor.isAfter(fimLoop)) {
      final comp = competenciaFinanceira(cursor);
      final docId = idLancamentoRecorrencia(rd.id, comp);
      final ref = fin.doc(docId);
      final exist = await ref.get();
      if (!exist.exists) {
        final labelMes =
            '${cursor.month.toString().padLeft(2, '0')}/${cursor.year}';
        final titularNome = isFornecedor
            ? (fornecedorNome.isNotEmpty ? fornecedorNome : fornecedorId)
            : (memberNome.isNotEmpty ? memberNome : memberDocId);
        final descTitular = titularNome;
        final base = <String, dynamic>{
          'type': 'entrada',
          'amount': v,
          'categoria': categoria,
          'descricao':
              '$categoria — $descTitular ($labelMes) · recorrente',
          'recebimentoConfirmado': false,
          'pendenteConciliacaoRecorrencia': true,
          'recorrenciaId': rd.id,
          'competencia': comp,
          'titularNome': titularNome,
          'vinculoTipo': isFornecedor ? 'fornecedor' : 'membro',
          if (contaDestinoId.isNotEmpty) 'contaDestinoId': contaDestinoId,
          if (contaDestinoNome.isNotEmpty) 'contaDestinoNome': contaDestinoNome,
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (isFornecedor) {
          base['fornecedorId'] = fornecedorId;
          base['fornecedorNome'] =
              fornecedorNome.isNotEmpty ? fornecedorNome : fornecedorId;
        } else {
          base['memberDocId'] = memberDocId;
          base['memberNome'] = memberNome;
          if (memberTelefone.isNotEmpty) {
            base['memberTelefone'] = memberTelefone;
          }
        }
        await ref.set(base);
        criados++;
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }
  return criados;
}
