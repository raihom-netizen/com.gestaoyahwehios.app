import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/firestore_map_fields.dart';
import 'package:gestao_yahweh/core/models/blind_member_doc.dart';
import 'package:gestao_yahweh/ui/widgets/member_display_name_utils.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'firestore_stream_utils.dart' show FirestoreStreamUtils, MergedFirestoreQuerySnapshot;

/// Entrada leve em `igrejas/{tid}/_panel_cache/members_directory`.
class MemberDirectoryEntry {
  const MemberDirectoryEntry({
    required this.memberDocId,
    required this.displayName,
    this.photoUrl,
    this.photoThumbUrl,
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
    this.carteirinhaAssinadaEm,
    this.carteirinhaAssinadaPor,
    this.carteirinhaAssinadaPorNome,
    this.carteirinhaAssinadaPorCargo,
    this.carteirinhaAssinaturaUrl,
  });

  final String memberDocId;
  final String displayName;
  final String? photoUrl;
  final String? photoThumbUrl;
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
  /// Timestamp Firestore ou ISO local — estado da assinatura da carteirinha.
  final dynamic carteirinhaAssinadaEm;
  final String? carteirinhaAssinadaPor;
  final String? carteirinhaAssinadaPorNome;
  final String? carteirinhaAssinadaPorCargo;
  final String? carteirinhaAssinaturaUrl;

  factory MemberDirectoryEntry.fromMap(Map<String, dynamic> raw) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    List<String> strList(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }

    Timestamp? ts(dynamic v) => v is Timestamp ? v : null;
    final photo = (raw['photoUrl'] ?? raw['fotoUrl'] ?? '').toString().trim();
    final thumb =
        (raw['photoThumbUrl'] ?? raw['fotoThumbUrl'] ?? raw['photoThumb'] ?? '')
            .toString()
            .trim();

