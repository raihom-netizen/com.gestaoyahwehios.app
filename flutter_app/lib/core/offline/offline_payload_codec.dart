import 'package:cloud_firestore/cloud_firestore.dart';

/// Serializa payloads Firestore para Hive (FieldValue, Timestamp, mapas aninhados).
abstract final class OfflinePayloadCodec {
  OfflinePayloadCodec._();

  static const _fvKey = '_yfv';
  static const _tsKey = '_yts';

  static Map<String, dynamic> encodeMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      final encoded = encodeValue(value);
      if (encoded != null) out[key] = encoded;
    });
    return out;
  }

  static dynamic encodeValue(dynamic value) {
    if (value == null) return null;
    if (value is FieldValue) {
      return <String, dynamic>{_fvKey: _fieldValueToken(value)};
    }
    if (value is Timestamp) {
      return <String, dynamic>{_tsKey: value.millisecondsSinceEpoch};
    }
    if (value is Map) {
      return encodeMap(Map<String, dynamic>.from(value));
    }
    if (value is List) {
      return value.map(encodeValue).toList();
    }
    if (value is num || value is String || value is bool) return value;
    return value.toString();
  }

  static String _fieldValueToken(FieldValue fv) {
    final s = fv.toString().toLowerCase();
    if (s.contains('servertimestamp')) return 'serverTimestamp';
    if (s.contains('arrayunion')) return 'arrayUnion';
    if (s.contains('arrayremove')) return 'arrayRemove';
    if (s.contains('increment')) return 'increment';
    if (s.contains('delete')) return 'delete';
    return 'serverTimestamp';
  }

  static Map<String, dynamic> decodeMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      out[key] = decodeValue(value);
    });
    return out;
  }

  static dynamic decodeValue(dynamic value) {
    if (value is Map) {
      final m = Map<String, dynamic>.from(value);
      if (m.length == 1 && m.containsKey(_fvKey)) {
        return _fieldValueFromToken(m[_fvKey]?.toString() ?? '');
      }
      if (m.length == 1 && m.containsKey(_tsKey)) {
        final ms = m[_tsKey];
        if (ms is int) return Timestamp.fromMillisecondsSinceEpoch(ms);
        if (ms is num) {
          return Timestamp.fromMillisecondsSinceEpoch(ms.toInt());
        }
      }
      return decodeMap(m);
    }
    if (value is List) {
      return value.map(decodeValue).toList();
    }
    return value;
  }

  static FieldValue _fieldValueFromToken(String token) {
    switch (token) {
      case 'delete':
        return FieldValue.delete();
      case 'arrayUnion':
        return FieldValue.arrayUnion(const []);
      case 'arrayRemove':
        return FieldValue.arrayRemove(const []);
      case 'increment':
        return FieldValue.increment(1);
      case 'serverTimestamp':
      default:
        return FieldValue.serverTimestamp();
    }
  }
}
