import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/chat_engine/tdlib_chat_adapter.dart';

/// Gestão de grupos de departamento via Telegram (TDLib).
///
/// Mapeia departamentos da igreja → grupos Telegram supergroup.
/// Auto-cria grupo quando departamento é criado; auto-adiciona membros
/// pelo telefone do cadastro.
abstract final class TdlibDepartmentGroupService {
  TdlibDepartmentGroupService._();

  /// Cria grupo Telegram para departamento + gera link de convite.
  ///
  /// Retorna `(chatId, inviteLink)` do grupo Telegram criado.
  static Future<({int chatId, String? inviteLink})> createGroupForDepartment({
    required String departmentName,
    String description = '',
  }) async {
    if (!TdlibChatAdapter.isAvailable) {
      throw StateError(
        'TDLib não disponível. Conecte-se ao Telegram primeiro.',
      );
    }
    return TdlibChatAdapter.createDepartmentGroup(
      title: departmentName,
      description: description,
    );
  }

  /// Adiciona membros ao grupo pelo telefone do cadastro.
  ///
  /// Retorna lista de telefones que falharam (não encontrados no Telegram).
  static Future<List<String>> addMembersByPhone({
    required int tdlibChatId,
    required List<String> phoneNumbers,
  }) async {
    if (!TdlibChatAdapter.isAvailable) return phoneNumbers;
    final failed = <String>[];
    for (final phone in phoneNumbers) {
      try {
        final ok = await TdlibChatAdapter.addMemberByPhone(
          tdlibChatId,
          phone,
        );
        if (!ok) failed.add(phone);
      } catch (e) {
        debugPrint('[DeptGroup] addMember $phone falhou: $e');
        failed.add(phone);
      }
    }
    return failed;
  }

  /// Remove membro do grupo (pelo user_id Telegram).
  static Future<void> removeMember({
    required int tdlibChatId,
    required int userId,
  }) =>
      TdlibChatAdapter.removeMember(tdlibChatId, userId);

  /// Sincroniza todos os departamentos → grupos Telegram.
  ///
  /// Para cada departamento com `telegramChatId` salvo no Firestore,
  /// verifica se o grupo existe; senão, cria.
  static Future<Map<String, ({int chatId, String? inviteLink})>>
      syncDepartmentsToGroups({
    required Map<String, String> departmentNames,
    Map<String, int>? existingChatIds,
  }) async {
    if (!TdlibChatAdapter.isAvailable) return {};
    final results = <String, ({int chatId, String? inviteLink})>{};

    for (final entry in departmentNames.entries) {
      final deptId = entry.key;
      final name = entry.value;

      // Skip if already has a Telegram group
      if (existingChatIds != null && existingChatIds.containsKey(deptId)) {
        continue;
      }

      try {
        final result = await createGroupForDepartment(
          departmentName: name,
          description: 'Grupo do departamento $name — Gestão YAHWEH',
        );
        results[deptId] = result;
      } catch (e) {
        debugPrint('[DeptGroup] criar grupo "$name" falhou: $e');
      }
    }
    return results;
  }

  /// Entra em grupo existente por link de convite.
  static Future<int> joinExistingGroup(String inviteUrl) =>
      TdlibChatAdapter.joinByInvite(inviteUrl);
}
