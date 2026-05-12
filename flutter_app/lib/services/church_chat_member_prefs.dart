import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Modos de alerta (alinhados a [ChurchChatNotificationPrefs]).
const Set<String> _kChatAlertModes = {'sound', 'vibrate', 'silent'};

String _normalizeChatAlertMode(String raw) {
  final m = raw.trim().toLowerCase();
  if (_kChatAlertModes.contains(m)) return m;
  return 'sound';
}

/// Preferências por utilizador na igreja: favoritos, silenciar conversa, bloquear contacto (DM),
/// modo de alerta por DM / grupo e por conversa (`threadNotifModes`).
/// Firestore: `igrejas/{tenantId}/chat_member_prefs/{uid}`.
class ChurchChatMemberPrefsModel {
  final List<String> favoriteThreadIds;
  final List<String> mutedThreadIds;
  final List<String> blockedPeerUids;

  /// `null` = herdar o modo global da conta (`users.pushChatAlertMode`).
  final String? dmNotificationStyle;

  /// `null` = herdar o modo global.
  final String? groupNotificationStyle;

  /// `threadId` → `sound` | `vibrate` | `silent` (sobrepõe DM/grupo/global).
  final Map<String, String> threadNotifModes;

  const ChurchChatMemberPrefsModel({
    this.favoriteThreadIds = const [],
    this.mutedThreadIds = const [],
    this.blockedPeerUids = const [],
    this.dmNotificationStyle,
    this.groupNotificationStyle,
    this.threadNotifModes = const {},
  });

  bool isFavorite(String threadId) => favoriteThreadIds.contains(threadId);
  bool isMutedThread(String threadId) => mutedThreadIds.contains(threadId);
  bool isBlockedPeer(String peerUid) =>
      peerUid.isNotEmpty && blockedPeerUids.contains(peerUid);

  String? threadNotifOverride(String threadId) => threadNotifModes[threadId];
}

class ChurchChatMemberPrefs {
  ChurchChatMemberPrefs._();

  /// Máximo de conversas favoritas (grupos + DM) por utilizador.
  static const int maxFavoriteThreads = 5;

  /// Máximo de conversas com alerta personalizado (mapa `threadNotifModes`).
  static const int maxThreadNotifOverrides = 30;

  static DocumentReference<Map<String, dynamic>> docRef(
    String tenantId,
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('chat_member_prefs')
        .doc(uid);
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String tenantId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return docRef(tenantId, uid).snapshots();
  }

  static ChurchChatMemberPrefsModel parse(
    DocumentSnapshot<Map<String, dynamic>>? snap,
  ) {
    final d = snap?.data();
    return ChurchChatMemberPrefsModel(
      favoriteThreadIds: _stringList(d?['favoriteThreadIds']),
      mutedThreadIds: _stringList(d?['mutedThreadIds']),
      blockedPeerUids: _stringList(d?['blockedPeerUids']),
      dmNotificationStyle: _optionalAlertMode(d?['dmNotificationStyle']),
      groupNotificationStyle: _optionalAlertMode(d?['groupNotificationStyle']),
      threadNotifModes: _threadNotifMap(d?['threadNotifModes']),
    );
  }

  static String? _optionalAlertMode(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String || raw.trim().isEmpty) return null;
    return _normalizeChatAlertMode(raw);
  }

  static Map<String, String> _threadNotifMap(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final id = k.toString().trim();
      if (id.isEmpty) return;
      if (v is! String || v.trim().isEmpty) return;
      out[id] = _normalizeChatAlertMode(v);
    });
    return out;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  static Future<ChurchChatMemberPrefsModel> load(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const ChurchChatMemberPrefsModel();
    final snap = await docRef(tenantId, uid).get();
    return parse(snap);
  }

  /// Remove favorito: sempre `true`. Adicionar: `false` se já existirem [maxFavoriteThreads] favoritos.
  static Future<bool> setFavorite({
    required String tenantId,
    required String threadId,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (value) {
      final cur = await load(tenantId);
      final ids = cur.favoriteThreadIds.toSet();
      if (!ids.contains(threadId) && ids.length >= maxFavoriteThreads) {
        return false;
      }
    }
    await docRef(tenantId, uid).set(
      {
        'favoriteThreadIds': value
            ? FieldValue.arrayUnion([threadId])
            : FieldValue.arrayRemove([threadId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  static Future<void> setMutedThread({
    required String tenantId,
    required String threadId,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await docRef(tenantId, uid).set(
      {
        'mutedThreadIds': value
            ? FieldValue.arrayUnion([threadId])
            : FieldValue.arrayRemove([threadId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setBlockedPeer({
    required String tenantId,
    required String peerUid,
    required bool value,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await docRef(tenantId, uid).set(
      {
        'blockedPeerUids': value
            ? FieldValue.arrayUnion([peerUid])
            : FieldValue.arrayRemove([peerUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setDmNotificationStyle({
    required String tenantId,
    required String? mode,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (mode == null) {
      await docRef(tenantId, uid).set(
        {
          'dmNotificationStyle': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }
    await docRef(tenantId, uid).set(
      {
        'dmNotificationStyle': _normalizeChatAlertMode(mode),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setGroupNotificationStyle({
    required String tenantId,
    required String? mode,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (mode == null) {
      await docRef(tenantId, uid).set(
        {
          'groupNotificationStyle': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }
    await docRef(tenantId, uid).set(
      {
        'groupNotificationStyle': _normalizeChatAlertMode(mode),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// `mode == null` remove a entrada. `false` se o mapa já está no limite.
  static Future<bool> setThreadNotificationOverride({
    required String tenantId,
    required String threadId,
    required String? mode,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final cur = await load(tenantId);
    final map = Map<String, String>.from(cur.threadNotifModes);
    if (mode == null) {
      map.remove(threadId);
    } else {
      if (!map.containsKey(threadId) &&
          map.length >= maxThreadNotifOverrides) {
        return false;
      }
      map[threadId] = _normalizeChatAlertMode(mode);
    }
    await docRef(tenantId, uid).set(
      {
        'threadNotifModes': map,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// DM: não enviar se bloqueou o interlocutor.
  static Future<bool> canSendToDmThread({
    required String tenantId,
    required String threadId,
  }) async {
    if (!threadId.startsWith('dm_')) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final thread =
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tenantId)
            .collection('chat_threads')
            .doc(threadId)
            .get();
    final peers = thread.data()?['participantUids'];
    if (peers is! List) return true;
    String peer = '';
    for (final p in peers) {
      if (p.toString() != uid) peer = p.toString();
    }
    if (peer.isEmpty) return true;
    final prefs = await load(tenantId);
    return !prefs.isBlockedPeer(peer);
  }
}
