import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:gestao_yahweh/firebase_options.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// Falha estruturada — expõe causa original (não mensagem genérica).
class FirebaseBootstrapException implements Exception {
  FirebaseBootstrapException({
    required this.code,
    required this.userMessage,
    required this.cause,
    this.stackTrace,
    this.health,
  });

  final String code;
  final String userMessage;
  final Object cause;
  final StackTrace? stackTrace;
  final FirebaseHealthReport? health;

  @override
  String toString() => 'FirebaseBootstrapException($code): $cause';

  static FirebaseBootstrapException from(
    Object cause,
    StackTrace? stackTrace, {
    String? code,
    FirebaseHealthReport? health,
  }) {
    final c = code ?? _codeFrom(cause);
    return FirebaseBootstrapException(
      code: c,
      userMessage: _userMessageFrom(cause, c, health),
      cause: cause,
      stackTrace: stackTrace,
      health: health,
    );
  }

  static String _codeFrom(Object e) {
    if (e is FirebaseAuthException) return 'auth_${e.code}';
    if (e is FirebaseException) return '${e.plugin}_${e.code}';
    if (e is TimeoutException) return 'timeout';
    if (_isNoFirebaseApp(e)) return 'no_firebase_app';
    return 'bootstrap_failed';
  }

  static String _userMessageFrom(
    Object e,
    String code,
    FirebaseHealthReport? health,
  ) {
    if (e is StateError && e.message.contains('Sessão expirada')) {
      return e.message;
    }
    if (code == 'auth_no_user' || code == 'auth_anonymous') {
      return 'Sessão expirada. Saia e entre de novo no painel antes de publicar.';
    }
    if (e is FirebaseException) {
      final m = e.message?.trim();
      if (e.code == 'permission-denied' || e.code == 'unauthorized') {
        return 'Sem permissão (${e.plugin}/$code). Verifique login e regras.';
      }
      return 'Firebase ${e.plugin} ($code)${m != null ? ': $m' : ''}';
    }
    if (_isNoFirebaseApp(e)) {
      return 'Firebase não inicializou. Toque em «Reconectar» ou reinicie o app.';
    }
    if (health != null && !health.allCoreOk) {
      return health.summaryForUser;
    }
    final raw = e.toString();
    return raw.length > 180 ? 'Falha Firebase ($code).' : raw;
  }

  static bool _isNoFirebaseApp(Object e) {
    final low = e.toString().toLowerCase();
    return low.contains('no firebase app') ||
        low.contains('firebase.initializeapp') ||
        low.contains('core/no-app') ||
        low.contains('has not been initialized');
  }
}

class FirebaseHealthReport {
  FirebaseHealthReport({
    required this.coreInitialized,
    required this.authOk,
    required this.firestoreOk,
    required this.storageOk,
    required this.functionsOk,
    required this.fcmOk,
    this.authDetail,
    this.firestoreDetail,
    this.storageDetail,
    this.functionsDetail,
    this.fcmDetail,
    this.checkedAt,
  });

  final bool coreInitialized;
  final bool authOk;
  final bool firestoreOk;
  final bool storageOk;
  final bool functionsOk;
  final bool fcmOk;
  final String? authDetail;
  final String? firestoreDetail;
  final String? storageDetail;
  final String? functionsDetail;
  final String? fcmDetail;
  final DateTime? checkedAt;

  bool get allCoreOk =>
      coreInitialized && firestoreOk && storageOk && functionsOk;

  bool get canPublishMedia => allCoreOk && authOk;

  String get summaryForUser {
    final parts = <String>[];
    if (!coreInitialized) parts.add('núcleo Firebase');
    if (!authOk) parts.add('autenticação (${authDetail ?? "?"})');
    if (!firestoreOk) parts.add('Firestore (${firestoreDetail ?? "?"})');
    if (!storageOk) parts.add('Storage (${storageDetail ?? "?"})');
    if (!functionsOk) {
      parts.add('Functions (${functionsDetail ?? "?"})');
    }
    if (!fcmOk && _fcmRelevantOnThisPlatform) {
      parts.add('FCM (${fcmDetail ?? "?"})');
    }
    return 'Indisponível: ${parts.join(", ")}.';
  }

