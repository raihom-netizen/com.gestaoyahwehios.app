import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:gestao_yahweh/ui/widgets/member_card_cnh_data.dart';

/// Padrão único Gestão YAHWEH — carteira membro digital premium.
/// Somente [data.churchTitle], [data.churchSubtitle] e [logoSlot] variam por igreja.
class MemberCardCnhDigital extends StatelessWidget {
  const MemberCardCnhDigital({
    super.key,
    required this.data,
    required this.logoSlot,
    required this.photoSlot,
    this.showPhoto = true,
    this.maxWidth = 400,
  });

  final MemberCardCnhViewData data;
  final Widget logoSlot;
  final Widget photoSlot;
  final bool showPhoto;
  final double maxWidth;

  static const Color _headerNavy = Color(0xFF0D2C54);
  static const Color _borderGreen = Color(0xFF2E7D32);
  static const Color _labelColor = Color(0xFF4A5D48);
  static const Color _valueColor = Color(0xFF142414);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderGreen, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                const Positioned.fill(child: _CnhSecurityBackground()),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: 0.07,
                        child: Transform.rotate(
                          angle: -0.22,
                          child: SizedBox(
                            width: maxWidth * 0.72,
                            height: maxWidth * 0.72,
                            child: logoSlot,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 52,
                  right: -8,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(120, 56),
                      painter: _BrRibbonPainter(),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 12,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A2342), _headerNavy],
                        ),
                      ),
                      child: Text(
                        'MEMBRO PADRÃO — GESTÃO YAHWEH',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.45,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showPhoto)
                            Container(
                              width: 90,
                              height: 114,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.grey.shade600,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                clipBehavior: Clip.hardEdge,
                                child: SizedBox(
                                  width: 90,
                                  height: 114,
                                  child: photoSlot,
                                ),
                              ),
                            ),
                          if (showPhoto) const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 136,
                                  height: 136,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _borderGreen.withValues(
                                        alpha: 0.72,
                                      ),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _borderGreen.withValues(
                                          alpha: 0.22,
                                        ),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.12),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: logoSlot,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  data.churchTitle.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    color: _headerNavy,
                                    height: 1.15,
                                  ),
                                ),
                                if (data.churchSubtitle.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    data.churchSubtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 8.5,
                                      color: _labelColor,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                _field('CÓD. MEMBRO', data.codigoMembro),
                                const SizedBox(height: 5),
                                _field('IGREJA SEDE', data.igrejaSede),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.black.withValues(alpha: 0.1),
                      indent: 12,
                      endIndent: 12,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field('NOME', data.nome, valueSize: 15, bold: true),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _field('CPF', data.cpf)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  'DATA NASC.',
                                  data.dataNascimento,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _field('FILIAÇÃO', data.filiacao, maxLines: 2),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _field(
                                  'DATA ADMISSÃO',
                                  data.dataAdmissao,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _field(
                                  'VÁLIDO ATÉ',
                                  data.validade,
                                  valueColor: data.validade == 'Permanente'
                                      ? const Color(0xFF0F5132)
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _field('CATEGORIA', data.categoria),
                        ],
                      ),
                    ),
                    if (data.assinada)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F5132).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF0F5132).withValues(alpha: 0.28),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: Color(0xFF0F5132),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'ASSINATURA DIGITAL',
                                        style: GoogleFonts.poppins(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: _labelColor,
                                          letterSpacing: 0.35,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        data.assinanteNomeCargo.isNotEmpty
                                            ? data.assinanteNomeCargo
                                            : 'Credencial assinada',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F5132),
                                          height: 1.2,
                                        ),
                                      ),
                                      if (data.assinadaEmTexto.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          data.assinadaEmTexto,
                                          style: GoogleFonts.poppins(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: _labelColor,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: logoSlot,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'YHAWEH',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: _headerNavy,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        'GESTÃO',
                                        style: GoogleFonts.poppins(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: _labelColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: QrImageView(
                              data: data.qrPayload,
                              version: QrVersions.auto,
                              size: 96,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: _valueColor,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: _valueColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      color: _headerNavy.withValues(alpha: 0.06),
                      child: Text(
                        'VALIDAÇÃO VIA GESTÃO YAHWEH',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: _labelColor,
                          letterSpacing: 0.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String value, {
    double valueSize = 12.5,
    bool bold = false,
    Color? valueColor,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: _labelColor,
            letterSpacing: 0.25,
          ),
        ),
        Text(
          value.isEmpty ? '—' : value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: valueSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? _valueColor,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CnhSecurityBackground extends StatelessWidget {
  const _CnhSecurityBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFE8F5E9),
            const Color(0xFFF1F8E9),
            const Color(0xFFFFFDE7),
            const Color(0xFFE2F0D9),
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: CustomPaint(painter: _GuillochePainter()),
    );
  }
}

class _GuillochePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2E7D32).withValues(alpha: 0.04)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (var i = -2; i < 24; i++) {
      final y = i * 18.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + size.width * 0.15), paint);
    }
    for (var i = 0; i < 12; i++) {
      final cx = size.width * (0.1 + i * 0.08);
      canvas.drawCircle(Offset(cx, size.height * 0.4), 40 + i * 6.0, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrRibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.1,
        size.width,
        0,
      )
      ..lineTo(size.width, size.height * 0.35)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.55,
        0,
        size.height,
      )
      ..close();

    final green = Paint()..color = const Color(0xFF009B3A).withValues(alpha: 0.85);
    final yellow = Paint()..color = const Color(0xFFFEDD00).withValues(alpha: 0.75);

    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
      green,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.55),
      yellow,
    );
    canvas.restore();

    final diamond = Paint()..color = const Color(0xFF002776).withValues(alpha: 0.9);
    final c = Offset(size.width * 0.72, size.height * 0.22);
    final r = 5.0;
    final diamondPath = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(diamondPath, diamond);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
