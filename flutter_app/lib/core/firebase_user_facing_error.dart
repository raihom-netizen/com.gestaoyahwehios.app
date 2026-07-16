import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Mensagens para o utilizador com o **erro real** (não genérico).
String formatFirebaseErrorForUser(
  Object error, {
  StackTrace? stackTrace,
  bool logToCrashlytics = true,
}) {
  if (error is FirebaseBootstrapException) {
    if (logToCrashlytics) {
      logFirebaseDiagnostic(error.cause, error.stackTrace, context: error.code);
    }
    return error.userMessage;
  }
  if (logToCrashlytics) {
    logFirebaseDiagnostic(error, stackTrace, context: 'user_facing_error');
  }

  if (error is TimeoutException) {
    final m = error.message?.trim();
    if (m != null && m.isNotEmpty) {
      if (m.contains('Future not completed')) {
        return 'Demorou demais a carregar. Verifique a rede e toque em Tentar de novo.';
      }
      return m;
    }
    return 'Tempo esgotado. Verifique a rede e tente de novo.';
  }

  if (error is SocketException) {
    return 'Sem ligação à internet (${error.message}).';
  }

  if (error is FirebaseAuthException) {
    if (FirebaseAuthTokenGuard.isQuotaExceeded(error)) {
      return FirebaseAuthTokenGuard.quotaUserMessage;
    }
    final m = error.message?.trim();
    return 'Autenticação Firebase (${error.code})'
        '${m != null && m.isNotEmpty ? ': $m' : ''}';
  }

  if (error is FirebaseException) {
    final plugin = error.plugin.isNotEmpty ? error.plugin : 'firebase';
    final code = error.code.isNotEmpty ? error.code : 'unknown';
    final m = error.message?.trim();
    if (code == 'permission-denied' || code == 'unauthorized') {
      return plugin == 'firebase_storage'
          ? 'Sem permissão no Storage ($code). Confirme que está logado no painel e tente de novo.'
          : 'Sem permissão no Firestore ($code).';
    }
    if (plugin == 'firebase_storage' &&
        (code == 'unauthenticated' || code == 'object-not-found')) {
      return 'Erro no Storage ($code). Saia e entre de novo no painel, depois tente o envio.';
    }
    if (_isNoFirebaseAppError(error)) {
      return kFirebaseSyncRetryUserMessage;
    }
    if (plugin == 'firebase_storage') {
      return 'Não foi possível enviar a mídia ($code)'
          '${m != null && m.isNotEmpty ? ': $m' : ''}. '
          'O conteúdo pode ser guardado localmente — toque em Tentar de novo.';
    }
    return 'Firebase $plugin ($code)'
        '${m != null && m.isNotEmpty ? ': $m' : ''}';
  }

  if (error is PlatformException) {
    return 'Erro nativo (${error.code}): ${error.message ?? error.toString()}';
  }

  if (error is StateError) {
    final m = error.message.trim();
    if (m.contains('Sessão expirada')) return m;
    if (_isNoFirebaseAppError(error)) {
      return kFirebaseSyncRetryUserMessage;
    }
    return m.isNotEmpty ? m : error.toString();
  }

  final raw = error.toString();
  if (FirestoreWebGuard.isInternalAssertionError(error) ||
      FirestoreWebGuard.isClientTerminated(error) ||
      raw.contains('WatchChangeAggregator') ||
      raw.contains('PersistentListenStream')) {
    if (FirestoreWebGuard.isClientTerminated(error) ||
        raw.toLowerCase().contains('terminated')) {
      return 'Sincronização Firebase interrompida. Toque em «Tentar novamente».';
    }
    return 'Sincronização com o servidor em curso. '
        'Aguarde alguns segundos e toque em Tentar de novo.';
  }
  if (_isNoFirebaseAppError(error)) {
    return 'Firebase não disponível: $raw';
  }
  if (raw.contains('Sessão expirada')) return raw;
  if (raw.contains('Tempo esgotado')) {
    final low = raw.toLowerCase();
    final isUploadContext = low.contains('envio') ||
        low.contains('upload') ||
        low.contains('mídia') ||
        low.contains('midia') ||
        low.contains('publicar') ||
        low.contains('storage');
    if (isUploadContext) {
      return 'Tempo esgotado no envio. Use Wi‑Fi ou tente de novo.';
    }
    return 'Tempo esgotado ao carregar. Verifique a rede e toque em Tentar de novo.';
  }
  if (raw.contains('Future not completed')) {
    return 'Demorou demais a carregar. Verifique a rede e toque em Tentar de novo.';
  }
  if (raw.length > 200) {
    return 'Falha na operação. Tente de novo.';
  }
  return raw.replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
}

/// Mensagem curta — falha transitória de sync (com retry).
const String kFirebaseSyncRetryUserMessage =
    'Não foi possível publicar agora. '
    'Toque em «Tentar novamente». '
    'Se a ligação falhar, o conteúdo fica guardado localmente para envio automático.';

/// Sucesso local — fila offline aceite.
const String kFeedPublishQueuedUserMessage =
    'Não foi possível publicar agora. '
    'O seu conteúdo foi guardado localmente e será enviado automaticamente '
    'quando houver conexão.';

bool isFirebaseNoAppError(Object e) {
  final low = e.toString().toLowerCase();
  if (low.contains('bucket vazio')) return false;
  // Evitar falso positivo: "channel has not been initialized" (plugins nativos).
  if (low.contains('no firebase app') ||
      low.contains('firebase.initializeapp') ||
      low.contains('core/no-app') ||
      low.contains('no_firebase_app')) {
    return true;
  }
  return low.contains('firebase') &&
      (low.contains('has not been initialized') ||
          low.contains('não inicializou') ||
          low.contains('nao inicializou'));
}

bool _isNoFirebaseAppError(Object e) => isFirebaseNoAppError(e);

/// Alias legado (upload / mural / chat).
String formatUploadErrorForUser(Object error) =>
    formatFirebaseErrorForUser(error);
