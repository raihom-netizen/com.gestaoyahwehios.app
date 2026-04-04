import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_logo_storage_naming.dart';

/// Layout canônico do **Firebase Storage** por igreja (tenant = id do doc em `igrejas/{id}`).
///
/// ## Padrão
/// Toda mídia da igreja fica sob **`igrejas/{igrejaDocId}/`**, com estas pastas (PT-BR):
/// - **[membros]** — fotos de membros, gestor, assinatura, digital, variantes.
/// - **[noticias]** — legado: uploads antigos do mural (timestamp no nome).
/// - **[avisos]** — canónico: `avisos/{postId}/capa_aviso.jpg` (+ `galeria_XX.jpg`).
/// - **[eventos]** — canónico: `eventos/{postId}/banner_evento.jpg` (+ `galeria_XX.jpg`); vídeos em `eventos/videos/`, thumbs, **templates** em `eventos/templates/`.
/// - **[patrimonio]** — canónico: `patrimonio/{itemId}/foto_item.jpg` (+ `galeria_XX.jpg`).
/// Padrão geral: `igrejas/{id_igreja}/{modulo}/{id_item}/arquivo.jpg` (IDs estáveis do Firestore quando aplicável).
/// - **[configuracoes]** — identidade: `configuracoes/logo_igreja.png` (único, sobrescrito ao trocar);
///   assinatura do pastor em `assinatura.png` / `.jpg`.
/// - **[templates/certificados]** — fundos de certificado em alta resolução: `modelo_*.png` ou `.jpg`.
/// - **[logo]** — legado: `logo/logo_{nomeIgreja}_{id}.jpg`, `logo_principal.jpg`, `branding/` (migração).
///
/// Outros nós sob `igrejas/{id}/` (ex.: `comprovantes`, `departamentos`, `certificados_gestor`) são
/// módulos operacionais; continuam **dentro** do prefixo da igreja.
///
/// ## Gestão YAHWEH (institucional / divulgação)
/// Conteúdo do **site do produto** e materiais que **não** pertencem a uma igreja cliente deve ficar
/// **fora** de `igrejas/…` (ex.: pastas do app público no bucket), para não misturar com dados das igrejas.
///
/// ## Pastas virtuais (GCS / Firebase Storage)
/// Não existem diretórios vazios: `configuracoes/` só aparece no console após o primeiro objeto
/// (ex.: `logo_igreja.png`). O app pode materializar um PNG mínimo transparente só quando ainda não há
/// ficheiro canónico — o upload real **substitui** no mesmo path.
abstract final class ChurchStorageLayout {
  ChurchStorageLayout._();

  /// Tamanho mínimo (bytes) para tratar o ficheiro em `logo_igreja.png` como logo real e sincronizar URL no Firestore.
  /// Abaixo disso considera-se placeholder de estrutura (1×1 transparente).
  static const int kChurchIdentityLogoMinBytesForFirestoreSync = 400;

  /// PNG 1×1 transparente — materializa `configuracoes/` quando ainda não existe logo canónica.
  /// `true` se [b] for exatamente o PNG mínimo usado só para materializar a pasta no bucket.
  static bool isIdentityStructurePlaceholderPng(Uint8List b) {
    final p = kMinimalTransparentIdentityPng;
    if (b.length != p.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (b[i] != p[i]) return false;
    }
    return true;
  }

  static final Uint8List kMinimalTransparentIdentityPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  /// Segmentos canônicos (nomes de pasta) sob `igrejas/{id}/`.
  static const String kSegMembros = 'membros';
  static const String kSegNoticias = 'noticias';
  static const String kSegAvisos = 'avisos';
  static const String kSegEventos = 'eventos';
  static const String kSegPatrimonio = 'patrimonio';
  static const String kSegLogo = 'logo';

  /// Configurações diversas (ex.: assinatura do pastor para carteirinha digital).
  static const String kSegConfiguracoes = 'configuracoes';

  static String churchRoot(String tenantId) => 'igrejas/${tenantId.trim()}';

  static String _safeDocId(String id) {
    var s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.isEmpty ? 'doc' : s;
  }

  /// Foto de perfil canónica: `membros/{memberDocId}/foto_perfil.jpg` (sobrescreve ao atualizar).
  static String memberCanonicalProfilePhotoPath(
      String tenantId, String memberDocId) {
    final tid = tenantId.trim();
    final mid = _safeDocId(memberDocId);
    return '${churchRoot(tid)}/$kSegMembros/$mid/foto_perfil.jpg';
  }

