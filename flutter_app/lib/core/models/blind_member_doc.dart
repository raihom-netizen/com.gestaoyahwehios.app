import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/firestore_map_fields.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;

/// Membro normalizado a partir do Firestore real (chaves UPPERCASE ou legado).
class BlindMemberDoc {
  const BlindMemberDoc({
    required this.id,
    required this.displayName,
    required this.raw,
    this.photoUrl,
    this.photoThumbUrl,
    this.cpfDigits = '',
    this.email = '',
    this.telefone = '',
    this.status = 'ativo',
    this.funcao = '',
    this.funcoes = const [],
    this.departamentos = const [],
    this.genero = '',
    this.createdAt,
    this.updatedAt,
    this.dataNascimento,
    this.fotoUrlCacheRevision = 0,
    this.authUid,
  });

  final String id;
  final String displayName;
  final Map<String, dynamic> raw;
  final String? photoUrl;
  final String? photoThumbUrl;
  final String cpfDigits;
  final String email;
  final String telefone;
  final String status;
  final String funcao;
  final List<String> funcoes;
  final List<String> departamentos;
  final String genero;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;
  final dynamic dataNascimento;
  final int fotoUrlCacheRevision;
  final String? authUid;

  /// Mapa canónico para filtros/UI — nunca lança exceção.
  Map<String, dynamic> toMemberDataMap() {
    final thumb = (photoThumbUrl != null && photoThumbUrl!.isNotEmpty)
        ? photoThumbUrl
        : photoUrl;
    return <String, dynamic>{
      'NOME_COMPLETO': displayName,
      'nome': displayName,
      'name': displayName,
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
      if (cpfDigits.isNotEmpty) 'CPF': cpfDigits,
      if (email.isNotEmpty) 'EMAIL': email,
      if (telefone.isNotEmpty) 'TELEFONES': telefone,
      'STATUS': status,
      'status': status,
      if (funcao.isNotEmpty) ...{
        'FUNCAO': funcao,
        'CARGO': funcao,
      },
      if (funcoes.isNotEmpty) 'FUNCOES': funcoes,
      if (departamentos.isNotEmpty) 'DEPARTAMENTOS': departamentos,
      if (genero.isNotEmpty) 'SEXO': genero,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (dataNascimento != null) 'DATA_NASCIMENTO': dataNascimento,
      ...raw,
    };
  }

  MemberDirectoryEntry toDirectoryEntry() => MemberDirectoryEntry(
        memberDocId: id,
        displayName: displayName,
        photoUrl: photoUrl,
        photoThumbUrl: photoThumbUrl,
        fotoUrlCacheRevision: fotoUrlCacheRevision,
        authUid: authUid,
        cpfDigits: cpfDigits.isEmpty ? null : cpfDigits,
        email: email.isEmpty ? null : email,
        telefone: telefone.isEmpty ? null : telefone,
        status: status,
        funcao: funcao.isEmpty ? null : funcao,
        funcoes: funcoes,
        departamentos: departamentos,
        genero: genero.isEmpty ? null : genero,
        createdAt: createdAt,
        updatedAt: updatedAt,
        dataNascimento: dataNascimento,
      );

  static BlindMemberDoc fromFirestore({
    required String id,
    Map<String, dynamic>? data,
  }) {
    final map = Map<String, dynamic>.from(data ?? const {});
    final name = FirestoreMapFields.pickString(
      map,
      const ['NOME_COMPLETO', 'nome', 'name'],
      fallback: 'Membro',
    );
    final photo =
        MemberProfilePhotoResolver.displayRef(map, preferThumb: false) ??
            imageUrlFromMap(map);
    final thumb =
        MemberProfilePhotoResolver.displayRef(map, preferThumb: true) ??
            MemberImageFields.photoThumbDownloadUrl(map) ??
            '';
    final cpf = FirestoreMapFields.pickCpfDigits(map);
    final status = FirestoreMapFields.pickString(
      map,
      const ['STATUS', 'status'],
      fallback: 'ativo',
    ).toLowerCase();

    return BlindMemberDoc(
      id: id.trim().isEmpty ? 'membro' : id.trim(),
      displayName: name,
      raw: map,
      photoUrl: photo.trim().isEmpty ? null : photo.trim(),
      photoThumbUrl: thumb.trim().isEmpty ? null : thumb.trim(),
      cpfDigits: cpf,
      email: FirestoreMapFields.pickString(map, const ['EMAIL', 'email']),
      telefone: FirestoreMapFields.pickString(
        map,
        const ['TELEFONES', 'TELEFONE', 'telefone', 'phone'],
      ),
      status: status.isEmpty ? 'ativo' : status,
      funcao: FirestoreMapFields.pickString(
        map,
        const ['FUNCAO', 'funcao', 'CARGO', 'cargo', 'role'],
      ),
      funcoes: FirestoreMapFields.pickStringList(
        map,
        const ['FUNCOES', 'funcoes'],
      ),
      departamentos: FirestoreMapFields.pickStringList(
        map,
        const ['DEPARTAMENTOS', 'departamentos'],
      ),
      genero: FirestoreMapFields.pickString(
        map,
        const ['SEXO', 'sexo', 'genero'],
      ),
      createdAt: FirestoreMapFields.pickTimestamp(
        map,
        const ['createdAt', 'CRIADO_EM', 'criadoEm'],
      ),
      updatedAt: FirestoreMapFields.pickTimestamp(
        map,
        const ['updatedAt', 'ATUALIZADO_EM', 'atualizadoEm'],
      ),
      dataNascimento: map['DATA_NASCIMENTO'] ?? map['dataNascimento'],
      fotoUrlCacheRevision:
          memberPhotoDisplayCacheRevision(map) ??
              FirestoreMapFields.pickInt(
                map,
                const ['fotoUrlCacheRevision'],
              ),
      authUid: MemberProfilePhotoResolver.authUidFromData(map, memberDocId: id),
    );
  }

  static BlindMemberDoc fromSnapshot(DocumentSnapshot<Map<String, dynamic>> d) =>
      fromFirestore(id: d.id, data: d.data());
}
