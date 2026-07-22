/// Lápides de exclusão por tenant/módulo — blindagem «excluiu, não volta».
///
/// Quando um documento é excluído, os caches em camadas (RAM, Hive,
/// persistência do Firestore, refresh em background) podem re-hidratar a
/// lista com o doc antigo. Este registo guarda os IDs recém-excluídos e os
/// load services filtram qualquer snapshot que ainda os contenha.
abstract final class TenantDeletedDocTombstones {
  TenantDeletedDocTombstones._();

  /// TTL generoso: depois disso o servidor já é a única fonte da verdade.
  static const Duration _ttl = Duration(hours: 12);

  /// chave: `tenantId|module` → mapa docId → momento da exclusão.
  static final Map<String, Map<String, DateTime>> _byModule = {};

  static String _moduleKey(String tenantId, String module) =>
      '${tenantId.trim()}|${module.trim()}';

  /// Regista IDs excluídos (chamar ANTES do delete para fechar corrida com
  /// refresh em background que já esteja em curso).
  static void mark(
    String tenantId,
    String module,
    Iterable<String> docIds,
  ) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final bucket = _byModule.putIfAbsent(
      _moduleKey(tid, module),
      () => <String, DateTime>{},
    );
    final now = DateTime.now();
    for (final raw in docIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      bucket[id] = now;
    }
  }

  /// O doc foi excluído há pouco? (dentro do TTL)
  static bool contains(String tenantId, String module, String docId) {
    final bucket = _byModule[_moduleKey(tenantId, module)];
    if (bucket == null || bucket.isEmpty) return false;
    final at = bucket[docId.trim()];
    if (at == null) return false;
    if (DateTime.now().difference(at) > _ttl) {
      bucket.remove(docId.trim());
      return false;
    }
    return true;
  }

  /// Há alguma lápide activa para este tenant/módulo?
  static bool hasAny(String tenantId, String module) {
    final bucket = _byModule[_moduleKey(tenantId, module)];
    if (bucket == null || bucket.isEmpty) return false;
    final now = DateTime.now();
    bucket.removeWhere((_, at) => now.difference(at) > _ttl);
    return bucket.isNotEmpty;
  }

  /// Filtra uma lista de itens pelo ID (genérico — qualquer tipo de doc).
  static List<T> filter<T>(
    String tenantId,
    String module,
    List<T> items,
    String Function(T item) idOf,
  ) {
    if (items.isEmpty || !hasAny(tenantId, module)) return items;
    return items
        .where((item) => !contains(tenantId, module, idOf(item)))
        .toList();
  }

  /// Descarta a lápide (ex.: doc foi recriado de propósito).
  static void unmark(String tenantId, String module, String docId) {
    _byModule[_moduleKey(tenantId, module)]?.remove(docId.trim());
  }
}
