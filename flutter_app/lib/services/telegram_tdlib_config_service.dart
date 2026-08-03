import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/data/app_global_firestore_access.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Credenciais TDLib / Telegram API — doc global `config/telegram_tdlib`.
///
/// Escrita: painel master. Leitura: app autenticado (mobile TDLib).
abstract final class TelegramTdlibConfigService {
  TelegramTdlibConfigService._();

  static const String docId = 'telegram_tdlib';
  static const String firestorePath = 'config/$docId';

  static DocumentReference<Map<String, dynamic>> get docRef =>
      AppGlobalFirestoreAccess.configDoc(docId);

  /// Carrega do Firestore. Preferência: servidor (painel master) → cache.
  /// Não engole erro em silêncio — o caller mostra o problema.
  static Future<TelegramTdlibConfig> load({bool preferServer = true}) async {
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Object? lastError;

    if (preferServer) {
      try {
        final snap = await FirestoreWebGuard.runWithWebRecovery(
          () => AppGlobalFirestoreAccess.getConfig(
            docId,
            source: Source.server,
          ),
          maxAttempts: 3,
        );
        if (snap.exists) {
          return TelegramTdlibConfig.fromMap(snap.data());
        }
      } catch (e) {
        lastError = e;
        debugPrint('[TelegramTdlibConfig] load server: $e');
      }
    }

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => AppGlobalFirestoreAccess.getConfig(
          docId,
          source: Source.serverAndCache,
        ),
        maxAttempts: 3,
      );
      if (snap.exists) {
        return TelegramTdlibConfig.fromMap(snap.data());
      }
      return const TelegramTdlibConfig.empty();
    } catch (e) {
      lastError ??= e;
      debugPrint('[TelegramTdlibConfig] load cache: $e');
      // Última tentativa: cache puro (offline).
      try {
        final cached = await docRef.get(const GetOptions(source: Source.cache));
        if (cached.exists) {
          return TelegramTdlibConfig.fromMap(cached.data());
        }
      } catch (_) {}
      throw TelegramTdlibConfigException(
        'Não foi possível ler $firestorePath. $lastError',
      );
    }
  }

  /// Grava no Firestore (merge) e confirma leitura de volta.
  static Future<TelegramTdlibConfig> save({
    required int apiId,
    required String apiHash,
    String? deviceModel,
    String? systemLanguageCode,
  }) async {
    final hash = apiHash.trim();
    if (apiId <= 0) {
      throw ArgumentError('api_id inválido');
    }
    if (hash.length < 16) {
      throw ArgumentError('api_hash inválido (mín. 16 caracteres)');
    }
    await FirestoreWebGuard.recoverFirestoreWebSession(
      allowHardReconnect: true,
    ).catchError((_) {});
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    final email = firebaseDefaultAuth.currentUser?.email ?? '';
    final payload = <String, dynamic>{
      'apiId': apiId,
      'apiHash': hash,
      'api_id': apiId,
      'api_hash': hash,
      'deviceModel': (deviceModel ?? '').trim().isEmpty
          ? 'Gestao YAHWEH'
          : deviceModel!.trim(),
      'systemLanguageCode': (systemLanguageCode ?? '').trim().isEmpty
          ? 'pt-br'
          : systemLanguageCode!.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
      'updatedByEmail': email,
      'source': 'master_panel',
      'configured': true,
    };

    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload, SetOptions(merge: true)),
      maxAttempts: 4,
    );

    // Confirmação — evita “salvei” sem dados no doc.
    final verified = await FirestoreWebGuard.runWithWebRecovery(
      () => AppGlobalFirestoreAccess.getConfig(docId, source: Source.server),
      maxAttempts: 3,
    );
    if (!verified.exists) {
      throw TelegramTdlibConfigException(
        'Gravação sem confirmação: $firestorePath não existe após set.',
      );
    }
    final cfg = TelegramTdlibConfig.fromMap(verified.data());
    if (!cfg.isConfigured || cfg.apiId != apiId || cfg.apiHash != hash) {
      throw TelegramTdlibConfigException(
        'Gravação inconsistente em $firestorePath '
        '(lido apiId=${cfg.apiId}). Tente novamente.',
      );
    }
    return cfg;
  }
}

class TelegramTdlibConfigException implements Exception {
  TelegramTdlibConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TelegramTdlibConfig {
  const TelegramTdlibConfig({
    required this.apiId,
    required this.apiHash,
    this.deviceModel = '',
    this.systemLanguageCode = '',
    this.updatedByEmail = '',
  });

  const TelegramTdlibConfig.empty()
      : apiId = 0,
        apiHash = '',
        deviceModel = '',
        systemLanguageCode = '',
        updatedByEmail = '';

  final int apiId;
  final String apiHash;
  final String deviceModel;
  final String systemLanguageCode;
  final String updatedByEmail;

  bool get isConfigured => apiId > 0 && apiHash.trim().length >= 16;

  factory TelegramTdlibConfig.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return const TelegramTdlibConfig.empty();
    }
    final idRaw = data['apiId'] ?? data['api_id'] ?? data['TELEGRAM_API_ID'];
    final hashRaw =
        data['apiHash'] ?? data['api_hash'] ?? data['TELEGRAM_API_HASH'];
    final id = idRaw is int
        ? idRaw
        : int.tryParse('${idRaw ?? ''}'.trim()) ?? 0;
    final hash = '${hashRaw ?? ''}'.trim();
    return TelegramTdlibConfig(
      apiId: id,
      apiHash: hash,
      deviceModel: '${data['deviceModel'] ?? ''}'.trim(),
      systemLanguageCode: '${data['systemLanguageCode'] ?? ''}'.trim(),
      updatedByEmail: '${data['updatedByEmail'] ?? ''}'.trim(),
    );
  }
}
