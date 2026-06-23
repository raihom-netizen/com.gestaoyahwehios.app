import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/master_admin_firestore.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

enum MultiTenantCheckStatus { ok, warn, error, loading }

class MultiTenantCheckResult {
  final String id;
  final String label;
  final MultiTenantCheckStatus status;
  final String detail;

  const MultiTenantCheckResult({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
  });
}

/// DiagnÃ³stico Multi-Tenant â€” Regra 7 (Painel Master).
abstract final class MultiTenantDiagnosticService {
  MultiTenantDiagnosticService._();

  static Future<List<MultiTenantCheckResult>> runFull({
    String? churchSeedId,
  }) async {
    final results = <MultiTenantCheckResult>[];
    final user = firebaseDefaultAuth.currentUser;
    final uid = user?.uid ?? '';

    results.add(await _checkAuth(user));
    if (uid.isEmpty) return results;

    results.add(await _checkUserDoc(uid));

    var seed = (churchSeedId ?? '').trim();
    if (seed.isEmpty) {
      try {
        final u = await firebaseDefaultFirestore.collection('users').doc(uid).get();
        seed = (u.data()?['igrejaId'] ?? u.data()?['tenantId'] ?? '')
            .toString()
            .trim();
      } catch (_) {}
    }

    if (seed.isEmpty) {
      results.add(const MultiTenantCheckResult(
        id: 'church_seed',
        label: 'Igreja de teste',
        status: MultiTenantCheckStatus.warn,
        detail: 'Informe um ID de igreja ou vincule users.igrejaId.',
      ));
      return results;
    }

    results.add(await _checkAlias(seed));
    results.add(await _checkCanonical(seed, uid));
    results.add(await _checkFirestoreRules(seed));
    results.add(await _checkCadastro(seed, uid));
    results.add(await _checkDepartamentos(seed, uid));
    results.add(await _checkCargos(seed, uid));

    return results;
  }

  static Future<MultiTenantCheckResult> _checkAuth(User? user) async {
    if (user == null) {
      return const MultiTenantCheckResult(
        id: 'auth',
        label: 'Firebase Auth',
        status: MultiTenantCheckStatus.error,
        detail: 'Sem sessÃ£o ativa.',
      );
    }
    return MultiTenantCheckResult(
      id: 'auth',
      label: 'Firebase Auth',
      status: MultiTenantCheckStatus.ok,
      detail: '${user.email ?? user.uid}',
    );
  }

