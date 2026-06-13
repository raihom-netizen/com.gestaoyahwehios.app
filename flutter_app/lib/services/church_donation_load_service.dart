import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

typedef DonationMpConta = ({String id, String nome});

/// Resultado da carga do módulo Doação — contas MP + config integração.
class ChurchDonationLoadResult {
  const ChurchDonationLoadResult({
    required this.churchId,
    required this.contas,
    required this.mercadoPagoReady,
    required this.readSource,
    this.softError,
  });

  final String churchId;
  final List<DonationMpConta> contas;
  final bool mercadoPagoReady;
  final String readSource;
  final String? softError;
}

/// Carga canónica Doação — `igrejas/{churchId}/contas` + `config/mercado_pago`.
abstract final class ChurchDonationLoadService {
  ChurchDonationLoadService._();

  static const int kContasLimit = 80;

  static final Map<String, ({List<DonationMpConta> contas, DateTime at})>
      _contasRam = {};
  static final Map<String, ({bool ready, DateTime at})> _configRam = {};

  static const Duration _ramTtl = Duration(minutes: 25);

  static String contasCacheKey(String churchId) =>
      '${churchId.trim()}_contas_mp_donation_$kContasLimit';

  static List<DonationMpConta>? peekContasRam(String churchId) {
    final key = churchId.trim();
    if (key.isEmpty) return null;
    final hit = _contasRam[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _contasRam.remove(key);
      return null;
    }
    return hit.contas;
  }

  static void putContasRam(String churchId, List<DonationMpConta> contas) {
    final key = churchId.trim();
    if (key.isEmpty || contas.isEmpty) return;
    _contasRam[key] = (contas: contas, at: DateTime.now());
  }

  static bool? peekConfigReadyRam(String churchId) {
    final key = churchId.trim();
    if (key.isEmpty) return null;
    final hit = _configRam[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _configRam.remove(key);
      return null;
    }
    return hit.ready;
  }

  static void putConfigReadyRam(String churchId, bool ready) {
    final key = churchId.trim();
    if (key.isEmpty) return;
    _configRam[key] = (ready: ready, at: DateTime.now());
  }

  static bool isMercadoPagoTreasuryAccount(Map<String, dynamic> data) {
    final cod = (data['bancoCodigo'] ?? '').toString().trim();
    if (cod == '323') return true;
    final bn = (data['bancoNome'] ?? '').toString().toLowerCase();
    if (bn.contains('mercado pago')) return true;
    if ((data['seedPreset'] ?? '').toString() == 'tesouraria_mercado_pago') {
      return true;
    }
    final nome = (data['nome'] ?? '').toString().toLowerCase();
    if (nome.contains('mercado pago')) return true;
    return false;
  }

  static bool mercadoPagoConfigReady(Map<String, dynamic> data) {
    if (data.isEmpty) return false;
    if (data['enabled'] == true) return true;
    if (data['hasClientSecret'] == true) return true;
    if ((data['publicKey'] ?? '').toString().trim().isNotEmpty) return true;
    if ((data['clientId'] ?? '').toString().trim().isNotEmpty) return true;
    return false;
  }

