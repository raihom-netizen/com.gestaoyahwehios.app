import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_list_limits.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';

/// Leituras Firestore do tenant (padrão Controle Total): cache → retry → último bom.
///
/// Usar em **todos** os módulos do painel em vez de `.get()` directo.
abstract final class ChurchTenantResilientReads {
  ChurchTenantResilientReads._();

  static String _key(String tenantId, String suffix) =>
      '${tenantId.trim()}_$suffix';

  static DocumentReference<Map<String, dynamic>> _church(String tenantId) =>
      firebaseDefaultFirestore.collection('igrejas').doc(tenantId.trim());

  /// Token + Firestore pronto (leitura do painel, sem health check de upload).
  static Future<void> preparePanelRead({bool refreshToken = false}) async {
    await ensureFirebaseReadyForPanelRead().catchError((_) {});
    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: refreshToken);
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> churchDocument(
    String tenantId,
  ) async {
    await preparePanelRead();
    return FirestoreReadResilience.getDocument(
      _church(tenantId),
      cacheKey: _key(tenantId, 'igreja_doc'),
    );
  }

  /// Iglesia + slug (mural, site público, formulários).
  static Future<({
    String firestoreTenantId,
    String churchSlug,
    Map<String, dynamic> tenantData,
  })> loadTenantBundle(
    String tenantIdHint, {
    String? userUid,
  }) async {
    try {
      await preparePanelRead();
    } catch (_) {
      final fallback = tenantIdHint.trim();
      return (
        firestoreTenantId: fallback,
        churchSlug: fallback,
        tenantData: <String, dynamic>{},
      );
    }
    final tid =
        await TenantResolverService.resolveEffectiveTenantIdPreferringUserBinding(
      tenantIdHint,
      userUid: userUid,
    );
    final snap = await churchDocument(tid);
    final data = snap.data() ?? {};
    final slug = (data['slug'] ?? '').toString().trim();
    final churchSlug = slug.isEmpty ? tid : slug;
    return (
      firestoreTenantId: tid,
      churchSlug: churchSlug,
      tenantData: data,
    );
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> avisosFeed(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) =>
      _orderedQuery(
        tenantId,
        'avisos',
        'createdAt',
        descending: true,
        limit: limit,
        cacheSuffix: 'avisos_feed_$limit',
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> noticiasByStartAt(
    String tenantId, {
    int limit = ChurchTenantListLimits.defaultPageSize,
  }) async {
    final church = _church(tenantId);
    try {
      return await FirestoreReadResilience.getQuery(
        church
            .collection('eventos')
            .orderBy('startAt', descending: true)
            .limit(limit),
        cacheKey: _key(tenantId, 'noticias_start_$limit'),
      );
    } catch (_) {
      return FirestoreReadResilience.getQuery(
        church.collection('eventos').limit(limit),
        cacheKey: _key(tenantId, 'noticias_plain_$limit'),
      );
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> eventCategories(
    String tenantId,
  ) =>
      FirestoreReadResilience.getQuery(
        _church(tenantId).collection('event_categories'),
        cacheKey: _key(tenantId, 'event_categories'),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> pedidosOracao(
    String tenantId, {
    bool? respondidaFilter,
    int limit = 300,
  }) async {
    final col = _church(tenantId).collection('pedidosOracao');
    late final Query<Map<String, dynamic>> q;
    late final String suffix;
    if (respondidaFilter == true) {
      q = col
          .where('respondida', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      suffix = 'respondidas';
    } else if (respondidaFilter == false) {
      q = col
          .where('respondida', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      suffix = 'pendentes';
    } else {
      q = col.orderBy('createdAt', descending: true).limit(limit);
      suffix = 'all';
    }
    return FirestoreReadResilience.getQuery(
      q,
      cacheKey: _key(tenantId, 'pedidos_oracao_$suffix'),
    );
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> visitantes(
    String tenantId, {
    int limit = 400,
  }) =>
      _orderedQuery(
        tenantId,
        'visitantes',
        'createdAt',
        descending: true,
        limit: limit,
        cacheSuffix: 'visitantes_$limit',
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> membrosRecent(
    String tenantId, {
    int limit = 220,
  }) async {
    final church = _church(tenantId);
    try {
      return await FirestoreReadResilience.getQuery(
        church
            .collection('membros')
            .orderBy('updatedAt', descending: true)
            .limit(limit),
        cacheKey: _key(tenantId, 'membros_updated_$limit'),
      );
    } catch (_) {
      return FirestoreReadResilience.getQuery(
        church.collection('membros').limit(limit),
        cacheKey: _key(tenantId, 'membros_plain_$limit'),
      );
    }
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> departamentos(
    String tenantId, {
    int limit = 80,
  }) =>
      FirestoreReadResilience.getQuery(
        _church(tenantId).collection('departamentos').limit(limit),
        cacheKey: _key(tenantId, 'departamentos_$limit'),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> financeRecent(
    String tenantId, {
    int limit = 250,
  }) =>
      _orderedQuery(
        tenantId,
        'finance',
        'createdAt',
        descending: true,
        limit: limit,
        cacheSuffix: 'finance_$limit',
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> patrimonio(
    String tenantId, {
    int limit = 250,
  }) =>
      FirestoreReadResilience.getQuery(
        _church(tenantId).collection('patrimonio').limit(limit),
        cacheKey: _key(tenantId, 'patrimonio_$limit'),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> contas(
    String tenantId, {
    int limit = 80,
  }) =>
      _orderedQuery(
        tenantId,
        'contas',
        'nome',
        descending: false,
        limit: limit,
        cacheSuffix: 'contas_$limit',
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> fornecedores(
    String tenantId, {
    int limit = 200,
  }) =>
      FirestoreReadResilience.getQuery(
        _church(tenantId).collection('fornecedores').limit(limit),
        cacheKey: _key(tenantId, 'fornecedores_$limit'),
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> escalasRecent(
    String tenantId, {
    int limit = 120,
  }) =>
      _orderedQuery(
        tenantId,
        'escalas',
        'date',
        descending: true,
        limit: limit,
        cacheSuffix: 'escalas_$limit',
      );

  static Future<DocumentSnapshot<Map<String, dynamic>>> panelCacheSummary(
    String tenantId,
  ) =>
      FirestoreReadResilience.getDocument(
        _church(tenantId).collection('_panel_cache').doc('dashboard_summary'),
        cacheKey: _key(tenantId, 'panel_cache_summary'),
      );

  /// Stream do painel / feeds — erros de rede não derrubam o módulo.
  static Stream<QuerySnapshot<Map<String, dynamic>>> querySnapshotsResilient(
    Query<Map<String, dynamic>> query,
  ) =>
      FirestoreStreamUtils.resilientQuery(query.snapshots());

  static Future<QuerySnapshot<Map<String, dynamic>>> _orderedQuery(
    String tenantId,
    String subcollection,
    String orderField, {
    required bool descending,
    required int limit,
    required String cacheSuffix,
  }) async {
    await preparePanelRead();
    return FirestoreReadResilience.getQuery(
      _church(tenantId)
          .collection(subcollection)
          .orderBy(orderField, descending: descending)
          .limit(limit),
      cacheKey: _key(tenantId, cacheSuffix),
    );
  }
}
