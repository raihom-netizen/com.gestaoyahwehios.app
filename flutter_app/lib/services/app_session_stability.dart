import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/church_auto_session_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/services/persistent_auth_session_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/web_resume_repaint_stub.dart'
    if (dart.library.html) 'package:gestao_yahweh/web_resume_repaint_web.dart';

/// Sessão e retoma estáveis em **toda** a app (web, Android, iOS) — padrão Controle Total.
///
/// - Não desloga ao trocar de aba / voltar do background (só «Sair» explícito).
/// - Renova token Firebase sem `reconnect()` pesado.
/// - Cache de acesso master e utilizador «sticky» para evitar tela branca.
abstract final class AppSessionStability {
  AppSessionStability._();

  static User? _stickyUser;
  static int? _cachedMasterLevel;
  static String? _cachedMasterUid;
  static DateTime? _cachedMasterAt;
  static bool _adminPanelVerified = false;
  static bool _bound = false;
  static bool _keepaliveBound = false;
  static Timer? _keepaliveTimer;
  static final List<void Function()> _resumeListeners = <void Function()>[];

  static const Duration _masterCacheTtl = Duration(hours: 12);
  static const Duration _sessionKeepaliveInterval = Duration(minutes: 4);

  /// Regista lifecycle + visibilidade da aba (web). Idempotente.
  static void bindGlobal(WidgetsBindingObserver observer) {
    if (_bound) return;
    _bound = true;
    final u = firebaseDefaultAuth.currentUser;
    if (u != null && !u.isAnonymous) _stickyUser = u;
    if (kIsWeb) {
      registerWebResumeRepaint(onGlobalResume);
    }
  }

  static void registerResumeListener(void Function() listener) {
    if (!_resumeListeners.contains(listener)) {
      _resumeListeners.add(listener);
    }
  }

  static void unregisterResumeListener(void Function() listener) {
    _resumeListeners.remove(listener);
  }

  /// Pulso periódico — mantém sessão e Firestore activos (web/Android/iOS).
  static void bindSessionKeepalive() {
    if (_keepaliveBound) return;
    _keepaliveBound = true;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(_sessionKeepaliveInterval, (_) {
      unawaited(_runSoftKeepalive());
    });
  }

