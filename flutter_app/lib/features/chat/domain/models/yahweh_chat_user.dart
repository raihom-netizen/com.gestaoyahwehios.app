import 'package:cloud_firestore/cloud_firestore.dart';

/// Participante / perfil leve do YAHWEH CHAT (membro da igreja).
///
/// Fonte típica: `igrejas/{churchId}/membros/{id}` ou Auth + perfil.
class YahwehChatUser {
  const YahwehChatUser({
    required this.uid,
    required this.nome,
    this.cpf = '',
    this.role = '',
    this.photoUrl,
    this.isOnline = false,
    this.lastSeen,
    this.telefone,
  });

  final String uid;
  final String nome;
  final String cpf;
  final String role;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? telefone;

  String get displayName {
    final n = nome.trim();
    if (n.isNotEmpty) return n;
    if (cpf.length == 11) {
      return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.'
          '${cpf.substring(6, 9)}-${cpf.substring(9)}';
    }
    return uid.isEmpty ? 'Membro' : uid;
  }

  YahwehChatUser copyWith({
    String? uid,
    String? nome,
    String? cpf,
    String? role,
    String? photoUrl,
    bool? isOnline,
    DateTime? lastSeen,
    String? telefone,
  }) {
    return YahwehChatUser(
      uid: uid ?? this.uid,
      nome: nome ?? this.nome,
      cpf: cpf ?? this.cpf,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      telefone: telefone ?? this.telefone,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'nome': nome,
        'cpf': cpf,
        'role': role,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
        'isOnline': isOnline,
        if (lastSeen != null) 'lastSeen': Timestamp.fromDate(lastSeen!),
        if (telefone != null && telefone!.isNotEmpty) 'telefone': telefone,
      };

  factory YahwehChatUser.fromJson(Map<String, dynamic> json) {
    return YahwehChatUser(
      uid: _str(json['uid'] ?? json['userId'] ?? json['id']),
      nome: _str(
        json['nome'] ??
            json['NOME_COMPLETO'] ??
            json['displayName'] ??
            json['name'],
      ),
      cpf: _digits(json['cpf'] ?? json['CPF']),
      role: _str(json['role'] ?? json['FUNCAO'] ?? json['funcao']),
      photoUrl: _nullableUrl(
        json['photoUrl'] ??
            json['fotoUrl'] ??
            json['FOTO'] ??
            json['avatarUrl'],
      ),
      isOnline: json['isOnline'] == true || json['online'] == true,
      lastSeen: _asDate(json['lastSeen'] ?? json['lastSeenAt']),
      telefone: _nullableStr(
        json['telefone'] ?? json['TELEFONES'] ?? json['phone'],
      ),
    );
  }

  factory YahwehChatUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final mapped = Map<String, dynamic>.from(data);
    if (_str(mapped['uid']).isEmpty) {
      mapped['uid'] = doc.id;
    }
    return YahwehChatUser.fromJson(mapped);
  }

  static String _str(Object? v) => (v ?? '').toString().trim();

  static String? _nullableStr(Object? v) {
    final s = _str(v);
    return s.isEmpty ? null : s;
  }

  static String? _nullableUrl(Object? v) {
    final s = _str(v);
    if (s.isEmpty) return null;
    return s;
  }

  static String _digits(Object? v) =>
      _str(v).replaceAll(RegExp(r'\D'), '');

  static DateTime? _asDate(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: false);
    }
    return DateTime.tryParse(v.toString());
  }
}
