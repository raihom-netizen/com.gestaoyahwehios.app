// Credenciais TDLib — lidas via flutter_dotenv (sem hardcode).
// Asset commitado: `.env.example`. Localmente pode copiar para `.env` e
// preencher secrets; no CI o exemplo (vazio) basta — TDLib fica desligado.
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';

const String _telegramApiIdFromBuild =
    String.fromEnvironment('TELEGRAM_API_ID');
const String _telegramApiHashFromBuild =
    String.fromEnvironment('TELEGRAM_API_HASH');

/// Carrega dotenv. Seguro chamar várias vezes; falha soft se ausente.
Future<void> loadTdlibDotEnv() async {
  if (dotenv.isInitialized) return;
  // Preferir `.env` se existir no bundle (builds locais que o incluem);
  // senão `.env.example` (produção / CodeMagic).
  for (final name in ['.env', '.env.example']) {
    try {
      await rootBundle.loadString(name);
      await dotenv.load(fileName: name);
      return;
    } catch (_) {
      // tenta próximo
    }
  }
}

int get telegramApiId {
  final buildValue = _telegramApiIdFromBuild.trim();
  if (buildValue.isNotEmpty) return int.tryParse(buildValue) ?? 0;
  final raw = (dotenv.isInitialized ? dotenv.env['TELEGRAM_API_ID'] : null)
          ?.trim() ??
      '';
  return int.tryParse(raw) ?? 0;
}

String get telegramApiHash {
  final buildValue = _telegramApiHashFromBuild.trim();
  if (buildValue.isNotEmpty) return buildValue;
  return (dotenv.isInitialized ? dotenv.env['TELEGRAM_API_HASH'] : null)
          ?.trim() ??
      '';
}

String get telegramDeviceModel {
  final v = (dotenv.isInitialized ? dotenv.env['TELEGRAM_DEVICE_MODEL'] : null)
      ?.trim();
  if (v == null || v.isEmpty) return 'Gestao YAHWEH';
  return v;
}

String get telegramSystemLanguageCode {
  final v =
      (dotenv.isInitialized ? dotenv.env['TELEGRAM_SYSTEM_LANGUAGE_CODE'] : null)
          ?.trim();
  if (v == null || v.isEmpty) return 'pt-br';
  return v;
}

bool get kTelegramCredentialsConfigured =>
    telegramApiId > 0 && telegramApiHash.length >= 16;
