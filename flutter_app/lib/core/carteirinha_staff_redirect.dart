import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Papéis que podem ir ao painel ao ler o QR da carteirinha (mesma lógica do acesso web ao painel).
bool carteirinhaPainelStaffRole(String roleLower) {
  const staff = {
    'adm',
    'admin',
    'administrador',
    'administradora',
    'gestor',
    'master',
    'lider',
    'secretario',
    'pastor',
    'presbitero',
    'diacono',
    'evangelista',
    'musico',
    'tesoureiro',
    'tesouraria',
    'pastor_auxiliar',
    'pastor_presidente',
    'lider_departamento',
  };
  return staff.contains(roleLower.trim().toLowerCase());
}

/// Verifica se o utilizador autenticado gere a mesma igreja que o QR (aliases / slug).
Future<bool> carteirinhaUserTenantMatchesQr({
  required String qrTenantId,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  final raw = qrTenantId.trim();
  if (raw.isEmpty) return false;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data() ?? {};
    var userTid =
        (data['tenantId'] ?? data['igrejaId'] ?? '').toString().trim();
    if (userTid.isEmpty) return false;
    userTid = await TenantResolverService.resolveEffectiveTenantId(userTid);
    final related =
        await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(userTid);
    if (related.contains(raw)) return true;
    final qrResolved =
        await TenantResolverService.resolveEffectiveTenantId(raw);
    if (related.contains(qrResolved)) return true;
    return userTid == raw || userTid == qrResolved;
  } catch (_) {
    return false;
  }
}
