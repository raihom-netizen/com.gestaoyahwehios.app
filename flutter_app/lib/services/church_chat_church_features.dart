import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:intl/intl.dart';

/// Integrações do chat com o ecossistema da igreja (pastoral, escalas, etc.).
abstract final class ChurchChatChurchFeatures {
  ChurchChatChurchFeatures._();

  /// Mensagem pastoral destacada no grupo do departamento (estilo aviso no chat).
  static Future<bool> sendPastoralHighlightToDepartment({
    required String tenantId,
    required String departmentId,
    required String departmentName,
    required String message,
  }) async {
    final text = message.trim();
    if (text.isEmpty || departmentId.trim().isEmpty) return false;
    try {
      final me = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
      await ChurchChatService.ensureDepartmentThread(
        tenantId: tenantId,
        departmentId: departmentId,
        departmentName:
            departmentName.trim().isNotEmpty ? departmentName : 'Departamento',
        participantUids: me.isNotEmpty ? [me] : const [],
      );
      final threadId = ChurchChatService.deptThreadId(departmentId);
      final sender = ChurchChatService.senderDisplayNameForNewMessage();
      final body = '📢 Mensagem pastoral\n$text';
      final ok = await ChurchChatService.sendTextMessage(
        tenantId: tenantId,
        threadId: threadId,
        text: body,
        senderDisplayName: sender,
      );
      if (!ok) return false;
      final last = await ChurchChatService.messagesCol(tenantId, threadId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (last.docs.isNotEmpty) {
        await last.docs.first.reference.set(
          {'pastoralHighlight': true, 'churchFeature': 'pastoral'},
          SetOptions(merge: true),
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('sendPastoralHighlightToDepartment: $e');
      }
      return false;
    }
  }

  /// Transmissão nos grupos `dept_*` (paralelo limitado).
  static Future<int> postBroadcastToDepartmentThreads({
    required String tenantId,
    required String title,
    required String body,
    required Iterable<({String id, String name})> departments,
  }) async {
    var ok = 0;
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty || b.isEmpty) return 0;
    final message = t == b ? t : '$t\n$b';
    for (final d in departments) {
      if (d.id.trim().isEmpty) continue;
      final sent = await sendPastoralHighlightToDepartment(
        tenantId: tenantId,
        departmentId: d.id,
        departmentName: d.name,
        message: message,
      );
      if (sent) ok++;
    }
    return ok;
  }

  /// Aviso automático no grupo quando uma escala é criada/gerada.
  static Future<void> notifyDepartmentEscalaCreated({
    required String tenantId,
    required String departmentId,
    required String departmentName,
    required String escalaTitle,
    required DateTime when,
    String? timeLabel,
  }) async {
    if (departmentId.trim().isEmpty) return;
    try {
      final me = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
      await ChurchChatService.ensureDepartmentThread(
        tenantId: tenantId,
        departmentId: departmentId,
        departmentName:
            departmentName.trim().isNotEmpty ? departmentName : 'Departamento',
        participantUids: me.isNotEmpty ? [me] : const [],
      );
      final threadId = ChurchChatService.deptThreadId(departmentId);
      final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
      final hour = (timeLabel ?? '').trim();
      final whenLine = hour.isNotEmpty
          ? '${dateFmt.format(when)} às $hour'
          : dateFmt.format(when);
      final sender =
          FirebaseAuth.instance.currentUser?.displayName?.trim() ?? 'Escalas';
      final text =
          '📅 Nova escala — $escalaTitle\n$whenLine\nConfirme a sua presença no módulo Escalas.';
      await ChurchChatService.sendTextMessage(
        tenantId: tenantId,
        threadId: threadId,
        text: text,
        senderDisplayName: sender,
      );
      final last = await ChurchChatService.messagesCol(tenantId, threadId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (last.docs.isNotEmpty) {
        await last.docs.first.reference.set(
          {'churchFeature': 'escala', 'escalaTitle': escalaTitle},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('notifyDepartmentEscalaCreated: $e');
      }
    }
  }
}
