import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/install_pwa_button.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show churchTenantLogoUrl, memCacheExtentForLogicalSize;
import 'package:gestao_yahweh/ui/widgets/church_public_social_gallery.dart'
    show ChurchPublicSocialPresets;

/// Endereço em uma linha — **mesma regra** que [IgrejaCadastroPage._buildEnderecoCompleto]:
/// monta a partir de rua, quadra/número, bairro, cidade, UF e CEP no Firestore.
/// O campo único [endereco] só entra como **fallback** (dados legados sem partes separadas).
String churchPublicFormattedAddress(Map<String, dynamic> data) {
  String s(dynamic v) => (v ?? '').toString().trim();

  final rua = s(data['rua'] ?? data['address'] ?? data['logradouro']);
  final qd = s(data['quadraLoteNumero'] ?? data['quadra_lote_numero']);
  final ruaCompleta =
      rua.isEmpty ? qd : (qd.isEmpty ? rua : '$rua, $qd');
  final bairro = s(data['bairro'] ?? data['BAIRRO']);
  final cidade =
      s(data['cidade'] ?? data['CIDADE'] ?? data['localidade'] ?? data['LOCALIDADE']);
  final estado = s(data['estado'] ?? data['ESTADO'] ?? data['uf'] ?? data['UF']);
  final cep = s(data['cep'] ?? data['CEP']);

  final cidadeEstado = cidade.isNotEmpty && estado.isNotEmpty
      ? '$cidade - $estado'
      : (cidade.isNotEmpty ? cidade : estado);

  final lista = <String>[];
  if (ruaCompleta.isNotEmpty) lista.add(ruaCompleta);
  if (bairro.isNotEmpty) lista.add(bairro);
  if (cidadeEstado.isNotEmpty) lista.add(cidadeEstado);
  if (cep.isNotEmpty) lista.add('CEP $cep');

  if (lista.isNotEmpty) return lista.join(', ');

  final legacy = s(data['endereco'] ?? data['ENDERECO']);
  if (legacy.isNotEmpty) return legacy;

  return '';
}

/// Telefone/WhatsApp público da igreja (com fallback ao gestor).
String? churchPublicFormattedPhone(Map<String, dynamic> data) {
  final whatsapp = (data['whatsappIgreja'] ??
          data['whatsapp_igreja'] ??
          data['whatsapp'] ??
          data['telefoneIgreja'] ??
          data['telefone'] ??
          data['phone'] ??
          '')
      .toString()
      .trim();
  final gestorTelefone = (data['whatsappGestor'] ??
          data['whatsapp_gestor'] ??
          data['gestorWhatsapp'] ??
          data['gestorTelefone'] ??
          data['gestor_telefone'] ??
          '')
      .toString()
      .trim();
  final raw = whatsapp.isNotEmpty ? whatsapp : gestorTelefone;
  if (raw.isEmpty) return null;
  return raw;
}

/// Valor do cadastro: URL (`https://wa.me/...`) ou **só dígitos** (DDI + número).
String? churchPublicWhatsappDirectUrl(Map<String, dynamic> data) {
  final u = (data['whatsappChatUrl'] ??
          data['socialWhatsappUrl'] ??
          data['whatsappLink'] ??
          data['linkWhatsapp'] ??
          '')
      .toString()
      .trim();
  return u.isEmpty ? null : u;
}

/// Instagram, YouTube ou Facebook — mesmas chaves alternativas que [IgrejaCadastroPage] (`instagramUrl`, etc.).
Uri? churchPublicSocialHttpUri(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final k in keys) {
    final raw = (data[k] ?? '').toString().trim();
    if (raw.isEmpty) continue;
    final normalized =
        raw.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? raw
            : 'https://$raw';
    final u = Uri.tryParse(normalized);
    if (u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty) {
      return u;
    }
  }
  return null;
}

