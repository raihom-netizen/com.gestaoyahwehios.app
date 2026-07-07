import 'dart:async' show unawaited;



import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatUploadErrorForUser, isFirebaseNoAppError;
import 'package:gestao_yahweh/core/public_site_media_auth.dart';

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

  divulgacao,

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

      case YahwehMediaModule.divulgacao:

        return 'divulgação';

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



  /// Visitante público — carregar/exibir mídia (Storage/Firestore leitura) sem login.

  static Future<bool> ensureReadyForPublicMedia({

    BuildContext? context,

    YahwehMediaModule? module,

  }) async {

    try {

      await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess();

      await EcoFireDirectFirebase.ensureDefaultApp();

      await EcoFireDirectFirebase.ensureStorageLinked();

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



  /// Antes de abrir câmera/galeria/ficheiro (todos os módulos).

  static Future<bool> ensureReadyForPick({

    BuildContext? context,

    YahwehMediaModule? module,

    bool requireAuth = true,

  }) async {

    try {

      if (requireAuth) {

        await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: true);

      } else {

        await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess();

        await EcoFireDirectFirebase.ensureDefaultApp();

      }

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

    bool requireAuth = true,

  }) async {

    try {

      if (!requireAuth) {

        await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess();

      }

      await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: requireAuth);

      if (kIsWeb) {

        if (requireAuth) {

          await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);

        }

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



  /// Garante Firebase/Storage antes do `put` (evita core/no-app no meio do upload).

  static Future<void> assertReadyForUploadAction({

    bool requireAuth = true,

    bool withPhotos = true,

  }) async {

    await DirectStorageUrlPublish.ensureReady(requireAuth: requireAuth);

    if (requireAuth) {

      await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);

    } else if (kIsWeb) {

      await FirestoreWebGuard.ensureFirestoreClientAlive().catchError((_) {});

    }

  }

  static Future<bool> prepareForPublishUpload({

    BuildContext? context,

    YahwehMediaModule? module,

    String logLabel = 'media_publish',

    bool withPhotos = true,

    bool requireAuth = true,

  }) async {

    Object? last;

    for (var attempt = 0; attempt < 5; attempt++) {

      try {

        if (attempt > 0) {

          await recoverNoAppAfterPublishError(

            last ?? StateError('core/no-app'),

            requireAuth: requireAuth,

          );

          await Future<void>.delayed(Duration(milliseconds: 240 * (attempt + 1)));

        }

        await ensureFirebaseReadyForPublishUpload();

        await DirectStorageUrlPublish.ensureReady(
          requireAuth: requireAuth,
        );

        return true;

      } catch (e) {

        last = e;

        if (
          attempt < 4 &&
          (isFirebaseNoAppError(e) || FirestoreWebGuard.isClientTerminated(e))
        ) {

          continue;

        }

        break;

      }

    }

    if (context != null && context.mounted) {

      final msg = last != null

          ? formatUploadErrorForUser(last)

          : blockedPublishMessage(module, last);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(msg),

          backgroundColor: ThemeCleanPremium.error,

          behavior: SnackBarBehavior.floating,

          action: SnackBarAction(

            label: 'Tentar novamente',

            textColor: Colors.white,

            onPressed: () {

              unawaited(

                prepareForPublishUpload(

                  context: context,

                  module: module,

                  logLabel: logLabel,

                  withPhotos: withPhotos,

                  requireAuth: requireAuth,

                ),

              );

            },

          ),

        ),

      );

    }

    return false;

  }



  /// Após falha de publish/upload — relink Firebase/Storage (core/no-app, web terminated).

  static Future<void> recoverNoAppAfterPublishError(

    Object e, {

    bool requireAuth = true,

  }) async {

    if (FirestoreWebGuard.isClientTerminated(e)) {

      await recoverAfterTerminatedIfWeb();

    }

    if (!isFirebaseNoAppError(e)) return;

    try {
      await FirebaseBootstrapService.ensureAlwaysOn(
        refreshAuthToken: requireAuth,
      );
      await ensureFirebaseReadyForPublishUpload();
      await EcoFireDirectFirebase.ensureDefaultApp();
      await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: requireAuth);
      if (kIsWeb && requireAuth) {
        await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
      }
    } catch (_) {}

  }

}

