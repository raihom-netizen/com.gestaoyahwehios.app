import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';

/// Configuracao da ponte Telegram Bot API para Firestore Chat.
///
/// O visual continua sendo o YAHWEH Chat. O Telegram funciona como
/// motor de transporte real das mensagens, tanto entrada quanto saida.
class ChurchTelegramBridgeService {
  ChurchTelegramBridgeService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instance;

  /// Ativa a ponte para uma igreja.
  ///
  /// [botToken] - token obtido em @BotFather.
  /// [chatId] - ID do grupo/canal no Telegram (pode ser negativo para grupos).
  /// [threadDocId] - thread do YAHWEH Chat que recebera/enviara mensagens
  ///                 (padrao: "telegram").
  static Future<void> enableBridge({
    required String churchId,
    required String botToken,
    required String chatId,
    String threadDocId = 'telegram',
  }) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) throw StateError('churchId vazio');
    if (botToken.trim().isEmpty) throw StateError('botToken vazio');
    if (chatId.trim().isEmpty) throw StateError('chatId vazio');

    final callable = _functions.httpsCallable('telegramSetWebhook');
    final result = await callable.call<Map<String, dynamic>>({
      'churchId': cid,
      'botToken': botToken.trim(),
      'chatId': chatId.trim(),
      'threadDocId': threadDocId.trim(),
    });

    final data = result.data;
    final ok = data['ok'] == true;
    final webhookUrl = (data['webhookUrl'] ?? '').toString();
    if (!ok || webhookUrl.isEmpty) {
      throw StateError(
        'Falha ao ativar ponte Telegram: ${data['error'] ?? result.data}',
      );
    }

    final threadRef = ChurchChatService.threadRef(cid, threadDocId.trim());
    await threadRef.set({
      'telegramChatId': chatId.trim(),
      'telegramBotToken': botToken.trim(),
      'title': 'Telegram',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('Ponte Telegram ativada: $webhookUrl');
  }

  /// Desativa a ponte (remove webhook e desabilita no Firestore).
  static Future<void> disableBridge({
    required String churchId,
    String threadDocId = 'telegram',
  }) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) return;

    final churchRef = FirebaseFirestore.instance.collection('igrejas').doc(cid);
    final snap = await churchRef.get();
    final bridge = snap.data()?['telegramBridge'] as Map<String, dynamic>?;
    final botToken = (bridge?['botToken'] ?? '').toString().trim();

    if (botToken.isNotEmpty) {
      try {
        await _functions
            .httpsCallable('telegramSetWebhook')
            .call<Map<String, dynamic>>({
              'churchId': cid,
              'botToken': botToken,
              'chatId': '',
              'threadDocId': threadDocId,
            });
      } catch (_) {
        // best effort
      }
    }

    await churchRef.set({
      'telegramBridge': {
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  /// Verifica se a ponte esta ativa para a igreja.
  static Future<bool> isBridgeEnabled(String churchId) async {
    final cid = ChurchRepository.churchId(churchId);
    if (cid.isEmpty) return false;
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(cid)
        .get();
    final bridge = snap.data()?['telegramBridge'] as Map<String, dynamic>?;
    return bridge?['enabled'] == true &&
        (bridge?['botToken'] ?? '').toString().isNotEmpty;
  }
}
