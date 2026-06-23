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
    this.textBody,
    this.replyToData,
    this.mentionedUids,
    this.albumGroupId,
    this.albumIndex = 0,
    this.albumCount = 1,
    this.voiceDurationMs,
    this.byteSize,
  }) : createdAt = DateTime.now();

  final String localId;
  final String kind;
  final String fileName;
  final String mime;
  /// Texto instantâneo (bolha local antes do Firestore).
  final String? textBody;
  final Map<String, dynamic>? replyToData;
  final List<String>? mentionedUids;
  Uint8List? previewBytes;
  String? localPath;
  final String? replyPreview;
  final String? albumGroupId;
  final int albumIndex;
  final int albumCount;
  /// Duração da gravação de voz (ms) — exibição estilo WhatsApp.
  final int? voiceDurationMs;
  /// Tamanho do ficheiro local (bytes), quando disponível.
  final int? byteSize;
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
