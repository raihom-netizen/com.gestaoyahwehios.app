import 'dart:typed_data';

/// Bytes locais de fotos património ainda não publicadas — mantém miniatura na lista.
abstract final class PatrimonioPendingPhotosCache {
  PatrimonioPendingPhotosCache._();

  static final Map<String, Map<int, Uint8List>> _byItem = {};

  static String _key(String churchId, String itemId) =>
      '${churchId.trim()}|${itemId.trim()}';

  static void set(
    String churchId,
    String itemId,
    Map<int, Uint8List> bySlot,
  ) {
    final k = _key(churchId, itemId);
    if (bySlot.isEmpty) {
      _byItem.remove(k);
      return;
    }
    _byItem[k] = Map<int, Uint8List>.from(bySlot);
  }

  static Map<int, Uint8List>? peek(String churchId, String itemId) {
    final hit = _byItem[_key(churchId, itemId)];
    if (hit == null || hit.isEmpty) return null;
    return Map<int, Uint8List>.from(hit);
  }

  static Uint8List? firstThumb(String churchId, String itemId) {
    final m = peek(churchId, itemId);
    if (m == null) return null;
    final slots = m.keys.toList()..sort();
    for (final s in slots) {
      final b = m[s];
      if (b != null && b.isNotEmpty) return b;
    }
    return null;
  }

  static void clear(String churchId, String itemId) {
    _byItem.remove(_key(churchId, itemId));
  }
}