    return MemberDirectoryEntry(
      memberDocId: (raw['memberDocId'] ?? '').toString(),
      displayName: memberDisplayNameFromData(raw),
      photoUrl: photo.isEmpty ? null : photo,
      photoThumbUrl: thumb.isEmpty ? null : thumb,
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
      carteirinhaAssinadaEm: raw['carteirinhaAssinadaEm'],
      carteirinhaAssinadaPor: _pickOptStr(raw['carteirinhaAssinadaPor']),
      carteirinhaAssinadaPorNome: _pickOptStr(raw['carteirinhaAssinadaPorNome']),
      carteirinhaAssinadaPorCargo: _pickOptStr(raw['carteirinhaAssinadaPorCargo']),
      carteirinhaAssinaturaUrl: _pickOptStr(raw['carteirinhaAssinaturaUrl']),
    );
  }

  static String? _pickOptStr(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Mapa compatível com filtros / [FotoMembroWidget] da lista de membros.
  Map<String, dynamic> toMemberDataMap() {
    final thumb = (photoThumbUrl != null && photoThumbUrl!.isNotEmpty)
        ? photoThumbUrl
        : photoUrl;
    return <String, dynamic>{
      'NOME_COMPLETO': displayName,
      if (photoUrl != null && photoUrl!.isNotEmpty) ...{
        'fotoUrl': photoUrl,
        'FOTO_URL_OU_ID': photoUrl,
      },
      if (thumb != null && thumb.isNotEmpty) ...{
        'fotoThumbUrl': thumb,
        'photoThumb': thumb,
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
      if (carteirinhaAssinadaEm != null)
        'carteirinhaAssinadaEm': carteirinhaAssinadaEm,
      if (carteirinhaAssinadaPor != null &&
          carteirinhaAssinadaPor!.trim().isNotEmpty)
        'carteirinhaAssinadaPor': carteirinhaAssinadaPor,
      if (carteirinhaAssinadaPorNome != null &&
          carteirinhaAssinadaPorNome!.trim().isNotEmpty)
        'carteirinhaAssinadaPorNome': carteirinhaAssinadaPorNome,
      if (carteirinhaAssinadaPorCargo != null &&
          carteirinhaAssinadaPorCargo!.trim().isNotEmpty)
        'carteirinhaAssinadaPorCargo': carteirinhaAssinadaPorCargo,
      if (carteirinhaAssinaturaUrl != null &&
          carteirinhaAssinaturaUrl!.trim().isNotEmpty)
        'carteirinhaAssinaturaUrl': carteirinhaAssinaturaUrl,
    };
  }

  /// Mescla campos gravados no Firestore — lista/painel actualizam sem reload.
  MemberDirectoryEntry mergeFirestoreFields(Map<String, dynamic> fields) {
    final name = FirestoreMapFields.pickString(
      fields,
      const ['NOME_COMPLETO', 'nome', 'name'],
      fallback: displayName,
    );
    final st = FirestoreMapFields.pickString(
      fields,
      const ['STATUS', 'status'],
      fallback: status,
    );
    final fn = FirestoreMapFields.pickString(
      fields,
      const ['FUNCAO', 'funcao', 'CARGO', 'cargo'],
      fallback: funcao ?? '',
    );
    final mail = FirestoreMapFields.pickString(
      fields,
      const ['EMAIL', 'email'],
      fallback: email ?? '',
    );
    final tel = FirestoreMapFields.pickString(
      fields,
      const ['TELEFONES', 'TELEFONE', 'telefone'],
      fallback: telefone ?? '',
    );
    final gen = FirestoreMapFields.pickString(
      fields,
      const ['SEXO', 'sexo', 'genero'],
      fallback: genero ?? '',
    );
    final cpf = FirestoreMapFields.pickCpfDigits(fields);
    final dn = fields['DATA_NASCIMENTO'] ?? fields['dataNascimento'] ?? dataNascimento;
    final funcoesMerged = FirestoreMapFields.pickStringList(
      fields,
      const ['FUNCOES', 'funcoes'],
      fallback: funcoes,
    );
    final incomingPhotoRevision = FirestoreMapFields.pickInt(
      fields,
      const ['fotoUrlCacheRevision'],
    );

    final assinadaEm = fields.containsKey('carteirinhaAssinadaEm')
        ? fields['carteirinhaAssinadaEm']
        : carteirinhaAssinadaEm;
    final assinadaPor = FirestoreMapFields.pickString(
      fields,
      const ['carteirinhaAssinadaPor'],
      fallback: carteirinhaAssinadaPor ?? '',
    );
    final assinadaPorNome = FirestoreMapFields.pickString(
      fields,
      const ['carteirinhaAssinadaPorNome'],
      fallback: carteirinhaAssinadaPorNome ?? '',
    );
    final assinadaPorCargo = FirestoreMapFields.pickString(
      fields,
      const ['carteirinhaAssinadaPorCargo'],
      fallback: carteirinhaAssinadaPorCargo ?? '',
    );
    final assinaturaUrl = FirestoreMapFields.pickString(
      fields,
      const ['carteirinhaAssinaturaUrl'],
      fallback: carteirinhaAssinaturaUrl ?? '',
    );

    return MemberDirectoryEntry(
      memberDocId: memberDocId,
      displayName: name,
      photoUrl: _pickOptional(fields, const ['fotoUrl', 'photoUrl', 'FOTO_URL_OU_ID'], photoUrl),
      photoThumbUrl: _pickOptional(
        fields,
        const ['fotoThumbUrl', 'photoThumbUrl', 'photoThumb'],
        photoThumbUrl,
      ),
      fotoUrlCacheRevision: incomingPhotoRevision > 0
          ? incomingPhotoRevision
          : fotoUrlCacheRevision,
      authUid: authUid,
      cpfDigits: cpf.isEmpty ? cpfDigits : cpf,
      email: mail.isEmpty ? email : mail,
      telefone: tel.isEmpty ? telefone : tel,
      status: st,
      funcao: fn.isEmpty ? funcao : fn,
      funcoes: funcoesMerged,
      departamentos: departamentos,
      genero: gen.isEmpty ? genero : gen,
      createdAt: createdAt,
      updatedAt: Timestamp.now(),
      dataNascimento: dn,
      carteirinhaAssinadaEm: assinadaEm,
      carteirinhaAssinadaPor:
          assinadaPor.isEmpty ? carteirinhaAssinadaPor : assinadaPor,
      carteirinhaAssinadaPorNome: assinadaPorNome.isEmpty
          ? carteirinhaAssinadaPorNome
          : assinadaPorNome,
      carteirinhaAssinadaPorCargo: assinadaPorCargo.isEmpty
          ? carteirinhaAssinadaPorCargo
          : assinadaPorCargo,
      carteirinhaAssinaturaUrl:
          assinaturaUrl.isEmpty ? carteirinhaAssinaturaUrl : assinaturaUrl,
    );
  }

  /// Entrada blindada a partir de documento Firestore real.
  static MemberDirectoryEntry fromFirestoreDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      BlindMemberDoc.fromSnapshot(doc).toDirectoryEntry();

  static String? _pickOptional(
    Map<String, dynamic> fields,
    List<String> keys,
    String? current,
  ) {
    final picked = FirestoreMapFields.pickString(fields, keys);
    return picked.isEmpty ? current : picked;
  }
}

/// Totais agregados — válidos mesmo quando `entries` ainda está a sincronizar.
class MembersDirectorySummary {
  const MembersDirectorySummary({
    this.total = 0,
    this.ativos = 0,
    this.inativos = 0,
    this.pendentes = 0,
    this.homens = 0,
    this.mulheres = 0,
    this.sexoNi = 0,
  });

  final int total;
  final int ativos;
  final int inativos;
  final int pendentes;
  final int homens;
  final int mulheres;
  final int sexoNi;

  factory MembersDirectorySummary.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const MembersDirectorySummary();
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return MembersDirectorySummary(
      total: n(raw['total']),
      ativos: n(raw['ativos']),
      inativos: n(raw['inativos']),
      pendentes: n(raw['pendentes']),
      homens: n(raw['homens']),
      mulheres: n(raw['mulheres']),
      sexoNi: n(raw['sexoNi']),
    );
  }

  bool get hasCounts => total > 0 || ativos > 0 || homens > 0 || mulheres > 0;
}

