import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Contexto de tenant — **único** `churchId` da sessão.
///
/// Uso obrigatório em módulos:
/// ```dart
/// final churchId = ChurchContext.currentChurchId;
/// ```
/// **Nunca** montar path manual (`igrejas/...`) nas telas.
abstract final class ChurchContext {
  ChurchContext._();

  /// ID do documento em `igrejas/{churchId}` (Firestore + Storage).
  static String? get currentChurchId => ChurchContextService.currentChurchId;

  static Map<String, dynamic>? get currentChurchData =>
      ChurchContextService.currentChurchData;

  static String? get seedId => ChurchContextService.seedId;

  static DateTime? get boundAt => ChurchContextService.boundAt;

  /// `igrejas/{churchId}` — Firestore.
  static String get firestorePath => ChurchContextService.firestorePath;

  /// `igrejas/{churchId}` — Storage.
  static String get storageRoot => ChurchContextService.storageRoot;

  static String storagePath(String relative) {
    final root = storageRoot;
    if (root.isEmpty) return relative.trim();
    final rel = relative.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    return rel.isEmpty ? root : '$root/$rel';
  }

  static String churchStorageRoot([String? hint]) {
    final id = resolveChurchId(hint);
    return id.isEmpty ? '' : ChurchStorageLayout.churchRoot(id);
  }

  /// Resolve churchId: sessão bound → mapa BPC/slug → hint do shell (ID directo).
  ///
  /// **Sempre** aplica [TenantResolverService.mapLegacySeedToCanonical] — mesmo quando
  /// a sessão ficou bound a um slug legado (`o-brasil-cristo-jardim-goiano`).
  static String resolveChurchId([String? shellHint]) {
    final ctx = currentChurchId;
    if (ctx != null && ctx.isNotEmpty) return _canonicalize(ctx);
    return _canonicalize(shellHint ?? '');
  }

  static String _canonicalize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final mapped = TenantResolverService.mapLegacySeedToCanonical(t);
    if (mapped != null && mapped.isNotEmpty) return mapped;
    return t;
  }

  static String requireChurchId([String? shellHint]) {
    final id = resolveChurchId(shellHint);
    if (id.isEmpty) {
      throw StateError(
        'ChurchContext não inicializado. Chame resolveAndBind após login.',
      );
    }
    return id;
  }

  static Future<String> bind({
    required String seed,
    String? userUid,
    bool forceRefresh = false,
  }) =>
      ChurchContextService.resolveAndBind(
        seed: seed,
        userUid: userUid,
        forceRefresh: forceRefresh,
      );

  static void bindData({
    required String churchId,
    required Map<String, dynamic> data,
    int? bootstrapMs,
  }) =>
      ChurchContextService.bindChurchData(
        churchId: churchId,
        data: data,
        bootstrapMs: bootstrapMs,
      );

  static void clear() => ChurchContextService.clear();

  /// Bind imediato após login/shell — `igrejas/{churchId}` antes de leituras async.
  static void bindImmediate({
    required String seed,
    String? canonicalId,
    String? userUid,
  }) =>
      ChurchContextService.bindPanelIdImmediate(
        seed: seed,
        canonicalId: canonicalId,
        userUid: userUid,
      );

  static bool get isBound =>
      currentChurchId != null && currentChurchId!.isNotEmpty;
}
