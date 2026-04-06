import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _configured = false;

  Future<void> configure({
    required String uid,
    required String tenantId,
    required String cpf,
    required String role,
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    if (_configured || kIsWeb) return;
    _configured = true;

    try {
      await _configureImpl(
        uid: uid,
        tenantId: tenantId,
        cpf: cpf,
        role: role,
        onForegroundMessage: onForegroundMessage,
      );
    } catch (e, st) {
      // Evita Future rejeitado não tratado (Crashlytics fatal) se Firestore/rede falhar.
      debugPrint('FcmService.configure: $e\n$st');
    }
  }

  Future<void> _configureImpl({
    required String uid,
    required String tenantId,
    required String cpf,
    required String role,
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .set({
          'token': token,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Regras/permissão ou offline: notificações ainda podem funcionar parcialmente.
      }
    }

    List<String> deptIds = <String>[];
    var cargoLabel = '';
    try {
      deptIds = await _loadMemberDepartments(tenantId, cpf);
      cargoLabel = await _loadMemberCargoLabel(tenantId, cpf);
    } catch (_) {
      // Firestore offline/regras: ainda inscreve em tópicos da igreja/admin abaixo.
    }
    final cargoSlug = slugTopicPart(cargoLabel);
    final tid = tenantId.trim();
    final deptTopics = deptIds.map((id) => 'dept_$id').toList();
    final nextTopics = <String>[
      ...deptTopics,
      if (cargoSlug.isNotEmpty) 'cargo_$cargoSlug',
      if (tid.isNotEmpty) 'igreja_$tid',
    ];

    final prefs = await SharedPreferences.getInstance();
    final prevTopics = prefs.getStringList('church_fcm_topics') ??
        prefs.getStringList('dept_topics') ??
        <String>[];

    for (final t in prevTopics) {
      if (!nextTopics.contains(t)) {
        await messaging.unsubscribeFromTopic(t);
      }
    }
    for (final t in nextTopics) {
      if (!prevTopics.contains(t)) {
        await messaging.subscribeToTopic(t);
      }
    }

    final roleNorm = role.trim().toLowerCase();
    final isAdmin = roleNorm == 'adm' ||
        roleNorm == 'admin' ||
        roleNorm == 'administrador' ||
        roleNorm == 'gestor' ||
        roleNorm == 'master' ||
        roleNorm == 'lider' ||
        roleNorm == 'pastor' ||
        roleNorm == 'secretario' ||
        roleNorm == 'tesoureiro';
    if (isAdmin) {
      await messaging.subscribeToTopic('admin');
    }

    FirebaseMessaging.onMessage.listen((message) {
      if (onForegroundMessage != null) {
        onForegroundMessage(message);
      }
    });

    await prefs.setStringList('church_fcm_topics', nextTopics);
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

    final members = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
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

    final members = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
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
