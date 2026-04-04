/// Constantes centralizadas do app — assinatura, limites, paginação, UX.
/// Ajuste aqui para alterar carência, tolerância de membros e tamanhos de lista.
class AppConstants {
  AppConstants._();

  // ——— Site público e cadastro (seu domínio) ———
  /// URL base do site público da igreja e cadastro público de membros. Use seu domínio próprio.
  static const String publicWebBaseUrl = 'https://gestaoyahweh.com.br';

  /// Base https normalizada (sem path final). [raw] pode ser `dominio.com` ou URL completa.
  static String? normalizePublicSiteBaseUrl(String? raw) {
    var t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    t = t.replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return null;
    if (!t.toLowerCase().startsWith('http')) t = 'https://$t';
    final u = Uri.tryParse(t);
    if (u == null || u.host.isEmpty) return null;
    final port = u.hasPort && u.port != 443 && u.scheme == 'https' ? ':${u.port}' : '';
    final portHttp = u.hasPort && u.port != 80 && u.scheme == 'http' ? ':${u.port}' : '';
    if (u.scheme == 'http') return 'http://${u.host}$portHttp';
    return 'https://${u.host}$port';
  }

  /// Domínio público configurado no doc `igrejas` (Painel Master / cadastro). Fallback: [publicWebBaseUrl].
  static String publicWebBaseUrlForChurch(Map<String, dynamic>? church) {
    if (church == null) return publicWebBaseUrl;
    for (final k in [
      'customPublicDomain',
      'publicSiteDomain',
      'dominioPublico',
      'publicDomain',
      'siteCustomDomain',
    ]) {
      final base = normalizePublicSiteBaseUrl(church[k]?.toString());
      if (base != null) return base;
    }
    return publicWebBaseUrl;
  }

  /// Home pública da igreja: respeita [customPublicDomain] quando preenchido.
  static String publicChurchHomeUrlForChurch(
    String slug, {
    Map<String, dynamic>? church,
  }) {
    final s = slug.trim();
    if (s.isEmpty) return publicWebBaseUrlForChurch(church);
    final base = publicWebBaseUrlForChurch(church);
    return '$base/${Uri.encodeComponent(s)}';
  }

  /// Slugs reservados (não usar como link público — colidem com rotas do app).
  static const Set<String> reservedChurchSlugs = {
    'admin',
    'login',
    'login_admin',
    'cadastro',
    'signup',
    'painel',
    'planos',
    's',
    'i',
    'igreja',
    'usuarios_permissoes',
    'aprovar_membros_pendentes',
    'carteirinha-validar',
    'convite-departamento',
    'api',
    'version',
    'icons',
    'assets',
    'index.html',
    // Nome da marca / hosting — não são slugs de igreja (site de divulgação na raiz).
    'gestaoyahweh',
    'gestaoyahweh-21e23',
  };

  /// Slug que aponta para o site de divulgação (marca), não para uma igreja no Firestore.
  static bool isMarketingBrandSlug(String? slug) {
    if (slug == null || slug.isEmpty) return false;
    const brand = {'gestaoyahweh', 'gestaoyahweh-21e23'};
    return brand.contains(slug.trim().toLowerCase());
  }

  /// Site público da igreja: `/{slug}` (domínio único + subpasta).
  static String publicChurchHomeUrl(String slug) {
    final s = slug.trim();
    if (s.isEmpty) return publicWebBaseUrl;
    return '$publicWebBaseUrl/${Uri.encodeComponent(s)}';
  }

  /// Cadastro público de membros: `/{slug}/cadastro-membro`.
  static String publicChurchMemberSignupUrl(String slug) {
    final s = slug.trim();
    if (s.isEmpty) return publicWebBaseUrl;
    return '${publicChurchHomeUrl(s)}/cadastro-membro';
  }