  static bool get _fcmRelevantOnThisPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

class FirebaseBootstrapResult {
  FirebaseBootstrapResult._({
    required this.isReady,
    this.failure,
    this.health,
  });

  final bool isReady;
  final FirebaseBootstrapException? failure;
  final FirebaseHealthReport? health;

  factory FirebaseBootstrapResult.ready(FirebaseHealthReport health) =>
      FirebaseBootstrapResult._(isReady: true, health: health);

  factory FirebaseBootstrapResult.failed(FirebaseBootstrapException failure) =>
      FirebaseBootstrapResult._(isReady: false, failure: failure);
}

/// Único ponto de inicialização / saúde / reconexão Firebase do app.
abstract final class FirebaseBootstrapService {
  FirebaseBootstrapService._();

  static const _reconnectDelaysSec = [1, 2, 5, 10, 30, 60];

  static Completer<void>? _initCompleter;
  static Future<void>? _ensureOnceFuture;

  /// Inicialização única partilhada (padrão pedido para paridade nativa).
  static Future<void> ensureInitializedOnce() {
    _ensureOnceFuture ??= _runEnsureInitializedOnce();
    return _ensureOnceFuture!;
  }

  static Future<void> _runEnsureInitializedOnce() async {
    final r = await initialize();
    if (!r.isReady && r.failure != null) {
      throw r.failure!;
    }
  }
  static FirebaseApp? _cachedApp;
  static DateTime? _healthOkAt;
  static FirebaseHealthReport? _lastHealth;
  static FirebaseBootstrapException? _lastFailure;

  static bool isReady() {
    if (!_hasApp()) return false;
    final inflight = _initCompleter;
    if (inflight != null && !inflight.isCompleted) return false;
    return _healthOkAt != null && _lastFailure == null;
  }

  static FirebaseHealthReport? get lastHealth => _lastHealth;
  static FirebaseBootstrapException? get lastFailure => _lastFailure;

  static FirebaseApp get defaultApp {
    if (_cachedApp != null) {
      try {
        _cachedApp!.name;
        return _cachedApp!;
      } catch (_) {
        _cachedApp = null;
      }
    }
    final app = Firebase.app();
    _cachedApp = app;
    return app;
  }

  static FirebaseFirestore get firestore =>
      FirebaseFirestore.instanceFor(app: defaultApp);

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: defaultApp);

  static FirebaseStorage get storage =>
      FirebaseStorage.instanceFor(app: defaultApp);

  static Reference storageRef(String path) => storage.ref(path);

  /// Arranque obrigatório — chamar em [main] **antes** de [runApp].
  static Future<FirebaseBootstrapResult> initialize() async {
    if (_initCompleter != null) {
      if (!_initCompleter!.isCompleted) await _initCompleter!.future;
      if (_lastFailure == null && _lastHealth != null) {
        return FirebaseBootstrapResult.ready(_lastHealth!);
      }
      if (_lastFailure != null) {
        return FirebaseBootstrapResult.failed(_lastFailure!);
      }
    }
    if (_hasApp() && _healthOkAt != null) {
      try {
        final h = await healthCheck(requireAuthSession: false);
        return FirebaseBootstrapResult.ready(h);
      } catch (e, st) {
        _lastFailure = FirebaseBootstrapException.from(e, st);
        return FirebaseBootstrapResult.failed(_lastFailure!);
      }
    }

    final c = Completer<void>();
    _initCompleter = c;
    Object? last;
    StackTrace? lastSt;
    for (var attempt = 0; attempt < _reconnectDelaysSec.length + 1; attempt++) {
      try {
        if (!_hasApp()) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        _cachedApp = Firebase.app();
        final health = await healthCheck(requireAuthSession: false);
        _lastHealth = health;
        _lastFailure = null;
        _healthOkAt = DateTime.now();
        c.complete();
        if (kDebugMode) {
          debugPrint('FirebaseBootstrapService: OK ${health.checkedAt}');
        }
        return FirebaseBootstrapResult.ready(health);
      } catch (e, st) {
        last = e;
        lastSt = st;
        if (kDebugMode) {
          debugPrint('FirebaseBootstrapService.initialize tentativa $attempt: $e');
        }
        if (attempt < _reconnectDelaysSec.length) {
          await Future.delayed(
            Duration(seconds: _reconnectDelaysSec[attempt]),
          );
        }
      }
    }
    final fail = FirebaseBootstrapException.from(last!, lastSt);
    _lastFailure = fail;
    if (!c.isCompleted) c.completeError(fail, lastSt);
    unawaited(CrashlyticsService.record(fail, lastSt, reason: 'firebase_init'));
    return FirebaseBootstrapResult.failed(fail);
  }