  /// Post **evento** em [noticias]: capa `banner_evento.jpg`, mais fotos `galeria_01.jpg`…
  static String eventPostPhotoPath(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegEventos/$pid';
    if (slotIndex <= 0) return '$root/banner_evento.jpg';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  /// Post **aviso** em [noticias]: capa `capa_aviso.jpg`, mais fotos `galeria_01.jpg`…
  static String avisoPostPhotoPath(
      String tenantId, String postDocId, int slotIndex) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${churchRoot(tid)}/$kSegAvisos/$pid';
    if (slotIndex <= 0) return '$root/capa_aviso.jpg';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  /// Caminhos tentados para assinatura institucional (`assinatura.png` / `.jpg`).
  static List<String> pastorSignatureConfigPaths(String tenantId) {
    final r = churchRoot(tenantId);
    return [
      '$r/$kSegConfiguracoes/assinatura.png',
      '$r/$kSegConfiguracoes/assinatura.jpg',
    ];
  }

  /// Logo institucional canónica (carteirinha, certificados, relatórios, site).
  /// Nome fixo para sobrescrever no Storage sem gerar ficheiros órfãos.
  static String churchIdentityLogoPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegConfiguracoes/logo_igreja.png';

  /// Legado: tentativa `.jpg` na mesma pasta (antes da padronização PNG).
  static String churchIdentityLogoPathJpgLegacy(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegConfiguracoes/logo_igreja.jpg';

  static String logoPrincipalPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegLogo/logo_principal.jpg';

  /// Base sem extensão (variantes thumb/card/full).
  static String logoPrincipalBaseWithoutExt(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegLogo/logo_principal';

  /// Logo nomeada: `igrejas/{id}/logo/logo_{nomeSanitizado}_{id}.jpg`.
  static String logoNamedPath(String tenantId, String churchName) {
    final stem = ChurchLogoStorageNaming.fileStemWithoutExt(
      churchName: churchName,
      tenantId: tenantId,
    );
    return '${churchRoot(tenantId)}/$kSegLogo/$stem.jpg';
  }

  /// Base sem extensão para variantes `_thumb` / `_card` / `_full`.
  static String logoNamedBaseWithoutExt(String tenantId, String churchName) {
    final stem = ChurchLogoStorageNaming.fileStemWithoutExt(
      churchName: churchName,
      tenantId: tenantId,
    );
    return '${churchRoot(tenantId)}/$kSegLogo/$stem';
  }

  /// Ordem de tentativa no Storage: identidade em [configuracoes], depois legados.
  static List<String> churchLogoObjectPathsToTry(
    String tenantId,
    String? churchName,
  ) {
    final tid = tenantId.trim();
    final out = <String>[
      churchIdentityLogoPath(tid),
      churchIdentityLogoPathJpgLegacy(tid),
    ];
    final n = churchName?.trim();
    if (n != null && n.isNotEmpty) {
      out.add(logoNamedPath(tid, n));
    }
    out.add(logoPrincipalPath(tid));
    out.addAll(legacyLogoObjectPaths(tid));
    return out;
  }

  /// Capa de **template** de culto/evento fixo (Firestore: `event_templates`).
  /// Fica em `eventos/templates/` para obedecer ao padrão `…/eventos/…`.
  ///
  /// [uniqueId] deve ser estável por doc quando possível (ex.: id do Firestore), para sobrescrever
  /// o mesmo arquivo ao trocar a imagem.
  static String eventTemplateCoverPath(String tenantId, String uniqueId) {
    final safe =
        uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    final id = safe.isEmpty ? 'template' : safe;
    return '${churchRoot(tenantId)}/$kSegEventos/templates/$id.jpg';
  }

  /// Caminho legado da capa de template (antes de `eventos/templates/`).
  static String legacyEventTemplateCoverPath(String tenantId, String uniqueId) {
    final safe =
        uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    final id = safe.isEmpty ? 'template' : safe;
    return '${churchRoot(tenantId)}/event_templates/$id.jpg';
  }

  /// Foto principal do membro no painel (mesmo padrão do cadastro público).
  static String memberMainPhotoPath(String tenantId, String memberId) =>
      '${churchRoot(tenantId)}/$kSegMembros/$memberId.jpg';

  /// Base sem extensão para variantes thumb/card/full do membro.
  static String memberMainPhotoBaseWithoutExt(String tenantId, String memberId) =>
      '${churchRoot(tenantId)}/$kSegMembros/$memberId';

  /// [stem] = ID do documento em `membros` (em geral CPF 11 dígitos) ou outro id estável.
  static String gestorMemberPhotoPath(String tenantId, String stem) {
    final s = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${churchRoot(tenantId)}/$kSegMembros/${s}_gestor.jpg';
  }

  /// Espelho estável da foto do gestor (painel / URLs diretas) — além de `membros/…/foto_perfil.jpg`.
  static String gestorPublicProfilePhotoPath(String tenantId) =>
      '${churchRoot(tenantId)}/gestor/foto_perfil.jpg';

  /// Foto do patrimônio por **slot** (0–4): pasta por item — `foto_item.jpg` e `galeria_XX.jpg`.
  static String patrimonioPhotoPath(String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    if (s == 0) return '$root/foto_item.jpg';
    final n = s.toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  /// Base sem extensão (limpeza de variantes `_thumb` / `_card` / `_full` e legado `id_slot`).
  static String patrimonioPhotoBaseWithoutExt(
      String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    if (s == 0) return '$root/foto_item';
    final n = s.toString().padLeft(2, '0');
    return '$root/galeria_$n';
  }

  /// Caminhos legados (EcoFire / versões anteriores) — podem ser removidos após novo upload.
  static List<String> legacyLogoObjectPaths(String tenantId) => [
        '${churchRoot(tenantId)}/branding/logo_igreja.jpg',
        '${churchRoot(tenantId)}/branding/logo_igreja.png',
      ];

  /// Fundos luxo para PDF: `igrejas/{id}/templates/certificados/{stem}.png|.jpg`.
  static const String kSegCertificadosTemplates = 'templates/certificados';

  static List<String> certificateTemplateBackgroundPaths(
    String tenantId,
    String storageStem,
  ) {
    final stem =
        storageStem.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (stem.isEmpty) return const [];
    final base =
        '${churchRoot(tenantId)}/$kSegCertificadosTemplates/$stem';
    return ['$base.png', '$base.jpg'];
  }
}
