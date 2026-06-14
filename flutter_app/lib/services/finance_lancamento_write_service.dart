import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'package:gestao_yahweh/core/finance_saldo_policy.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Gravação atómica de lançamento + ajuste de `saldo` nas contas (quando efetivado).
abstract final class FinanceLancamentoWriteService {
  FinanceLancamentoWriteService._();

  static double _readSaldo(Map<String, dynamic>? data) {
    if (data == null) return 0;
    return financeParseValorBr(data['saldo'] ?? data['balance'] ?? 0);
  }

  static Map<String, double> _deltasForPayload(Map<String, dynamic> data) {
    if (!financeLancamentoEfetivadoParaSaldo(data)) return const {};
    final tipo = financeInferTipo(data);
    final valor = financeParseValorBr(data['amount'] ?? data['valor']);
    if (valor <= 0) return const {};

    final out = <String, double>{};
    if (tipo == 'transferencia') {
      final origem = (data['contaOrigemId'] ?? '').toString().trim();
      final destino = (data['contaDestinoId'] ?? '').toString().trim();
      if (origem.isNotEmpty) out[origem] = (out[origem] ?? 0) - valor;
      if (destino.isNotEmpty) out[destino] = (out[destino] ?? 0) + valor;
      return out;
    }
    if (tipo.contains('entrada') || tipo.contains('receita')) {
      final destino = financeContaDestinoReceitaId(data);
      if (destino.isNotEmpty) out[destino] = (out[destino] ?? 0) + valor;
      return out;
    }
    final origem = (data['contaOrigemId'] ?? '').toString().trim();
    if (origem.isNotEmpty) out[origem] = (out[origem] ?? 0) - valor;
    return out;
  }

  static Map<String, double> _netDelta({
    Map<String, dynamic>? previous,
    required Map<String, dynamic> next,
  }) {
    final net = <String, double>{};
    if (previous != null) {
      for (final e in _deltasForPayload(previous).entries) {
        net[e.key] = (net[e.key] ?? 0) - e.value;
      }
    }
    for (final e in _deltasForPayload(next).entries) {
      net[e.key] = (net[e.key] ?? 0) + e.value;
    }
    net.removeWhere((_, v) => v == 0);
    return net;
  }

  static Future<void> commitInTransaction({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> lancamentoRef,
    required Map<String, dynamic> payload,
    required bool merge,
    Map<String, dynamic>? previousPayload,
  }) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) {
      throw StateError('Igreja não identificada para gravar lançamento.');
    }

    final deltas = _netDelta(previous: previousPayload, next: payload);
    final contasCol = ChurchUiCollections.churchDoc(cid).collection('contas');

    Future<void> runTxn() => firebaseDefaultFirestore.runTransaction((tx) async {
      for (final entry in deltas.entries) {
        final contaRef = contasCol.doc(entry.key);
        final snap = await tx.get(contaRef);
        if (!snap.exists) continue;
        final saldo = _readSaldo(snap.data());
        tx.update(contaRef, {
          'saldo': saldo + entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (merge) {
        tx.set(lancamentoRef, payload, SetOptions(merge: true));
      } else {
        tx.set(lancamentoRef, payload);
      }
    });

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      await FirestoreWebGuard.runWithWebRecovery(runTxn, maxAttempts: 4);
    } else {
      await runTxn();
    }
  }
}
