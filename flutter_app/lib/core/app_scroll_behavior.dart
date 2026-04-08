import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// Painel web/desktop: permite arrastar para rolar (não só toque), alinhado ao uso com mouse e trackpad.
class GestaoYahwehScrollBehavior extends MaterialScrollBehavior {
  const GestaoYahwehScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}
