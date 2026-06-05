import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Configurações do financeiro por igreja — doc `igrejas/{id}/config/finance_settings`.
class FinanceTenantSettings {
  final double limiteAprovacaoDespesa;
  final Map<String, double> orcamentosDespesa;

  const FinanceTenantSettings({
    this.limiteAprovacaoDespesa = 0,
    this.orcamentosDespesa = const {},
  });

  static DocumentReference<Map<String, dynamic>> docRef(String tenantId) =>
      firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection('config')
          .doc('finance_settings');

  static Future<FinanceTenantSettings> load(String tenantId) async {
    try {
      final d = await docRef(tenantId).get(
        const GetOptions(source: Source.serverAndCache),
      );
      if (!d.exists) return const FinanceTenantSettings();
      final m = d.data() ?? {};
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
        limiteAprovacaoDespesa: lim is num
            ? lim.toDouble()
            : (double.tryParse('$lim') ?? 0),
        orcamentosDespesa: map,
      );
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
