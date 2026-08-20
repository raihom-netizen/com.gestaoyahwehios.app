import 'package:gestao_yahweh/core/tenant/church_tenant_override.dart';
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

  /// Igreja escolhida a dedo pelo operador global (seletor «Trocar de igreja»).
  ///
  /// Existe porque nem todo documento em `igrejas/` respeita o padrao
  /// `igreja_*`: ha tenants gravados como `assembleia_de_deus_...` e
  /// `igreta_batista_...` (gralha no nome de origem). Sem esta excecao, o
  /// `resolveChurchId` descartava a dica e caia no `currentChurchId` — a
  /// igreja do proprio utilizador —, e a troca nunca saia do lugar.
  ///
  /// Delegado a [ChurchTenantOverride], que e partilhado por todos os modulos
  /// (nove ficheiros duplicavam o teste de id canonico).
  static String? get explicitTenantOverride => ChurchTenantOverride.explicit;

  static set explicitTenantOverride(String? v) =>
      ChurchTenantOverride.explicit = v;

  /// Resolve churchId: tenant escolhido → sessão bound → mapa BPC/slug → hint.
  ///
  /// **Sempre** aplica [TenantResolverService.mapLegacySeedToCanonical] — mesmo
  /// quando a sessão ficou bound a um slug legado
  /// (`o-brasil-cristo-jardim-goiano`).
  /// Resolve um id de igreja **ignorando** a escolha do operador global.
  ///
  /// É para o site público e o cadastro público, onde o tenant vem do slug da
  /// URL e não pode ser trocado por aquilo que o operador tem aberto no painel.
  static String resolveExactChurchId(String churchId) {
    final t = churchId.trim();
    if (t.isEmpty) return '';
    final mapped = TenantResolverService.mapLegacySeedToCanonical(t);
    if (mapped != null && mapped.isNotEmpty) return mapped;
    return t;
  }

  /// Resolve o churchId do **painel**.
  ///
  /// A igreja escolhida no seletor «Trocar de igreja» ganha de qualquer dica.
  ///
  /// Antes era ao contrário: uma dica válida ganhava e o override só servia de
  /// recurso. Isso ainda podia funcionar enquanto ids fora do padrão
  /// `igreja_*` eram rejeitados — mas depois de [ChurchKnownTenantsStore]
  /// passar a reconhecer **todos** os ids reais, qualquer dica guardada antes
  /// da troca (a igreja de origem, tipicamente `widget.tenantId` capturado na
  /// construção do módulo) passou a ganhar sempre. Resultado: o cabeçalho
  /// mudava, o resto do painel continuava na igreja antiga.
  ///
  /// Quem precisa mesmo de outro tenant usa [resolveExactChurchId].
  static String resolveChurchId([String? shellHint]) {
    final forced = explicitTenantOverride?.trim() ?? '';
    if (forced.isNotEmpty) return forced;

    final hint = shellHint?.trim() ?? '';
    if (hint.isNotEmpty) {
      final mapped = TenantResolverService.mapLegacySeedToCanonical(hint);
      if (mapped != null && mapped.isNotEmpty) return mapped;
      if (ChurchTenantOverride.isChurchDocId(hint)) return hint;
    }

    final ctx = currentChurchId;
    if (ctx != null && ctx.isNotEmpty) return _canonicalize(ctx);
    return _canonicalize(hint);
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