  /// Verificação Auth + Firestore + Storage (+ sessão se [requireAuthSession]).
  static Future<FirebaseHealthReport> healthCheck({
    bool requireAuthSession = false,
    String? logLabel,
  }) async {
    if (!_hasApp()) {
      throw FirebaseBootstrapException.from(
        StateError('Firebase.initializeApp() ainda não foi chamado.'),
        StackTrace.current,
        code: 'not_initialized',
      );
    }

    final app = defaultApp;
    var authOk = true;
    var firestoreOk = true;
    var storageOk = true;
    var functionsOk = true;
    var fcmOk = true;
    String? authDetail;
    String? firestoreDetail;
    String? storageDetail;
    String? functionsDetail;
    String? fcmDetail;

    try {
      FirebaseFirestore.instanceFor(app: app);
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (e) {
        if (!_isNoFirebaseApp(e)) {
          firestoreDetail = e.toString();
        }
      }
    } catch (e) {
      firestoreOk = false;
      firestoreDetail = e.toString();
      if (_isNoFirebaseApp(e)) rethrow;
    }

    try {
      final a = FirebaseAuth.instanceFor(app: app);
      final user = a.currentUser;
      if (requireAuthSession) {
        if (user == null) {
          authOk = false;
          authDetail = 'no_user';
          throw StateError(
            'Sessão expirada. Saia e entre de novo no painel antes de publicar.',
          );
        }
        if (user.isAnonymous) {
          authOk = false;
          authDetail = 'anonymous';
          throw StateError(
            'Sessão expirada. Saia e entre de novo no painel antes de publicar.',
          );
        }
        try {
          await user.getIdToken(false).timeout(const Duration(seconds: 20));
        } catch (e) {
          authDetail = e.toString();
          if (_isNoFirebaseApp(e)) rethrow;
        }
      }
    } catch (e) {
      if (e is StateError && e.message.contains('Sessão')) rethrow;
      authOk = false;
      authDetail ??= e.toString();
      if (_isNoFirebaseApp(e)) rethrow;
    }

    try {
      final s = FirebaseStorage.instanceFor(app: app);
      // ignore: unnecessary_statements
      s.bucket;
    } catch (e) {
      storageOk = false;
      storageDetail = e.toString();
      if (_isNoFirebaseApp(e)) rethrow;
    }

    try {
      FirebaseFunctions.instanceFor(app: app, region: 'us-central1');
    } catch (e) {
      functionsOk = false;
      functionsDetail = e.toString();
      if (_isNoFirebaseApp(e)) rethrow;
    }

    if (FirebaseHealthReport._fcmRelevantOnThisPlatform) {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.setAutoInitEnabled(true);
        await messaging.getToken().timeout(const Duration(seconds: 12));
      } catch (e) {
        fcmOk = false;
        fcmDetail = e.toString();
      }
    }