  static List<DonationMpConta> contasFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    return snap.docs
        .where((d) => d.data()['ativo'] != false)
        .where((d) => isMercadoPagoTreasuryAccount(d.data()))
        .map((d) => (id: d.id, nome: (d.data()['nome'] ?? '').toString()))
        .where((e) => e.nome.isNotEmpty)
        .toList();
  }

  static List<DonationMpConta> contasFromHiveRows(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <DonationMpConta>[];
    for (final row in rows) {
      final dataRaw = row['data'];
      final data = dataRaw is Map
          ? Map<String, dynamic>.from(dataRaw)
          : Map<String, dynamic>.from(row);
      if (data['ativo'] == false) continue;
      if (!isMercadoPagoTreasuryAccount(data)) continue;
      final id = (row['id'] ?? row['docId'] ?? data['id'] ?? '').toString();
      final nome = (data['nome'] ?? '').toString();
      if (id.isEmpty || nome.isEmpty) continue;
      out.add((id: id, nome: nome));
    }
    return out;
  }

  static Future<bool> loadMercadoPagoConfigReady(String churchId) async {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return false;

    final cached = peekConfigReadyRam(id);
    if (cached != null) return cached;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final hit = await IgrejaDirectFirestoreReads.readIgrejaConfig(
        id,
        'mercado_pago',
      ).timeout(Duration(seconds: kIsWeb ? 45 : 20));
      final ready = hit != null && mercadoPagoConfigReady(hit.data);
      putConfigReadyRam(id, ready);
      return ready;
    } catch (_) {
      return false;
    }
  }

  static Future<List<DonationMpConta>> _loadContasFirestoreFull(
    String churchId,
  ) async {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return const [];

    final cacheKey = contasCacheKey(id);

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final cacheSnap = await ChurchUiCollections.contas(id)
          .limit(kContasLimit)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 5));
      final fromCache = contasFromSnapshot(cacheSnap);
      if (fromCache.isNotEmpty) return fromCache;
    } catch (_) {}

    Future<QuerySnapshot<Map<String, dynamic>>> readServer() =>
        FirestoreReadResilience.getQuery(
          ChurchUiCollections.contas(id).limit(kContasLimit),
          cacheKey: cacheKey,
          maxAttempts: kIsWeb ? 5 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 24)
              : const Duration(seconds: 16),
        );

    final snap = kIsWeb
        ? await FirestoreWebGuard.runWithWebRecovery(
            readServer,
            maxAttempts: 4,
          ).timeout(const Duration(seconds: 100))
        : await readServer().timeout(const Duration(seconds: 50));

    return contasFromSnapshot(snap);
  }

  static Future<List<DonationMpConta>> loadMercadoPagoContas({
    required String churchId,
    bool forceRefresh = false,
  }) async {
    final id = ChurchRepository.churchId(churchId);
    if (id.isEmpty) return const [];

    if (!forceRefresh) {
      final ram = peekContasRam(id);
      if (ram != null && ram.isNotEmpty) return ram;

      final mem =
          FirestoreReadResilience.peekLastGoodQuery(contasCacheKey(id));
      if (mem != null && mem.docs.isNotEmpty) {
        final list = contasFromSnapshot(mem);
        if (list.isNotEmpty) {
          putContasRam(id, list);
          return list;
        }
      }

      try {
        final hive = await TenantModuleHiveCache.readDocs(
          id,
          TenantModuleKeys.financeiro,
        );
        if (hive.isNotEmpty) {
          final fromHive = contasFromHiveRows(hive);
          if (fromHive.isNotEmpty) {
            putContasRam(id, fromHive);
            return fromHive;
          }
        }
      } catch (_) {}
    }

    Object? lastError;
    try {
      final list = await _loadContasFirestoreFull(id);
      if (list.isNotEmpty) {
        putContasRam(id, list);
        return list;
      }
    } catch (e) {
      lastError = e;
    }

    try {
      final snap = await IgrejaDirectFirestoreReads.listSubcollection(
        id,
        'contas',
        moduleLabel: 'Doação MP',
        limit: kContasLimit,
        cacheKey: contasCacheKey(id),
      );
      final list = contasFromSnapshot(snap);
      if (list.isNotEmpty) {
        putContasRam(id, list);
        return list;
      }
    } catch (e) {
      lastError ??= e;
    }

    final mem =
        FirestoreReadResilience.peekLastGoodQuery(contasCacheKey(id));
    if (mem != null && mem.docs.isNotEmpty) {
      final list = contasFromSnapshot(mem);
      if (list.isNotEmpty) return list;
    }

    if (lastError != null) throw lastError;
    return const [];
  }

  /// Contas MP + flag de integração — paralelo, cache-first, timeout longo web.
  static Future<ChurchDonationLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final churchId = ChurchRepository.churchId(seedTenantId.trim());
    if (churchId.isEmpty) {
      return const ChurchDonationLoadResult(
        churchId: '',
        contas: [],
        mercadoPagoReady: false,
        readSource: 'empty_id',
        softError: 'Igreja não identificada.',
      );
    }

    Object? contasError;
    List<DonationMpConta> contas = [];
    var readSource = 'none';

    if (!forceRefresh) {
      final ram = peekContasRam(churchId);
      if (ram != null && ram.isNotEmpty) {
        contas = ram;
        readSource = 'ram';
      }
    }

    final configFuture = loadMercadoPagoConfigReady(churchId);

    if (contas.isEmpty) {
      try {
        contas = await loadMercadoPagoContas(
          churchId: churchId,
          forceRefresh: forceRefresh,
        );
        readSource = contas.isNotEmpty ? 'firestore_contas' : 'empty_contas';
      } catch (e) {
        contasError = e;
        readSource = 'error';
      }
    }

    final mpReady = await configFuture;

    String? softError;
    if (contas.isEmpty && contasError != null) {
      softError = contasError is TimeoutException
          ? 'A conexão demorou demais ao carregar as contas Mercado Pago.'
          : contasError.toString();
    }

    return ChurchDonationLoadResult(
      churchId: churchId,
      contas: contas,
      mercadoPagoReady: mpReady,
      readSource: readSource,
      softError: softError,
    );
  }
}