  static Future<MultiTenantCheckResult> _checkUserDoc(String uid) async {
    try {
      final snap = await FirestoreReadResilience.getDocument(
        firebaseDefaultFirestore.collection('users').doc(uid),
        cacheKey: 'diag_user_$uid',
      );
      if (!snap.exists) {
        return const MultiTenantCheckResult(
          id: 'users',
          label: 'users/{uid}',
          status: MultiTenantCheckStatus.error,
          detail: 'Documento users ausente.',
        );
      }
      final d = snap.data() ?? {};
      final ig = (d['igrejaId'] ?? '').toString();
      final tn = (d['tenantId'] ?? '').toString();
      final canon = (d['churchCanonicalId'] ?? '').toString();
      return MultiTenantCheckResult(
        id: 'users',
        label: 'users/{uid}',
        status: ig.isNotEmpty ? MultiTenantCheckStatus.ok : MultiTenantCheckStatus.warn,
        detail: 'igrejaId=$ig Â· tenantId=$tn Â· canonical=$canon',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'users',
        label: 'users/{uid}',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkAlias(String seed) async {
    try {
      final id = seed.trim();
      if (id.isEmpty) {
        return const MultiTenantCheckResult(
          id: 'direct_path',
          label: 'igrejas/{churchId}',
          status: MultiTenantCheckStatus.warn,
          detail: 'ID vazio',
        );
      }
      final snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(id)
          .get();
      if (snap.exists) {
        return MultiTenantCheckResult(
          id: 'direct_path',
          label: 'igrejas/{churchId}',
          status: MultiTenantCheckStatus.ok,
          detail: 'igrejas/$id',
        );
      }
      return MultiTenantCheckResult(
        id: 'direct_path',
        label: 'igrejas/{churchId}',
        status: MultiTenantCheckStatus.warn,
        detail: 'Doc nÃ£o encontrado: igrejas/$id',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'direct_path',
        label: 'igrejas/{churchId}',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkCanonical(
    String seed,
    String uid,
  ) async {
    try {
      final ctx = await TenantResolverService.resolveOperationalChurch(
        seed,
        userUid: uid,
      );
      if (ctx.canonicalId.isEmpty) {
        return const MultiTenantCheckResult(
          id: 'canonical',
          label: 'canonicalId',
          status: MultiTenantCheckStatus.error,
          detail: 'Resolver devolveu ID vazio.',
        );
      }
      final synced = await TenantResolverService.syncUserToCanonicalChurchId(
        userUid: uid,
        canonicalId: ctx.canonicalId,
      );
      return MultiTenantCheckResult(
        id: 'canonical',
        label: 'canonicalId',
        status: MultiTenantCheckStatus.ok,
        detail: '${ctx.seedId} â†’ ${ctx.canonicalId}'
            '${synced ? ' Â· users sincronizado' : ''}',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'canonical',
        label: 'canonicalId',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkFirestoreRules(String seed) async {
    try {
      await MasterAdminFirestore.ensureReady();
      final canonical = await TenantResolverService.resolveOperationalChurchDocId(seed);
      final snap = await FirestoreReadResilience.getDocument(
        firebaseDefaultFirestore.collection('igrejas').doc(canonical),
        cacheKey: 'diag_igreja_$canonical',
      );
      if (!snap.exists) {
        return MultiTenantCheckResult(
          id: 'rules',
          label: 'Regras Firestore',
          status: MultiTenantCheckStatus.error,
          detail: 'permission-denied ou igrejas/$canonical inexistente.',
        );
      }
      return MultiTenantCheckResult(
        id: 'rules',
        label: 'Regras Firestore',
        status: MultiTenantCheckStatus.ok,
        detail: 'Leitura igrejas/$canonical OK.',
      );
    } catch (e) {
      final msg = MasterAdminFirestore.formatLoadError(e);
      return MultiTenantCheckResult(
        id: 'rules',
        label: 'Regras Firestore',
        status: msg.contains('permission')
            ? MultiTenantCheckStatus.error
            : MultiTenantCheckStatus.warn,
        detail: msg,
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkCadastro(
    String seed,
    String uid,
  ) async {
    try {
      final profile = await TenantResolverService.loadIgrejaCadastroDocDirect(
        await TenantResolverService.resolveOperationalChurchDocId(seed, userUid: uid),
      );
      final score = TenantResolverService.churchProfileRichnessScore(profile);
      return MultiTenantCheckResult(
        id: 'cadastro',
        label: 'Cadastro igreja',
        status: score >= 4
            ? MultiTenantCheckStatus.ok
            : MultiTenantCheckStatus.warn,
        detail: score >= 4
            ? 'Perfil carregado (score $score).'
            : 'Perfil vazio ou incompleto (score $score).',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'cadastro',
        label: 'Cadastro igreja',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkDepartamentos(
    String seed,
    String uid,
  ) async {
    try {
      final snap = await ChurchTenantResilientReads.departamentos(seed);
      final n = snap.docs.length;
      return MultiTenantCheckResult(
        id: 'departamentos',
        label: 'Departamentos',
        status: n > 0 ? MultiTenantCheckStatus.ok : MultiTenantCheckStatus.warn,
        detail: n > 0 ? '$n departamento(s).' : 'Lista vazia apÃ³s resolver.',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'departamentos',
        label: 'Departamentos',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }

  static Future<MultiTenantCheckResult> _checkCargos(String seed, String uid) async {
    try {
      final snap = await ChurchTenantResilientReads.cargos(seed);
      final n = snap.docs.length;
      return MultiTenantCheckResult(
        id: 'cargos',
        label: 'Cargos',
        status: n > 0 ? MultiTenantCheckStatus.ok : MultiTenantCheckStatus.warn,
        detail: n > 0 ? '$n cargo(s).' : 'Lista vazia apÃ³s resolver.',
      );
    } catch (e) {
      return MultiTenantCheckResult(
        id: 'cargos',
        label: 'Cargos',
        status: MultiTenantCheckStatus.error,
        detail: MasterAdminFirestore.formatLoadError(e),
      );
    }
  }
}

