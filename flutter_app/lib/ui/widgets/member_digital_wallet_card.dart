import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        refreshFirebaseStorageDownloadUrl,
        SafeNetworkImage,
        sanitizeImageUrl;

/// Dimensões no estilo CR80 (cartão físico), em lógica de layout.
abstract final class DigitalWalletCardLayout {
  static const double cornerRadius = 16;
  static const double aspect = 85.6 / 53.98;

  static double cardHeight(double width) => width / aspect;
}

String walletRgFromMember(Map<String, dynamic> member) {
  const keys = ['RG', 'rg', 'DOCUMENTO_RG', 'documentoRg', 'identidade', 'RG_NUMERO'];
  for (final k in keys) {
    final s = (member[k] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

String walletBloodFromMember(Map<String, dynamic> member) {
  const keys = [
    'TIPO_SANGUE',
    'tipoSangue',
    'tipo_sangue',
    'TIPO_SANGUINEO',
    'tipoSanguineo',
    'sangue',
    'bloodType',
  ];
  for (final k in keys) {
    final s = (member[k] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// Selo metálico / holográfico (gradiente) contra falsificações simples.
/// Marca d’água discreta (anti-cópia simples) — logo + texto.
class _SubtleCredentialWatermark extends StatelessWidget {
  const _SubtleCredentialWatermark();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Opacity(
                  opacity: 0.04,
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Image.asset(
                      'assets/LOGO_GESTAO_YAHWEH.png',
                      width: 130,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: 0.055,
                  child: Transform.rotate(
                    angle: -0.48,
                    child: Text(
                      'GESTÃO YAHWEH',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletAuthenticitySeal extends StatelessWidget {
  final double size;

  const WalletAuthenticitySeal({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.18,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFC9A227),
              Color(0xFFE8D5A3),
              Color(0xFF7DD3FC),
              Color(0xFFC084FC),
              Color(0xFFFDE68A),
            ],
            stops: [0.0, 0.25, 0.5, 0.72, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC9A227).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'AUTÊNTICO',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: size * 0.16,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.95),
                height: 1.05,
                shadows: const [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
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

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({required this.child, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frente: logo, foto circular, nome, cargo, admissão.
class MemberDigitalWalletFront extends StatelessWidget {
  final double width;
  final Color colorA;
  final Color colorB;
  final Color textColor;
  final Color accentGold;
  final String churchTitle;
  final String churchSubtitle;
  final Widget logoSlot;
  final Widget photoSlot;
  final bool showPhoto;
  final String memberName;
  final String cargo;
  final String admission;

  const MemberDigitalWalletFront({
    super.key,
    required this.width,
    required this.colorA,
    required this.colorB,
    required this.textColor,
    required this.accentGold,
    required this.churchTitle,
    required this.churchSubtitle,
    required this.logoSlot,
    required this.photoSlot,
    required this.showPhoto,
    required this.memberName,
    required this.cargo,
    required this.admission,
  });

  @override
  Widget build(BuildContext context) {
    final h = DigitalWalletCardLayout.cardHeight(width);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorA, colorB],
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -8,
              top: -8,
              child: Icon(
                Icons.credit_card_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: WalletAuthenticitySeal(size: width * 0.14),
            ),
            const _SubtleCredentialWatermark(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 44, height: 44, child: logoSlot),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              churchTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: textColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              churchSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: textColor.withValues(alpha: 0.82),
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _GlassPanel(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (showPhoto) ...[
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                              border: Border.all(
                                color: accentGold.withValues(alpha: 0.65),
                                width: 2,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: photoSlot,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (cargo.trim().isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentGold.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    cargo.toUpperCase(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              if (cargo.trim().isNotEmpty) const SizedBox(height: 6),
                              Text(
                                memberName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                admission.trim().isEmpty
                                    ? 'Admissão: —'
                                    : 'Admissão: ${admission.trim()}',
                                style: GoogleFonts.poppins(
                                  color: textColor.withValues(alpha: 0.88),
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletSignatureStrip extends StatelessWidget {
  final String? imageUrl;
  final String signatoryName;
  final String signatoryCargo;
  final Color lineColor;
  final Color textColor;

  const WalletSignatureStrip({
    super.key,
    required this.imageUrl,
    required this.signatoryName,
    required this.signatoryCargo,
    required this.lineColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final u = (imageUrl ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 140, height: 1, color: lineColor.withValues(alpha: 0.45)),
        if (u.isNotEmpty)
          SizedBox(
            height: 36,
            width: 120,
            child: _WalletSigImage(url: u),
          ),
        if (signatoryName.trim().isNotEmpty)
          Text(
            signatoryName.trim(),
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        if (signatoryCargo.trim().isNotEmpty)
          Text(
            signatoryCargo.trim(),
            style: GoogleFonts.poppins(
              fontSize: 7.5,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
      ],
    );
  }
}

class _WalletSigImage extends StatelessWidget {
  final String url;

  const _WalletSigImage({required this.url});

  Future<String> _resolve() async {
    var u = sanitizeImageUrl(url);
    if (u.isEmpty || !isValidImageUrl(u)) return '';
    if (isFirebaseStorageHttpUrl(u)) {
      final fresh = await refreshFirebaseStorageDownloadUrl(u);
      u = sanitizeImageUrl(fresh ?? u);
    }
    return isValidImageUrl(u) ? u : '';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolve(),
      builder: (context, snap) {
        final u = snap.data ?? '';
        if (u.isEmpty) return const SizedBox.shrink();
        if (isFirebaseStorageHttpUrl(u)) {
          return FreshFirebaseStorageImage(
            imageUrl: u,
            fit: BoxFit.contain,
            width: 120,
            height: 36,
            errorWidget: const SizedBox.shrink(),
          );
        }
        return SafeNetworkImage(
          imageUrl: u,
          fit: BoxFit.contain,
          width: 120,
          height: 36,
          errorWidget: const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Verso: dados secundários, validade em destaque, QR, assinatura.
class MemberDigitalWalletBack extends StatelessWidget {
  final double width;
  final Color colorA;
  final Color colorB;
  final Color textColor;
  final Color accentGold;
  final String churchTitle;
  final String cpfOrDoc;
  final String rg;
  final String nascimento;
  final String sangue;
  final String validade;
  final String validationUrl;
  final String? signatureImageUrl;
  final String signatoryName;
  final String signatoryCargo;
  final String congregacao;
  final String fraseRodape;

  const MemberDigitalWalletBack({
    super.key,
    required this.width,
    required this.colorA,
    required this.colorB,
    required this.textColor,
    required this.accentGold,
    required this.churchTitle,
    required this.cpfOrDoc,
    required this.rg,
    required this.nascimento,
    required this.sangue,
    required this.validade,
    required this.validationUrl,
    required this.signatureImageUrl,
    required this.signatoryName,
    required this.signatoryCargo,
    this.congregacao = '',
    this.fraseRodape = '',
  });

  @override
  Widget build(BuildContext context) {
    final h = DigitalWalletCardLayout.cardHeight(width);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [colorB, colorA],
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 8,
              bottom: 8,
              child: WalletAuthenticitySeal(size: width * 0.12),
            ),
            const _SubtleCredentialWatermark(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    churchTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: textColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _GlassPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.event_available_rounded,
                            size: 18, color: accentGold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VALIDADE',
                                style: GoogleFonts.poppins(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withValues(alpha: 0.75),
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                validade.trim().isEmpty ? '—' : validade.trim(),
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _miniField('CPF / Doc.', cpfOrDoc, textColor),
                              _miniField('RG', rg, textColor),
                              _miniField('Nascimento', nascimento, textColor),
                              _miniField('Tipagem', sangue, textColor),
                              _miniField('Congregação', congregacao, textColor),
                              const Spacer(),
                              WalletSignatureStrip(
                                imageUrl: signatureImageUrl,
                                signatoryName: signatoryName,
                                signatoryCargo: signatoryCargo,
                                lineColor: textColor,
                                textColor: textColor,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: validationUrl,
                                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                                  size: width * 0.22,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF0F172A),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Validar credencial',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w600,
                                  color: textColor.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (fraseRodape.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      fraseRodape.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 7,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        color: textColor.withValues(alpha: 0.78),
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _miniField(String label, String value, Color textColor) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: GoogleFonts.poppins(
            fontSize: 8,
            color: textColor.withValues(alpha: 0.78),
            height: 1.2,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: v,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.95),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
