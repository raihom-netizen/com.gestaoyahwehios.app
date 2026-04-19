import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/carteirinha_pdf_signature_enhance.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        refreshFirebaseStorageDownloadUrl,
        sanitizeImageUrl;

/// Dimensões no estilo CR80 (cartão físico), em lógica de layout.
abstract final class DigitalWalletCardLayout {
  static const double cornerRadius = 16;
  static const double aspect = 85.6 / 53.98;

  static double cardHeight(double width) => width / aspect;
}

String _normFiliacaoNome(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Filiação para o verso da carteirinha (mesma lógica usada no cadastro de membros).
/// Evita repetir o nome da mãe quando o campo do pai está vazio/errado ou duplicado.
String walletFiliacaoFromMember(Map<String, dynamic> member) {
  final pai =
      (member['FILIACAO_PAI'] ?? member['filiacaoPai'] ?? '').toString().trim();
  final mae =
      (member['FILIACAO_MAE'] ?? member['filiacaoMae'] ?? '').toString().trim();
  final leg = (member['FILIACAO'] ?? member['filiacao'] ?? '').toString().trim();

  final np = _normFiliacaoNome(pai);
  final nm = _normFiliacaoNome(mae);

  if (np.isNotEmpty && nm.isNotEmpty && np == nm) {
    return 'Mãe: $mae';
  }
  if (pai.isNotEmpty && mae.isNotEmpty) {
    return 'Pai: $pai / Mãe: $mae';
  }
  if (pai.isNotEmpty) return 'Pai: $pai';
  if (mae.isNotEmpty) return 'Mãe: $mae';
  return leg;
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

/// Faixa superior em gradiente (identidade visual mais atual).
class _WalletTopAccent extends StatelessWidget {
  final Color accentGold;

  const _WalletTopAccent({required this.accentGold});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accentGold.withValues(alpha: 0.95),
              accentGold.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.5),
            ],
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

/// Frente: logo, foto circular, nome, cargo, admissão (inclui estado civil), validade.
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
  /// Data de validade da credencial (mesmo texto que o PDF).
  final String validade;

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
    required this.validade,
  });

  @override
  Widget build(BuildContext context) {
    final h = DigitalWalletCardLayout.cardHeight(width);
    // Quadrado branco mais compacto; a logo preenche o interior (FittedBox abaixo).
    final logoBox = math
        .min(width * 0.27, math.min(h * 0.31, 100.0))
        .clamp(56.0, 100.0);
    final logoPad = 3.0;
    final logoInner = (logoBox - logoPad * 2).clamp(40.0, 200.0);
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
        border: Border.all(
          color: accentGold.withValues(alpha: 0.88),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _WalletTopAccent(accentGold: accentGold),
            Positioned(
              right: -8,
              top: -8,
              child: Icon(
                Icons.credit_card_rounded,
                size: 120,
                color: Colors.white.withValues(alpha: 0.06),
              ),
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
                      Container(
                        width: logoBox,
                        height: logoBox,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(logoPad),
                        child: SizedBox(
                          width: logoInner,
                          height: logoInner,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            child: logoSlot,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              churchTitle.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: textColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
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
                                    : admission.trim(),
                                style: GoogleFonts.poppins(
                                  color: textColor.withValues(alpha: 0.88),
                                  fontSize: 9,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'VALIDADE',
                                    style: GoogleFonts.poppins(
                                      fontSize: 6.5,
                                      fontWeight: FontWeight.w700,
                                      color: textColor.withValues(alpha: 0.72),
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      () {
                                        final v = validade.trim();
                                        if (v.isEmpty || v == '—') {
                                          return '—';
                                        }
                                        return v;
                                      }(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        color: textColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        height: 1.05,
                                      ),
                                    ),
                                  ),
                                ],
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
            height: 52,
            width: 140,
            child: _WalletSigImage(url: u),
          ),
        if (signatoryName.trim().isNotEmpty)
          Text(
            signatoryName.trim(),
            style: GoogleFonts.poppins(
              fontSize: 9.8,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.15,
            ),
          ),
        if (signatoryCargo.trim().isNotEmpty)
          Text(
            signatoryCargo.trim(),
            style: GoogleFonts.poppins(
              fontSize: 8.2,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.15,
            ),
          ),
      ],
    );
  }
}

