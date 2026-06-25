import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_profile_loader.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';



/// Leitura **directa** de `igrejas/{churchId}` — sem alias, cluster nem resolver.

///

/// O [tenantId] deve ser o ID real do documento (ex.: `igreja_nome_da_igreja`).

abstract final class IgrejaDirectFirestoreReads {

  IgrejaDirectFirestoreReads._();



  /// Sempre o doc canónico pedido pelo módulo (slug BPC → `igreja_o_brasil_…`).
  static String _directChurchDocId(String tenantId) {
    return ChurchRepository.churchId(tenantId);
  }



  /// Subcoleção `igrejas/{id}/{sub}` — retry web, cache-key, timeout (painel).
  static Future<QuerySnapshot<Map<String, dynamic>>> listSubcollection(
    String tenantId,
    String subcollection, {
    required String moduleLabel,
    int limit = 120,
    String? cacheKey,
  }) async {
    final id = _directChurchDocId(tenantId);
    final sub = subcollection.trim();
    if (id.isEmpty || sub.isEmpty) {
      return const MergedFirestoreQuerySnapshot([]);
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final key = cacheKey ?? 'direct_${id}_${sub}_$limit';
    try {
      return await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchFirestoreAccess.listOnce(
          module: moduleLabel,
          churchId: id,
          subcollectionName: sub,
          limit: limit,
          cacheKey: key,
        ),
        maxAttempts: kIsWeb ? 4 : 2,
      ).timeout(Duration(seconds: kIsWeb ? 90 : 24));
    } on TimeoutException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ChurchRepositoryException(
        'Falha ao carregar $sub: ${e.message ?? e.code}',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id/$sub',
      );
    } catch (e) {
      if (e is ChurchRepositoryException) rethrow;
      throw ChurchRepositoryException(
        'Falha ao carregar $sub: $e',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id/$sub',
      );
    }
  }



  /// Perfil público — **sem** scan de cluster (site + cadastro membro).
  static Future<({String docId, Map<String, dynamic> data})?> readIgrejaPublicProfile(
    String tenantId,
  ) async {
    final id = _directChurchDocId(tenantId);
    if (id.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => FirestoreReadResilience.getDocument(
          ChurchFirestoreAccess.churchDoc(id),
          cacheKey: 'igreja_public_$id',
          maxAttempts: kIsWeb ? 3 : 2,
          attemptTimeout: Duration(seconds: kIsWeb ? 8 : 6),
        ),
        maxAttempts: kIsWeb ? 3 : 2,
      ).timeout(Duration(seconds: kIsWeb ? 12 : 10));

      if (!snap.exists) return null;
      final raw = snap.data();
      return (
        docId: snap.id,
        data: raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw),
      );
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Doc raiz `igrejas/{id}` — leitura resiliente (cache + retry web).
  ///
  /// Retorna `null` apenas se o documento **não existir** ou o id estiver vazio.
  /// Falhas de rede/SDK propagam [ChurchRepositoryException] ou [TimeoutException].
  static Future<({String docId, Map<String, dynamic> data})?> readIgrejaDoc(
    String tenantId,
  ) async {
    final id = _directChurchDocId(tenantId);
    if (id.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => FirestoreReadResilience.getDocument(
          ChurchFirestoreAccess.churchDoc(id),
          cacheKey: 'igreja_direct_$id',
          maxAttempts: kIsWeb ? 4 : 2,
          attemptTimeout: Duration(seconds: kIsWeb ? 12 : 10),
        ),
        maxAttempts: 4,
      ).timeout(Duration(seconds: kIsWeb ? 90 : 24));

      if (!snap.exists) return null;
      final raw = snap.data();
      return (
        docId: snap.id,
        data: raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw),
      );
    } on TimeoutException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ChurchRepositoryException(
        'Falha ao carregar igreja: ${e.message ?? e.code}',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id',
      );
    } catch (e) {
      if (e is ChurchRepositoryException) rethrow;
      throw ChurchRepositoryException(
        'Falha ao carregar igreja: $e',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id',
      );
    }
  }

  /// Subdoc `igrejas/{id}/config/{configDocId}` — path directo.
  static Future<({String docId, Map<String, dynamic> data})?> readIgrejaConfig(
    String tenantId,
    String configDocId,
  ) async {
    final id = _directChurchDocId(tenantId);
    final cfgId = configDocId.trim();
    if (id.isEmpty || cfgId.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchFirestoreAccess.getDocument(
          module: 'Cadastro Igreja',
          churchId: id,
          subcollectionName: 'config',
          docId: cfgId,
        ),
        maxAttempts: 4,
      ).timeout(const Duration(seconds: 14));

      if (!snap.exists) return null;
      final raw = snap.data();
      if (raw == null || raw.isEmpty) return null;
      return (
        docId: id,
        data: Map<String, dynamic>.from(raw),
      );
    } on TimeoutException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ChurchRepositoryException(
        'Falha ao carregar config: ${e.message ?? e.code}',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id/config/$cfgId',
      );
    } catch (e) {
      if (e is ChurchRepositoryException) rethrow;
      throw ChurchRepositoryException(
        'Falha ao carregar config: $e',
        seedTenantId: tenantId.trim(),
        resolvedChurchId: id,
        firestorePath: 'igrejas/$id/config/$cfgId',
      );
    }
  }
}

