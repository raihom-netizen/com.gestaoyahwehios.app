import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// Carrega do Firestore (cache → servidor).
  static Future<TelegramTdlibConfig> load() async {
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => AppGlobalFirestoreAccess.getConfig(docId),
        maxAttempts: 3,
      );
      return TelegramTdlibConfig.fromMap(snap.data());
    } catch (_) {
      return const TelegramTdlibConfig.empty();
    }
  }

  /// Grava no Firestore (merge). Só master via regras.
  static Future<void> save({
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
    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set({
        'apiId': apiId,
        'apiHash': hash,
        if ((deviceModel ?? '').trim().isNotEmpty)
          'deviceModel': deviceModel!.trim(),
        if ((systemLanguageCode ?? '').trim().isNotEmpty)
          'systemLanguageCode': systemLanguageCode!.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': uid,
        'updatedByEmail': email,
        'source': 'master_panel',
      }, SetOptions(merge: true)),
      maxAttempts: 4,
    );
  }
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
