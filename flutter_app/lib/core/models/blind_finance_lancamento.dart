import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/firestore_map_fields.dart';

/// Lançamento financeiro normalizado — tolerante a aliases legados.
class BlindFinanceLancamento {
  const BlindFinanceLancamento({
    required this.id,
    required this.raw,
    required this.valor,
    required this.tipo,
    required this.descricao,
    required this.categoria,
    this.data,
    this.contaId = '',
    this.contaDestinoId = '',
    this.comprovanteUrl = '',
    this.efetivadoParaSaldo = true,
  });

  final String id;
  final Map<String, dynamic> raw;
  final double valor;
  final String tipo;
  final String descricao;
  final String categoria;
  final DateTime? data;
  final String contaId;
  final String contaDestinoId;
  final String comprovanteUrl;
  final bool efetivadoParaSaldo;

  static BlindFinanceLancamento fromFirestore({
    required String id,
    Map<String, dynamic>? data,
  }) {
    final map = Map<String, dynamic>.from(data ?? const {});
    final valorRaw = map['amount'] ??
        map['valor'] ??
        map['VALOR'] ??
        map['value'];
    return BlindFinanceLancamento(
      id: id.trim().isEmpty ? 'lancamento' : id.trim(),
      raw: map,
      valor: financeParseValorBr(valorRaw),
      tipo: financeInferTipo(map),
      descricao: FirestoreMapFields.pickString(
        map,
        const ['descricao', 'description', 'titulo', 'title', 'nome'],
      ),
      categoria: FirestoreMapFields.pickString(
        map,
        const ['categoria', 'category', 'CATEGORIA'],
      ),
      data: financeLancamentoDate(map),
      contaId: FirestoreMapFields.pickString(
        map,
        const ['contaId', 'conta_id', 'accountId'],
      ),
      contaDestinoId: financeContaDestinoReceitaId(map),
      comprovanteUrl: FirestoreMapFields.pickString(
        map,
        const [
          'comprovanteUrl',
          'comprovante_url',
          'receiptUrl',
          'urlComprovante',
        ],
      ),
      efetivadoParaSaldo: financeLancamentoEfetivadoParaSaldo(map),
    );
  }

  static BlindFinanceLancamento fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) =>
      fromFirestore(id: d.id, data: d.data());
}
