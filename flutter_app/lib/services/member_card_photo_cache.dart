import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Cache RAM de URLs de foto resolvidas para PDF em lote (evita N× Storage).
abstract final class MemberCardPhotoCache {
  MemberCardPhotoCache._();

  static final Map<String, _Entry> _ram = {};
  static const _ttl = Duration(minutes: 20);

  static String _key(String tenantId, String memberId) =>
      '${tenantId.trim()}|${memberId.trim()}';

  static String? get(String tenantId, String memberId) {
    final e = _ram[_key(tenantId, memberId)];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _ttl) {
      _ram.remove(_key(tenantId, memberId));
      return null;
    }
    return e.url;
  }

  static void put(String tenantId, String memberId, String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    _ram[_key(tenantId, memberId)] = _Entry(u, DateTime.now());
    if (_ram.length > 400) {
      final oldest = _ram.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (var i = 0; i < 80 && i < oldest.length; i++) {
        _ram.remove(oldest[i].key);
      }
    }
  }

  static void clear() => _ram.clear();

  /// Resolve em paralelo limitado (lote PDF).
  static Future<void> warmUrls({
    required Iterable<Future<String> Function()> resolvers,
  }) async {
    final list = resolvers.toList();
    if (list.isEmpty) return;
    const chunk = YahwehPerformanceV4.memberCardPdfPhotoParallel;
    for (var i = 0; i < list.length; i += chunk) {
      final end = (i + chunk > list.length) ? list.length : i + chunk;
      await Future.wait(list.sublist(i, end).map((r) => r()));
    }
  }
}

class _Entry {
  _Entry(this.url, this.at);
  final String url;
  final DateTime at;
}
