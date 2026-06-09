import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_engine_paths.dart';

/// Estado de entrega — relógio → enviado → entregue → lido.
enum ChatDeliveryState {
  sending,
  uploading,
  queued,
  sent,
  delivered,
  read,
  failed;

  static ChatDeliveryState fromRaw(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'sending':
        return ChatDeliveryState.sending;
      case 'uploading':
      case 'queued':
        return ChatDeliveryState.uploading;
      case 'sent':
        return ChatDeliveryState.sent;
      case 'delivered':
        return ChatDeliveryState.delivered;
      case 'read':
        return ChatDeliveryState.read;
      case 'failed':
        return ChatDeliveryState.failed;
      default:
        return ChatDeliveryState.sent;
    }
  }

  String get firestoreValue => name;
}

/// Conversa — `igrejas/{churchId}/chats/{chatId}`.
class ChatThread {
  const ChatThread({
    required this.chatId,
    required this.churchId,
    required this.tipo,
    required this.participants,
    this.nome = '',
    this.foto = '',
    this.lastMessage = '',
    this.lastSenderId = '',
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
    this.admins = const [],
    this.memberCount = 0,
    this.raw = const {},
  });

  final String chatId;
  final String churchId;
  final String tipo; // privado | grupo | dm | department
  final List<String> participants;
  final String nome;
  final String foto;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> admins;
  final int memberCount;
  final Map<String, dynamic> raw;

  bool get isGroup => tipo == 'grupo' || tipo == 'group' || tipo == 'department';

  factory ChatThread.fromDoc(String churchId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }
    final parts = <String>[];
    final pu = d['participants'] ?? d['participantUids'];
    if (pu is List) {
      for (final e in pu) {
        final s = '$e'.trim();
        if (s.isNotEmpty) parts.add(s);
      }
    }
    final adm = <String>[];
    final ad = d['admins'];
    if (ad is List) {
      for (final e in ad) {
        final s = '$e'.trim();
        if (s.isNotEmpty) adm.add(s);
      }
    }
    return ChatThread(
      chatId: doc.id,
      churchId: churchId,
      tipo: (d['tipo'] ?? d['type'] ?? 'privado').toString(),
      participants: parts,
      nome: (d['nome'] ?? d['name'] ?? d['title'] ?? '').toString(),
      foto: (d['foto'] ?? d['photoUrl'] ?? '').toString(),
      lastMessage: (d['lastMessage'] ?? d['lastMessagePreview'] ?? '').toString(),
      lastSenderId: (d['lastSenderId'] ?? d['lastSenderUid'] ?? '').toString(),
      lastMessageAt: ts(d['lastMessageAt']),
      createdAt: ts(d['createdAt']),
      updatedAt: ts(d['updatedAt']),
      admins: adm,
      memberCount: d['memberCount'] is num ? (d['memberCount'] as num).toInt() : parts.length,
      raw: d,
    );
  }
}

/// Mensagem — `…/chats/{chatId}/messages/{messageId}`.
class ChatMessage {
  const ChatMessage({
    required this.messageId,
    required this.chatId,
    required this.churchId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.senderName = '',
    this.senderPhoto,
    this.text = '',
    this.mediaUrl,
    this.thumbnailUrl,
    this.storagePath,
    this.thumbStoragePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.replyTo,
    this.forwarded = false,
    this.edited = false,
    this.deleted = false,
    this.delivery = ChatDeliveryState.sent,
    this.deliveredAt,
    this.readBy = const {},
    this.raw = const {},
  });

  final String messageId;
  final String chatId;
  final String churchId;
  final String senderId;
  final String senderName;
  final String? senderPhoto;
  final ChatMessageType type;
  final String text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final String? storagePath;
  final String? thumbStoragePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final Map<String, dynamic>? replyTo;
  final bool forwarded;
  final bool edited;
  final bool deleted;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final Map<String, DateTime> readBy;
  final ChatDeliveryState delivery;
  final Map<String, dynamic> raw;

  bool get isMedia => type.requiresMediaUpload;
  bool get uploadPending =>
      delivery == ChatDeliveryState.sending ||
      delivery == ChatDeliveryState.uploading;

  factory ChatMessage.fromDoc(
    String churchId,
    String chatId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }
    final typeRaw = (d['type'] ?? 'text').toString();
    final type = ChatMessageType.values.firstWhere(
      (t) => t.name == typeRaw,
      orElse: () => ChatMessageType.text,
    );
    final readMap = <String, DateTime>{};
    final rb = d['readBy'];
    if (rb is Map) {
      for (final e in rb.entries) {
        final t = ts(e.value);
        if (t != null) readMap['${e.key}'] = t;
      }
    }
    return ChatMessage(
      messageId: doc.id,
      chatId: chatId,
      churchId: churchId,
      senderId: (d['senderId'] ?? d['senderUid'] ?? '').toString(),
      senderName: (d['senderName'] ?? d['senderDisplayName'] ?? '').toString(),
      senderPhoto: (d['senderPhoto'] ?? d['senderPhotoUrl'])?.toString(),
      type: type,
      text: (d['text'] ?? '').toString(),
      mediaUrl: (d['mediaUrl'] ?? d['fileUrl'])?.toString(),
      thumbnailUrl: (d['thumbnailUrl'] ?? d['thumbUrl'] ?? d['posterUrl'])?.toString(),
      storagePath: (d['storagePath'] ?? d['storage_path'])?.toString(),
      thumbStoragePath: (d['thumbStoragePath'] ?? d['thumb_storage_path'])?.toString(),
      fileName: d['fileName']?.toString(),
      fileSize: d['fileSize'] is num ? (d['fileSize'] as num).toInt() : null,
      mimeType: d['mimeType']?.toString(),
      replyTo: d['replyTo'] is Map ? Map<String, dynamic>.from(d['replyTo'] as Map) : null,
      forwarded: d['forwarded'] == true,
      edited: d['edited'] == true,
      deleted: d['deleted'] == true,
      createdAt: ts(d['createdAt']) ?? DateTime.now(),
      deliveredAt: ts(d['deliveredAt']),
      readBy: readMap,
      delivery: ChatDeliveryState.fromRaw(
        (d['status'] ?? d['deliveryStatus'])?.toString(),
      ),
      raw: d,
    );
  }
}
