import 'dart:async' show unawaited;



import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/services/church_brand_service.dart';

import 'package:gestao_yahweh/services/church_operational_paths.dart';

import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';



/// Contexto de igreja da sessão — expõe [currentChurchId] a partir de `users/{uid}`.

///

/// SaaS multi-tenant: path **directo** `igrejas/{churchId}/…` — sem alias, slug resolver

/// nem coleção `church_aliases`.

abstract final class ChurchContextService {

  ChurchContextService._();



  static const Duration kResolveTimeout = Duration(seconds: 10);



  static String? _currentChurchId;

  static Map<String, dynamic>? _currentChurchData;

  static String? _seedId;

  static String? _userUid;

  static DateTime? _boundAt;

  static String? _lastError;

  static int? _lastBootstrapMs;



  static String? get currentChurchId {
    final raw = _currentChurchId?.trim();
    if (raw == null || raw.isEmpty) return null;
    return _canonicalizePanelId(raw);
  }



  static Map<String, dynamic>? get currentChurchData =>

      _currentChurchData == null || _currentChurchData!.isEmpty

          ? null

          : Map<String, dynamic>.unmodifiable(_currentChurchData!);



  static String? get seedId => _seedId?.trim().isNotEmpty == true

      ? _seedId!.trim()

      : null;



  static DateTime? get boundAt => _boundAt;

  static String? get lastError => _lastError;

  static int? get lastBootstrapMs => _lastBootstrapMs;



  static String get firestorePath {

    final id = currentChurchId;

    if (id == null || id.isEmpty) return '';

    return 'igrejas/$id';

  }



  static String get storageRoot {

    final id = currentChurchId;

    if (id == null || id.isEmpty) return '';

    return 'igrejas/$id';

  }



  /// ID do painel — contexto bound ou hint do shell (com mapa BPC/slug síncrono).
  static String panelChurchId([String? shellTenantId]) {
    final ctx = currentChurchId;
    if (ctx != null && ctx.isNotEmpty) {
      return _canonicalizePanelId(ctx);
    }
    return _canonicalizePanelId(shellTenantId ?? '');
  }

  static String _canonicalizePanelId(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final mapped = TenantResolverService.mapLegacySeedToCanonical(t);
    if (mapped != null && mapped.isNotEmpty) return mapped;
    return t;
  }



  static Future<bool> _igrejaDocExists(String churchId) async {

    final id = churchId.trim();

    if (id.isEmpty) return false;

    try {

      final snap = await firebaseDefaultFirestore

          .collection('igrejas')

          .doc(id)

          .get(const GetOptions(source: Source.serverAndCache))

          .timeout(kResolveTimeout);

      return snap.exists;

    } catch (_) {

      return false;

    }

  }



  static Future<String?> _churchIdFromUser(String? uid) async {

    final u = uid?.trim();

    if (u == null || u.isEmpty) return null;

    try {

      final snap = await firebaseDefaultFirestore

          .collection('users')

          .doc(u)

          .get(const GetOptions(source: Source.serverAndCache))

          .timeout(kResolveTimeout);

      final data = snap.data();

      if (data == null || data.isEmpty) return null;

      for (final key in const ['igrejaId', 'churchId', 'tenantId']) {

        final v = (data[key] ?? '').toString().trim();

        if (v.isNotEmpty) return v;

      }

    } catch (_) {}

    return null;

  }



  static Future<void> _syncUserDirectChurchId(String uid, String churchId) async {

    final id = churchId.trim();

    if (uid.trim().isEmpty || id.isEmpty) return;

    try {

      final ref = firebaseDefaultFirestore.collection('users').doc(uid);

      final snap = await ref.get(const GetOptions(source: Source.serverAndCache));

      if (!snap.exists) return;

      final stored =

          (snap.data()?['igrejaId'] ?? snap.data()?['tenantId'] ?? '')

              .toString()

              .trim();

      if (stored == id) return;

      await ref.set(

        {

          'igrejaId': id,

          'tenantId': id,

          'churchId': id,

          'churchCanonicalId': id,

          'canonicalTenantId': id,

          'tenantSyncedAt': FieldValue.serverTimestamp(),

        },

        SetOptions(merge: true),

      );

    } catch (_) {}

  }



