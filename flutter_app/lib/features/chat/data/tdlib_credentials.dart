// Credenciais TDLib — prioridade: Firestore (painel master) → dart-define → .env
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gestao_yahweh/services/telegram_tdlib_config_service.dart';

const String _telegramApiIdFromBuild =
    String.fromEnvironment('TELEGRAM_API_ID');
const String _telegramApiHashFromBuild =
    String.fromEnvironment('TELEGRAM_API_HASH');

int? _firestoreApiId;
String? _firestoreApiHash;
String? _firestoreDeviceModel;
String? _firestoreSystemLanguageCode;
bool _firestoreLoadAttempted = false;

/// Carrega dotenv. Seguro chamar várias vezes; falha soft se ausente.
Future<void> loadTdlibDotEnv() async {
  if (dotenv.isInitialized) return;
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

/// Lê `config/telegram_tdlib` (painel master) e cacheia em memória.
Future<void> ensureTelegramCredentialsLoaded({bool force = false}) async {
  if (_firestoreLoadAttempted && !force && (_firestoreApiId ?? 0) > 0) {
    return;
  }
  _firestoreLoadAttempted = true;
  await loadTdlibDotEnv();
  try {
    final cfg = await TelegramTdlibConfigService.load(preferServer: true);
    if (cfg.isConfigured) {
      _firestoreApiId = cfg.apiId;
      _firestoreApiHash = cfg.apiHash;
      if (cfg.deviceModel.isNotEmpty) {
        _firestoreDeviceModel = cfg.deviceModel;
      }
      if (cfg.systemLanguageCode.isNotEmpty) {
        _firestoreSystemLanguageCode = cfg.systemLanguageCode;
      }
    }
  } catch (_) {
    // Retry permitido na próxima chamada se ainda não houver credencial.
    if ((_firestoreApiId ?? 0) <= 0) {
      _firestoreLoadAttempted = false;
    }
  }
}

/// Injeta valores já lidos (ex.: após salvar no master na mesma sessão).
void applyTelegramCredentialsCache({
  required int apiId,
  required String apiHash,
  String? deviceModel,
  String? systemLanguageCode,
}) {
  if (apiId > 0 && apiHash.trim().length >= 16) {
    _firestoreApiId = apiId;
    _firestoreApiHash = apiHash.trim();
    _firestoreLoadAttempted = true;
  }
  if ((deviceModel ?? '').trim().isNotEmpty) {
    _firestoreDeviceModel = deviceModel!.trim();
  }
  if ((systemLanguageCode ?? '').trim().isNotEmpty) {
    _firestoreSystemLanguageCode = systemLanguageCode!.trim();
  }
}

int get telegramApiId {
  final fromFs = _firestoreApiId ?? 0;
  if (fromFs > 0) return fromFs;
  final buildValue = _telegramApiIdFromBuild.trim();
  if (buildValue.isNotEmpty) return int.tryParse(buildValue) ?? 0;
  final raw = (dotenv.isInitialized ? dotenv.env['TELEGRAM_API_ID'] : null)
          ?.trim() ??
      '';
  return int.tryParse(raw) ?? 0;
}

String get telegramApiHash {
  final fromFs = (_firestoreApiHash ?? '').trim();
  if (fromFs.isNotEmpty) return fromFs;
  final buildValue = _telegramApiHashFromBuild.trim();
  if (buildValue.isNotEmpty) return buildValue;
  return (dotenv.isInitialized ? dotenv.env['TELEGRAM_API_HASH'] : null)
          ?.trim() ??
      '';
}

String get telegramDeviceModel {
  final fromFs = (_firestoreDeviceModel ?? '').trim();
  if (fromFs.isNotEmpty) return fromFs;
  final v = (dotenv.isInitialized ? dotenv.env['TELEGRAM_DEVICE_MODEL'] : null)
      ?.trim();
  if (v == null || v.isEmpty) return 'Gestao YAHWEH';
  return v;
}

String get telegramSystemLanguageCode {
  final fromFs = (_firestoreSystemLanguageCode ?? '').trim();
  if (fromFs.isNotEmpty) return fromFs;
  final v =
      (dotenv.isInitialized ? dotenv.env['TELEGRAM_SYSTEM_LANGUAGE_CODE'] : null)
          ?.trim();
  if (v == null || v.isEmpty) return 'pt-br';
  return v;
}

bool get kTelegramCredentialsConfigured =>
    telegramApiId > 0 && telegramApiHash.length >= 16;
