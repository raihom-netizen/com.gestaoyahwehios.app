import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';

/// Paths oficiais do Motor de Mensagens — Gestão YAHWEH.
///
/// Firestore: `igrejas/{churchId}/chats/{chatId}/messages`
/// Storage:   `igrejas/{churchId}/chat_media/{images|videos|audio|documents}/`
abstract final class ChatEnginePaths {
  ChatEnginePaths._();

  static String resolveChurchId([String? hint]) =>
      ChurchContext.resolveChurchId(hint);

  static String firestoreChatsRoot(String churchId) =>
      ChurchDataPaths.subcollection(churchId, ChurchDataPaths.chats);

  static String firestoreMessagesPath(String churchId, String chatId) =>
      '${firestoreChatsRoot(churchId)}/$chatId/messages';

  static String storageRoot(String churchId) =>
      '${ChurchStorageLayout.churchRoot(churchId)}/chat_media';

  static const storageImages = 'images';
  static const storageVideos = 'videos';
  static const storageAudio = 'audio';
  static const storageDocuments = 'documents';
  static const storageThumbs = 'thumbs';

  static String storageFolderForType(ChatMessageType type) =>
      ChurchStorageLayout.chatMediaFolderForKind(type.storageKind);

  static String buildMediaObjectPath({
    required String churchId,
    required String chatId,
    required ChatMessageType type,
    required String uid,
    required int timestampMs,
    required String fileName,
  }) =>
      ChurchStorageLayout.buildChatMediaObjectPath(
        tenantId: churchId,
        threadId: chatId,
        kind: type.storageKind,
        uid: uid,
        timestampMs: timestampMs,
        fileName: fileName,
      );

  static String buildThumbnailPath({
    required String churchId,
    required String uid,
    required int timestampMs,
    String suffix = 'thumb',
  }) =>
      ChurchStorageLayout.buildChatMediaThumbPath(
        tenantId: churchId,
        uid: uid,
        timestampMs: timestampMs,
        suffix: suffix,
      );
}

/// Tipos de mensagem suportados pelo motor.
enum ChatMessageType {
  text,
  emoji,
  image,
  video,
  audio,
  pdf,
  doc,
  xls,
  ppt,
  zip,
  document,
  link,
  contact,
  location,
  sticker;

  String get firestoreValue => name;

  String get storageKind => switch (this) {
        ChatMessageType.image || ChatMessageType.sticker => 'image',
        ChatMessageType.video => 'video',
        ChatMessageType.audio => 'audio',
        ChatMessageType.pdf ||
        ChatMessageType.doc ||
        ChatMessageType.xls ||
        ChatMessageType.ppt ||
        ChatMessageType.zip ||
        ChatMessageType.document =>
          'document',
        _ => 'document',
      };

  bool get requiresMediaUpload => switch (this) {
        ChatMessageType.text ||
        ChatMessageType.emoji ||
        ChatMessageType.link ||
        ChatMessageType.contact ||
        ChatMessageType.location =>
          false,
        _ => true,
      };

  bool get showThumbnailOnlyInList => requiresMediaUpload;
}
