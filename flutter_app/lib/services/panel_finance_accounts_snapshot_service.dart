import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';

/// Conta bancária com saldo pré-calculado (`_panel_cache/finance_accounts`).
class PanelFinanceAccountBalance {
  const PanelFinanceAccountBalance({
    required this.contaId,
    required this.nome,
    this.bancoNome = '',
    this.tipoConta = '',
    this.saldoAtual = 0,
    this.receitasMes = 0,
    this.despesasMes = 0,
  });

  final String contaId;
  final String nome;
  final String bancoNome;
  final String tipoConta;
  final double saldoAtual;
  final double receitasMes;
  final double despesasMes;

  double get fluxoMes => receitasMes - despesasMes;

  factory PanelFinanceAccountBalance.fromMap(Map<String, dynamic> raw) {
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    return PanelFinanceAccountBalance(
      contaId: (raw['contaId'] ?? '').toString(),
      nome: (raw['nome'] ?? '').toString(),
      bancoNome: (raw['bancoNome'] ?? '').toString(),
      tipoConta: (raw['tipoConta'] ?? '').toString(),
      saldoAtual: n(raw['saldoAtual']),
      receitasMes: n(raw['receitasMes']),
      despesasMes: n(raw['despesasMes']),
    );
  }
}

class PanelFinanceAccountsSnapshot {
  const PanelFinanceAccountsSnapshot({
    this.contas = const [],
    this.saldoTotal = 0,
    this.receitasMesTotal = 0,
    this.despesasMesTotal = 0,
    this.mesReferencia = '',
    this.updatedAt,
  });

  final List<PanelFinanceAccountBalance> contas;
  final double saldoTotal;
  final double receitasMesTotal;
  final double despesasMesTotal;
  final String mesReferencia;
  final Timestamp? updatedAt;

  bool get hasData => contas.isNotEmpty || saldoTotal != 0;

  double get fluxoMesTotal => receitasMesTotal - despesasMesTotal;

  Map<String, double> get saldoPorConta => {
        for (final c in contas) c.contaId: c.saldoAtual,
      };

  factory PanelFinanceAccountsSnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const PanelFinanceAccountsSnapshot();
    }
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    final list = <PanelFinanceAccountBalance>[];
    final contasRaw = raw['contas'];
    if (contasRaw is List) {
      for (final e in contasRaw) {
        if (e is Map) {
          list.add(
            PanelFinanceAccountBalance.fromMap(
              Map<String, dynamic>.from(e),
            ),
          );
        }
      }
    }

    return PanelFinanceAccountsSnapshot(
      contas: list,
      saldoTotal: n(raw['saldoTotal']),
      receitasMesTotal: n(raw['receitasMesTotal']),
      despesasMesTotal: n(raw['despesasMesTotal']),
      mesReferencia: (raw['mesReferencia'] ?? '').toString(),
      updatedAt:
          raw['updatedAt'] is Timestamp ? raw['updatedAt'] as Timestamp : null,
    );
  }
}

abstract final class PanelFinanceAccountsSnapshotService {
  PanelFinanceAccountsSnapshotService._();

  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return ChurchOperationalPaths.churchDoc(tenantId.trim())
        .collection('_panel_cache')
        .doc('finance_accounts');
  }

  static Future<PanelFinanceAccountsSnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const PanelFinanceAccountsSnapshot();
    try {
      final snap = await cacheRef(tid).get();
      return PanelFinanceAccountsSnapshot.fromMap(snap.data());
    } catch (_) {
      return const PanelFinanceAccountsSnapshot();
    }
  }

  static Stream<PanelFinanceAccountsSnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const PanelFinanceAccountsSnapshot());
    }
    return cacheRef(tid).watchSafe().map((snap) {
      return PanelFinanceAccountsSnapshot.fromMap(snap.data());
    });
  }
}
