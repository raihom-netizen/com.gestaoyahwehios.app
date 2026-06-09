import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_engine_paths.dart';
import 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
import 'package:gestao_yahweh/services/church_chat_message_fields.dart';

/// Constrói payloads Firestore canónicos + aliases legados.
abstract final class ChatMessagePayload {
  ChatMessagePayload._();

  static Map<String, dynamic> text({
    required String senderId,
    required String senderName,
    String? senderPhoto,
    required String text,
    Map<String, dynamic>? replyTo,
    bool forwarded = false,
    List<String>? mentionedUids,
    ChatDeliveryState delivery = ChatDeliveryState.sending,
  }) {
    final now = FieldValue.serverTimestamp();
    final patch = <String, dynamic>{
      'messageId': '', // preenchido após set
      'senderId': senderId,
      'senderUid': senderId,
      'senderName': senderName,
      'senderDisplayName': senderName,
      if (senderPhoto != null && senderPhoto.isNotEmpty) 'senderPhoto': senderPhoto,
      'type': ChatMessageType.text.firestoreValue,
      'text': text,
      'status': delivery.firestoreValue,
      'deliveryStatus': delivery.firestoreValue,
      'createdAt': now,
      'uploadCompleted': true,
      if (replyTo != null) 'replyTo': replyTo,
      'forwarded': forwarded,
      'edited': false,
      'deleted': false,
      if (mentionedUids != null && mentionedUids.isNotEmpty)
        'mentionedUids': mentionedUids,
    };
    return ChurchChatMessageFields.withCanonicalAliases(patch);
  }

  static Map<String, dynamic> mediaStub({
    required String senderId,
    required String senderName,
    String? senderPhoto,
    required ChatMessageType type,
    String? text,
    Map<String, dynamic>? replyTo,
    String? localId,
  }) {
    final now = FieldValue.serverTimestamp();
    final patch = <String, dynamic>{
      'senderId': senderId,
      'senderUid': senderId,
      'senderName': senderName,
      'senderDisplayName': senderName,
      if (senderPhoto != null && senderPhoto.isNotEmpty) 'senderPhoto': senderPhoto,
      'type': type.firestoreValue,
      if (text != null && text.isNotEmpty) 'text': text,
      'status': ChatDeliveryState.uploading.firestoreValue,
      'deliveryStatus': ChatDeliveryState.uploading.firestoreValue,
      'createdAt': now,
      'uploadCompleted': false,
      'storageVerified': false,
      'pendingMedia': true,
      if (replyTo != null) 'replyTo': replyTo,
      if (localId != null) 'localId': localId,
    };
    return ChurchChatMessageFields.withCanonicalAliases(patch);
  }

  static Map<String, dynamic> mediaFinalized({
    required String storagePath,
    String? mediaUrl,
    String? thumbnailUrl,
    String? thumbStoragePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
  }) {
    final patch = <String, dynamic>{
      'storagePath': storagePath,
      if (mediaUrl != null) ...{'mediaUrl': mediaUrl, 'fileUrl': mediaUrl},
      if (thumbnailUrl != null) ...{
        'thumbnailUrl': thumbnailUrl,
        'thumbUrl': thumbnailUrl,
      },
      if (thumbStoragePath != null) 'thumbStoragePath': thumbStoragePath,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) ...{'fileSize': fileSize, 'size': fileSize},
      if (mimeType != null) 'mimeType': mimeType,
      'status': ChatDeliveryState.sent.firestoreValue,
      'deliveryStatus': ChatDeliveryState.sent.firestoreValue,
      'uploadCompleted': true,
      'storageVerified': true,
      'pendingMedia': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    return ChurchChatMessageFields.withCanonicalAliases(patch);
  }

  static Map<String, dynamic> threadLastMessagePatch({
    required String preview,
    required String type,
    required String senderId,
  }) =>
      {
        'lastMessage': preview,
        'lastMessagePreview': preview,
        'lastMessageType': type,
        'lastSenderId': senderId,
        'lastSenderUid': senderId,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'hasConversation': true,
      };
}
