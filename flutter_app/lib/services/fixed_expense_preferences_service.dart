import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/constants/app_business_rules.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Preferências de exibição das despesas fixas: contas pendentes e quantos meses à frente.
class FixedExpensePreferencesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _showInPendingKey = 'showInPending';
  static const int _defaultPendingMonthsAhead =
      AppBusinessRules.pendingMonthsAheadDefault;
  static const String _pendingMonthsAheadKey = 'pendingMonthsAhead';

  DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      ChurchUiCollections.config(uid.trim()).doc('fixed_expenses_prefs');

  /// Mostrar parcelas de despesas fixas na lista "Despesas pendentes" (módulo financeiro).
  Future<bool> getShowInPending(String uid) async {
    final snap = await _settingsRef(uid).get();
    final data = snap.data();
    if (data == null) return true;
    return data[_showInPendingKey] as bool? ?? true;
  }

  /// Quantos meses à frente considerar nas despesas pendentes (0 a 12).
  /// 0 = apenas o mês atual, 1 = mês atual + próximo, etc.
  Future<int> getPendingMonthsAhead(String uid) async {
    final snap = await _settingsRef(uid).get();
    final data = snap.data();
    if (data == null) return _defaultPendingMonthsAhead;
    final v = data[_pendingMonthsAheadKey];
    if (v is num) return (v.toInt()).clamp(0, 12);
    return _defaultPendingMonthsAhead;
  }

  /// Salva preferências.
  Future<void> set(String uid,
      {bool? showInPending, int? pendingMonthsAhead}) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (showInPending != null) data[_showInPendingKey] = showInPending;
    if (pendingMonthsAhead != null) {
      data[_pendingMonthsAheadKey] = pendingMonthsAhead.clamp(0, 12);
    }
    await _settingsRef(uid).set(data, SetOptions(merge: true));
  }

  Map<String, dynamic> _mapFrom(Map<String, dynamic>? d) => {
        _showInPendingKey: d?[_showInPendingKey] as bool? ?? true,
        _pendingMonthsAheadKey:
            (d?[_pendingMonthsAheadKey] as num?)?.toInt().clamp(0, 12) ??
                _defaultPendingMonthsAhead,
      };

  /// Stream das preferências (para reagir na UI).
  Stream<Map<String, dynamic>> watch(String uid) {
    // Web: listener ao vivo aqui somava-se aos das outras faixas do Financeiro
    // e disparava "INTERNAL ASSERTION FAILED" no WatchChangeAggregator do SDK
    // (muitos alvos de watch em paralelo). Poll leve substitui sem travar o painel.
    if (FirestoreWebGuard.disableLiveSnapshotsOnWeb) {
      return _pollWatch(uid);
    }
    return _settingsRef(uid).snapshots().map((s) => _mapFrom(s.data()));
  }

  Stream<Map<String, dynamic>> _pollWatch(String uid) async* {
    while (true) {
      try {
        final snap = await _settingsRef(uid).get();
        yield _mapFrom(snap.data());
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 180));
    }
  }
}
