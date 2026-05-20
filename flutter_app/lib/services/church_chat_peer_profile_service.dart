import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Perfis denormalizados para avatares no Chat Igreja (`chat_peer_profiles/{authUid}`).
class ChurchChatPeerProfileService {
  ChurchChatPeerProfileService._();

  static const int _whereInChunk = 10;
  static const Duration _cacheTtl = Duration(minutes: 15);

  static final Map<String, Map<String, ChurchChatMemberRef>> _cacheByTenant = {};
  static final Map<String, DateTime> _cacheLoadedAt = {};

  static CollectionReference<Map<String, dynamic>> _profilesCol(
    String tenantId,
  ) {
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('chat_peer_profiles');
  }

  static ChurchChatMemberRef? _refFromProfileDoc(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    if (!snap.exists) return null;
    final d = snap.data();
    if (d == null) return null;
    final authUid = (d['authUid'] ?? snap.id).toString().trim();
    if (authUid.isEmpty) return null;
    final memberId = (d['memberDocId'] ?? '').toString().trim();
    if (memberId.isEmpty) return null;
    var url = sanitizeImageUrl((d['photoUrl'] ?? '').toString());
    if (!isValidImageUrl(url)) {
      url = '';
    }
    final rev = d['fotoUrlCacheRevision'];
    final memberData = <String, dynamic>{
      'authUid': authUid,
      'firebaseUid': authUid,
      if (url.isNotEmpty) 'fotoUrl': url,
      'NOME_COMPLETO': (d['displayName'] ?? '').toString(),
      if (rev != null) 'fotoUrlCacheRevision': rev,
    };
    return ChurchChatMemberRef(
      memberId: memberId,
      data: memberData,
      authUid: authUid,
      photoUrl: url.isEmpty ? null : url,
    );
  }

  static Future<Map<String, ChurchChatMemberRef>> loadMemberRefsForAuthUids({
    required String tenantId,
    required Iterable<String> authUids,
    bool forceRefresh = false,
    Set<String>? refetchAuthUids,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return {};

    final wanted = authUids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (wanted.isEmpty) return {};

    final mustRefetch = refetchAuthUids
            ?.map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        <String>{};

    final now = DateTime.now();
    final cached = _cacheByTenant[tid];
    final loadedAt = _cacheLoadedAt[tid];
    final cacheFresh = !forceRefresh &&
        cached != null &&
        loadedAt != null &&
        now.difference(loadedAt) < _cacheTtl;

    final out = <String, ChurchChatMemberRef>{};
    final missing = <String>[];

    if (cacheFresh) {
      for (final uid in wanted) {
        if (mustRefetch.contains(uid)) {
          missing.add(uid);
          continue;
        }
        final hit = cached[uid];
        if (hit != null) {
          out[uid] = hit;
        } else {
          missing.add(uid);
        }
      }
      if (missing.isEmpty) return out;
    } else {
      missing.addAll(wanted);
      _cacheByTenant.remove(tid);
      _cacheLoadedAt.remove(tid);
    }

    final refetchFirst =
        missing.where((u) => mustRefetch.contains(u)).toList(growable: false);
    final fetchProfilesFirst =
        missing.where((u) => !mustRefetch.contains(u)).toList(growable: false);

    if (refetchFirst.isNotEmpty) {
      final fromMembros = await _fallbackFromMembros(tid, refetchFirst);
      out.addAll(fromMembros);
    }

    final needProfiles = <String>[
      ...fetchProfilesFirst,
      ...refetchFirst.where((u) => !out.containsKey(u)),
    ];
    if (needProfiles.isNotEmpty) {
      final fetched = await _fetchProfiles(tid, needProfiles);
      out.addAll(fetched);
    }

    final stillMissing = missing.where((u) => !out.containsKey(u)).toList();
    if (stillMissing.isNotEmpty) {
      final fallback = await _fallbackFromMembros(tid, stillMissing);
      out.addAll(fallback);
    }

    final store = _cacheByTenant.putIfAbsent(tid, () => {});
    store.addAll(out);
    _cacheLoadedAt[tid] = now;

    return Map.fromEntries(
      wanted.map((u) => MapEntry(u, out[u])).where((e) => e.value != null).map(
            (e) => MapEntry(e.key, e.value!),
          ),
    );
  }

  static Future<Map<String, ChurchChatMemberRef>> _fetchProfiles(
    String tenantId,
    List<String> authUids,
  ) async {
    final out = <String, ChurchChatMemberRef>{};
    for (var i = 0; i < authUids.length; i += _whereInChunk) {
      final chunk = authUids.sublist(
        i,
        i + _whereInChunk > authUids.length ? authUids.length : i + _whereInChunk,
      );
      final refs = chunk.map((u) => _profilesCol(tenantId).doc(u));
      final snaps = await Future.wait(refs.map((r) => r.get()));
      for (final snap in snaps) {
        final ref = _refFromProfileDoc(snap);
        if (ref != null) out[ref.authUid] = ref;
      }
    }
    return out;
  }

  static Future<Map<String, ChurchChatMemberRef>> _fallbackFromMembros(
    String tenantId,
    List<String> authUids,
  ) async {
    final out = <String, ChurchChatMemberRef>{};
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros');

    for (var i = 0; i < authUids.length; i += _whereInChunk) {
      final chunk = authUids.sublist(
        i,
        i + _whereInChunk > authUids.length ? authUids.length : i + _whereInChunk,
      );
      try {
        final q = await col.where('authUid', whereIn: chunk).limit(30).get();
        for (final doc in q.docs) {
          final ref = churchChatMemberRefFromMemberDoc(doc.id, doc.data());
          if (ref != null) out[ref.authUid] = ref;
        }
      } catch (_) {}

      final missingInChunk =
          chunk.where((u) => !out.containsKey(u)).toList(growable: false);
      if (missingInChunk.isEmpty) continue;
      try {
        final q2 =
            await col.where('firebaseUid', whereIn: missingInChunk).limit(30).get();
        for (final doc in q2.docs) {
          final ref = churchChatMemberRefFromMemberDoc(doc.id, doc.data());
          if (ref != null) out[ref.authUid] = ref;
        }
      } catch (_) {}
    }
    return out;
  }

  static void invalidateTenantCache(String tenantId) {
    final tid = tenantId.trim();
    _cacheByTenant.remove(tid);
    _cacheLoadedAt.remove(tid);
  }

  static void invalidateAuthUid(String tenantId, String authUid) {
    final tid = tenantId.trim();
    final uid = authUid.trim();
    if (tid.isEmpty || uid.isEmpty) return;
    _cacheByTenant[tid]?.remove(uid);
  }

  static void patchCachedMemberRef(String tenantId, ChurchChatMemberRef ref) {
    final tid = tenantId.trim();
    final uid = ref.authUid.trim();
    if (tid.isEmpty || uid.isEmpty) return;
    final store = _cacheByTenant.putIfAbsent(tid, () => {});
    store[uid] = ref;
    _cacheLoadedAt[tid] = DateTime.now();
  }
}
