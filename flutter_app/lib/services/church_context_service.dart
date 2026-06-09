import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Contexto de igreja da sessão — resolve **uma vez** e expõe [currentChurchId].
///
/// Alias (`church_aliases`) só entra na resolução inicial.
/// Depois disso, todos os módulos usam [currentChurchId] → `igrejas/{churchId}/…`.
abstract final class ChurchContextService {
  ChurchContextService._();

  static const Duration kResolveTimeout = Duration(seconds: 15);

  static String? _currentChurchId;
  static Map<String, dynamic>? _currentChurchData;
  static String? _seedId;
  static String? _userUid;
  static DateTime? _boundAt;
  static String? _lastError;
  static int? _lastBootstrapMs;

  static String? get currentChurchId => _currentChurchId?.trim().isNotEmpty == true
      ? _currentChurchId!.trim()
      : null;

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
      TenantResolverService.invalidateOperationalChurchDocCache(
        seedId: s,
        userUid: uid,
      );
      TenantResolverService.invalidateRegistrationContextCache(
        seedId: s,
        userUid: uid,
      );
    }

    if (!forceRefresh &&
        _currentChurchId != null &&
        _currentChurchId!.isNotEmpty &&
        _seedId == s &&
        _userUid == uid) {
      return _currentChurchId!;
    }

    try {
      final resolved = await TenantResolverService.resolveOperationalChurchDocId(
        s,
        userUid: uid,
        forceRefresh: forceRefresh,
      ).timeout(kResolveTimeout);

      final id = resolved.trim();
      if (id.isEmpty) {
        _lastError = 'Não foi possível resolver churchId para "$s".';
        return '';
      }

      _currentChurchId = id;
      _seedId = s;
      _userUid = uid;
      _boundAt = DateTime.now();
      _lastError = null;

      if (!forceRefresh &&
          (_currentChurchData == null || _currentChurchData!.isEmpty)) {
        final cached = await ChurchPanelLocalCache.readMap(
          churchId: id,
          module: ChurchPanelLocalCache.moduleCadastro,
        );
        if (cached != null && cached.isNotEmpty) {
          _currentChurchData = Map<String, dynamic>.from(cached);
        }
      }

      ChurchOperationalPaths.rememberResolved(s, id, userUid: uid);
      TenantResolverService.rememberModuleReadTenantId(s, id, userUid: uid);

      debugPrint('CHURCH_CONTEXT bound seed=$s churchId=$id');
      return id;
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
    final id = churchId.trim();
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
