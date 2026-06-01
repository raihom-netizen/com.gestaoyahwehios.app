import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';

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
    if (m != null && m.isNotEmpty) return m;
    return 'Tempo esgotado. Verifique a rede e tente de novo.';
  }

  if (error is SocketException) {
    return 'Sem ligação à internet (${error.message}).';
  }

  if (error is FirebaseAuthException) {
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
          ? 'Sem permissão no Storage ($code). Confirme que está logado no painel.'
          : 'Sem permissão no Firestore ($code).';
    }
    if (_isNoFirebaseAppError(error)) {
      return 'Firebase não inicializou ($plugin/$code). '
          'Toque em «Tentar de novo» no ecrã ou reinicie o app.';
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
      return 'Firebase: $m';
    }
    return m.isNotEmpty ? m : error.toString();
  }

  final raw = error.toString();
  if (raw.contains('INTERNAL ASSERTION')) {
    return 'Ligação com o servidor instável. Atualize a página (Ctrl+F5) ou toque em Tentar de novo.';
  }
  if (_isNoFirebaseAppError(error)) {
    return 'Firebase não disponível: $raw';
  }
  if (raw.contains('Sessão expirada')) return raw;
  if (raw.contains('Tempo esgotado')) {
    return 'Tempo esgotado no envio. Use Wi‑Fi ou tente de novo.';
  }
  if (raw.length > 200) {
    return 'Falha na operação. Tente de novo.';
  }
  return raw.replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
}

bool isFirebaseNoAppError(Object e) {
  final low = e.toString().toLowerCase();
  return low.contains('no firebase app') ||
      low.contains('firebase.initializeapp') ||
      low.contains('core/no-app') ||
      low.contains('has not been initialized');
}

bool _isNoFirebaseAppError(Object e) => isFirebaseNoAppError(e);

/// Alias legado (upload / mural / chat).
String formatUploadErrorForUser(Object error) =>
    formatFirebaseErrorForUser(error);