  /// Link compartilhável da publicação: `/{slug}/{noticiaId}` (abre no app web com deep link).
  static String shareNoticiaPublicUrl(String churchSlug, String noticiaId) {
    final s = churchSlug.trim();
    final e = noticiaId.trim();
    if (s.isEmpty || e.isEmpty) return publicWebBaseUrl;
    return '$publicWebBaseUrl/${Uri.encodeComponent(s)}/${Uri.encodeComponent(e)}';
  }

  /// Link “smart” para WhatsApp: `/igreja/{slug}/evento/{id}` → Hosting reescreve para [shareEvento] (OG + imagem).
  static String shareNoticiaIgrejaEventoUrl(String churchSlug, String noticiaId) {
    final s = churchSlug.trim();
    final e = noticiaId.trim();
    if (s.isEmpty || e.isEmpty) return publicWebBaseUrl;
    return '$publicWebBaseUrl/igreja/${Uri.encodeComponent(s)}/evento/${Uri.encodeComponent(e)}';
  }

  /// Página OG (Cloud Function): `c` = tenantId. Mantida para links antigos e crawlers.
  /// O Hosting reescreve `/s/evento` para a Cloud Function `shareEvento` (HTML + og:image).
  static String shareNoticiaCardUrl(String tenantId, String noticiaId) {
    final c = Uri.encodeComponent(tenantId);
    final e = Uri.encodeComponent(noticiaId);
    return '$publicWebBaseUrl/s/evento?c=$c&e=$e';
  }

  /// OG com resolução por slug (`s`) + id da notícia (`e`) — mesma function que `c`+`e`.
  static String shareNoticiaOgUrlBySlug(String churchSlug, String noticiaId) {
    final s = Uri.encodeComponent(churchSlug.trim());
    final e = Uri.encodeComponent(noticiaId.trim());
    return '$publicWebBaseUrl/s/evento?s=$s&e=$e';
  }

  /// Mesmo destino que [shareNoticiaCardUrl] — preview social (tenantId).
  static String publicNoticiaSharePageUrl(String tenantId, String noticiaId) =>
      shareNoticiaCardUrl(tenantId, noticiaId);

  /// Link curto do site público — mesmo formato que [publicChurchHomeUrl].
  static String publicSiteShortUrl(String slug) => publicChurchHomeUrl(slug);

  /// Link curto do mapa (coordenadas = curto; endereço = form shortest).
  static String mapsShortUrl({double? lat, double? lng, String? address}) {
    if (lat != null && lng != null) {
      return 'https://maps.google.com/?q=$lat,$lng';
    }
    if (address != null && address.trim().isNotEmpty) {
      return 'https://maps.google.com/?q=${Uri.encodeComponent(address.trim())}';
    }
    return '';
  }

  /// Convite para o membro abrir no navegador/app web e vincular-se ao departamento (`tid` = id da igreja, `did` = id do doc).
  static String departmentInviteUrl(String tenantId, String departmentDocId) {
    final t = Uri.encodeComponent(tenantId.trim());
    final d = Uri.encodeComponent(departmentDocId.trim());
    return '$publicWebBaseUrl/convite-departamento?tid=$t&did=$d';
  }

  // ——— Assinatura / Trial ———
  /// Dias de carência após o vencimento antes de bloquear o acesso (igual Controle Total).
  static const int subscriptionGraceDays = 3;
  /// WhatsApp do suporte master (somente dígitos com DDI/DDD). Ex.: 5562999999999
  static const String masterSupportWhatsApp = '';

  // ——— Limite de membros por plano ———
  /// Liberdade de membros a mais após o limite do plano antes de travar inclusão.
  static const int membersGraceOverLimit = 5;

  // ——— Paginação ———
  /// Quantidade de itens por página em listas (membros, eventos, etc.).
  static const int pageSize = 20;

  // ——— UX ———
  /// Duração padrão de SnackBar (segundos).
  static const int snackBarDurationSeconds = 3;
  /// Timeout de chamadas HTTP/Cloud Functions (segundos).
  static const int callableTimeoutSeconds = 25;
}