/// Cache `_panel_cache/members_directory` — lista instantânea no módulo Membros.
class MembersDirectorySnapshot {
  final int totalCount;
  final List<MemberDirectoryEntry> entries;
  final MembersDirectorySummary? summary;

  const MembersDirectorySnapshot({
    this.totalCount = 0,
    this.entries = const [],
    this.summary,
  });

  bool get hasEntries => entries.isNotEmpty;

  bool get isCompleteForStats =>
      totalCount > 0 && entries.length >= totalCount;

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
    final summaryRaw = raw['summary'];
    final summary = summaryRaw is Map
        ? MembersDirectorySummary.fromMap(
            Map<String, dynamic>.from(summaryRaw),
          )
        : null;
    return MembersDirectorySnapshot(
      totalCount: n(raw['totalCount']),
      entries: entries,
      summary: summary?.hasCounts == true ? summary : null,
    );
  }
}

class MembersDirectorySnapshotService {
  static final _functions =
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static final Map<String, MembersDirectorySnapshot> _memoryByTenant = {};

  static void rememberInMemory(String tenantId, MembersDirectorySnapshot snap) {
    final tid = tenantId.trim();
    if (tid.isEmpty || !snap.hasEntries) return;
    final filtered = snap.entries
        .where(
          (e) => !TenantDeletedDocTombstones.contains(
            tid,
            TenantModuleKeys.membros,
            e.memberDocId,
          ),
        )
        .toList();
    if (filtered.isEmpty) return;
    _memoryByTenant[tid] = MembersDirectorySnapshot(
      totalCount: snap.totalCount,
      entries: filtered,
      summary: snap.summary,
    );
  }

  /// Atualiza assinatura da carteirinha no cache RAM (Cartão membro / Membros).
  static void patchMembersSignatureInMemory({
    required String tenantId,
    required Iterable<String> memberIds,
    required Map<String, dynamic> signatureFields,
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty || signatureFields.isEmpty) return;
    final snap = peekMemory(tid);
    if (snap == null || !snap.hasEntries) return;
    final idSet = memberIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (idSet.isEmpty) return;
    var touched = false;
    final entries = snap.entries.map((e) {
      if (!idSet.contains(e.memberDocId)) return e;
      touched = true;
      return e.mergeFirestoreFields(signatureFields);
    }).toList();
    if (!touched) return;
    rememberInMemory(
      tid,
      MembersDirectorySnapshot(
        totalCount: snap.totalCount,
        entries: entries,
        summary: snap.summary,
      ),
    );
  }

