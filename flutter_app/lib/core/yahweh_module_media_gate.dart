import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Gate único — fotos/anexos (Eventos, Avisos, Membros, Patrimônio, Financeiro).
enum YahwehMediaModule {
  eventos,
  avisos,
  membros,
  patrimonio,
  financeiro,
  chat,
  cadastro,
}

abstract final class YahwehModuleMediaGate {
  YahwehModuleMediaGate._();

  static String _label(YahwehMediaModule? module) {
    switch (module) {
      case YahwehMediaModule.eventos:
        return 'evento';
      case YahwehMediaModule.avisos:
        return 'aviso';
      case YahwehMediaModule.membros:
        return 'foto de perfil';
      case YahwehMediaModule.patrimonio:
        return 'patrimônio';
      case YahwehMediaModule.financeiro:
        return 'comprovante';
      case YahwehMediaModule.chat:
        return 'chat';
      case YahwehMediaModule.cadastro:
        return 'cadastro';
      case null:
        return 'mídia';
    }
  }

  static String blockedPickMessage(YahwehMediaModule? module, [Object? error]) {
    final label = _label(module);
    if (error != null && FirestoreWebGuard.isClientTerminated(error)) {
      return 'Sincronização Firebase interrompida. Aguarde e tente anexar $label novamente.';
    }
    return 'Não foi possível preparar anexo de $label. Verifique a sessão e tente de novo.';
  }

  static String blockedPublishMessage(YahwehMediaModule? module, [Object? error]) {
    final label = _label(module);
    if (error != null && FirestoreWebGuard.isClientTerminated(error)) {
      return 'Sincronização Firebase interrompida. Toque em «Tentar novamente» para publicar $label.';
    }
    return 'Não foi possível publicar $label. Verifique a sessão e tente de novo.';
  }

  /// Antes de abrir câmera/galeria/ficheiro (todos os módulos).
  static Future<bool> ensureReadyForPick({
    BuildContext? context,
    YahwehMediaModule? module,
  }) async {
    try {
      await ensureFirebaseReadyForMediaUpload();
      if (kIsWeb) {
        await FirestoreWebGuard.ensureFirestoreClientAlive();
      }
      return true;
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(blockedPickMessage(module, e)),
            backgroundColor: ThemeCleanPremium.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Antes de publicar/gravar com Storage + Firestore.
  static Future<bool> ensureReadyForPublish({
    BuildContext? context,
    YahwehMediaModule? module,
  }) async {
    try {
      await ensureFirebaseCore(requireAuth: true);
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForPublishWrite();
        await FirestoreWebGuard.ensureFirestoreClientAlive();
      }
      return true;
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(blockedPublishMessage(module, e)),
            backgroundColor: ThemeCleanPremium.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }

  /// Recuperação explícita após erro «client terminated» (web).
  static Future<void> recoverAfterTerminatedIfWeb() async {
    if (!kIsWeb) return;
    await FirestoreWebGuard.ensureFirestoreClientAlive();
  }
}
