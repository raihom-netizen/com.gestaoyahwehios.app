import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_profile_loader.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart'
    show TenantResolverService;

/// Caminhos Firestore `igrejas/{churchId}/…` — **só** [ChurchRepository.churchId].
///
/// Painel igreja: sem tenant/alias/slug resolver. Legado isolado em
/// [TenantResolverService] (site público / ADM / migração).
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

    if (!forceRefresh) {
      final ctx = ChurchContextService.currentChurchId;
      if (ctx != null && ctx.isNotEmpty) {
        if (s == ctx ||
            s == ChurchContextService.seedId ||
            _resolvedMemory[_cacheKey(s, userUid)] == ctx) {
          return ctx;
        }
      }
    }

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
    final id = ChurchRepository.churchId(seed);
    if (id.isNotEmpty) return id;
    return seed.trim();
  }

  static void invalidateResolved(String seed, {String? userUid}) {
    final key = _cacheKey(seed.trim(), userUid);
    _resolveInflight.remove(key);
    _resolvedMemory.remove(key);
  }

  static void clearSessionCache() {
    _resolveInflight.clear();
    _resolvedMemory.clear();
  }

  /// Após [TenantResolverService.resolveModuleReadTenantId] no shell — evita re-resolver em cada módulo.
  static void rememberResolved(
    String seed,
    String operationalId, {
    String? userUid,
  }) {
    final op = operationalId.trim();
    if (op.isEmpty) return;
    final s = seed.trim();
    _resolvedMemory[_cacheKey(s, userUid)] = op;
    if (op != s) {
      _resolvedMemory[_cacheKey(op, userUid)] = op;
    }
  }

  /// ID operacional em memória/contexto — mesmo critério Membros/Android.
  static String syncEffectiveChurchId(String seedOrOperational) {
    final panel = ChurchContextService.panelChurchId(seedOrOperational);
    if (panel.isNotEmpty) return panel;
    final mem = _resolvedMemory[_cacheKey(seedOrOperational.trim(), _currentUid)];
    if (mem != null && mem.isNotEmpty) return mem;
    return seedOrOperational.trim();
  }

  /// Referência `igrejas/{churchId}` — delega a [ChurchRepository] (API única).
  static DocumentReference<Map<String, dynamic>> churchDoc(String operationalId) =>
      ChurchRepository.churchDoc(operationalId);

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
    try {
      final result = await ChurchRepository.loadChurchData(
        seedTenantId: seed,
        userUid: userUid,
        forceRefresh: preferServer,
        directDocOnly: true,
      );
      return result.data;
    } on ChurchRepositoryException {
      rethrow;
    }
  }

  /// Resolve slug/legado → doc canónico + doc com subcoleções reais (leituras).
  static Future<String> resolveModuleReadTenantId(
    String seed, {
    String? userUid,
  }) {
    final ctx = ChurchContextService.currentChurchId;
    if (ctx != null && ctx.isNotEmpty) {
      return Future.value(ctx);
    }
    final id = ChurchRepository.churchId(seed);
    return Future.value(id.isNotEmpty ? id : seed.trim());
  }

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
