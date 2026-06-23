import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/utils/firestore_reliable_read.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferências de push — cache local + `users/{uid}` + `config_notificacoes` no membro.
class ChurchMemberNotificationPrefs {
  const ChurchMemberNotificationPrefs({
    this.receberAvisos = true,
    this.receberEscalas = true,
    this.receberEventosTempo = true,
    this.receberAniversariantes = true,
    this.receberChat = true,
    this.receberFinanceiroTempo = false,
  });

  final bool receberAvisos;
  final bool receberEscalas;
  final bool receberEventosTempo;
  final bool receberAniversariantes;
  final bool receberChat;
  final bool receberFinanceiroTempo;

  ChurchMemberNotificationPrefs copyWith({
    bool? receberAvisos,
    bool? receberEscalas,
    bool? receberEventosTempo,
    bool? receberAniversariantes,
    bool? receberChat,
    bool? receberFinanceiroTempo,
  }) {
    return ChurchMemberNotificationPrefs(
      receberAvisos: receberAvisos ?? this.receberAvisos,
      receberEscalas: receberEscalas ?? this.receberEscalas,
      receberEventosTempo: receberEventosTempo ?? this.receberEventosTempo,
      receberAniversariantes:
          receberAniversariantes ?? this.receberAniversariantes,
      receberChat: receberChat ?? this.receberChat,
      receberFinanceiroTempo:
          receberFinanceiroTempo ?? this.receberFinanceiroTempo,
    );
  }

  Map<String, dynamic> toMap() => {
        'receberAvisos': receberAvisos,
        'receberEscalas': receberEscalas,
        'receberEventosTempo': receberEventosTempo,
        'receberAniversariantes': receberAniversariantes,
        'receberChat': receberChat,
        'receberFinanceiroTempo': receberFinanceiroTempo,
      };

  static ChurchMemberNotificationPrefs fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const ChurchMemberNotificationPrefs();
    bool b(String k, bool def) => raw[k] is bool ? raw[k] as bool : def;
    return ChurchMemberNotificationPrefs(
      receberAvisos: b('receberAvisos', true),
      receberEscalas: b('receberEscalas', true),
      receberEventosTempo: b('receberEventosTempo', true),
      receberAniversariantes: b('receberAniversariantes', true),
      receberChat: b('receberChat', true),
      receberFinanceiroTempo: b('receberFinanceiroTempo', false),
    );
  }

  /// Campos legados em `users/{uid}` (compatível com [FcmService]).
  Map<String, dynamic> toLegacyUserFields() => {
        'pushAvisos': receberAvisos,
        'pushEventos': receberEventosTempo,
        'pushEscalas': receberEscalas,
        'pushAniversariantes': receberAniversariantes,
        'pushChat': receberChat,
        'pushFornecedorAgenda': receberFinanceiroTempo,
        'config_notificacoes': toMap(),
      };
}

abstract final class ChurchMemberNotificationPrefsService {
  ChurchMemberNotificationPrefsService._();

  static const String field = 'config_notificacoes';

  static ChurchMemberNotificationPrefs fromLegacyUserDoc(
    Map<String, dynamic>? d,
  ) {
    if (d == null) return const ChurchMemberNotificationPrefs();
    final nested = d[field];
    if (nested is Map) {
      return ChurchMemberNotificationPrefs.fromMap(
        Map<String, dynamic>.from(nested),
      );
    }
    return ChurchMemberNotificationPrefs(
      receberAvisos: d['pushAvisos'] is bool ? d['pushAvisos'] as bool : true,
      receberEscalas: d['pushEscalas'] is bool ? d['pushEscalas'] as bool : true,
      receberEventosTempo:
          d['pushEventos'] is bool ? d['pushEventos'] as bool : true,
      receberAniversariantes: d['pushAniversariantes'] is bool
          ? d['pushAniversariantes'] as bool
          : true,
      receberChat: d['pushChat'] is bool ? d['pushChat'] as bool : true,
      receberFinanceiroTempo: d['pushFornecedorAgenda'] is bool
          ? d['pushFornecedorAgenda'] as bool
          : false,
    );
  }

  static Future<ChurchMemberNotificationPrefs> load({
    required String uid,
    String? churchIdHint,
    String? memberDocIdHint,
  }) async {
    ChurchMemberNotificationPrefs fromSp = const ChurchMemberNotificationPrefs();
    try {
      final prefs = await SharedPreferences.getInstance();
      fromSp = ChurchMemberNotificationPrefs(
        receberAvisos: prefs.getBool('notif_avisos') ?? true,
        receberEscalas: prefs.getBool('notif_escalas') ?? true,
        receberEventosTempo: prefs.getBool('notif_eventos') ?? true,
        receberAniversariantes: prefs.getBool('notif_aniversariantes') ?? true,
        receberChat: prefs.getBool('notif_chat') ?? true,
        receberFinanceiroTempo: prefs.getBool('notif_fornecedor') ?? false,
      );
    } catch (_) {}

    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final userSnap = await firestoreDocumentGetReliable(
        firebaseDefaultFirestore.collection('users').doc(uid.trim()),
      ).timeout(const Duration(seconds: 6));
      var out = fromLegacyUserDoc(userSnap.data());

      final churchId = ChurchRepository.churchId(churchIdHint ?? '');
      final memberId = (memberDocIdHint ?? '').trim();
      if (churchId.isNotEmpty && memberId.isNotEmpty) {
        try {
          final mSnap = await ChurchUiCollections.membros(churchId)
              .doc(memberId)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 3));
          final nested = mSnap.data()?[field];
          if (nested is Map) {
            out = ChurchMemberNotificationPrefs.fromMap(
              Map<String, dynamic>.from(nested),
            );
          }
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return fromSp;
    }
  }

  static Future<void> save({
    required String uid,
    required ChurchMemberNotificationPrefs prefs,
    String? churchIdHint,
    String? memberDocIdHint,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('notif_avisos', prefs.receberAvisos);
    await sp.setBool('notif_eventos', prefs.receberEventosTempo);
    await sp.setBool('notif_escalas', prefs.receberEscalas);
    await sp.setBool('notif_aniversariantes', prefs.receberAniversariantes);
    await sp.setBool('notif_chat', prefs.receberChat);
    await sp.setBool('notif_fornecedor', prefs.receberFinanceiroTempo);

    final payload = prefs.toLegacyUserFields();
    await firebaseDefaultFirestore
        .collection('users')
        .doc(uid.trim())
        .set(payload, SetOptions(merge: true));

    final churchId = ChurchRepository.churchId(churchIdHint ?? '');
    final memberId = (memberDocIdHint ?? uid).trim();
    if (churchId.isNotEmpty && memberId.isNotEmpty) {
      try {
        await ChurchUiCollections.membros(churchId)
            .doc(memberId)
            .set({field: prefs.toMap()}, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}
