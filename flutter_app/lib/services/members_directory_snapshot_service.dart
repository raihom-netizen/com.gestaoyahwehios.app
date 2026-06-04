import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'firestore_stream_utils.dart' show FirestoreStreamUtils, MergedFirestoreQuerySnapshot;

/// Entrada leve em `igrejas/{tid}/_panel_cache/members_directory`.
class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.memberDocId,
    required this.displayName,
    this.photoUrl,
    this.fotoUrlCacheRevision = 0,
    this.authUid,
    this.cpfDigits,
    this.email,
    this.telefone,
    this.status = 'ativo',
    this.funcao,
    this.funcoes = const [],
    this.departamentos = const [],
    this.genero,
    this.createdAt,
    this.updatedAt,
    this.dataNascimento,
  });

  final String memberDocId;
  final String displayName;
  final String? photoUrl;
  final int fotoUrlCacheRevision;
  final String? authUid;
  final String? cpfDigits;
  final String? email;
  final String? telefone;
  final String status;
  final String? funcao;
  final List<String> funcoes;
  final List<String> departamentos;
  final String? genero;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final dynamic dataNascimento;

  factory MemberDirectoryEntry.fromMap(Map<String, dynamic> raw) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }

    Timestamp? ts(dynamic v) => v is Timestamp ? v : null;
    final photo = (raw['photoUrl'] ?? '').toString().trim();

    return MemberDirectoryEntry(
      memberDocId: (raw['memberDocId'] ?? '').toString(),
      displayName: (raw['displayName'] ?? 'Membro').toString(),
      photoUrl: photo.isEmpty ? null : photo,
      fotoUrlCacheRevision: n(raw['fotoUrlCacheRevision']),
      authUid: (raw['authUid'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['authUid'] ?? '').toString(),
      cpfDigits: (raw['cpfDigits'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['cpfDigits'] ?? '').toString(),
      email: (raw['email'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['email'] ?? '').toString(),
      telefone: (raw['telefone'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['telefone'] ?? '').toString(),
      status: (raw['status'] ?? raw['STATUS'] ?? 'ativo').toString(),
      funcao: (raw['funcao'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['funcao'] ?? '').toString(),
      funcoes: strList(raw['funcoes']),
      departamentos: strList(raw['departamentos']),
      genero: (raw['genero'] ?? '').toString().trim().isEmpty
          ? null
          : (raw['genero'] ?? '').toString(),
      createdAt: ts(raw['createdAt']),
      updatedAt: ts(raw['updatedAt']),
      dataNascimento: raw['dataNascimento'],
    );
  }

  /// Mapa compatível com filtros / [FotoMembroWidget] da lista de membros.
  Map<String, dynamic> toMemberDataMap() {
    return <String, dynamic>{
      'NOME_COMPLETO': displayName,
      if (photoUrl != null && photoUrl!.isNotEmpty) ...{
        'fotoUrl': photoUrl,
        'photoThumb': photoUrl,
        'photoMedium': photoUrl,
      },
      if (fotoUrlCacheRevision > 0)
        'fotoUrlCacheRevision': fotoUrlCacheRevision,
      if (authUid != null && authUid!.isNotEmpty) ...{
        'authUid': authUid,
        'firebaseUid': authUid,
      },
      if (cpfDigits != null && cpfDigits!.isNotEmpty) 'CPF': cpfDigits,
      if (email != null && email!.isNotEmpty) 'EMAIL': email,
      if (telefone != null && telefone!.isNotEmpty) 'TELEFONES': telefone,
      'STATUS': status,
      'status': status,
      if (funcao != null && funcao!.isNotEmpty) 'FUNCAO': funcao,
      if (funcoes.isNotEmpty) 'FUNCOES': funcoes,
      if (departamentos.isNotEmpty) 'DEPARTAMENTOS': departamentos,
      if (genero != null && genero!.isNotEmpty) 'SEXO': genero,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (dataNascimento != null) 'DATA_NASCIMENTO': dataNascimento,
    };
  }
}

/// Cache `_panel_cache/members_directory` — lista instantânea no módulo Membros.
class MembersDirectorySnapshot {
  final int totalCount;
  final List<MemberDirectoryEntry> entries;

  const MembersDirectorySnapshot({
    this.totalCount = 0,
    this.entries = const [],
  });

  bool get hasEntries => entries.isNotEmpty;

  factory MembersDirectorySnapshot.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const MembersDirectorySnapshot();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final list = raw['entries'];
    final entries = list is List
        ? list
            .whereType<Map>()
            .map((e) => MemberDirectoryEntry.fromMap(
                  Map<String, dynamic>.from(e),
                ))
            .toList()
        : <MemberDirectoryEntry>[];
    return MembersDirectorySnapshot(
      totalCount: n(raw['totalCount']),
      entries: entries,
    );
  }
}

class MembersDirectorySnapshotService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static final Map<String, MembersDirectorySnapshot> _memoryByTenant = {};

  static void rememberInMemory(String tenantId, MembersDirectorySnapshot snap) {
    final tid = tenantId.trim();
    if (tid.isEmpty || !snap.hasEntries) return;
    _memoryByTenant[tid] = snap;
  }

  static MembersDirectorySnapshot? peekMemory(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    final m = _memoryByTenant[tid];
    if (m != null && m.hasEntries) return m;
    return null;
  }

  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tenantId.trim())
        .collection('_panel_cache')
        .doc('members_directory');
  }

  static Stream<MembersDirectorySnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const MembersDirectorySnapshot());
    }
    return FirestoreStreamUtils.documentWatchBootstrap(cacheRef(tid)).map(
      (snap) => MembersDirectorySnapshot.fromMap(snap.data()),
    );
  }

  static Future<MembersDirectorySnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    final mem = peekMemory(tid);
    if (mem != null) return mem;
    try {
      final cached = await cacheRef(tid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      final fromCache = MembersDirectorySnapshot.fromMap(cached.data());
      if (fromCache.hasEntries) {
        rememberInMemory(tid, fromCache);
        return fromCache;
      }
    } catch (_) {}
    try {
      final snap = await cacheRef(tid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      final fromServer = MembersDirectorySnapshot.fromMap(snap.data());
      if (fromServer.hasEntries) {
        rememberInMemory(tid, fromServer);
      }
      return fromServer;
    } catch (_) {
      return peekMemory(tid) ?? const MembersDirectorySnapshot();
    }
  }

  static const Duration _staleAfter = Duration(minutes: 8);

  static Future<MembersDirectorySnapshot> warmFromCallableIfStale(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    final mem = peekMemory(tid);
    if (mem != null) return mem;
    try {
      final doc = await cacheRef(tid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp &&
          DateTime.now().difference(u.toDate()) < _staleAfter) {
        final fresh = MembersDirectorySnapshot.fromMap(doc.data());
        if (fresh.hasEntries) {
          rememberInMemory(tid, fresh);
          return fresh;
        }
      }
    } catch (_) {}
    return warmFromCallable(tenantId: tid);
  }

  static Future<MembersDirectorySnapshot> warmFromCallable({
    String? tenantId,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'getChurchMembersDirectory',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 18)),
      );
      final payload = <String, dynamic>{};
      final tidArg = (tenantId ?? '').trim();
      if (tidArg.isNotEmpty) payload['tenantId'] = tidArg;
      final res = await callable
          .call<Map<String, dynamic>>(payload)
          .timeout(const Duration(seconds: 20));
      final data = res.data;
      final directory = data['directory'];
      if (directory is Map) {
        final snap = MembersDirectorySnapshot.fromMap(
          Map<String, dynamic>.from(directory),
        );
        final tid = (tenantId ?? data['tenantId'] ?? '').toString().trim();
        if (tid.isNotEmpty && snap.hasEntries) {
          rememberInMemory(tid, snap);
        }
        return snap;
      }
    } catch (_) {}
    return const MembersDirectorySnapshot();
  }

  /// Converte entradas do cache em snapshot compatível com gráficos / stats do painel.
  static MergedFirestoreQuerySnapshot toMergedQuerySnapshot(
    String tenantId,
    MembersDirectorySnapshot snap,
  ) {
    final tid = tenantId.trim();
    if (tid.isEmpty || !snap.hasEntries) {
      return const MergedFirestoreQuerySnapshot([]);
    }
    final baseRef = firebaseDefaultFirestore.collection('igrejas').doc(tid);
    final docs = snap.entries.map((e) {
      final id = e.memberDocId.trim().isNotEmpty ? e.memberDocId.trim() : 'dir_${e.displayName.hashCode}';
      return _DirectoryMemberQueryDocumentSnapshot(
        reference: baseRef.collection('membros').doc(id),
        docId: id,
        data: e.toMemberDataMap(),
      );
    }).toList();
    return MergedFirestoreQuerySnapshot(docs);
  }
}

// ignore: subtype_of_sealed_class — paint instantâneo a partir de `_panel_cache/members_directory`.
class _DirectoryMemberQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _DirectoryMemberQueryDocumentSnapshot({
    required this.reference,
    required this.docId,
    required Map<String, dynamic> data,
  }) : _data = data;

  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final String docId;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  bool get exists => true;

  @override
  String get id => docId;

  @override
  SnapshotMetadata get metadata => const _DirectorySnapshotMetadata();
}

class _DirectorySnapshotMetadata implements SnapshotMetadata {
  const _DirectorySnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