  /// Propaga foto nova no directory RAM — painel, chat e cartão sem esperar CF.
  static void patchMemberPhotoInMemory({
    required String tenantId,
    required String memberDocId,
    String? authUid,
    String? photoUrl,
    String? photoThumbUrl,
    String? photoStoragePath,
    String? photoThumbStoragePath,
    required int cacheRevision,
  }) {
    final tid = tenantId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    final snap = peekMemory(tid);
    if (snap == null || !snap.hasEntries) return;
    final au = (authUid ?? '').trim();
    final fields = <String, dynamic>{
      'fotoUrlCacheRevision': cacheRevision,
      if ((photoUrl ?? '').trim().isNotEmpty) ...{
        'fotoUrl': photoUrl!.trim(),
        'photoUrl': photoUrl.trim(),
        'FOTO_URL_OU_ID': photoUrl.trim(),
      },
      if ((photoThumbUrl ?? '').trim().isNotEmpty) ...{
        'fotoThumbUrl': photoThumbUrl!.trim(),
        'photoThumbUrl': photoThumbUrl.trim(),
        'photoThumb': photoThumbUrl.trim(),
      },
      if ((photoStoragePath ?? '').trim().isNotEmpty) ...{
        'photoStoragePath': photoStoragePath!.trim(),
        'fotoPath': photoStoragePath.trim(),
      },
      if ((photoThumbStoragePath ?? '').trim().isNotEmpty) ...{
        'photoThumbStoragePath': photoThumbStoragePath!.trim(),
        'fotoThumbPath': photoThumbStoragePath.trim(),
      },
    };
    var touched = false;
    final entries = snap.entries.map((e) {
      final hit = e.memberDocId == mid ||
          (au.isNotEmpty && (e.authUid ?? '').trim() == au);
      if (!hit) return e;
      touched = true;
      return e.mergeFirestoreFields(fields);
    }).toList();
    if (!touched) return;
    rememberInMemory(
      tid,
      MembersDirectorySnapshot(
        totalCount: snap.totalCount,
        entries: entries,
        summary: snap.summary,
      ),
    );
  }

  static void invalidateMemory(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    _memoryByTenant.remove(tid);
  }

  static MembersDirectorySnapshot? peekMemory(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    final m = _memoryByTenant[tid];
    if (m == null || !m.hasEntries) return null;
    if (!TenantDeletedDocTombstones.hasAny(tid, TenantModuleKeys.membros)) {
      return m;
    }
    final filtered = m.entries
        .where(
          (e) => !TenantDeletedDocTombstones.contains(
            tid,
            TenantModuleKeys.membros,
            e.memberDocId,
          ),
        )
        .toList();
    if (filtered.isEmpty) return null;
    return MembersDirectorySnapshot(
      totalCount: m.totalCount,
      entries: filtered,
      summary: m.summary,
    );
  }

  static DocumentReference<Map<String, dynamic>> cacheRefForOperational(
    String operationalTenantId,
  ) {
    return ChurchOperationalPaths.churchDoc(operationalTenantId.trim())
        .collection('_panel_cache')
        .doc('members_directory');
  }

  static DocumentReference<Map<String, dynamic>> cacheRef(String tenantId) {
    final op = ChurchRepository.churchId(tenantId.trim());
    return cacheRefForOperational(op.isNotEmpty ? op : tenantId.trim());
  }

  static Stream<MembersDirectorySnapshot> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return Stream.value(const MembersDirectorySnapshot());
    }
    final op = ChurchRepository.churchId(tid);
    final churchId = op.isNotEmpty ? op : tid;
    return FirestoreStreamUtils.documentWatchBootstrap(
      cacheRefForOperational(churchId),
    ).map((snap) => MembersDirectorySnapshot.fromMap(snap.data()));
  }

  static Future<MembersDirectorySnapshot> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    final mem = peekMemory(tid);
    if (mem != null) return mem;
    final ref = cacheRef(tid);
    try {
      final cached = await ref
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      final fromCache = MembersDirectorySnapshot.fromMap(cached.data());
      if (fromCache.hasEntries) {
        rememberInMemory(tid, fromCache);
        return fromCache;
      }
    } catch (_) {}
    try {
      final snap = await ref
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

  static bool _snapshotComplete(MembersDirectorySnapshot snap) {
    if (!snap.hasEntries) return false;
    if (snap.totalCount <= 0) return true;
    return snap.entries.length >= snap.totalCount;
  }

  static Future<MembersDirectorySnapshot> warmFromCallableIfStale(
    String tenantId,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return const MembersDirectorySnapshot();
    final mem = peekMemory(tid);
    if (mem != null && _snapshotComplete(mem)) return mem;
    try {
      final doc = await cacheRef(tid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      final u = doc.data()?['updatedAt'];
      final cached = MembersDirectorySnapshot.fromMap(doc.data());
      if (_snapshotComplete(cached) &&
          u is Timestamp &&
          DateTime.now().difference(u.toDate()) < _staleAfter) {
        rememberInMemory(tid, cached);
        return cached;
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
    final baseRef = ChurchOperationalPaths.churchDoc(tid);
    final docs = snap.entries
        .where((e) => isRealMemberDisplayName(e.displayName))
        .map((e) {
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