  static Future<void> _runSoftKeepalive() async {
    final u = firebaseDefaultAuth.currentUser ?? _stickyUser;
    if (u == null || u.isAnonymous) return;
    rememberUser(u);
    try {
      await FirebaseAuthTokenGuard.refreshIfStale();
      if (kIsWeb) {
        await FirestoreWebGuard.ensureWebDatabaseConnected(refreshAuth: false);
      } else {
        await firebaseDefaultFirestore.enableNetwork().catchError((_) {});
      }
      // Mantém Storage ligado — evita core/no-app ao publicar após background.
      await FirebaseBootstrapService.ensureStorageAlwaysLinked(
        refreshAuthToken: false,
      ).catchError((_) {});
      await ChurchAutoSessionService.ensureAutoPainelFlagForPersistedSession();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('AppSessionStability keepalive: $e\n$st');
      }
    }
  }

  /// Volta da rede (modo avião / Wi‑Fi) — recuperação completa sem throttle de resume.
  static void onConnectivityRestored() => onGlobalResume(force: true);

  /// Chamado ao voltar do background / foco na aba (web + mobile).
  static void onGlobalResume({bool force = false}) {
    final u = firebaseDefaultAuth.currentUser;
    if (u != null && !u.isAnonymous) {
      _stickyUser = u;
    }
    final runHeavy = force || FirebaseAuthTokenGuard.shouldHandleAppResume();
    if (runHeavy && !(kIsWeb && WebPanelStability.isSessionExpired)) {
      if (kIsWeb) {
        unawaited(FirestoreWebGuard.ensureWebDatabaseConnected(refreshAuth: true));
      } else {
        unawaited(AppFinalizeBootstrap.onAppResume());
      }
      if (kIsWeb) {
        unawaited(FirestoreWebGuard.bindWebHostingDomainSession());
      }
    }
    for (final cb in List<void Function()>.from(_resumeListeners)) {
      try {
        cb();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AppSessionStability resume listener: $e\n$st');
        }
      }
    }
  }

  static void rememberUser(User? user) {
    if (user != null && !user.isAnonymous) {
      _stickyUser = user;
    }
  }

  /// Limpa utilizador «sticky» após falha de restauração (evita AuthGate preso).
  static void clearStickyUser() {
    _stickyUser = null;
  }

  /// Utilizador efetivo para [StreamBuilder] de auth — evita logout fantasma.
  static User? effectiveAuthUser(
    User? streamUser, {
    ConnectionState connectionState = ConnectionState.active,
  }) {
    if (streamUser != null && !streamUser.isAnonymous) {
      _stickyUser = streamUser;
      return streamUser;
    }
    final sync = firebaseDefaultAuth.currentUser;
    if (sync != null && !sync.isAnonymous) {
      _stickyUser = sync;
      return sync;
    }
    // Só durante «waiting» — em «active» sem Firebase o sticky causa tela branca no AuthGate.
    final sticky = _stickyUser;
    if (sticky != null &&
        !sticky.isAnonymous &&
        connectionState == ConnectionState.waiting) {
      return sticky;
    }
    return streamUser;
  }

  static bool hasReturningSessionHints() {
    if (LoginPreferences.startupAccountSwitchPending == true) return false;
    if (_stickyUser != null) return true;
    final shellUid = AppShellSessionCache.cachedUidSync();
    if (shellUid != null && shellUid.isNotEmpty) return true;
    return LoginPreferences.autoPainelLoginSync;
  }

  static Future<User?> tryRestoreSession() async {
    return PersistentAuthSessionService.currentPersistedUser();
  }

  // â”€â”€â”€ Painel Master (/admin) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// 0 = sem login, 1 = logado sem ADM, 2 = ADM/master.
  static int? peekCachedMasterAccessLevel() {
    final uid =
        (firebaseDefaultAuth.currentUser?.uid ?? _stickyUser?.uid ?? '')
            .trim();
    if (uid.isEmpty) return null;
    if (_cachedMasterUid == uid &&
        _cachedMasterLevel != null &&
        _cachedMasterAt != null &&
        DateTime.now().difference(_cachedMasterAt!) < _masterCacheTtl) {
      return _cachedMasterLevel;
    }
    return null;
  }

  static void cacheMasterAccessLevel(int level, String uid) {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    _cachedMasterUid = clean;
    _cachedMasterLevel = level;
    _cachedMasterAt = DateTime.now();
    if (level >= 2) _adminPanelVerified = true;
  }

  static void clearMasterAccessCache() {
    _cachedMasterUid = null;
    _cachedMasterLevel = null;
    _cachedMasterAt = null;
    _adminPanelVerified = false;
  }

  static bool get adminPanelWasVerified => _adminPanelVerified;

  static void markAdminPanelVerified() => _adminPanelVerified = true;

  /// Verificação de acesso master — cache + claims + Firestore resiliente.
  static Future<int> resolveMasterAccessLevel({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final peek = peekCachedMasterAccessLevel();
      if (peek != null) return peek;
    }

    final user = firebaseDefaultAuth.currentUser ?? _stickyUser;
    if (user == null || user.isAnonymous) {
      cacheMasterAccessLevel(0, '');
      return 0;
    }
    rememberUser(user);

    final email = (user.email ?? '').toString().toLowerCase();
    if (email == 'raihom@gmail.com') {
      cacheMasterAccessLevel(2, user.uid);
      return 2;
    }

    try {
      await FirebaseAuthTokenGuard.refreshIfStale();
      var token = await user.getIdTokenResult(false).timeout(
            const Duration(seconds: 8),
          );
      if (_tokenIsMaster(token)) {
        cacheMasterAccessLevel(2, user.uid);
        return 2;
      }
      if (!forceRefresh && !FirebaseAuthTokenGuard.isInQuotaBackoff) {
        token = await user.getIdTokenResult(true).timeout(
              const Duration(seconds: 12),
            );
        if (_tokenIsMaster(token)) {
          cacheMasterAccessLevel(2, user.uid);
          return 2;
        }
      }
    } catch (_) {}

    try {
      final snap = await FirestoreReadResilience.getDocument(
        firebaseDefaultFirestore.collection('users').doc(user.uid),
        cacheKey: 'master_users_${user.uid}',
        maxAttempts: 3,
      );
      final data = snap.data() ?? {};
      final role =
          (data['role'] ?? data['nivel'] ?? '').toString().toUpperCase();
      final nivel = (data['nivel'] ?? '').toString().toLowerCase();
      if (role == 'ADM' ||
          role == 'ADMIN' ||
          role == 'MASTER' ||
          nivel == 'adm') {
        cacheMasterAccessLevel(2, user.uid);
        return 2;
      }
      cacheMasterAccessLevel(1, user.uid);
      return 1;
    } on TimeoutException {
      try {
        final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp).httpsCallable('getAdminCheck');
        final res = await fn
            .call<Map<String, dynamic>>()
            .timeout(const Duration(seconds: 10));
        if (res.data['allowed'] == true) {
          cacheMasterAccessLevel(2, user.uid);
          return 2;
        }
      } catch (_) {}
      final peek = peekCachedMasterAccessLevel();
      if (peek != null && peek >= 2) return peek;
      cacheMasterAccessLevel(0, user.uid);
      return 0;
    } catch (_) {
      try {
        final snap = await FirestoreReadResilience.getDocument(
          firebaseDefaultFirestore.collection('usuarios').doc(user.uid),
          cacheKey: 'master_usuarios_${user.uid}',
        );
        final nivel = (snap.data()?['nivel'] ?? '').toString().toLowerCase();
        if (nivel == 'adm') {
          cacheMasterAccessLevel(2, user.uid);
          return 2;
        }
      } catch (_) {}
      try {
        final fn = FirebaseFunctions.instanceFor(app: firebaseDefaultApp).httpsCallable('getAdminCheck');
        final res = await fn
            .call<Map<String, dynamic>>()
            .timeout(const Duration(seconds: 10));
        if (res.data['allowed'] == true) {
          cacheMasterAccessLevel(2, user.uid);
          return 2;
        }
      } catch (_) {}
      final peek = peekCachedMasterAccessLevel();
      if (peek != null) return peek;
      cacheMasterAccessLevel(1, user.uid);
      return 1;
    }
  }

  static bool _tokenIsMaster(IdTokenResult token) {
    final roleClaim = (token.claims?['role'] ?? token.claims?['nivel'] ?? '')
        .toString()
        .toUpperCase();
    if (roleClaim == 'ADM' || roleClaim == 'ADMIN' || roleClaim == 'MASTER') {
      return true;
    }
    if ((token.claims?['nivel'] ?? '').toString().toLowerCase() == 'adm') {
      return true;
    }
    return token.claims?['admin'] == true;
  }

  /// Verificação rápida para [AdminPanelPage] — não repõe spinner se já validou.
  static Future<bool> resolveIsMasterAdmin({bool forceRefresh = false}) async {
    if (!forceRefresh && _adminPanelVerified) return true;
    final level = await resolveMasterAccessLevel(forceRefresh: forceRefresh);
    return level >= 2;
  }
}