/// Abre o chat: URL do cadastro ou `wa.me` montado a partir do telefone público.
Uri? churchPublicWhatsappLaunchUri(
  Map<String, dynamic> data, {
  required String fallbackPhoneRaw,
  String? churchName,
}) {
  final direct = churchPublicWhatsappDirectUrl(data);
  if (direct != null && direct.isNotEmpty) {
    final t = direct.trim();
    if (RegExp(r'^[0-9]+$').hasMatch(t)) {
      final phone = t.startsWith('55') ? t : '55$t';
      final safeChurch = (churchName ?? '').trim();
      final msg = safeChurch.isEmpty
          ? 'Olá! Vi o site no Gestão YAHWEH e gostaria de mais informações.'
          : 'Olá! Vi o site da $safeChurch no Gestão YAHWEH e gostaria de mais informações.';
      return Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
    }
    final normalized =
        t.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? t
            : 'https://$t';
    final uri = Uri.tryParse(normalized);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri;
    }
  }
  final digits = fallbackPhoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final phone = digits.startsWith('55') ? digits : '55$digits';
  final safeChurch = (churchName ?? '').trim();
  final msg = safeChurch.isEmpty
      ? 'Olá! Vi o site no Gestão YAHWEH e gostaria de mais informações.'
      : 'Olá! Vi o site da $safeChurch no Gestão YAHWEH e gostaria de mais informações.';
  return Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
}

/// FAB “pedido de oração”: prioriza telefone; se houver só link `wa.me` no cadastro, reusa o número do path com texto de oração.
Uri? churchPublicWhatsappPrayerUri(
  Map<String, dynamic> data, {
  required String churchPhoneRaw,
  required String gestorPhoneRaw,
}) {
  const prayer =
      'Olá! Gostaria de deixar um pedido de oração. (Site da igreja — Gestão YAHWEH)';
  final direct = churchPublicWhatsappDirectUrl(data);
  if (direct != null && direct.isNotEmpty) {
    final t = direct.trim();
    if (RegExp(r'^[0-9]+$').hasMatch(t)) {
      final phone = t.startsWith('55') ? t : '55$t';
      return Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(prayer)}');
    }
    final normalized =
        t.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? t
            : 'https://$t';
    final u = Uri.tryParse(normalized);
    if (u != null && u.scheme.startsWith('http')) {
      final host = u.host.toLowerCase();
      if (host.contains('wa.me')) {
        final pathDigits =
            u.path.replaceAll(RegExp(r'[^0-9]'), '');
        if (pathDigits.isNotEmpty) {
          final phone = pathDigits.startsWith('55')
              ? pathDigits
              : '55$pathDigits';
          return Uri.parse(
              'https://wa.me/$phone?text=${Uri.encodeComponent(prayer)}');
        }
      }
      return u;
    }
  }
  for (final raw in [churchPhoneRaw, gestorPhoneRaw]) {
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isNotEmpty) {
      final phone = d.startsWith('55') ? d : '55$d';
      return Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(prayer)}');
    }
  }
  return null;
}

/// Logo do site público: sempre [StableChurchLogo] (Firestore + path + fallback Storage).
class ChurchPublicSiteLogoBadge extends StatelessWidget {
  final String tenantId;
  final Map<String, dynamic>? churchData;
  final double size;
  final double borderRadius;
  /// Preenchimento do quadrado sem bandas vazias grandes (contain deixa “moldura” larga).
  final BoxFit logoFit;
  /// Spinner enquanto resolve URL/bytes (ex.: cabeçalho escuro).
  final Widget? loadingPlaceholder;

  const ChurchPublicSiteLogoBadge({
    super.key,
    required this.tenantId,
    this.churchData,
    required this.size,
    this.borderRadius = 16,
    this.logoFit = BoxFit.contain,
    this.loadingPlaceholder,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode proporcional ao badge — evita decodificar resolução desnecessária na web.
    final cache = memCacheExtentForLogicalSize(size, dpr, maxPx: 512, oversample: 2.25);
    final prefer = churchData != null ? churchTenantLogoUrl(churchData!) : '';
    final path =
        churchData != null ? ChurchImageFields.logoStoragePath(churchData) : null;
    final r = borderRadius.clamp(8.0, 28.0);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.42),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r - 0.5),
        child: ColoredBox(
          color: Colors.white,
          child: StableChurchLogo(
            tenantId: tenantId,
            tenantData: churchData,
            imageUrl: prefer.isNotEmpty ? prefer : null,
            storagePath: path,
            width: size,
            height: size,
            fit: logoFit,
            memCacheWidth: cache,
            memCacheHeight: cache,
            loadingPlaceholder: loadingPlaceholder,
          ),
        ),
      ),
    );
  }
}

