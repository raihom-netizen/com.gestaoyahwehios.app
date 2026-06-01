import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
    this.albumGroupId,
    this.albumIndex = 0,
    this.albumCount = 1,
  }) : createdAt = DateTime.now();

  final String localId;
  final String kind;
  final String fileName;
  final String mime;
  Uint8List? previewBytes;
  String? localPath;
  final String? replyPreview;
  final String? albumGroupId;
  final int albumIndex;
  final int albumCount;
  final DateTime createdAt;

  double progress = 0;
  /// Atualiza só a bolha pendente (sem rebuild da thread inteira).
  final ValueNotifier<double> progressListenable = ValueNotifier(0);
  bool failed = false;
  String? errorMessage;
  bool cancelled = false;

  /// Mensagem stub no Firestore (envio otimista).
  String? firestoreMessageId;
  String? storagePath;

  void dispose() {
    progressListenable.dispose();
  }
}
