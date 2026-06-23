
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show ValueNotifier, debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';

/// Estabilidade do painel igreja na **Web** — um bootstrap por login, sem recovery
/// automático em loop, listeners deduplicados e sessão expirada com «Entrar novamente».
abstract final class WebPanelStability {
  WebPanelStability._();

  static String? _loginUid;
  static bool _bootstrapDone = false;
  static bool _bootstrapInFlight = false;
  static bool _sessionExpired = false;

  static final ValueNotifier<bool> sessionExpiredNotifier =
      ValueNotifier<bool>(false);

  static final Map<String, int> _activeListeners = <String, int>{};

  static bool get isWeb => kIsWeb;

  static bool get isSessionExpired => kIsWeb && _sessionExpired;

  /// Recovery automático (RECOVERY / UPLOAD_QUEUE / chat preso) — desligado no EcoFire e na Web expirada.
  static bool get allowAutomaticRecovery =>
      !EcoFireFlow.disableAutomaticRecovery && (!kIsWeb || !_sessionExpired);

  static bool get bootstrapDoneForSession => _bootstrapDone;

  static void bindLoginSession(User? user) {
    if (!kIsWeb || user == null || user.isAnonymous) return;
    final uid = user.uid.trim();
    if (uid.isEmpty) return;
    if (_loginUid != uid) {
      _loginUid = uid;
      _bootstrapDone = false;
      _bootstrapInFlight = false;
      clearSessionExpired();
      _activeListeners.clear();
    }
  }

  static void clearOnSignOut() {
    _loginUid = null;
    _bootstrapDone = false;
    _bootstrapInFlight = false;
    clearSessionExpired();
    _activeListeners.clear();
  }

  static void markSessionExpired() {
    if (!kIsWeb) return;
    if (_sessionExpired) return;
    _sessionExpired = true;
    sessionExpiredNotifier.value = true;
    if (kDebugMode) {
      debugPrint('WebPanelStability: sessão expirada — recovery automático desligado.');
    }
  }

  static void clearSessionExpired() {
    if (!_sessionExpired && !sessionExpiredNotifier.value) return;
    _sessionExpired = false;
    sessionExpiredNotifier.value = false;
  }

  /// Apenas **um** bootstrap por login (cold start / resume).
  static bool tryBeginBootstrap() {
    if (!kIsWeb) return true;
    if (_sessionExpired) return false;
    if (_bootstrapDone || _bootstrapInFlight) return false;
    _bootstrapInFlight = true;
    YahwehFlowLog.sync('BOOTSTRAP', 'START');
    return true;
  }

  static void markBootstrapEnd({bool ok = true}) {
    if (!kIsWeb) return;
    if (!_bootstrapInFlight && _bootstrapDone) return;
    _bootstrapInFlight = false;
    if (ok) _bootstrapDone = true;
    YahwehFlowLog.sync('BOOTSTRAP', ok ? 'END' : 'END_FAIL');
  }

  /// Evita abrir o mesmo listener Firestore duas vezes (INTERNAL ASSERTION ca9).
  static bool tryOpenListener(String collection) {
    if (!kIsWeb) return true;
    final key = collection.trim().toLowerCase();
    if (key.isEmpty) return true;
    final n = _activeListeners[key] ?? 0;
    if (n > 0) {
      if (kDebugMode) debugPrint('LISTENER SKIP $key (already active)');
      return false;
    }
    _activeListeners[key] = 1;
    debugPrint('LISTENER OPEN $key');
    return true;
  }

  static void closeListener(String collection) {
    if (!kIsWeb) return;
    final key = collection.trim().toLowerCase();
    if (key.isEmpty) return;
    final n = (_activeListeners[key] ?? 0) - 1;
    if (n <= 0) {
      _activeListeners.remove(key);
      debugPrint('LISTENER CLOSE $key');
    } else {
      _activeListeners[key] = n;
    }
  }

  static bool isListenerOpen(String collection) {
    if (!kIsWeb) return false;
    return (_activeListeners[collection.trim().toLowerCase()] ?? 0) > 0;
  }
}
