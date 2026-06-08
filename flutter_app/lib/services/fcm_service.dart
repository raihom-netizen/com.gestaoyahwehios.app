import 'dart:async';

import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'church_panel_navigation_bridge.dart';
import 'panel_notification_service.dart';
import 'yahweh_push_cache_refresh.dart';

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _configured = false;
  String? _lastUid;
  String? _lastTenantId;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;
  void Function(RemoteMessage message)? _foregroundHandler;

  static const _prefPushTenant = 'church_fcm_push_tenant';
  static const _prefGypushTopics = 'church_fcm_gypush_topics';
  static const _legacyWrongTenantIds = <String>[
    'brasilparacristo_sistema',
    'brasilparacristo',
  ];
  static const _gypushKinds = <String>[
    'aviso',
    'evento',
    'escala',
    'chat',
    'aniversario',
    'gestores',
    'financeiro',
    'fornecedor_agenda',
  ];

  /// Doc Firestore + tópicos FCM (`gypush_{tenant}_…`) — alinhado ao Storage.
  static Future<String> resolvePushTenantId(
    String seed, {
    String? userUid,
    bool forceRefresh = false,
  }) async {
    final s = seed.trim();
    if (s.isEmpty) return s;
    try {
      final op = await TenantResolverService.resolveOperationalChurchDocId(
        s,
        userUid: userUid,
        forceRefresh: forceRefresh,
      );
      return op.trim().isEmpty ? s : op.trim();
    } catch (_) {
      return s;
    }
  }

  /// Alinhado a Cloud Functions [topicPushNovo] (`gypush_{tenant}_{aviso|evento|…}`).
  static String fcmTenantSafe(String tenantId) =>
      tenantId.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_');

  static String topicPushNovo(String tenantId, String kind) =>
      'gypush_${fcmTenantSafe(tenantId)}_$kind';

  static String topicIgrejaBroadcast(String tenantId) => 'igreja_$tenantId';

  Future<void> configure({
    required String uid,
    required String tenantId,
    required String cpf,
    required String role,
    void Function(RemoteMessage message)? onForegroundMessage,
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) return;
    if (uid.trim().isEmpty) return;

    final tid = await resolvePushTenantId(
      tenantId,
      userUid: uid,
      forceRefresh: forceRefresh,
    );
    if (tid.isEmpty) return;

    if (!forceRefresh &&
        _configured &&
        _lastUid == uid &&
        _lastTenantId == tid) {
      return;
    }

    _lastUid = uid;
    _lastTenantId = tid;
    _configured = true;
    if (onForegroundMessage != null) {
      _foregroundHandler = onForegroundMessage;
    }

    try {
      await _configureImpl(
        uid: uid,
        tenantId: tid,
        cpf: cpf,
        role: role,
      );
    } catch (e, st) {
      debugPrint('FcmService.configure: $e\n$st');
    }
  }

  Future<void> _configureImpl({
    required String uid,
    required String tenantId,
    required String cpf,
    required String role,
  }) async {
    await PanelNotificationService.instance.registerAndroidChannelsForBoot();
    await PanelNotificationService.instance
        .ensureAndroidPostNotificationsPermission();

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _migratePushTopics(messaging, tenantId);

    Future<void> persistToken(String token) async {
      if (token.isEmpty) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .set({
          'token': token,
          'tenantId': tenantId,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    final token = await messaging.getToken();
    if (token != null) await persistToken(token);

    await _onTokenRefreshSub?.cancel();
    _onTokenRefreshSub = messaging.onTokenRefresh.listen(persistToken);

    List<String> deptIds = <String>[];
    var cargoLabel = '';
    try {
      deptIds = await _loadMemberDepartments(tenantId, cpf);
      cargoLabel = await _loadMemberCargoLabel(tenantId, cpf);
    } catch (_) {}

    final cargoSlug = slugTopicPart(cargoLabel);
    final tid = tenantId.trim();
    final deptTopics = deptIds.map((id) => 'dept_$id').toList();
    final nextTopics = <String>[
      ...deptTopics,
      if (cargoSlug.isNotEmpty) 'cargo_$cargoSlug',
      if (tid.isNotEmpty) topicIgrejaBroadcast(tid),
    ];

    final prefs = await SharedPreferences.getInstance();
    final prevTopics = prefs.getStringList('church_fcm_topics') ??
        prefs.getStringList('dept_topics') ??
        <String>[];

    for (final t in prevTopics) {
      if (!nextTopics.contains(t)) {
        try {
          await messaging.unsubscribeFromTopic(t);
        } catch (_) {}
      }
    }
    for (final t in nextTopics) {
      if (!prevTopics.contains(t)) {
        try {
          await messaging.subscribeToTopic(t);
        } catch (_) {}
      }
    }

    final roleNorm = role.trim().toLowerCase();
    final isGestoresStaff = _isGestoresStaffRole(roleNorm);
    final isFinanceStaff = _isFinanceStaffRole(roleNorm);
    final isFornecedorStaff = isFinanceStaff ||
        roleNorm == 'secretario' ||
        roleNorm == 'secretaria';

    try {
      await messaging.unsubscribeFromTopic('admin');
    } catch (_) {}

    await _setTopicSubscribed(
      messaging,
      topicPushNovo(tid, 'gestores'),
      isGestoresStaff,
    );

    if (isFinanceStaff) {
      await _setTopicSubscribed(messaging, topicPushNovo(tid, 'financeiro'), true);
      await _setTopicSubscribed(
        messaging,
        topicPushNovo(tid, 'fornecedor_agenda'),
        true,
      );
    } else if (isFornecedorStaff) {
      await _setTopicSubscribed(
        messaging,
        topicPushNovo(tid, 'fornecedor_agenda'),
        true,
      );
      await _setTopicSubscribed(messaging, topicPushNovo(tid, 'financeiro'), false);
    } else {
      await _setTopicSubscribed(messaging, topicPushNovo(tid, 'financeiro'), false);
      await _setTopicSubscribed(
        messaging,
        topicPushNovo(tid, 'fornecedor_agenda'),
        false,
      );
    }

    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
      YahwehPushCacheRefresh.handleMessage(message);
      _foregroundHandler?.call(message);
    });
    _onMessageOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen(routeNotificationTap);
    final initialOpen = await FirebaseMessaging.instance.getInitialMessage();
    if (initialOpen != null) {
      routeNotificationTap(initialOpen);
    }

    await prefs.setStringList('church_fcm_topics', nextTopics);
    await syncPreferencePushTopics(uid: uid, tenantId: tid);
    await prefs.setString(_prefPushTenant, tid);
  }

  static Future<void> _migratePushTopics(
    FirebaseMessaging messaging,
    String newTenantId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prevTenant = (prefs.getString(_prefPushTenant) ?? '').trim();
    if (prevTenant == newTenantId && prevTenant.isNotEmpty) {
      await _unsubscribeLegacyWrongTopics(messaging);
      return;
    }

    final prevGypush = prefs.getStringList(_prefGypushTopics) ?? const [];
    for (final t in prevGypush) {
      try {
        await messaging.unsubscribeFromTopic(t);
      } catch (_) {}
    }

    await _unsubscribeLegacyWrongTopics(messaging);

    if (prevTenant.isNotEmpty && prevTenant != newTenantId) {
      for (final k in _gypushKinds) {
        try {
          await messaging.unsubscribeFromTopic(topicPushNovo(prevTenant, k));
        } catch (_) {}
      }
      try {
        await messaging.unsubscribeFromTopic(topicIgrejaBroadcast(prevTenant));
      } catch (_) {}
    }
  }

  static Future<void> _unsubscribeLegacyWrongTopics(
    FirebaseMessaging messaging,
  ) async {
    for (final wrong in _legacyWrongTenantIds) {
      for (final k in _gypushKinds) {
        try {
          await messaging.unsubscribeFromTopic(topicPushNovo(wrong, k));
        } catch (_) {}
      }
      try {
        await messaging.unsubscribeFromTopic(topicIgrejaBroadcast(wrong));
      } catch (_) {}
    }
  }

  static Future<void> _setTopicSubscribed(
    FirebaseMessaging messaging,
    String topic,
    bool subscribe,
  ) async {
    try {
      if (subscribe) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (_) {}
  }

  /// Inscreve nos tópicos conforme preferências em `users/{uid}`.
  Future<void> syncPreferencePushTopics({
    required String uid,
    required String tenantId,
  }) async {
    if (kIsWeb) return;
    final tid = await resolvePushTenantId(tenantId, userUid: uid);
    if (tid.isEmpty) return;

    final messaging = FirebaseMessaging.instance;
    final topics = <String, String>{
      'pushAvisos': topicPushNovo(tid, 'aviso'),
      'pushEventos': topicPushNovo(tid, 'evento'),
      'pushEscalas': topicPushNovo(tid, 'escala'),
      'pushChat': topicPushNovo(tid, 'chat'),
      'pushAniversariantes': topicPushNovo(tid, 'aniversario'),
    };

    var pushAvisos = true;
    var pushEventos = true;
    var pushEscalas = true;
    var pushChat = true;
    var pushAniversariantes = true;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final d = doc.data();
      if (d != null) {
        if (d['pushAvisos'] is bool) pushAvisos = d['pushAvisos'] as bool;
        if (d['pushEventos'] is bool) pushEventos = d['pushEventos'] as bool;
        if (d['pushEscalas'] is bool) pushEscalas = d['pushEscalas'] as bool;
        if (d['pushChat'] is bool) pushChat = d['pushChat'] as bool;
        if (d['pushAniversariantes'] is bool) {
          pushAniversariantes = d['pushAniversariantes'] as bool;
        }
      }
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        pushAvisos = prefs.getBool('notif_avisos') ?? true;
        pushEventos = prefs.getBool('notif_eventos') ?? true;
        pushEscalas = prefs.getBool('notif_escalas') ?? true;
        pushChat = prefs.getBool('notif_chat') ?? true;
        pushAniversariantes = prefs.getBool('notif_aniversariantes') ?? true;
      } catch (_) {}
    }

    final flags = {
      'pushAvisos': pushAvisos,
      'pushEventos': pushEventos,
      'pushEscalas': pushEscalas,
      'pushChat': pushChat,
      'pushAniversariantes': pushAniversariantes,
    };

    for (final entry in topics.entries) {
      await _setTopicSubscribed(
        messaging,
        entry.value,
        flags[entry.key] ?? true,
      );
    }

    final subscribed = <String>[
      for (final entry in topics.entries)
        if (flags[entry.key] == true) entry.value,
    ];

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'church_fcm_pref_topics',
        subscribed,
      );
      await prefs.setStringList(_prefGypushTopics, subscribed);
      await prefs.setString(_prefPushTenant, tid);
    } catch (_) {}
  }

  static bool _isGestoresStaffRole(String roleNorm) {
    return roleNorm == 'adm' ||
        roleNorm == 'admin' ||
        roleNorm == 'administrador' ||
        roleNorm == 'gestor' ||
        roleNorm == 'master' ||
        roleNorm == 'pastor' ||
        roleNorm == 'pastora' ||
        roleNorm == 'secretario' ||
        roleNorm == 'secretaria' ||
        roleNorm == 'lider' ||
        roleNorm == 'líder';
  }

  static bool _isFinanceStaffRole(String roleNorm) {
    return roleNorm == 'adm' ||
        roleNorm == 'admin' ||
        roleNorm == 'administrador' ||
        roleNorm == 'gestor' ||
        roleNorm == 'master' ||
        roleNorm == 'pastor' ||
        roleNorm == 'pastora' ||
        roleNorm == 'tesoureiro' ||
        roleNorm == 'tesoureira';
  }

  void routeNotificationTap(RemoteMessage message) {
    final raw = message.data['type'];
    final type = raw is String ? raw : raw?.toString();
    final t = (type ?? '').trim();

    if (t == 'novo_chat' || t == 'chat_message' || t == 'church_chat') {
      final threadId = (message.data['threadId'] ?? '').toString().trim();
      if (threadId.isNotEmpty) {
        final tenantRaw = (message.data['tenantId'] ?? '').toString().trim();
        ChurchPanelNavigationBridge.instance.requestNavigateToChatThread(
          threadId: threadId,
          tenantId: tenantRaw.isEmpty ? null : tenantRaw,
        );
        return;
      }
    }

    if (t == 'new_member') {
      final publicRaw = (message.data['publicSignup'] ?? '').toString().trim();
      if (publicRaw == '1') {
        ChurchPanelNavigationBridge.instance
            .requestNavigateToShellIndex(kChurchShellIndexAprovacoes);
      } else {
        ChurchPanelNavigationBridge.instance
            .requestNavigateToShellIndex(kChurchShellIndexMembers);
      }
      return;
    }

    if (t == 'birthday_daily') {
      ChurchPanelNavigationBridge.instance
          .requestNavigateToShellIndex(kChurchShellIndexPainel);
      return;
    }

    if (t == 'financeiro_vencimento_digest' ||
        t == 'financeiro_vencimento_24h') {
      ChurchPanelNavigationBridge.instance
          .requestNavigateToShellIndex(kChurchShellIndexFinanceiro);
      return;
    }

    final idx = ChurchPanelNavigationBridge.shellIndexForNotificationType(type);
    if (idx != null) {
      ChurchPanelNavigationBridge.instance.requestNavigateToShellIndex(idx);
    }
  }

  /// Alinhado ao slug em Cloud Functions (`pastoralComms.slugTopicPart`).
  static String slugTopicPart(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    const from = 'àáâãäåèéêëìíîïòóôõöùúûüñç';
    const to = 'aaaaaaeeeeiiiiooooouuuunc';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.length > 48) s = s.substring(0, 48);
    return s;
  }

  Future<String> _loadMemberCargoLabel(String tenantId, String cpf) async {
    final cpfDigits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpfDigits.isEmpty) return '';

    final op = await ChurchOperationalPaths.resolve(tenantId);
    final members =         ChurchOperationalPaths.churchDoc(op)
        .collection('membros');

    final byId = await members.doc(cpfDigits).get();
    Map<String, dynamic>? data;
    if (byId.exists) {
      data = byId.data();
    } else {
      final q =
          await members.where('CPF', isEqualTo: cpfDigits).limit(1).get();
      if (q.docs.isNotEmpty) data = q.docs.first.data();
    }
    if (data == null) return '';
    final v = (data['CARGO'] ??
            data['cargo'] ??
            data['FUNCAO'] ??
            data['funcao'] ??
            '')
        .toString()
        .trim();
    return v;
  }

  Future<List<String>> _loadMemberDepartments(
    String tenantId,
    String cpf,
  ) async {
    final cpfDigits = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpfDigits.isEmpty) return <String>[];

    final op = await ChurchOperationalPaths.resolve(tenantId);
    final members =         ChurchOperationalPaths.churchDoc(op)
        .collection('membros');

    final byId = await members.doc(cpfDigits).get();
    if (byId.exists) {
      return _deptList(byId.data());
    }

    final q = await members.where('CPF', isEqualTo: cpfDigits).limit(1).get();
    if (q.docs.isNotEmpty) return _deptList(q.docs.first.data());

    return <String>[];
  }

  List<String> _deptList(Map<String, dynamic>? data) {
    if (data == null) return <String>[];
    final ids = data['departamentosIds'];
    if (ids is List && ids.isNotEmpty) {
      return ids
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final raw = data['DEPARTAMENTOS'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return <String>[];
  }
}
