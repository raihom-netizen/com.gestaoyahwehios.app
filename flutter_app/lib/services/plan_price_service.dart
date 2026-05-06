import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';

/// Configuração efetiva de um plano: Firestore `config/plans/items/{planId}` sobrescreve [planosOficiais].
class EffectivePlanConfig {
  final String id;
  final String name;
  final String members;
  final int maxMembers;
  final double? monthlyPrice;
  /// Valor anual usado na UI (Firestore ou 10× mensal do plano base).
  final double? annualPrice;
  final bool featured;
  final String? note;

  const EffectivePlanConfig({
    required this.id,
    required this.name,
    required this.members,
    required this.maxMembers,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.featured,
    this.note,
  });

  /// Para widgets que já esperam [PlanoOficial] (preços na UI podem usar [annualPrice] separado).
  PlanoOficial toPlanoOficial() => PlanoOficial(
        id: id,
        name: name,
        members: members,
        maxMembers: maxMembers,
        monthlyPrice: monthlyPrice,
        featured: featured,
        note: note,
      );

  static EffectivePlanConfig merge(PlanoOficial base, Map<String, dynamic>? data) {
    double? monthly = base.monthlyPrice;
    double? annual = base.annualPrice;
    var name = base.name;
    var members = base.members;
    var maxMembers = base.maxMembers;
    String? note = base.note;

    if (data != null) {
      final pm = data['priceMonthly'];
      if (pm is num) monthly = pm.toDouble();
      final pa = data['priceAnnual'];
      if (pa is num) annual = pa.toDouble();
      final mm = data['maxMembers'];
      if (mm is int) {
        maxMembers = mm;
      } else if (mm is num) {
        maxMembers = mm.round();
      }
      final n = data['name'];
      if (n is String && n.trim().isNotEmpty) name = n.trim();
      final mem = data['members'];
      if (mem is String && mem.trim().isNotEmpty) members = mem.trim();
      final nt = data['note'];
      if (nt is String && nt.trim().isNotEmpty) note = nt.trim();
    }

    return EffectivePlanConfig(
      id: base.id,
      name: name,
      members: members,
      maxMembers: maxMembers,
      monthlyPrice: monthly,
      annualPrice: annual,
      featured: base.featured,
      note: note,
    );
  }
}

/// Preços e metadados de planos a partir do Firestore + defaults em [planosOficiais].
class PlanPriceService {
  static final _firestore = FirebaseFirestore.instance;
  static const _cacheDuration = Duration(minutes: 2);
  static DateTime? _lastFetch;
  static Map<String, EffectivePlanConfig>? _cache;

  /// Catálogo efetivo indexado por `planId` (só planos em [planosOficiais]).
  static Future<Map<String, EffectivePlanConfig>> getEffectivePlanConfigs() async {
    if (_cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return _cache!;
    }
    final fsData = <String, Map<String, dynamic>>{};
    try {
      final snap =
          await _firestore.collection('config').doc('plans').collection('items').get();
      for (final d in snap.docs) {
        fsData[d.id] = d.data();
      }
      final result = <String, EffectivePlanConfig>{};
      for (final p in planosOficiais) {
        result[p.id] = EffectivePlanConfig.merge(p, fsData[p.id]);
      }
      _cache = result;
      _lastFetch = DateTime.now();
      return _cache!;
    } catch (_) {
      final fallback = <String, EffectivePlanConfig>{
        for (final p in planosOficiais) p.id: EffectivePlanConfig.merge(p, null),
      };
      return fallback;
    }
  }

  /// Compatível com código legado: só preços mensal/anual efetivos.
  static Future<Map<String, ({double? monthly, double? annual})>> getEffectivePrices() async {
    final cfg = await getEffectivePlanConfigs();
    return {
      for (final e in cfg.entries)
        e.key: (monthly: e.value.monthlyPrice, annual: e.value.annualPrice),
    };
  }

  /// Invalida cache (ex.: após o master gravar em `config/plans/items`).
  static void invalidateCache() {
    _cache = null;
    _lastFetch = null;
  }
}