/// AppBar fixa — logo da igreja, nome completo, telefone e localização (dados do Firestore).
class ChurchPublicSiteSliverAppBar extends StatelessWidget {
  final String nome;
  final String tenantId;
  final Map<String, dynamic> churchData;
  final VoidCallback onAcessar;
  /// Doação PIX/cartão (Mercado Pago) — site público.
  final VoidCallback? onDoacao;
  final Color accentColor;

  const ChurchPublicSiteSliverAppBar({
    super.key,
    required this.nome,
    required this.tenantId,
    required this.churchData,
    required this.onAcessar,
    this.onDoacao,
    this.accentColor = const Color(0xFF2563EB),
  });

  /// Máximo no desktop — compacto para não roubar altura ao conteúdo.
  static const double _logoSizeMax = 96;

  static double _logoSizeForWidth(double w) {
    if (w < 360) return 56;
    if (w < 440) return 64;
    if (w < 560) return 72;
    if (w < 680) return 80;
    if (w < 880) return 88;
    if (w < 1080) return 92;
    return _logoSizeMax;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final layoutCompact = w < 640;
    final logoSize = _logoSizeForWidth(w);
    final logoRadius = logoSize >= 88 ? 18.0 : 14.0;

    final displayName = nome.trim();
    final phoneLine = churchPublicFormattedPhone(churchData);
    final address = churchPublicFormattedAddress(churchData).trim();
    final hasPhone = phoneLine != null && phoneLine.isNotEmpty;
    final hasAddress = address.isNotEmpty;
    final nameMaxLines = layoutCompact ? 6 : 4;
    final nameFontSize = layoutCompact ? 13.5 : 14.0;
    final charsPerLine = layoutCompact ? 22.0 : 34.0;
    final estNameLines = displayName.isEmpty
        ? 1
        : (displayName.length / charsPerLine).ceil().clamp(1, nameMaxLines);
    final nameBlockH = estNameLines * (nameFontSize * 1.28);

    var metaH = 0.0;
    if (hasPhone) metaH += 6 + 22;
    if (hasAddress) metaH += (hasPhone ? 4 : 6) + 40;

    final textColH = nameBlockH + metaH;
    final row1H = textColH > logoSize ? textColH : logoSize;
    final toolbarH = layoutCompact
        ? row1H + 6 + 44 + 12
        : (row1H + 12.0);
    final toolbarClamped = toolbarH.clamp(logoSize + 12.0, 148.0);

    final metaStyle = TextStyle(
      fontSize: 12.5,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: Colors.white.withValues(alpha: 0.9),
    );
    final iconMeta = IconThemeData(
      size: 16,
      color: Colors.white.withValues(alpha: 0.95),
    );

    final navBar = ThemeCleanPremium.navSidebar;
    final gradientMid =
        Color.lerp(navBar, ThemeCleanPremium.primary, 0.14)!;
    final gradientEnd = Color.lerp(
      Color.lerp(accentColor, navBar, 0.38)!,
      const Color(0xFF0A1628),
      0.32,
    )!;

    final logoLoading = SizedBox(
      width: logoSize,
      height: logoSize,
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );

    final infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName.isEmpty ? 'Igreja' : displayName,
          maxLines: nameMaxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: nameFontSize,
            fontWeight: FontWeight.w800,
            height: 1.28,
            color: Colors.white,
            letterSpacing: -0.25,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        if (phoneLine != null && phoneLine.isNotEmpty) ...[
          const SizedBox(height: 6),
          IconTheme(
            data: iconMeta,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.phone_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(phoneLine, style: metaStyle),
                ),
              ],
            ),
          ),
        ],
        if (hasAddress) ...[
          SizedBox(height: hasPhone ? 4 : 6),
          IconTheme(
            data: iconMeta,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.location_on_outlined),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final acessarRadius = ThemeCleanPremium.radiusLg;
    final acessarBtn = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: ThemeCleanPremium.minTouchTarget,
        minHeight: ThemeCleanPremium.minTouchTarget,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onAcessar,
          borderRadius: BorderRadius.circular(acessarRadius),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(acessarRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.52),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.34),
                  Colors.white.withValues(alpha: 0.14),
                  Colors.white.withValues(alpha: 0.07),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                  spreadRadius: -2,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.12),
                  blurRadius: 0,
                  offset: const Offset(0, -1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.login_rounded,
                    size: 19,
                    color: Colors.white.withValues(alpha: 0.98),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Acessar Sistema',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: Colors.white,
                      letterSpacing: -0.35,
                      height: 1.1,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final deepAccent = Color.lerp(accentColor, const Color(0xFF0F172A), 0.35)!;
    final donateRadius = ThemeCleanPremium.radiusLg;
    final hiAccent = Color.lerp(accentColor, Colors.white, 0.18)!;
    final Widget? doacaoBtn = onDoacao == null
        ? null
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDoacao,
              borderRadius: BorderRadius.circular(donateRadius),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(hiAccent, Colors.white, 0.08)!,
                      hiAccent,
                      deepAccent,
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(donateRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.38),
                      blurRadius: 26,
                      offset: const Offset(0, 11),
                      spreadRadius: -3,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.volunteer_activism_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 9),
                      Text(
                        layoutCompact ? 'Doar' : 'Doação PIX/Cartão',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          letterSpacing: -0.35,
                          height: 1.1,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

    return SliverAppBar(
      pinned: true,
      stretch: true,
      toolbarHeight: toolbarClamped,
      // Opaco: evita o corpo do scroll “vazar” por trás da AppBar na web.
      backgroundColor: navBar,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      leadingWidth: 0,
      titleSpacing: 0,
      centerTitle: false,
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              navBar,
              gradientMid,
              gradientEnd,
            ],
            stops: const [0.0, 0.48, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
      title: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 6, layoutCompact ? 12 : 6, 8),
          child: layoutCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ChurchPublicSiteLogoBadge(
                          tenantId: tenantId,
                          churchData: churchData,
                          size: logoSize,
                          borderRadius: logoRadius,
                          loadingPlaceholder: logoLoading,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: infoColumn),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (doacaoBtn != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          doacaoBtn,
                          const SizedBox(width: 8),
                          acessarBtn,
                        ],
                      )
                    else
                      Center(child: acessarBtn),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ChurchPublicSiteLogoBadge(
                      tenantId: tenantId,
                      churchData: churchData,
                      size: logoSize,
                      borderRadius: logoRadius,
                      loadingPlaceholder: logoLoading,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: infoColumn),
                    if (doacaoBtn != null) ...[
                      doacaoBtn,
                      const SizedBox(width: 8),
                    ],
                    acessarBtn,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Faixa de boas-vindas com cor da igreja — dados reais do Firestore (nome).
