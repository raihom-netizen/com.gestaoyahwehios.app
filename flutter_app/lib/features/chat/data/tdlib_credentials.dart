// Credenciais TDLib — lidas de `.env` via flutter_dotenv (sem hardcode).
// Ficheiro: flutter_app/.env (asset + gitignore). Modelo: .env.example
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Carrega o asset `.env`. Seguro chamar várias vezes; falha soft se ausente.
Future<void> loadTdlibDotEnv() async {
  if (dotenv.isInitialized) return;
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Builds sem .env (CI) — TdLib fica desligado até configurar.
  }
}

int get telegramApiId {
  final raw = (dotenv.isInitialized ? dotenv.env['TELEGRAM_API_ID'] : null)
          ?.trim() ??
      '';
  return int.tryParse(raw) ?? 0;
}

String get telegramApiHash {
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
