import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/features/chat/domain/models/yahweh_chat_enums.dart';

/// Conversa do YAHWEH CHAT (DM, departamento/grupo ou canal).
///
/// Firestore: `igrejas/{churchId}/chats/{chatId}`
class YahwehChatConversation {
  const YahwehChatConversation({
    required this.id,
    required this.type,
    this.name = '',
    this.photoUrl,
    this.participants = const [],
    this.adminIds = const [],
    this.departmentId,
    this.lastMessageText = '',
    this.lastMessageAt,
    this.lastSenderId = '',
    this.lastSenderName = '',
    this.unreadCount = 0,
    this.createdAt,
    this.updatedAt,
    this.muted = false,
    this.archived = false,
  });

  final String id;
  final YahwehChatType type;
  final String name;
  final String? photoUrl;

  /// UIDs / CPF / memberIds participantes.
  final List<String> participants;
  final List<String> adminIds;

  /// Preenchido quando [type] == [YahwehChatType.group].
  final String? departmentId;

  final String lastMessageText;
  final DateTime? lastMessageAt;
  final String lastSenderId;
  final String lastSenderName;
  final int unreadCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool muted;
  final bool archived;

  bool get isDirect => type == YahwehChatType.direct;
  bool get isGroup => type == YahwehChatType.group;
  bool get isChannel =>
      type == YahwehChatType.channel || type == YahwehChatType.announcements;

  /// ID do departamento derivado do doc (`dept_{id}`) ou campo explícito.
  String? get resolvedDepartmentId {
    final explicit = (departmentId ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    if (id.startsWith('dept_') && id.length > 5) return id.substring(5);
    return null;
  }

  YahwehChatConversation copyWith({
    String? id,
    YahwehChatType? type,
    String? name,
    String? photoUrl,
    List<String>? participants,
    List<String>? adminIds,
    String? departmentId,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastSenderId,
    String? lastSenderName,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? muted,
    bool? archived,
  }) {
    return YahwehChatConversation(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      participants: participants ?? this.participants,
      adminIds: adminIds ?? this.adminIds,
      departmentId: departmentId ?? this.departmentId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      lastSenderName: lastSenderName ?? this.lastSenderName,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      muted: muted ?? this.muted,
      archived: archived ?? this.archived,
    );
  }

  Map<String, dynamic> toJson() => {
        'chatId': id,
        'type': type.wire,
        'name': name,
        if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
        'memberIds': participants,
        'participants': participants,
        'adminIds': adminIds,
        if (resolvedDepartmentId != null)
          'departmentId': resolvedDepartmentId,
        'lastMessageText': lastMessageText,
        'lastMessage': lastMessageText,
        if (lastMessageAt != null)
          'lastMessageTime': Timestamp.fromDate(lastMessageAt!),
        if (lastMessageAt != null)
          'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
        'lastSenderId': lastSenderId,
        'lastSenderName': lastSenderName,
        'unreadCount': unreadCount,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
        'muted': muted,
        'archived': archived,
      };

  factory YahwehChatConversation.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    final chatId = (id ??
            json['chatId'] ??
            json['id'] ??
            json['threadId'] ??
            '')
        .toString()
        .trim();
    final type = YahwehChatTypeX.fromWire(
      (json['type'] ?? json['chatType'] ?? json['kind'])?.toString(),
      chatId: chatId,
    );
    final members = _stringList(
      json['memberIds'] ??
          json['participants'] ??
          json['memberUids'] ??
          json['uids'],
    );
    final admins = _stringList(
      json['adminIds'] ?? json['admins'] ?? json['leaderUids'],
    );
    final dept = _nullableStr(
      json['departmentId'] ?? json['deptId'] ?? json['departamentoId'],
    );

    return YahwehChatConversation(
      id: chatId,
      type: type,
      name: _str(
        json['name'] ??
            json['title'] ??
            json['nome'] ??
            json['displayName'] ??
            json['departmentName'],
      ),
      photoUrl: _nullableStr(
        json['photoUrl'] ?? json['fotoUrl'] ?? json['avatarUrl'] ?? json['imageUrl'],
      ),
      participants: members,
      adminIds: admins,
      departmentId: dept,
      lastMessageText: _str(
        json['lastMessageText'] ??
            json['lastMessage'] ??
            json['preview'] ??
            json['lastText'],
      ),
      lastMessageAt: _asDate(
        json['lastMessageTime'] ??
            json['lastMessageAt'] ??
            json['lastAt'] ??
            json['updatedAt'],
      ),
      lastSenderId: _str(
        json['lastSenderId'] ?? json['lastSender'] ?? json['lastUid'],
      ),
      lastSenderName: _str(
        json['lastSenderName'] ?? json['lastSenderDisplayName'],
      ),
      unreadCount: _asInt(json['unreadCount'] ?? json['unread']),
      createdAt: _asDate(json['createdAt']),
      updatedAt: _asDate(json['updatedAt'] ?? json['lastMessageTime']),
      muted: json['muted'] == true || json['silenced'] == true,
      archived: json['archived'] == true,
    );
  }

  factory YahwehChatConversation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return YahwehChatConversation.fromJson(doc.data() ?? const {}, id: doc.id);
  }

  static String _str(Object? v) => (v ?? '').toString().trim();

  static String? _nullableStr(Object? v) {
    final s = _str(v);
    return s.isEmpty ? null : s;
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

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
