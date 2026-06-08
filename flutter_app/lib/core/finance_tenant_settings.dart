import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Configurações do financeiro por igreja — doc `igrejas/{id}/config/finance_settings`.
class FinanceTenantSettings {
  final double limiteAprovacaoDespesa;
  final Map<String, double> orcamentosDespesa;

  const FinanceTenantSettings({
    this.limiteAprovacaoDespesa = 0,
    this.orcamentosDespesa = const {},
  });

  static DocumentReference<Map<String, dynamic>> docRef(String tenantId) =>
                ChurchOperationalPaths.churchDoc(tenantId)
          .collection('config')
          .doc('finance_settings');

  static FinanceTenantSettings _fromDocData(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return const FinanceTenantSettings();
    final lim = m['limiteAprovacaoDespesa'];
    final orc = m['orcamentosDespesa'];
    final map = <String, double>{};
    if (orc is Map) {
      for (final e in orc.entries) {
        final v = e.value;
        final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
        if (n > 0) map[e.key.toString().trim()] = n;
      }
    }
    return FinanceTenantSettings(
      limiteAprovacaoDespesa:
          lim is num ? lim.toDouble() : (double.tryParse('$lim') ?? 0),
      orcamentosDespesa: map,
    );
  }

  static bool _hasMeaningfulSettings(FinanceTenantSettings s) =>
      s.limiteAprovacaoDespesa > 0 || s.orcamentosDespesa.isNotEmpty;

  static Future<FinanceTenantSettings> load(String tenantId) async {
    final primary = tenantId.trim();
    if (primary.isEmpty) return const FinanceTenantSettings();

    Future<FinanceTenantSettings> readFor(String tid) async {
      try {
        final d = await docRef(tid).get(
          const GetOptions(source: Source.serverAndCache),
        );
        if (!d.exists) return const FinanceTenantSettings();
        return _fromDocData(d.data());
      } catch (_) {
        return const FinanceTenantSettings();
      }
    }

    try {
      final hit = await readFor(primary);
      if (_hasMeaningfulSettings(hit)) return hit;

      List<String> siblings;
      try {
        siblings = await TenantResolverService.getAllRelatedIgrejaDocIds(primary);
      } catch (_) {
        siblings = const [];
      }
      for (final sid in TenantResolverService.orderedSiblingsForReadFallback(
        primary,
        siblings,
        maxExtra: 6,
      )) {
        final alt = await readFor(sid);
        if (_hasMeaningfulSettings(alt)) return alt;
      }
      return hit;
    } catch (_) {
      return const FinanceTenantSettings();
    }
  }

  Future<void> save(String tenantId) async {
    await ensureFirebaseReadyForPublishUpload();
    await firebaseDefaultAuth.currentUser?.getIdToken(true);
    await docRef(tenantId).set(
      {
        'limiteAprovacaoDespesa': limiteAprovacaoDespesa,
        'orcamentosDespesa': orcamentosDespesa,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