  static void _applyBind(String churchId, String seed, String? uid) {

    final id = _canonicalizePanelId(churchId);

    _currentChurchId = id;

    _seedId = seed.trim();

    _userUid = uid;

    _boundAt = DateTime.now();

    _lastError = null;

    ChurchOperationalPaths.rememberResolved(seed, id, userUid: uid);

    debugPrint('CHURCH_CONTEXT bound churchId=$id path=igrejas/$id');

  }



  /// Resolve e fixa [currentChurchId] — só aceita doc existente em `igrejas/{churchId}`.

  static Future<String> resolveAndBind({

    required String seed,

    String? userUid,

    bool forceRefresh = false,

  }) async {

    final s = seed.trim();

    if (s.isEmpty) {

      _lastError = 'Seed de igreja vazio.';

      return '';

    }



    final uid = userUid ?? FirebaseAuth.instance.currentUser?.uid;



    if (forceRefresh) {

      clear();

      ChurchOperationalPaths.invalidateResolved(s, userUid: uid);

    }



    if (!forceRefresh &&

        _currentChurchId != null &&

        _currentChurchId!.isNotEmpty &&

        _seedId == s &&

        _userUid == uid) {

      return _currentChurchId!;

    }



    try {
      final tryOrder = <String>[];
      if (s.isNotEmpty) tryOrder.add(s);
      final fromUser = await _churchIdFromUser(uid);
      if (fromUser != null &&
          fromUser.isNotEmpty &&
          !tryOrder.contains(fromUser)) {
        tryOrder.add(fromUser);
      }

      String? boundId;
      for (final candidate in tryOrder) {
        var id = candidate.trim();
        if (id.isEmpty) continue;
        // Sempre preferir doc canónico (BPC/slug legado → igreja_…).
        final mapped = TenantResolverService.mapLegacySeedToCanonical(id);
        if (mapped != null && mapped.isNotEmpty) id = mapped;
        if (!await _igrejaDocExists(id)) continue;
        boundId = id;
        break;
      }

      if (boundId != null && boundId.isNotEmpty) {
        _applyBind(boundId, s, uid);
        if (uid != null && uid.isNotEmpty) {
          await _syncUserDirectChurchId(uid, boundId);
          final synced = await TenantResolverService.syncUserToCanonicalChurchId(
            userUid: uid,
            canonicalId: boundId,
          );
          if (synced) {
            try {
              await FirebaseAuth.instance.currentUser?.getIdToken(true);
            } catch (_) {}
          }
        }
        if (!forceRefresh &&
            (_currentChurchData == null || _currentChurchData!.isEmpty)) {
          final cached = await ChurchPanelLocalCache.readMap(
            churchId: boundId,
            module: ChurchPanelLocalCache.moduleCadastro,
          );
          if (cached != null && cached.isNotEmpty) {
            _currentChurchData = Map<String, dynamic>.from(cached);
          }
        }
        return boundId;
      }

      _lastError =
          'Igreja não encontrada em igrejas/$s. O ID deve ser o documento real (ex.: igreja_nome_da_igreja).';
      return '';
    } catch (e) {

      _lastError = e.toString();

      rethrow;

    }

  }



  static void bindChurchData({

    required String churchId,

    required Map<String, dynamic> data,

    int? bootstrapMs,

  }) {

    final id = _canonicalizePanelId(churchId);

    if (id.isEmpty || data.isEmpty) return;

    _currentChurchId = id;

    _currentChurchData = Map<String, dynamic>.from(data);

    if (bootstrapMs != null) _lastBootstrapMs = bootstrapMs;

    unawaited(

      ChurchPanelLocalCache.saveMap(

        churchId: id,

        module: ChurchPanelLocalCache.moduleCadastro,

        data: data,

      ),

    );

    unawaited(ChurchBrandService.preloadForSession(

      churchId: id,

      tenantData: data,

    ));

  }



  static String requireCurrentChurchId() {

    final id = currentChurchId;

    if (id == null || id.isEmpty) {

      throw StateError(

        'ChurchContext não inicializado. Chame resolveAndBind após login.',

      );

    }

    return id;

  }



  static void clear() {

    _currentChurchId = null;

    _currentChurchData = null;

    _seedId = null;

    _userUid = null;

    _boundAt = null;

    _lastError = null;

    _lastBootstrapMs = null;

    ChurchOperationalPaths.clearSessionCache();

  }

}

