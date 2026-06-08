import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Caminhos Firestore `igrejas/{id}/…` com ID **operacional** (cluster canónico).
///
/// Usar em **todos** os módulos (painel igreja, master, web/Android/iOS) antes de
/// `.get()`, `.watchSafe()` ou writes que dependem do doc com dados reais.
abstract final class ChurchOperationalPaths {
  ChurchOperationalPaths._();

  static String? get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid;

  static final Map<String, Future<String>> _resolveInflight = {};
  static final Map<String, String> _resolvedMemory = {};

  static String _cacheKey(String seed, String? userUid) =>
      '${(userUid ?? _currentUid ?? '').trim()}\x00${seed.trim()}';

  /// Resolve slug/legado/`_sistema` → doc canónico do cluster.
  static Future<String> resolve(
    String seed, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final s = seed.trim();
    if (s.isEmpty) return s;
    if (forceRefresh) {
      invalidateResolved(seed, userUid: userUid);
    }
    return resolveCached(s, userUid: userUid);
  }

  /// Dedupe awaits na mesma sessão/ecrã.
  static Future<String> resolveCached(
    String seed, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final s = seed.trim();
    if (s.isEmpty) return s;
    final key = _cacheKey(s, userUid);
    if (forceRefresh) {
      _resolveInflight.remove(key);
      _resolvedMemory.remove(key);
    }
    final mem = _resolvedMemory[key];
    if (mem != null && mem.isNotEmpty) return mem;

    final inflight = _resolveInflight[key];
    if (inflight != null) return inflight;

    final future = _resolveOperational(s, userUid: userUid);
    _resolveInflight[key] = future;
    try {
      final op = await future;
      if (op.isNotEmpty) _resolvedMemory[key] = op;
      return op;
    } finally {
      _resolveInflight.remove(key);
    }
  }

  static Future<String> _resolveOperational(
    String seed, {
    String? userUid,
  }) async {
    try {
      return await TenantResolverService.resolveOperationalChurchDocId(
        seed,
        userUid: userUid ?? _currentUid,
      );
    } catch (_) {
      return seed;
    }
  }

  static void invalidateResolved(String seed, {String? userUid}) {
    final key = _cacheKey(seed.trim(), userUid);
    _resolveInflight.remove(key);
    _resolvedMemory.remove(key);
    TenantResolverService.invalidateOperationalChurchDocCache(
      seedId: seed.trim(),
      userUid: userUid ?? _currentUid,
    );
  }

  static void clearSessionCache() {
    _resolveInflight.clear();
    _resolvedMemory.clear();
  }

  /// Referência com ID **já resolvido** (preferir após [resolveCached]).
  static DocumentReference<Map<String, dynamic>> churchDoc(String operationalId) =>
      firebaseDefaultFirestore.collection('igrejas').doc(operationalId.trim());

  static Future<DocumentReference<Map<String, dynamic>>> churchDocResolved(
    String seed, {
    String? userUid,
  }) async =>
      churchDoc(await resolveCached(seed, userUid: userUid));

  static Future<CollectionReference<Map<String, dynamic>>> subcollectionResolved(
    String seed,
    String subcollection, {
    String? userUid,
  }) async =>
      (await churchDocResolved(seed, userUid: userUid)).collection(subcollection);

  static Future<DocumentReference<Map<String, dynamic>>> subDocResolved(
    String seed,
    String subcollection,
    String docId, {
    String? userUid,
  }) async =>
      (await subcollectionResolved(seed, subcollection, userUid: userUid))
          .doc(docId.trim());

  /// Perfil da igreja (cadastro) — servidor + cache.
  static Future<Map<String, dynamic>> loadChurchProfileMap(
    String seed, {
    String? userUid,
    bool preferServer = false,
  }) async {
    final tid = await resolveModuleReadTenantId(seed, userUid: userUid);
    if (tid.isEmpty) return {};
    return TenantResolverService.loadIgrejaCadastroDocDirect(
      tid,
      preferServer: preferServer,
    );
  }

  /// Resolve slug/legado → doc canónico + doc com subcoleções reais (leituras).
  static Future<String> resolveModuleReadTenantId(
    String seed, {
    String? userUid,
  }) =>
      TenantResolverService.resolveModuleReadTenantId(
        seed,
        userUid: userUid ?? _currentUid,
      );

  /// IDs do cluster (canónico + irmãos) para leituras master / migração.
  static Future<List<String>> clusterDocIds(String seed) async {
    final canonical = await resolve(seed);
    if (canonical.isEmpty) return const [];
    try {
      final related =
          await TenantResolverService.getAllRelatedIgrejaDocIds(canonical);
      final out = <String>{canonical, ...related};
      return out.toList();
    } catch (_) {
      return [canonical];
    }
  }

  static Future<void> preparePanelRead({bool refreshToken = false}) =>
      ChurchTenantResilientReads.preparePanelRead(refreshToken: refreshToken);

  /// Contexto completo (alias → canónico + perfil) — Regra 3.
  static Future<({
    String canonicalId,
    String seedId,
    String? resolvedAlias,
    Map<String, dynamic> profile,
  })> resolveOperationalChurch(
    String seed, {
    String? userUid,
    bool forceRefresh = false,
  }) =>
      TenantResolverService.resolveOperationalChurch(
        seed,
        userUid: userUid ?? _currentUid,
        forceRefresh: forceRefresh,
      );
}
