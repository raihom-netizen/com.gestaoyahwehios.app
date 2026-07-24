import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/features/chat/domain/models/yahweh_chat_enums.dart';

/// Mensagem do YAHWEH CHAT.
///
/// Firestore: `igrejas/{churchId}/chats/{chatId}/messages/{messageId}`
class YahwehChatMessage {
  const YahwehChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.senderName = '',
    this.senderPhoto,
    this.text = '',
    this.type = YahwehMessageType.text,
    this.fileUrl,
    this.storagePath,
    this.thumbnailUrl,
    this.thumbStoragePath,
    this.fileName,
    this.fileSize,
    this.durationSeconds,
    this.replyToId,
    this.replyTo,
    this.forwarded = false,
    this.forwardedFrom,
    this.edited = false,
    this.deletedForMe = false,
    this.deletedForEveryone = false,
    this.pinned = false,
    this.favorited = false,
    this.status = YahwehMessageStatus.sent,
    this.readBy = const [],
    this.reactions = const {},
    this.createdAt,
    this.updatedAt,
    this.clientId,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderPhoto;
  final String text;
  final YahwehMessageType type;

  /// URL https legada / resolvida (preferir [storagePath] + resolver).
  final String? fileUrl;
  final String? storagePath;
  final String? thumbnailUrl;
  final String? thumbStoragePath;
  final String? fileName;
  final int? fileSize;
  final int? durationSeconds;

  final String? replyToId;
  final Map<String, dynamic>? replyTo;
  final bool forwarded;
  final Map<String, dynamic>? forwardedFrom;
  final bool edited;
  final bool deletedForMe;
  final bool deletedForEveryone;
  final bool pinned;
  final bool favorited;
  final YahwehMessageStatus status;
  final List<String> readBy;

  /// emoji → lista de uids.
  final Map<String, List<String>> reactions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// ID local otimista (fila offline).
  final String? clientId;

  bool get isMinePlaceholder => false;

  bool get hasMedia =>
      (fileUrl != null && fileUrl!.isNotEmpty) ||
      (storagePath != null && storagePath!.isNotEmpty);

  bool get isDeleted => deletedForEveryone;

  YahwehChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    String? senderPhoto,
    String? text,
    YahwehMessageType? type,
    String? fileUrl,
    String? storagePath,
    String? thumbnailUrl,
    String? thumbStoragePath,
    String? fileName,
    int? fileSize,
    int? durationSeconds,
    String? replyToId,
    Map<String, dynamic>? replyTo,
    bool? forwarded,
    Map<String, dynamic>? forwardedFrom,
    bool? edited,
    bool? deletedForMe,
    bool? deletedForEveryone,
    bool? pinned,
    bool? favorited,
    YahwehMessageStatus? status,
    List<String>? readBy,
    Map<String, List<String>>? reactions,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clientId,
  }) {
    return YahwehChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderPhoto: senderPhoto ?? this.senderPhoto,
      text: text ?? this.text,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      storagePath: storagePath ?? this.storagePath,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbStoragePath: thumbStoragePath ?? this.thumbStoragePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      replyToId: replyToId ?? this.replyToId,
      replyTo: replyTo ?? this.replyTo,
      forwarded: forwarded ?? this.forwarded,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      edited: edited ?? this.edited,
      deletedForMe: deletedForMe ?? this.deletedForMe,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      pinned: pinned ?? this.pinned,
      favorited: favorited ?? this.favorited,
      status: status ?? this.status,
      readBy: readBy ?? this.readBy,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clientId: clientId ?? this.clientId,
    );
  }

  Map<String, dynamic> toJson() => {
        'messageId': id,
        'conversationId': conversationId,
        'chatId': conversationId,
        'senderId': senderId,
        'senderName': senderName,
        if (senderPhoto != null && senderPhoto!.isNotEmpty)
          'senderPhoto': senderPhoto,
        'text': text,
        'message': text,
        'type': type.wire,
        if (fileUrl != null && fileUrl!.isNotEmpty) 'fileUrl': fileUrl,
        if (storagePath != null && storagePath!.isNotEmpty)
          'storagePath': storagePath,
        if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
          'thumbnail': thumbnailUrl,
        if (thumbStoragePath != null && thumbStoragePath!.isNotEmpty)
          'thumbStoragePath': thumbStoragePath,
        if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
        if (fileSize != null) 'fileSize': fileSize,
        if (durationSeconds != null) 'duration': durationSeconds,
        if (replyToId != null && replyToId!.isNotEmpty) 'replyToId': replyToId,
        if (replyTo != null) 'replyTo': replyTo,
        'forwarded': forwarded,
        if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
        'edited': edited,
        'deletedForMe': deletedForMe,
        'deletedForEveryone': deletedForEveryone,
        'deleted': deletedForEveryone,
        'pinned': pinned,
        'favorited': favorited,
        'status': status.wire,
        'deliveryStatus': status.wire,
        'readBy': readBy,
        'reactions': reactions,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
        if (clientId != null && clientId!.isNotEmpty) 'clientId': clientId,
      };

  factory YahwehChatMessage.fromJson(
    Map<String, dynamic> json, {
    String? id,
    String? conversationId,
  }) {
    final mid = (id ?? json['messageId'] ?? json['id'] ?? '').toString().trim();
    final cid = (conversationId ??
            json['conversationId'] ??
            json['chatId'] ??
            json['threadId'] ??
            '')
        .toString()
        .trim();

    final replyRaw = json['replyTo'];
    Map<String, dynamic>? replyMap;
    if (replyRaw is Map) {
      replyMap = Map<String, dynamic>.from(replyRaw);
    }

    final fwdRaw = json['forwardedFrom'];
    Map<String, dynamic>? fwdMap;
    if (fwdRaw is Map) {
      fwdMap = Map<String, dynamic>.from(fwdRaw);
    }

    return YahwehChatMessage(
      id: mid,
      conversationId: cid,
      senderId: _str(
        json['senderId'] ?? json['senderUid'] ?? json['uid'],
      ),
      senderName: _str(
        json['senderName'] ?? json['senderDisplayName'] ?? json['fromName'],
      ),
      senderPhoto: _nullableStr(
        json['senderPhoto'] ?? json['senderPhotoUrl'] ?? json['avatarUrl'],
      ),
      text: _str(
        json['text'] ?? json['message'] ?? json['body'] ?? json['caption'],
      ),
      type: YahwehMessageTypeX.fromWire(
        (json['type'] ?? json['messageType'] ?? json['kind'])?.toString(),
      ),
      fileUrl: _nullableStr(
        json['fileUrl'] ??
            json['mediaUrl'] ??
            json['url'] ??
            json['downloadUrl'],
      ),
      storagePath: _nullableStr(
        json['storagePath'] ?? json['path'] ?? json['mediaPath'],
      ),
      thumbnailUrl: _nullableStr(
        json['thumbnail'] ??
            json['thumbnailUrl'] ??
            json['thumbUrl'] ??
            json['previewUrl'],
      ),
      thumbStoragePath: _nullableStr(
        json['thumbStoragePath'] ?? json['thumbnailPath'],
      ),
      fileName: _nullableStr(json['fileName'] ?? json['name']),
      fileSize: _asIntOrNull(json['fileSize'] ?? json['size']),
      durationSeconds: _asIntOrNull(
        json['duration'] ?? json['durationSeconds'],
      ),
      replyToId: _nullableStr(
        json['replyToId'] ??
            (replyMap != null ? replyMap['id'] ?? replyMap['messageId'] : null),
      ),
      replyTo: replyMap,
      forwarded: json['forwarded'] == true || fwdMap != null,
      forwardedFrom: fwdMap,
      edited: json['edited'] == true || json['isEdited'] == true,
      deletedForMe: json['deletedForMe'] == true,
      deletedForEveryone: json['deletedForEveryone'] == true ||
          json['deleted'] == true ||
          json['deletedForAll'] == true,
      pinned: json['pinned'] == true || json['isPinned'] == true,
      favorited: json['favorited'] == true || json['starred'] == true,
      status: YahwehMessageStatusX.fromWire(
        (json['status'] ?? json['deliveryStatus'])?.toString(),
      ),
      readBy: _stringList(json['readBy'] ?? json['readUids']),
      reactions: _reactionsMap(json['reactions']),
      createdAt: _asDate(
        json['createdAt'] ?? json['sentAt'] ?? json['timestamp'],
      ),
      updatedAt: _asDate(json['updatedAt'] ?? json['editedAt']),
      clientId: _nullableStr(json['clientId'] ?? json['localId']),
    );
  }

  factory YahwehChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    String? conversationId,
  }) {
    return YahwehChatMessage.fromJson(
      doc.data() ?? const {},
      id: doc.id,
      conversationId: conversationId,
    );
  }

  static String _str(Object? v) => (v ?? '').toString().trim();

  static String? _nullableStr(Object? v) {
    final s = _str(v);
    return s.isEmpty ? null : s;
  }

  static int? _asIntOrNull(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, List<String>> _reactionsMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    raw.forEach((key, value) {
      final emoji = key.toString();
      if (value is List) {
        out[emoji] = value
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
    });
    return out;
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
