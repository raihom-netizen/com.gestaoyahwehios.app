import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';

/// Configurações do financeiro por igreja — doc `igrejas/{id}/config/finance_settings`.
class FinanceTenantSettings {
  final double limiteAprovacaoDespesa;
  final Map<String, double> orcamentosDespesa;

  const FinanceTenantSettings({
    this.limiteAprovacaoDespesa = 0,
    this.orcamentosDespesa = const {},
  });

  static DocumentReference<Map<String, dynamic>> docRef(String tenantId) =>
      ChurchRepository.churchDoc(tenantId)
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
    final primary = ChurchPanelTenant.resolve(tenantId.trim());
    if (primary.isEmpty) return const FinanceTenantSettings();

    try {
      final d = await docRef(primary)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(ChurchPanelReadTimeouts.attempt);
      if (!d.exists) return const FinanceTenantSettings();
      return _fromDocData(d.data());
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
