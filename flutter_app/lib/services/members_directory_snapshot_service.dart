import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'firestore_stream_utils.dart';

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
      if (photoUrl != null && photoUrl!.isNotEmpty) 'fotoUrl': photoUrl,
      if (fotoUrlCacheRevision > 0)
        'fotoUrlCacheRevision': fotoUrlCacheRevision,
      if (authUid != null && authUid!.isNotEmpty) 'authUid': authUid,
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

  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    return FirebaseFirestore.instance
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
    return FirestoreStreamUtils.resilientQuery(cacheRef(tid).snapshots()).map(
      (snap) => MembersDirectorySnapshot.fromMap(snap.data()),
    );
  }

  static Future<MembersDirectorySnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    try {
      final snap = await cacheRef(tid).get();
      return MembersDirectorySnapshot.fromMap(snap.data());
    } catch (_) {
      return const MembersDirectorySnapshot();
    }
  }

  static const Duration _staleAfter = Duration(minutes: 8);

  static Future<MembersDirectorySnapshot> warmFromCallableIfStale(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    try {
      final doc = await cacheRef(tid).get();
      final u = doc.data()?['updatedAt'];
      if (u is Timestamp &&
          DateTime.now().difference(u.toDate()) < _staleAfter) {
        return MembersDirectorySnapshot.fromMap(doc.data());
      }
    } catch (_) {}
    return warmFromCallable();
  }

  static Future<MembersDirectorySnapshot> warmFromCallable() async {
    try {
      final callable = _functions.httpsCallable(
        'getChurchMembersDirectory',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final res = await callable.call<Map<String, dynamic>>({});
      final data = res.data;
      final directory = data['directory'];
      if (directory is Map) {
        return MembersDirectorySnapshot.fromMap(
          Map<String, dynamic>.from(directory),
        );
      }
    } catch (_) {}
    return const MembersDirectorySnapshot();
  }
}
