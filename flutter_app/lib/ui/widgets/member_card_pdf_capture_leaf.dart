import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/member_card_cnh_layout.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_cnh_data.dart';
import 'package:gestao_yahweh/ui/widgets/member_card_cnh_digital.dart';

/// Árvore Flutter idêntica ao preview — usada só para rasterizar PDF/PNG em lote.
class MemberCardPdfCaptureLeaf extends StatelessWidget {
  const MemberCardPdfCaptureLeaf({
    super.key,
    required this.data,
    this.logoBytes,
    this.photoBytes,
  });

  final MemberCardCnhViewData data;
  final Uint8List? logoBytes;
  final Uint8List? photoBytes;

  static const Color _placeholderBg = Color(0xFFE8ECEF);
  static const Color _churchIcon = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(
        size: Size(
          MemberCardCnhLayout.captureLogicalWidth,
          MemberCardCnhLayout.captureLogicalHeight,
        ),
        textScaler: TextScaler.linear(1),
      ),
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: MemberCardCnhLayout.captureLogicalWidth,
          height: MemberCardCnhLayout.captureLogicalHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: MemberCardCnhLayout.captureLogicalWidth,
              child: MemberCardCnhDigital(
                data: data,
                maxWidth: MemberCardCnhLayout.captureLogicalWidth,
                logoSlot: _logoSlot(),
                photoSlot: _photoSlot(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoSlot() {
    final b = logoBytes;
    if (b != null && b.length > 33) {
      return Image.memory(b, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return ColoredBox(
      color: _placeholderBg,
      child: const Center(
        child: Icon(Icons.church_rounded, color: _churchIcon, size: 40),
      ),
    );
  }

  Widget _photoSlot() {
    final b = photoBytes;
    if (b != null && b.length > 33) {
      return Image.memory(
        b,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
      );
    }
    return ColoredBox(
      color: _placeholderBg,
      child: Center(
        child: Icon(Icons.person_rounded, color: Colors.grey.shade500, size: 44),
      ),
    );
  }
}
