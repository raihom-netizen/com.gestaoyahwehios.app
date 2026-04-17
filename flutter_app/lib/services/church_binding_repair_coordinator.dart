import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Evita chamadas repetidas a [repairMyChurchBinding] (login + abertura do app) e
/// permite saltar a função quando claims + `users/{uid}` já estão alinhados.
class ChurchBindingRepairCoordinator {
  ChurchBindingRepairCoordinator._();

  /// Janela (D): não voltar a chamar repair se acabou de correr com sucesso.
  static const Duration recentSuccessWindow = Duration(minutes: 5);

  static const _prefKeyPrefix = 'repair_church_binding_ok_ms_';

  static String _key(String uid) => '$_prefKeyPrefix$uid';

  static Future<bool> shouldSkipRepairDueToRecentSuccess(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(uid));
    if (ms == null) return false;
    final last = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now().difference(last) < recentSuccessWindow;
  }

  static Future<void> recordRepairSuccess(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(uid), DateTime.now().millisecondsSinceEpoch);
  }

  static String _tenantFromClaims(Map<String, dynamic> claims) {
    return (claims['igrejaId'] ?? claims['tenantId'] ?? '').toString().trim();
  }

  static String _tenantFromUserDoc(Map<String, dynamic> data) {
    return (data['igrejaId'] ?? data['tenantId'] ?? '').toString().trim();
  }

  /// (A) Conservador: token já tem igreja/tenant e `users/{uid}` confirma o mesmo vínculo.
  /// Se a leitura falhar ou houver divergência, devolve false (o caller corre o repair).
  static Future<bool> conservativeChurchBindingLooksOk(User user) async {
    try {
      final token = await user.getIdTokenResult(false);
      final fromClaims = _tenantFromClaims(token.claims ?? {});
      if (fromClaims.isEmpty) return false;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!snap.exists) return false;
      final fromDoc = _tenantFromUserDoc(snap.data() ?? {});
      if (fromDoc.isEmpty) return false;

      if (fromClaims == fromDoc) return true;

      final resolvedClaim =
          await TenantResolverService.resolveEffectiveTenantId(fromClaims);
      final resolvedDoc =
          await TenantResolverService.resolveEffectiveTenantId(fromDoc);
      return resolvedClaim.isNotEmpty && resolvedClaim == resolvedDoc;
    } catch (_) {
      return false;
    }
  }
}
