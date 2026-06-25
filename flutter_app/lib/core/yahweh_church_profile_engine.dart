import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/yahweh_central_engine_service.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Perfil da igreja — doc raiz `igrejas/{churchId}` (sem tenant fixo).
abstract final class YahwehChurchProfileEngine {
  YahwehChurchProfileEngine._();

  static const String pilotChurchIdHint = '';

  static String resolveChurchId(String? hint) =>
      ChurchRepository.churchId(hint?.trim() ?? '');

  /// Normaliza campos de produção (`dashboardAggregates`, `financeAggregates`).
  static Map<String, dynamic>? normalizeRootDoc(
    String churchId,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) return null;
    final out = Map<String, dynamic>.from(raw);
    final id = churchId.trim();
    if (id.isNotEmpty) {
      out['id'] = id;
      out['churchId'] = id;
    }

    final dash = raw['dashboardAggregates'];
    if (dash is Map) {
      for (final e in dash.entries) {
        out.putIfAbsent(e.key.toString(), () => e.value);
      }
      out['dashboardAggregates'] = Map<String, dynamic>.from(dash);
    }

    final fin = raw['financeAggregates'];
    if (fin is Map) {
      final fm = Map<String, dynamic>.from(fin);
      out['financeAggregates'] = fm;
      out.putIfAbsent('saldoAtual', () => fm['saldoAtual'] ?? fm['saldo_atual']);
    }

    final logoHttps = ChurchImageFields.logoHttpsUrlFromDoc(raw);
    if (logoHttps != null && logoHttps.isNotEmpty) {
      out['logoPath'] = logoHttps;
      out['logoUrl'] = logoHttps;
    } else {
      final logoPath = ChurchBrandService.logoPathFromData(raw, churchId: id);
      if (logoPath != null && logoPath.isNotEmpty) {
        out['logoStoragePath'] = logoPath;
      }
    }

    return out;
  }

  static Future<Map<String, dynamic>?> fetchChurchProfile({
    required String churchIdHint,
    bool forceRefresh = false,
  }) async {
    final loaded = await ChurchCadastroLoadService.load(
      seedTenantId: resolveChurchId(churchIdHint),
      forceRefresh: forceRefresh,
    );
    return normalizeRootDoc(loaded.churchId, loaded.data);
  }

  /// Web: polling leve; Mobile: `snapshots()` no doc raiz.
  static Stream<Map<String, dynamic>?> watchChurchProfile({
    required String churchIdHint,
  }) async* {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      yield null;
      return;
    }

    yield await fetchChurchProfile(churchIdHint: churchId);

    if (kIsWeb) {
      yield* Stream.periodic(const Duration(seconds: 30)).asyncMap((_) async {
        try {
          return await fetchChurchProfile(
            churchIdHint: churchId,
            forceRefresh: true,
          );
        } catch (_) {
          return null;
        }
      });
      return;
    }

    yield* ChurchRepository.churchDoc(churchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return normalizeRootDoc(churchId, doc.data());
    });
  }

  static Future<void> updateChurchDetails({
    required String churchIdHint,
    required Map<String, dynamic> updatedFields,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      throw StateError('churchId vazio');
    }
    final patch = Map<String, dynamic>.from(updatedFields)
      ..removeWhere((k, _) => k.startsWith('_'));
    patch['updatedAt'] = FieldValue.serverTimestamp();
    patch['countersUpdatedAt'] = FieldValue.serverTimestamp();

    if (kIsWeb) {
      await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchRepository.churchDoc(churchId).set(
              patch,
              SetOptions(merge: true),
            ),
        maxAttempts: 4,
      );
      return;
    }
    await ChurchRepository.churchDoc(churchId).set(
      patch,
      SetOptions(merge: true),
    );
  }

  /// Upload canónico — `igrejas/{id}/configuracoes/logo_igreja.png` + patch `logoPath`.
  static Future<void> uploadChurchLogo({
    required String churchIdHint,
    required Uint8List pngBytes,
    void Function(double progress)? onProgress,
  }) async {
    final churchId = resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      throw StateError('churchId vazio');
    }
    await YahwehCentralEngineService.executeSingleLogoSave(
      igrejaId: churchId,
      logoPngBytes: pngBytes,
      onProgress: onProgress,
    );
  }
}

/// Helpers partilhados — KPIs no doc raiz `igrejas/{churchId}`.
abstract final class ChurchRootAggregatesParser {
  ChurchRootAggregatesParser._();

  static Map<String, dynamic> flattenRootAggregates(Map<String, dynamic> raw) {
    final merged = Map<String, dynamic>.from(raw);
    final dash = raw['dashboardAggregates'];
    if (dash is Map) {
      merged.addAll(Map<String, dynamic>.from(dash));
    }
    final fin = raw['financeAggregates'];
    if (fin is Map) {
      final fm = Map<String, dynamic>.from(fin);
      merged.putIfAbsent('saldoAtual', () => fm['saldoAtual'] ?? fm['saldo_atual']);
      merged.putIfAbsent('saldo', () => fm['saldoAtual'] ?? fm['saldo_atual']);
      merged.putIfAbsent('receitasMes', () => fm['receitasMes']);
      merged.putIfAbsent('despesasMes', () => fm['despesasMes']);
    }
    return merged;
  }

  static bool rootDocHasAggregateHints(Map<String, dynamic> raw) {
    if (raw.isEmpty) return false;
    final flat = flattenRootAggregates(raw);
    for (final k in [
      'activeMembersCount',
      'membersCount',
      'departmentsCount',
      'saldoAtual',
      'name',
      'nome',
      'cnpj',
      'endereco',
    ]) {
      final v = flat[k];
      if (v == null) continue;
      if (v is num && v != 0) return true;
      if (v.toString().trim().isNotEmpty) return true;
    }
    return raw['dashboardAggregates'] is Map || raw['financeAggregates'] is Map;
  }
}
