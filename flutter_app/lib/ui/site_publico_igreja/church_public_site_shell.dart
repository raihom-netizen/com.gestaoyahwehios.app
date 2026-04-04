import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/install_pwa_button.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show churchTenantLogoUrl, memCacheExtentForLogicalSize;

/// Endereço em uma linha: [endereco] completo ou montagem rua/bairro/cidade (cadastro da igreja).
String churchPublicFormattedAddress(Map<String, dynamic> data) {
  final enderecoRaw = (data['endereco'] ?? '').toString().trim();
  if (enderecoRaw.isNotEmpty) return enderecoRaw;
  final rua = (data['rua'] ?? '').toString().trim();
  final bairro = (data['bairro'] ?? '').toString().trim();
  final cidade = (data['cidade'] ?? '').toString().trim();
  final estado = (data['estado'] ?? '').toString().trim();
  final cep = (data['cep'] ?? '').toString().trim();
  final parts = <String>[];
  if (rua.isNotEmpty) parts.add(rua);
  if (bairro.isNotEmpty) parts.add(bairro);
  if (cidade.isNotEmpty && estado.isNotEmpty) {
    parts.add('$cidade - $estado');
  } else if (cidade.isNotEmpty) {
    parts.add(cidade);
  } else if (estado.isNotEmpty) {
    parts.add(estado);
  }
  if (cep.isNotEmpty) parts.add('CEP $cep');
  return parts.join(', ');
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

/// Logo do site público: sempre [StableChurchLogo] (Firestore + path + fallback Storage).
class ChurchPublicSiteLogoBadge extends StatelessWidget {
  final String tenantId;
  final Map<String, dynamic>? churchData;
  final double size;
  final double borderRadius;

  const ChurchPublicSiteLogoBadge({
    super.key,
    required this.tenantId,
    this.churchData,
    required this.size,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = memCacheExtentForLogicalSize(size, dpr, maxPx: 1024);
    final prefer = churchData != null ? churchTenantLogoUrl(churchData!) : '';
    final path =
        churchData != null ? ChurchImageFields.logoStoragePath(churchData) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: StableChurchLogo(
        tenantId: tenantId,
        tenantData: churchData,
        imageUrl: prefer.isNotEmpty ? prefer : null,
        storagePath: path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        memCacheWidth: cache,
        memCacheHeight: cache,
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
  final Color accentColor;

  const ChurchPublicSiteSliverAppBar({
    super.key,
    required this.nome,
    required this.tenantId,
    required this.churchData,
    required this.onAcessar,
    this.accentColor = const Color(0xFF2563EB),
  });

  static const double _logoSize = 52;

  @override
  Widget build(BuildContext context) {
    final displayName = nome.trim();
    final phoneLine = churchPublicFormattedPhone(churchData);
    final address = churchPublicFormattedAddress(churchData).trim();
    final hasPhone = phoneLine != null && phoneLine.isNotEmpty;
    final hasAddress = address.isNotEmpty;
    var toolbarH = 88.0;
    if (hasPhone) toolbarH += 22;
    if (hasAddress) toolbarH += 38;
    toolbarH = toolbarH.clamp(88.0, 152.0);

    final metaStyle = TextStyle(
      fontSize: 12.5,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade700,
    );
    final iconMeta = IconThemeData(size: 16, color: accentColor.withValues(alpha: 0.9));

    return SliverAppBar(
      pinned: true,
      stretch: true,
      toolbarHeight: toolbarH,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: const Color(0x14000000),
      automaticallyImplyLeading: false,
      leadingWidth: 0,
      titleSpacing: 0,
      centerTitle: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: const Color(0xFFE5E7EB),
        ),
      ),
      title: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ChurchPublicSiteLogoBadge(
                tenantId: tenantId,
                churchData: churchData,
                size: _logoSize,
                borderRadius: ThemeCleanPremium.radiusMd,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName.isEmpty ? 'Igreja' : displayName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: Color(0xFF111827),
                        letterSpacing: -0.2,
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
                ),
              ),
              TextButton(
                onPressed: onAcessar,
                style: TextButton.styleFrom(
                  foregroundColor: accentColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(
                    ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Acessar Sistema',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de ações compacta (referência divulgação: CTAs secundários; login fica no topo + FAB).
class ChurchPublicSiteHero extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onMemberSignup;
  final VoidCallback? onTalkChurch;
  final VoidCallback? onOpenMaps;

  const ChurchPublicSiteHero({
    super.key,
    required this.accentColor,
    required this.onMemberSignup,
    this.onTalkChurch,
    this.onOpenMaps,
  });

  @override
  Widget build(BuildContext context) {
    const minTouch = Size(
      ThemeCleanPremium.minTouchTarget,
      ThemeCleanPremium.minTouchTarget,
    );
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
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onTalkChurch != null)
              FilledButton.icon(
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
            if (onOpenMaps != null)
              OutlinedButton.icon(
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
            OutlinedButton.icon(
              onPressed: onMemberSignup,
              icon: const Icon(Icons.person_add_rounded, size: 20),
              label: const Text('Cadastro de membro'),
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
            const InstallPwaButton(),
          ],
        ),
      ),
    );
  }
}

/// Fundo azul-cinza muito claro (páginas tipo landing / divulgação).
class ChurchPublicSiteScaffoldBackground extends StatelessWidget {
  final Widget child;

  const ChurchPublicSiteScaffoldBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF0F4FA),
            Color(0xFFE8EEF5),
            Color(0xFFF5F7FA),
          ],
          stops: [0.0, 0.35, 1.0],
        ),
      ),
      child: child,
    );
  }
}