/// Mesmo pipeline do PDF: traços realçados + fundo branco → transparente (assinatura «flutuando»).
class _WalletSigImage extends StatefulWidget {
  final String url;

  const _WalletSigImage({required this.url});

  @override
  State<_WalletSigImage> createState() => _WalletSigImageState();
}

class _WalletSigImageState extends State<_WalletSigImage> {
  static const double _sigW = 140;
  static const double _sigH = 52;

  Uint8List? _pngBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _WalletSigImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _pngBytes = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    var u = sanitizeImageUrl(widget.url);
    if (u.isEmpty || !isValidImageUrl(u)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (isFirebaseStorageHttpUrl(u)) {
      final fresh = await refreshFirebaseStorageDownloadUrl(u);
      u = sanitizeImageUrl(fresh ?? u);
    }
    if (!isValidImageUrl(u)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final raw = await ImageHelper.getBytesFromUrlOrNull(
      u,
      timeout: const Duration(seconds: 18),
    );
    if (!mounted) return;
    if (raw == null || raw.length < 33) {
      setState(() => _loading = false);
      return;
    }
    Uint8List? out;
    try {
      out = kIsWeb
          ? carteirinhaPdfSignaturePipelineSync(raw)
          : await compute(carteirinhaPdfSignaturePipelineForCompute, raw);
    } catch (_) {
      out = null;
    }
    if (!mounted) return;
    setState(() {
      _pngBytes = (out != null && out.length > 32) ? out : raw;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: _sigW,
        height: _sigH,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
            ),
          ),
        ),
      );
    }
    final b = _pngBytes;
    if (b == null || b.isEmpty) return const SizedBox.shrink();
    return Image.memory(
      b,
      width: _sigW,
      height: _sigH,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
    );
  }
}

/// Verso: CPF/nascimento, batismo, filiação, estado civil, telefone e assinatura (sem e-mail).
/// Validade na frente; estado civil também no verso (entre filiação e telefone).
class MemberDigitalWalletBack extends StatelessWidget {
  final double width;
  final Color colorA;
  final Color colorB;
  final Color textColor;
  final Color accentGold;
  final String churchTitle;
  final String cpfOrDoc;
  final String nascimento;
  final String dataBatismo;
  final String filiacaoPaiMae;
  /// Campo `ESTADO_CIVIL` / `estadoCivil` do membro.
  final String estadoCivil;
  final String telefone;
  final String? signatureImageUrl;
  final String signatoryName;
  final String signatoryCargo;
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
    required this.nascimento,
    required this.dataBatismo,
    required this.filiacaoPaiMae,
    this.estadoCivil = '',
    required this.telefone,
    required this.signatureImageUrl,
    required this.signatoryName,
    required this.signatoryCargo,
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
        border: Border.all(
          color: accentGold.withValues(alpha: 0.88),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DigitalWalletCardLayout.cornerRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _WalletTopAccent(accentGold: accentGold),
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
                  const SizedBox(height: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cpfNascimentoLine(cpfOrDoc, nascimento, textColor),
                        _miniField('Batismo', dataBatismo, textColor),
                        _miniField(
                            'Filiação (Pai e Mãe)', filiacaoPaiMae, textColor),
                        _miniField('Estado civil', estadoCivil, textColor),
                        _miniField('Telefone', telefone, textColor),
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

  /// CPF e nascimento na mesma linha — liberta espaço vertical para assinatura do pastor.
  static Widget _cpfNascimentoLine(
      String cpf, String nasc, Color textColor) {
    final c = cpf.trim().isEmpty ? '—' : cpf.trim();
    final n = nasc.trim().isEmpty ? '—' : nasc.trim();
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
            const TextSpan(
              text: 'CPF: ',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: c,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.12,
              ),
            ),
            TextSpan(
              text: '    ',
              style: TextStyle(color: textColor.withValues(alpha: 0.5)),
            ),
            const TextSpan(
              text: 'Nascimento: ',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: n,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.12,
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
                color: textColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
