import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' show GlobalKey, NavigatorState, ScaffoldMessenger, SnackBar, TargetPlatform, Text;
import 'package:window_manager/window_manager.dart';

/// Desktop: ao clicar no X da janela, volta para a tela anterior em vez de fechar o app.
Future<void> initWindowCloseHandler(GlobalKey<NavigatorState> navigatorKey) async {
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_WindowCloseListener(navigatorKey));
  } catch (_) {}
}

class _WindowCloseListener extends WindowListener {
  final GlobalKey<NavigatorState> navigatorKey;

  _WindowCloseListener(this.navigatorKey);

  @override
  void onWindowClose() async {
    final nav = navigatorKey.currentState;
    if (nav == null) {
      await windowManager.destroy();
      return;
    }
    if (nav.canPop()) {
      nav.maybePop();
    } else {
      // Não enviar ao site público: permanece no painel; saída só pelo Logout.
      final ctx = nav.context;
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('Use o botão Sair no menu para encerrar a sessão.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
