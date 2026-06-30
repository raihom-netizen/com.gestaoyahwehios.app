import 'dart:typed_data';

/// Payload comprimido em RAM — evita re-compressão no retry/upload.
abstract final class ChurchChatOptimizedPayloadCache {
  ChurchChatOptimizedPayloadCache._();

  static final Map<String, _Entry> _byLocalId = {};

  static String _key(String localId) => localId.trim();

  static void put({
    required String localId,
    required Uint8List fullBytes,
    required String fullMime,
    required String fullFileName,
    Uint8List? thumbBytes,
    Uint8List? previewBytes,
  }) {
    if (localId.trim().isEmpty || fullBytes.isEmpty) return;
    _byLocalId[_key(localId)] = _Entry(
      fullBytes: fullBytes,
      fullMime: fullMime,
      fullFileName: fullFileName,
      thumbBytes: thumbBytes,
      previewBytes: previewBytes,
    );
  }

  static _Entry? peek(String localId) => _byLocalId[_key(localId)];

  static void remove(String localId) => _byLocalId.remove(_key(localId));
}

class _Entry {
  _Entry({
    required this.fullBytes,
    required this.fullMime,
    required this.fullFileName,
    this.thumbBytes,
    this.previewBytes,
  });

  final Uint8List fullBytes;
  final String fullMime;
  final String fullFileName;
  final Uint8List? thumbBytes;
  final Uint8List? previewBytes;
}
