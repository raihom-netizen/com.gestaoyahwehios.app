import 'dart:typed_data';

/// Mensagem local enquanto upload/envio ao Firestore não termina (estilo WhatsApp).
class ChurchChatOutboundPending {
  ChurchChatOutboundPending({
    required this.localId,
    required this.kind,
    required this.fileName,
    required this.mime,
    this.previewBytes,
    this.localPath,
    this.replyPreview,
  }) : createdAt = DateTime.now();

  final String localId;
  final String kind;
  final String fileName;
  final String mime;
  final Uint8List? previewBytes;
  String? localPath;
  final String? replyPreview;
  final DateTime createdAt;

  double progress = 0;
  bool failed = false;
  String? errorMessage;
  bool cancelled = false;

  /// Mensagem stub no Firestore (envio otimista).
  String? firestoreMessageId;
  String? storagePath;
}