    final report = FirebaseHealthReport(
      coreInitialized: true,
      authOk: authOk,
      firestoreOk: firestoreOk,
      storageOk: storageOk,
      functionsOk: functionsOk,
      fcmOk: fcmOk,
      authDetail: authDetail,
      firestoreDetail: firestoreDetail,
      storageDetail: storageDetail,
      functionsDetail: functionsDetail,
      fcmDetail: fcmDetail,
      checkedAt: DateTime.now(),
    );
    _lastHealth = report;
    if (logLabel != null && kDebugMode) {
      debugPrint(
        'Firebase health [$logLabel]: auth=$authOk fs=$firestoreOk '
        'st=$storageOk fn=$functionsOk fcm=$fcmOk',
      );
    }
    return report;
  }

  /// Reconexão com backoff — sem exigir fechar o app.
  static Future<void> reconnect({bool requireAuthSession = false}) async {
    _healthOkAt = null;
    Object? last;
    StackTrace? lastSt;
    for (final sec in _reconnectDelaysSec) {
      try {
        await _softReinit();
        await healthCheck(requireAuthSession: requireAuthSession);
        _healthOkAt = DateTime.now();
        return;
      } catch (e, st) {
        last = e;
        lastSt = st;
        if (kDebugMode) debugPrint('Firebase reconnect (${sec}s): $e');
      }
      await Future.delayed(Duration(seconds: sec));
    }
    final ex = FirebaseBootstrapException.from(last!, lastSt);
    _lastFailure = ex;
    unawaited(CrashlyticsService.record(ex, lastSt, reason: 'firebase_reconnect'));
    throw ex;
  }

  /// Reinício completo (último recurso) — pode terminar sessão Auth nativa.
  static Future<void> restart() async {
    _initCompleter = null;
    _cachedApp = null;
    _healthOkAt = null;
    try {
      if (_hasApp()) await Firebase.app().delete();
    } catch (_) {}
    final r = await initialize();
    if (!r.isReady) throw r.failure!;
  }

  static Future<void> ensureReady({
    bool requireAuthSession = false,
    bool forceHealthCheck = false,
  }) async {
    if (!_hasApp()) {
      final r = await initialize();
      if (!r.isReady) throw r.failure!;
    }
    if (_initCompleter == null || (_initCompleter!.isCompleted == false)) {
      final r = await initialize();
      if (!r.isReady) throw r.failure!;
    }
    final cache = _healthOkAt;
    if (!forceHealthCheck &&
        cache != null &&
        DateTime.now().difference(cache) < const Duration(seconds: 45) &&
        (!requireAuthSession || (_lastHealth?.authOk ?? false))) {
      return;
    }
    try {
      await healthCheck(requireAuthSession: requireAuthSession);
      _healthOkAt = DateTime.now();
    } catch (e) {
      if (_isNoFirebaseApp(e) || e is FirebaseException) {
        await reconnect(requireAuthSession: requireAuthSession);
        return;
      }
      rethrow;
    }
  }

  static Future<void> ensureReadyForMediaUpload({bool force = false}) async {
    try {
      await ensureReady(requireAuthSession: true, forceHealthCheck: force);
    } catch (e, st) {
      if (e is FirebaseBootstrapException) rethrow;
      throw FirebaseBootstrapException.from(e, st);
    }
  }

  static Future<T> runGuarded<T>(
    Future<T> Function() fn, {
    String? debugLabel,
    bool requireAuth = true,
  }) async {
    Object? last;
    StackTrace? lastSt;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await ensureReady(
          requireAuthSession: requireAuth,
          forceHealthCheck: attempt > 1,
        );
        return await fn();
      } catch (e, st) {
        last = e;
        lastSt = st;
        unawaited(
          CrashlyticsService.record(
            e,
            st,
            reason: debugLabel ?? 'firebase_guarded',
          ),
        );
        if (attempt >= 3) break;
        try {
          await reconnect(requireAuthSession: requireAuth);
        } catch (_) {}
      }
    }
    if (last is FirebaseBootstrapException) {
      Error.throwWithStackTrace(last, lastSt ?? StackTrace.current);
    }
    throw FirebaseBootstrapException.from(last!, lastSt);
  }

  static bool _hasApp() {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _softReinit() async {
    _cachedApp = null;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app' && _hasApp()) {
        _cachedApp = Firebase.app();
        return;
      }
      rethrow;
    } catch (e) {
      final low = e.toString().toLowerCase();
      if ((low.contains('duplicate') || low.contains('already exists')) &&
          _hasApp()) {
        _cachedApp = Firebase.app();
        return;
      }
      rethrow;
    }
    _cachedApp = Firebase.app();
  }

  static bool _isNoFirebaseApp(Object e) {
    final low = e.toString().toLowerCase();
    return low.contains('no firebase app') ||
        low.contains('firebase.initializeapp') ||
        low.contains('core/no-app') ||
        low.contains('has not been initialized');
  }
}
