import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Resolve URLs HTTP e paths `igrejas/{churchId}/…` do Firestore.
abstract final class ChurchMediaUrlResolver {
  ChurchMediaUrlResolver._();

  static const _singleUrlKeys = [
    'imagemUrl',
    'imageUrl',
    'capaUrl',
    'coverUrl',
    'thumbnailUrl',
    'thumbUrl',
    'foto01Url',
    'foto02Url',
    'foto03Url',
    'foto04Url',
    'comprovanteUrl',
    'comprovanteLink',
    'videoUrl',
  ];

  static const _arrayUrlKeys = [
    'imagensUrls',
    'imageUrls',
    'fotos',
    'thumbUrls',
  ];

  static const _singlePathKeys = [
    'imagemStoragePath',
    'capaStoragePath',
    'videoStoragePath',
    'comprovanteStoragePath',
    'foto01StoragePath',
    'foto02StoragePath',
    'foto03StoragePath',
    'foto04StoragePath',
  ];

  static const _arrayPathKeys = [
    'imagensStoragePaths',
    'imageStoragePaths',
  ];

  static bool looksLikeHttpUrl(String raw) {
    final u = raw.trim().toLowerCase();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  static String normalizeStoragePath(String raw) {
    var s = raw.trim();
    if (s.startsWith('gs://')) {
      final slash = s.indexOf('/', 5);
      if (slash > 0) s = s.substring(slash + 1);
    }
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }

  static bool looksLikeChurchStoragePath(String raw) {
    final n = normalizeStoragePath(raw);
    return n.startsWith('igrejas/');
  }

  /// Padrão único — URL HTTP ou resolve path Storage.
  static Future<String> resolveMediaUrl({
    String? httpUrl,
    String? storagePath,
  }) async {
    final u = sanitizeImageUrl((httpUrl ?? '').trim());
    if (u.isNotEmpty && looksLikeHttpUrl(u)) return u;
    final p = normalizeStoragePath((storagePath ?? '').trim());
    if (p.isEmpty) return '';
    try {
      await ensureFirebaseCore(requireAuth: false);
      return await firebaseDefaultStorage.ref(p).getDownloadURL();
    } catch (_) {
      return '';
    }
  }

  static List<String> collectHttpUrls(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];

    void add(String? raw) {
      if (raw == null) return;
      final t = sanitizeImageUrl(raw.trim());
      if (t.isEmpty || !looksLikeHttpUrl(t)) return;
      if (seen.add(t)) out.add(t);
    }

    for (final key in _singleUrlKeys) {
      add((data[key] ?? '').toString());
    }
    for (final key in _arrayUrlKeys) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is String) add(item);
      }
    }
    return out;
  }

  static List<String> collectStoragePaths(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];

    void addPath(String? raw) {
      if (raw == null) return;
      final t = raw.trim();
      if (t.isEmpty || !looksLikeChurchStoragePath(t)) return;
      final n = normalizeStoragePath(t);
      if (seen.add(n)) out.add(n);
    }

    for (final key in _singlePathKeys) {
      addPath((data[key] ?? '').toString());
    }
    for (final key in _arrayPathKeys) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is String) addPath(item);
      }
    }
    return out;
  }

  static Future<List<String>> resolveImageUrls(
    Map<String, dynamic> data, {
    String? docId,
  }) async {
    final seen = <String>{};
    final out = <String>[];

    for (final u in collectHttpUrls(data)) {
      if (isValidImageUrl(u) && seen.add(u)) out.add(u);
    }

    for (final path in collectStoragePaths(data)) {
      final url = await resolveMediaUrl(storagePath: path);
      if (url.isNotEmpty && seen.add(url)) out.add(url);
    }

    return out;
  }

  static Map<String, dynamic> stripEmptyMediaFields(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    fields.forEach((key, value) {
      if (value is String && value.trim().isEmpty) return;
      out[key] = value;
    });
    return out;
  }
}
