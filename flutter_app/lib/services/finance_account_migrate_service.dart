import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/finance_lancamento_write_service.dart';

/// Migração de lançamentos entre contas — padrão Controle Total, com ajuste de `saldo`.
abstract final class FinanceAccountMigrateService {
  FinanceAccountMigrateService._();

  static bool semContaLancamento(Map<String, dynamic> d) {
    final tipo = financeInferTipo(d);
    if (tipo == 'transferencia') return false;
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      return financeContaDestinoReceitaId(d).isEmpty;
    }
    if (tipo.contains('saida') || tipo.contains('despesa')) {
      return (d['contaOrigemId'] ?? '').toString().trim().isEmpty;
    }
    return false;
  }

  static bool lancamentoVinculadoConta(
    Map<String, dynamic> d, {
    required String contaId,
  }) {
    final src = contaId.trim();
    if (src.isEmpty) return false;
    final tipo = financeInferTipo(d);
    if (tipo == 'transferencia') {
      final o = (d['contaOrigemId'] ?? '').toString().trim();
      final dest = (d['contaDestinoId'] ?? '').toString().trim();
      return o == src || dest == src;
    }
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      return financeContaDestinoReceitaId(d) == src;
    }
    return (d['contaOrigemId'] ?? '').toString().trim() == src;
  }

  static Map<String, dynamic>? buildMigratedPayload({
    required Map<String, dynamic> previous,
    required String destAccountId,
    required String destAccountName,
    String? sourceAccountId,
  }) {
    final dest = destAccountId.trim();
    final destNome = destAccountName.trim();
    if (dest.isEmpty) return null;

    final next = Map<String, dynamic>.from(previous);
    final tipo = financeInferTipo(previous);
    final src = (sourceAccountId ?? '').trim();

    if (src.isEmpty) {
      if (tipo == 'transferencia') return null;
      if (tipo.contains('entrada') || tipo.contains('receita')) {
        next['contaDestinoId'] = dest;
        next['contaDestinoNome'] = destNome;
      } else if (tipo.contains('saida') || tipo.contains('despesa')) {
        next['contaOrigemId'] = dest;
        next['contaOrigemNome'] = destNome;
      } else {
        return null;
      }
    } else {
      var touched = false;
      if (tipo == 'transferencia') {
        if ((previous['contaOrigemId'] ?? '').toString().trim() == src) {
          next['contaOrigemId'] = dest;
          next['contaOrigemNome'] = destNome;
          touched = true;
        }
        if ((previous['contaDestinoId'] ?? '').toString().trim() == src) {
          next['contaDestinoId'] = dest;
          next['contaDestinoNome'] = destNome;
          touched = true;
        }
      } else if (tipo.contains('entrada') || tipo.contains('receita')) {
        if (financeContaDestinoReceitaId(previous) == src) {
          next['contaDestinoId'] = dest;
          next['contaDestinoNome'] = destNome;
          touched = true;
        }
      } else if (tipo.contains('saida') || tipo.contains('despesa')) {
        if ((previous['contaOrigemId'] ?? '').toString().trim() == src) {
          next['contaOrigemId'] = dest;
          next['contaOrigemNome'] = destNome;
          touched = true;
        }
      }
      if (!touched) return null;
    }

    next['updatedAt'] = FieldValue.serverTimestamp();
    return next;
  }

  /// Aplica migração com recálculo de saldo (chunk ≤ 40 por transação Firestore).
  static Future<int> migrateDocuments({
    required String churchId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String destAccountId,
    required String destAccountName,
    String? sourceAccountId,
  }) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) throw StateError('Igreja não identificada.');

    var applied = 0;
    const chunk = 40;
    for (var i = 0; i < docs.length; i += chunk) {
      final slice = docs.skip(i).take(chunk).toList();
      for (final doc in slice) {
        final prev = doc.data();
        final next = buildMigratedPayload(
          previous: prev,
          destAccountId: destAccountId,
          destAccountName: destAccountName,
          sourceAccountId: sourceAccountId,
        );
        if (next == null) continue;
        await FinanceLancamentoWriteService.commitInTransaction(
          churchId: cid,
          lancamentoRef: doc.reference,
          payload: next,
          merge: true,
          previousPayload: prev,
        );
        applied++;
      }
    }
    return applied;
  }
}

/// Chave de deduplicação de contas (mesmo banco + agência + número, ou mesmo nome).
String financeContaDedupeKey(Map<String, dynamic> d) {
  final nome = (d['nome'] ?? '').toString().trim().toLowerCase();
  final cod = (d['bancoCodigo'] ?? '').toString().trim();
  final ag = (d['agencia'] ?? '').toString().trim();
  final nc = (d['numeroConta'] ?? '').toString().trim();
  if (cod.isNotEmpty && (ag.isNotEmpty || nc.isNotEmpty)) {
    return '$cod|$ag|$nc';
  }
  if (nome.isNotEmpty) return 'nome:$nome';
  return 'id:${(d['nome'] ?? '').hashCode}';
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> dedupeContasDocuments(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final seenActive = <String>{};
  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
  sorted.sort((a, b) {
    final pa = a.data()['contaPrincipal'] == true;
    final pb = b.data()['contaPrincipal'] == true;
    if (pa != pb) return pa ? -1 : 1;
    return a.id.compareTo(b.id);
  });
  for (final d in sorted) {
    if (d.data()['ativo'] == false) {
      out.add(d);
      continue;
    }
    final key = financeContaDedupeKey(d.data());
    if (seenActive.add(key)) out.add(d);
  }
  return out;
}

Future<String?> findDuplicateContaId({
  required CollectionReference<Map<String, dynamic>> col,
  required Map<String, dynamic> payload,
  String? excludeDocId,
}) async {
  final key = financeContaDedupeKey(payload);
  final snap = await col.get();
  for (final d in snap.docs) {
    if (excludeDocId != null && d.id == excludeDocId) continue;
    if (d.data()['ativo'] == false) continue;
    if (financeContaDedupeKey(d.data()) == key) return d.id;
  }
  return null;
}
