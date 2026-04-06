import 'dart:typed_data';

import 'package:gestao_yahweh/core/church_logo_storage_naming.dart';

/// Layout canônico do **Firebase Storage** por igreja (tenant = id do doc em `igrejas/{id}`).
///
/// ## Padrão
/// Toda mídia da igreja fica sob **`igrejas/{igrejaDocId}/`**, com estas pastas (PT-BR):
/// - **[membros]/{idDocumentoMembro}/foto_perfil.jpg** — foto de perfil canónica (id = doc em `igrejas/{tenant}/membros/`, ex. CPF); sempre este nome de ficheiro. Outros ficheiros: gestor, assinatura, digital, variantes legadas.
/// - **[noticias]** — legado Storage + **Firestore** `igrejas/{id}/noticias` (eventos no mural).
/// - **[avisos]** — canónico Storage `avisos/{postId}/…` + **Firestore** `igrejas/{id}/avisos` (só avisos do mural).
/// - **[eventos]** — canónico: `eventos/{postId}/banner_evento.jpg` (+ `galeria_XX.jpg`); vídeos hospedados só em `eventos/videos/` (`{postId}_v0.mp4` + `{postId}_v0_thumb.jpg`, slots 0–1); **templates** em `eventos/templates/`.
/// - **[patrimonio]** — canónico: pasta por bem `patrimonio/{itemId}/` com até **5** fotos:
///   só `galeria_01.jpg` … `galeria_05.jpg` (sem `foto_item` nem `thumb_*` no modelo).
/// Padrão geral: `igrejas/{id_igreja}/{modulo}/{id_item}/arquivo.jpg` (IDs estáveis do Firestore quando aplicável).
/// - **[configuracoes]** — identidade: `configuracoes/logo_igreja.png` (único, sobrescrito ao trocar; sem `thumb_*`);
///   assinatura do pastor em `assinatura.png` / `.jpg`.
/// - **[cartao_membro]** — logo dedicada da carteirinha: `logo.jpg` (substitui o legado `carteira_logos/{tenant}/`).
/// - **[certificados]** — logo dedicada dos certificados PDF (`logo_atual.jpg` etc.; substitui `certificado_logos/{tenant}/`).
/// - **[templates/certificados]** — fundos de certificado em alta resolução: `modelo_*.png` ou `.jpg`.
/// - **[logo]** — legado: `logo/logo_{nomeIgreja}_{id}.jpg`, `logo_principal.jpg`, `branding/` (migração).
///
/// Outros nós sob `igrejas/{id}/` (ex.: `comprovantes`, `departamentos`, `certificados_gestor`) são
/// módulos operacionais; continuam **dentro** do prefixo da igreja.
///
  /// ## Gestão YAHWEH (institucional / divulgação)
  /// Galeria institucional e PDFs do produto ficam em `public/gestao_yahweh/…` (sem `igrejas/`).
  /// A **capa «cliente em destaque»** no site de divulgação usa [kSegMarketingDestaque] **dentro** de `igrejas/{tenantId}/`
  /// (ID do documento em `igrejas/`), alinhado ao restante Storage da igreja.
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
  /// Cartão de membro (logo própria da carteirinha, não a logo institucional em `configuracoes/`).
  static const String kSegCartaoMembro = 'cartao_membro';
  /// Mídia dedicada ao módulo de certificados (logo própria; fundos HD ficam em [kSegCertificadosTemplates]).
  static const String kSegCertificadosMidia = 'certificados';
  static const String kSegEventos = 'eventos';
  static const String kSegPatrimonio = 'patrimonio';
  static const String kSegLogo = 'logo';

  /// Configurações diversas (ex.: assinatura do pastor para carteirinha digital).
  static const String kSegConfiguracoes = 'configuracoes';

  /// Capa no site de divulgação (aba Master «Igrejas cliente») — mesmo prefixo `igrejas/{tenantId}/` que o painel da igreja.
  static const String kSegMarketingDestaque = 'marketing_destaque';

  static String churchRoot(String tenantId) => 'igrejas/${tenantId.trim()}';

  /// `igrejas/{tenantId}/marketing_destaque/capa.jpg` (único ficheiro; sem `thumb_*`).
  static String marketingClienteShowcaseCapaPath(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return '';
    return '${churchRoot(tid)}/$kSegMarketingDestaque/capa.jpg';
  }

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

  /// Vídeo MP4 no Storage ligado ao doc do evento em [noticias] — [videoSlot] 0 ou 1 (máx. 2 vídeos).
  /// Sobrescreve o mesmo path ao trocar o ficheiro (evita “cemitério” de objetos).
  static String eventHostedVideoMp4Path(
      String tenantId, String postDocId, int videoSlot) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${churchRoot(tid)}/$kSegEventos/videos/${pid}_v$s.mp4';
  }

  /// Miniatura JPEG do vídeo — mesmo prefixo `eventos/videos/` (sem pasta `thumbs/`).
  static String eventHostedVideoThumbPath(
      String tenantId, String postDocId, int videoSlot) {
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${churchRoot(tid)}/$kSegEventos/videos/${pid}_v${s}_thumb.jpg';
  }

  /// Post **aviso**: capa canónica `capa_aviso.jpg` (Firestore usa só `url_original`; derivados `thumb_*` da extensão Storage são limpos em background).
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

  /// ID sanitizado usado na pasta `patrimonio/{safeId}/` (igual ao doc Firestore quando já é seguro).
  static String patrimonioStorageSafeItemId(String itemDocId) =>
      _safeDocId(itemDocId);

  /// Prefixo `igrejas/{tenant}/patrimonio/{safeItemId}` (pasta do bem).
  static String patrimonioItemFolderPrefix(String tenantId, String itemDocId) {
    final safeId = _safeDocId(itemDocId);
    return '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
  }

  /// Foto do patrimônio por **slot** (0–4 = 5 fotos): `galeria_01.jpg` … `galeria_05.jpg`.
  static String patrimonioPhotoPath(String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    final n = (s + 1).toString().padLeft(2, '0');
    return '$root/galeria_$n.jpg';
  }

  /// Base sem extensão (limpeza de variantes `_thumb` / `_card` / `_full` e legado `id_slot`).
  static String patrimonioPhotoBaseWithoutExt(
      String tenantId, String itemDocId, int slot) {
    final s = slot < 0 ? 0 : (slot > 4 ? 4 : slot);
    final safeId = _safeDocId(itemDocId);
    final root = '${churchRoot(tenantId)}/$kSegPatrimonio/$safeId';
    final n = (s + 1).toString().padLeft(2, '0');
    return '$root/galeria_$n';
  }

  /// Caminhos legados (EcoFire / versões anteriores) — podem ser removidos após novo upload.
  static List<String> legacyLogoObjectPaths(String tenantId) => [
        '${churchRoot(tenantId)}/branding/logo_igreja.jpg',
        '${churchRoot(tenantId)}/branding/logo_igreja.png',
      ];

  /// Logo fixa da carteirinha (sobrescreve no mesmo path).
  static String cartaoMembroLogoPath(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCartaoMembro/logo.jpg';

  /// Prefixo para limpar uploads da logo da carteirinha (`cartao_membro/`).
  static String cartaoMembroMediaPrefix(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCartaoMembro';

  /// Base sem extensão da logo dedicada dos certificados (`.jpg` / variantes).
  static String certificadoDedicatedLogoBaseWithoutExt(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCertificadosMidia/logo_atual';

  /// Prefixo da pasta de mídia dos certificados (logo dedicada, etc.).
  static String certificadoDedicatedMediaPrefix(String tenantId) =>
      '${churchRoot(tenantId)}/$kSegCertificadosMidia';

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
