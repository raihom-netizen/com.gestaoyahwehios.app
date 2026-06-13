import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Endereço do cadastro — cache instantâneo + leitura directa `igrejas/{churchId}`.
class ChurchCadastroAddressResult {
  const ChurchCadastroAddressResult({
    required this.churchId,
    required this.data,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final Map<String, dynamic> data;
  final String readSource;
  final String? softError;

  String get formattedLine => ChurchCadastroAddressService.formatAddress(data);

  bool get hasAddress => formattedLine.trim().isNotEmpty;
}

/// Carga ultra-rápida do endereço (Novo Aviso / Evento / Agenda).
abstract final class ChurchCadastroAddressService {
  ChurchCadastroAddressService._();

  static String _resolve(String hint) => ChurchRepository.churchId(hint.trim());

  static String formatAddress(Map<String, dynamic> data) {
    final endereco = (data['endereco'] ?? '').toString().trim();
    if (endereco.isNotEmpty) return endereco;

    final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
    final numero = (data['numero'] ?? '').toString().trim();
    final quadra = (data['quadraLoteNumero'] ??
            data['quadraLote'] ??
            data['quadra_lote'] ??
            '')
        .toString()
        .trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    final cepDigits =
        (data['cep'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

    final parts = <String>[];
    if (rua.isNotEmpty) {
      parts.add(numero.isNotEmpty ? '$rua, Nº $numero' : rua);
    } else if (numero.isNotEmpty) {
      parts.add('Nº $numero');
    }
    if (quadra.isNotEmpty) parts.add('Qd/Lt $quadra');
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cepDigits.length == 8) {
      final cep = '${cepDigits.substring(0, 5)}-${cepDigits.substring(5)}';
      parts.add('CEP $cep');
    }
    return parts.join(', ');
  }

  /// RAM/sessão/Hive — sem rede.
  static Future<ChurchCadastroAddressResult?> peekLocal(String seedTenantId) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) return null;

    final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
    final ctxData = ChurchContextService.currentChurchData;
    if (ctxData != null &&
        ctxId.isNotEmpty &&
        ChurchRepository.churchId(ctxId) == churchId &&
        ctxData.isNotEmpty) {
      return ChurchCadastroAddressResult(
        churchId: churchId,
        data: Map<String, dynamic>.from(ctxData),
        readSource: 'session_context',
      );
    }

    final local = await ChurchCadastroLoadService.tryLocalSources(
      seedTenantId: churchId,
    );
    if (local != null && local.data.isNotEmpty) {
      return ChurchCadastroAddressResult(
        churchId: local.churchId,
        data: local.data,
        readSource: local.readSource,
      );
    }
    return null;
  }

  /// Cache-first → doc directo (1 GET) → fallback load completo.
  static Future<ChurchCadastroAddressResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = _resolve(seedTenantId);
    if (churchId.isEmpty) {
      return const ChurchCadastroAddressResult(
        churchId: '',
        data: {},
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    if (!forceRefresh) {
      final peek = await peekLocal(churchId);
      if (peek != null && peek.hasAddress) {
        unawaited(_refreshBackground(churchId));
        return peek;
      }
    }

    Object? lastError;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final direct = await FirestoreWebGuard.runWithWebRecovery(
        () => IgrejaDirectFirestoreReads.readIgrejaDoc(churchId),
        maxAttempts: 4,
      ).timeout(ChurchPanelReadTimeouts.churchDocCap);
      if (direct != null && direct.data.isNotEmpty) {
        return ChurchCadastroAddressResult(
          churchId: direct.docId,
          data: direct.data,
          readSource: 'direct_read',
        );
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final loaded = await ChurchCadastroLoadService.load(
        seedTenantId: churchId,
        forceRefresh: forceRefresh,
      );
      return ChurchCadastroAddressResult(
        churchId: loaded.churchId,
        data: loaded.data,
        readSource: loaded.readSource,
        softError: loaded.softError,
      );
    } catch (e) {
      lastError ??= e;
      final peek = await peekLocal(churchId);
      if (peek != null) {
        return ChurchCadastroAddressResult(
          churchId: peek.churchId,
          data: peek.data,
          readSource: '${peek.readSource}_fallback',
          softError: '$lastError',
        );
      }
      return ChurchCadastroAddressResult(
        churchId: churchId,
        data: const {},
        readSource: 'error',
        softError: '$lastError',
      );
    }
  }

  static Future<void> _refreshBackground(String churchId) async {
    try {
      await IgrejaDirectFirestoreReads.readIgrejaDoc(churchId);
    } catch (_) {}
  }
}