class ChurchPublicWelcomeStrip extends StatelessWidget {
  final String churchName;
  final Color accentColor;

  const ChurchPublicWelcomeStrip({
    super.key,
    required this.churchName,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final name = churchName.trim();
    final deep = Color.lerp(accentColor, const Color(0xFF0F172A), 0.38)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 16),
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor,
                  deep,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seja bem-vindo(a)',
                  style: TextStyle(
                    fontSize: MediaQuery.sizeOf(context).width < 400 ? 22 : 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.12,
                    letterSpacing: -0.6,
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.94),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Portal da família — mural, cultos e novidades',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rede social no cartão “Contato” — **Material Icons** + gradiente (FA Brands falha na web).
class _ChurchPublicSocialLinkChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onPressed;

  const _ChurchPublicSocialLinkChip({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withValues(alpha: 0.36),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                  spreadRadius: -1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.42),
                width: 1.1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 19),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: -0.32,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de contato e localização — logo após [ChurchPublicWelcomeStrip].
class ChurchPublicContactBar extends StatelessWidget {
  final Color accentColor;
  final String? phoneLine;
  final String addressLine;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onMaps;
  final VoidCallback? onEmail;
  final VoidCallback? onInstagram;
  final VoidCallback? onYoutube;
  final VoidCallback? onFacebook;

  const ChurchPublicContactBar({
    super.key,
    required this.accentColor,
    this.phoneLine,
    this.addressLine = '',
    this.onWhatsApp,
    this.onMaps,
    this.onEmail,
    this.onInstagram,
    this.onYoutube,
    this.onFacebook,
  });

  @override
  Widget build(BuildContext context) {
    final phone = phoneLine?.trim() ?? '';
    final addr = addressLine.trim();
    if (phone.isEmpty &&
        addr.isEmpty &&
        onWhatsApp == null &&
        onMaps == null &&
        onEmail == null &&
        onInstagram == null &&
        onYoutube == null &&
        onFacebook == null) {
      return const SizedBox.shrink();
    }

    final deep = Color.lerp(accentColor, const Color(0xFF0F172A), 0.35)!;
    final subtle = Color.lerp(accentColor, Colors.white, 0.88)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            subtle,
            const Color(0xFFF8FAFC),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          ...ThemeCleanPremium.softUiCardShadow,
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accentColor, deep],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final chipR = ThemeCleanPremium.radiusLg;
                  final chips = <Widget>[
                    if (onWhatsApp != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onWhatsApp,
                          borderRadius: BorderRadius.circular(chipR),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(chipR),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFECFDF5),
                                  Color(0xFFD1FAE5),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFF6EE7B7)
                                    .withValues(alpha: 0.65),
                                width: 1.15,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF047857)
                                      .withValues(alpha: 0.12),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                                ...ThemeCleanPremium.softUiCardShadow,
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.chat_rounded,
                                    size: 19,
                                    color: Color(0xFF047857),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'WhatsApp',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      letterSpacing: -0.3,
                                      color: const Color(0xFF047857),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (onMaps != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onMaps,
                          borderRadius: BorderRadius.circular(chipR),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(chipR),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Color.lerp(accentColor, Colors.white, 0.92)!,
                                ],
                              ),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.28),
                                width: 1.15,
                              ),
                              boxShadow: ThemeCleanPremium.softUiCardShadow,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.map_outlined,
                                    size: 19,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Localização',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      letterSpacing: -0.3,
                                      color: deep,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (onEmail != null)
                      TextButton.icon(
                        onPressed: onEmail,
                        icon: Icon(Icons.email_outlined,
                            size: 18, color: accentColor),
                        label: const Text('E-mail'),
                        style: TextButton.styleFrom(
                          foregroundColor: deep,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                      ),
                    if (onInstagram != null)
                      _ChurchPublicSocialLinkChip(
                        label: 'Instagram',
                        icon: Icons.photo_camera_rounded,
                        gradient: ChurchPublicSocialPresets.instagramG,
                        onPressed: onInstagram!,
                      ),
                    if (onYoutube != null)
                      _ChurchPublicSocialLinkChip(
                        label: 'YouTube',
                        icon: Icons.play_circle_rounded,
                        gradient: ChurchPublicSocialPresets.youtubeG,
                        onPressed: onYoutube!,
                      ),
                    if (onFacebook != null)
                      _ChurchPublicSocialLinkChip(
                        label: 'Facebook',
                        icon: Icons.facebook_rounded,
                        gradient: ChurchPublicSocialPresets.facebookG,
                        onPressed: onFacebook!,
                      ),
                  ];

                  final infoCol = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.place_rounded,
                              size: 20, color: accentColor),
                          const SizedBox(width: 8),
                          Text(
                            'Contato e localização',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: deep,
                            ),
                          ),
                        ],
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(Icons.phone_in_talk_rounded,
                                  size: 18, color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (addr.isNotEmpty) ...[
                        SizedBox(height: phone.isNotEmpty ? 8 : 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(Icons.location_on_outlined,
                                  size: 18, color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                addr,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        infoCol,
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: chips,
                          ),
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: infoCol),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: chips,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa de ações: CTA duplo (visitante vs membro) + canais secundários (WhatsApp, mapa, PWA).
class ChurchPublicSiteHero extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onMemberSignup;
  /// Entrada explícita para quem já é membro (login / app), em paralelo ao cadastro público.
  final VoidCallback onMemberLogin;
  final VoidCallback? onTalkChurch;
  final VoidCallback? onOpenMaps;

  const ChurchPublicSiteHero({
    super.key,
    required this.accentColor,
    required this.onMemberSignup,
    required this.onMemberLogin,
    this.onTalkChurch,
    this.onOpenMaps,
  });

  @override
  Widget build(BuildContext context) {
    const minTouch = Size(
      ThemeCleanPremium.minTouchTarget,
      ThemeCleanPremium.minTouchTarget,
    );
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 420;
            final ctaVisitante = Semantics(
              button: true,
              label: 'Sou visitante. Abrir cadastro de novo membro na igreja.',
              child: SizedBox(
                width: narrow ? double.infinity : null,
                child: FilledButton.icon(
                  onPressed: onMemberSignup,
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  label: const Text('Sou visitante — Cadastro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    minimumSize: minTouch,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            );
            final ctaMembro = Semantics(
              button: true,
              label: 'Já sou membro. Entrar no sistema ou aplicativo da igreja.',
              child: SizedBox(
                width: narrow ? double.infinity : null,
                child: FilledButton.tonalIcon(
                  onPressed: onMemberLogin,
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: const Text('Já sou membro — Entrar'),
                  style: FilledButton.styleFrom(
                    foregroundColor: onSurface,
                    backgroundColor: const Color(0xFFE8EEF5),
                    minimumSize: minTouch,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: accentColor.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Comece por aqui',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ctaVisitante,
                      const SizedBox(height: 10),
                      ctaMembro,
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: ctaVisitante),
                      const SizedBox(width: 10),
                      Expanded(child: ctaMembro),
                    ],
                  ),
                if (onTalkChurch != null || onOpenMaps != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
                    child: Divider(height: 1, color: Colors.grey.shade200),
                  ),
                  Text(
                    'Outras opções',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (onTalkChurch != null)
                        Semantics(
                          button: true,
                          label: 'Abrir conversa no WhatsApp com a igreja.',
                          child: FilledButton.icon(
                            onPressed: onTalkChurch,
                            icon: const Icon(Icons.chat_rounded, size: 20),
                            label: const Text('Falar com a Igreja'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              minimumSize: minTouch,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      if (onOpenMaps != null)
                        Semantics(
                          button: true,
                          label: 'Abrir localização da igreja no mapa.',
                          child: OutlinedButton.icon(
                            onPressed: onOpenMaps,
                            icon: const Icon(Icons.location_on_rounded, size: 20),
                            label: const Text('Ver localização'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              minimumSize: minTouch,
                              side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      Semantics(
                        label: 'Instalar o site como aplicativo no celular ou computador.',
                        child: const InstallPwaButton(),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Semantics(
                        label: 'Instalar o site como aplicativo no celular ou computador.',
                        child: const InstallPwaButton(),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fundo do site público — gradiente suave alinhado ao Clean Premium (superfície + leve tom de marca).
class ChurchPublicSiteScaffoldBackground extends StatelessWidget {
  final Widget child;

  const ChurchPublicSiteScaffoldBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(ThemeCleanPremium.surfaceVariant, p, 0.04)!,
            const Color(0xFFF4F7FD),
            Color.lerp(ThemeCleanPremium.cardBackground, const Color(0xFFEEF2FF), 0.35)!,
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
      ),
      child: child,
    );
  }
}
