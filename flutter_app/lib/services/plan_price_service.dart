import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

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
///
/// O painel Master grava em `config/plans/items`. A UI de divulgação, login e renovação
/// deve usar [watchEffectivePlanConfigs] para refletir alterações sem novo deploy nem
/// esperar cache. Serviços pontuais podem usar [getEffectivePlanConfigs] (leitura única).
class PlanPriceService {
  static final _firestore = FirebaseFirestore.instance;

  static Map<String, EffectivePlanConfig> _mergeCatalogFromQuerySnap(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final fsData = {for (final d in snap.docs) d.id: d.data()};
    final result = <String, EffectivePlanConfig>{};
    for (final p in planosOficiais) {
      result[p.id] = EffectivePlanConfig.merge(p, fsData[p.id]);
    }
    return result;
  }

  /// Emite o catálogo sempre que `config/plans/items` muda (Painel Master ou outro cliente).
  static Stream<Map<String, EffectivePlanConfig>> watchEffectivePlanConfigs() {
    final q = _firestore
        .collection('config')
        .doc('plans')
        .collection('items');
    if (kIsWeb) {
      return FirestoreStreamUtils.queryOneShot(q).asyncMap((snap) async {
        try {
          return _mergeCatalogFromQuerySnap(snap);
        } catch (_) {
          final fb = await getEffectivePlanConfigs();
          return fb;
        }
      });
    }
    return FirestoreStreamUtils.queryWatchBootstrap(q)
        .map(_mergeCatalogFromQuerySnap);
  }

  /// Leitura única (ex.: limites de membros). Para ecrãs com preços visíveis, prefira [watchEffectivePlanConfigs].
  static Future<Map<String, EffectivePlanConfig>> getEffectivePlanConfigs() async {
    try {
      final snap = await FirestoreReadResilience.getQuery(
        _firestore
            .collection('config')
            .doc('plans')
            .collection('items'),
        cacheKey: 'config_plans_items',
      );
      return _mergeCatalogFromQuerySnap(snap);
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

  /// Compatível com ecrãs que invalidavam cache após gravar no Master (o stream atualiza sozinho).
  static void invalidateCache() {}
}
