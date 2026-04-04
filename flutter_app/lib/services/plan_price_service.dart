import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';

/// Preços efetivos por plano: Firestore (config/plans/items) sobrescreve os padrões de [planosOficiais].
class PlanPriceService {
  static final _firestore = FirebaseFirestore.instance;
  static const _cacheDuration = Duration(minutes: 5);
  static DateTime? _lastFetch;
  static Map<String, ({double? monthly, double? annual})>? _cache;

  /// Retorna preço mensal e anual efetivos para cada planId.
  /// Se existir em Firestore, usa; senão usa o padrão de [planosOficiais].
  static Future<Map<String, ({double? monthly, double? annual})>> getEffectivePrices() async {
    if (_cache != null && _lastFetch != null && DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return _cache!;
    }
    final result = <String, ({double? monthly, double? annual})>{};
    for (final p in planosOficiais) {
      result[p.id] = (monthly: p.monthlyPrice, annual: p.annualPrice);
    }
    try {
      final snap = await _firestore.collection('config').doc('plans').collection('items').get();
      for (final d in snap.docs) {
        final data = d.data();
        final id = d.id;
        final cur = result[id];
        if (cur == null) continue;
        final m = data['priceMonthly'];
        final a = data['priceAnnual'];
        result[id] = (
          monthly: m is num ? m.toDouble() : cur.monthly,
          annual: a is num ? a.toDouble() : cur.annual,
        );
      }
      _cache = result;
      _lastFetch = DateTime.now();
    } catch (_) {
      // mantém defaults
    }
    return result;
  }

  /// Invalida cache (ex.: após master salvar novos preços).
  static void invalidateCache() {
    _cache = null;
    _lastFetch = null;
  }
}
