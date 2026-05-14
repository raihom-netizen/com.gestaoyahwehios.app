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
/// modo de alerta por DM / grupo, por **departamento**, por **pessoa (DM)** e por **conversa** (`threadNotifModes`).
/// Firestore: `igrejas/{tenantId}/chat_member_prefs/{uid}`.
class ChurchChatMemberPrefsModel {
  final List<String> favoriteThreadIds;
  final List<String> mutedThreadIds;
  final List<String> blockedPeerUids;

  /// `null` = herdar o modo global da conta (`users.pushChatAlertMode`).
  final String? dmNotificationStyle;

  /// `null` = herdar o modo global.
  final String? groupNotificationStyle;

  /// `threadId` → `sound` | `vibrate` | `silent` (prioridade máxima por conversa).
  final Map<String, String> threadNotifModes;

  /// `departmentId` → modo para **todos** os grupos desse departamento (antes do estilo global de grupo).
  final Map<String, String> departmentAlertModes;

  /// `peerUid` → modo para **todas** as DMs com essa pessoa (antes do estilo global de DM).
  final Map<String, String> dmPeerAlertModes;

  /// DM oculta da lista «Conversas» (só para este utilizador; não apaga o thread).
  final List<String> hiddenDmThreadIds;

  /// Ordem preferida dos grupos (ids de `departamentos/{id}`). Vazio = ordem alfabética.
  final List<String> departmentGroupOrderIds;

  const ChurchChatMemberPrefsModel({
    this.favoriteThreadIds = const [],
    this.mutedThreadIds = const [],
    this.blockedPeerUids = const [],
    this.dmNotificationStyle,
    this.groupNotificationStyle,
    this.threadNotifModes = const {},
    this.departmentAlertModes = const {},
    this.dmPeerAlertModes = const {},
    this.hiddenDmThreadIds = const [],
    this.departmentGroupOrderIds = const [],
  });

  bool isFavorite(String threadId) => favoriteThreadIds.contains(threadId);
  bool isMutedThread(String threadId) => mutedThreadIds.contains(threadId);
  bool isBlockedPeer(String peerUid) =>
      peerUid.isNotEmpty && blockedPeerUids.contains(peerUid);
  bool isHiddenDmThread(String threadId) =>
      threadId.isNotEmpty && hiddenDmThreadIds.contains(threadId);

  String? threadNotifOverride(String threadId) => threadNotifModes[threadId];

  String? departmentAlertMode(String departmentId) =>
      departmentAlertModes[departmentId];

  String? dmPeerAlertMode(String peerUid) => dmPeerAlertModes[peerUid];
}

class ChurchChatMemberPrefs {
  ChurchChatMemberPrefs._();

  /// Máximo de conversas favoritas (grupos + DM) por utilizador.
  static const int maxFavoriteThreads = 5;

  /// Máximo de conversas com alerta personalizado (mapa `threadNotifModes`).
  static const int maxThreadNotifOverrides = 30;

  /// Máximo de departamentos com modo próprio (`departmentAlertModes`).
  static const int maxDepartmentAlertModes = 40;

  /// Máximo de contactos DM com modo próprio (`dmPeerAlertModes`).
  static const int maxDmPeerAlertModes = 40;

  /// Máximo de DMs ocultas na lista (evita documento gigante).
  static const int maxHiddenDmThreads = 80;

  /// Ordem personalizada dos grupos na aba Chat (ids de departamento).
  static const int maxDepartmentGroupOrderIds = 80;

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

  /// Nunca [Stream.empty] — alguns [StreamBuilder] ficavam sem snapshot útil (área cinza).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(
      String tenantId) async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return;
    }
    yield* docRef(tenantId, uid).snapshots();
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
      departmentAlertModes: _threadNotifMap(d?['departmentAlertModes']),
      dmPeerAlertModes: _threadNotifMap(d?['dmPeerAlertModes']),
      hiddenDmThreadIds: _stringList(d?['hiddenDmThreadIds']),
      departmentGroupOrderIds: _stringList(d?['departmentGroupOrderIds']),
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

  /// Oculta ou repõe uma conversa direta na lista (não apaga mensagens nem o thread).
  static Future<bool> setHiddenDmThread({
    required String tenantId,
    required String threadId,
    required bool hide,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final tid = threadId.trim();
    if (tid.isEmpty) return false;
    if (!tid.startsWith('dm_')) return false;
    if (hide) {
      final cur = await load(tenantId);
      final ids = cur.hiddenDmThreadIds.toSet();
      if (!ids.contains(tid) && ids.length >= maxHiddenDmThreads) {
        return false;
      }
    }
    await docRef(tenantId, uid).set(
      {
        'hiddenDmThreadIds': hide
            ? FieldValue.arrayUnion([tid])
            : FieldValue.arrayRemove([tid]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
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

  /// `mode == null` remove a entrada. `false` se o mapa já está no limite.
  static Future<bool> setDepartmentAlertMode({
    required String tenantId,
    required String departmentId,
    required String? mode,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final id = departmentId.trim();
    if (id.isEmpty) return false;
    final cur = await load(tenantId);
    final map = Map<String, String>.from(cur.departmentAlertModes);
    if (mode == null) {
      map.remove(id);
    } else {
      if (!map.containsKey(id) && map.length >= maxDepartmentAlertModes) {
        return false;
      }
      map[id] = _normalizeChatAlertMode(mode);
    }
    await docRef(tenantId, uid).set(
      {
        'departmentAlertModes': map,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// Modo de alerta para todas as DMs com [peerUid] (outro participante).
  static Future<bool> setDmPeerAlertMode({
    required String tenantId,
    required String peerUid,
    required String? mode,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final pid = peerUid.trim();
    if (pid.isEmpty || pid == uid) return false;
    final cur = await load(tenantId);
    final map = Map<String, String>.from(cur.dmPeerAlertModes);
    if (mode == null) {
      map.remove(pid);
    } else {
      if (!map.containsKey(pid) && map.length >= maxDmPeerAlertModes) {
        return false;
      }
      map[pid] = _normalizeChatAlertMode(mode);
    }
    await docRef(tenantId, uid).set(
      {
        'dmPeerAlertModes': map,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  /// Grava a ordem dos grupos (aba Grupos). Lista vazia remove preferência (volta ao A–Z).
  static Future<void> setDepartmentGroupOrder({
    required String tenantId,
    required List<String> departmentIdsInOrder,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final cleaned = departmentIdsInOrder
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(maxDepartmentGroupOrderIds)
        .toList();
    await docRef(tenantId, uid).set(
      {
        'departmentGroupOrderIds': cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Volta à ordenação alfabética na aba Grupos.
  static Future<void> clearDepartmentGroupOrder(String tenantId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await docRef(tenantId, uid).set(
      {
        'departmentGroupOrderIds': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
