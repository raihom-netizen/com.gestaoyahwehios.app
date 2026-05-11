import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Pré-carrega leituras frequentes no **cache persistente do Firestore** (mobile/web)
/// após o login, para o painel funcionar melhor **sem rede** (dados já visitados +
/// filas de escrita — ver `configureFirestoreForOfflineAndSpeed` em `firestore_app_config.dart`).
///
/// Não substitui servidor: regras de segurança e quotas aplicam-se sempre que online.
/// Falhas parciais (permissão / índice) são ignoradas — outras coleções já aquecidas ajudam na mesma.
class ChurchTenantOfflineWarmupService {
  ChurchTenantOfflineWarmupService._();
  static final ChurchTenantOfflineWarmupService instance =
      ChurchTenantOfflineWarmupService._();

  /// Evita repetir o mesmo trabalho ao mudar de aba no shell.
  String? _sessionTenant;
  bool _warmupDoneThisSession = false;

  /// Chamado uma vez ao abrir [IgrejaCleanShell] com rede disponível.
  Future<void> scheduleWarmupAfterLogin(String tenantIdRaw) async {
    final tidIn = tenantIdRaw.trim();
    if (tidIn.isEmpty) return;
    if (!AppConnectivityService.instance.isOnline) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    if (_sessionTenant != tidIn) {
      _sessionTenant = tidIn;
      _warmupDoneThisSession = false;
    }
    if (_warmupDoneThisSession) return;

    _warmupDoneThisSession = true;
    unawaited(_runWarmup(tidIn));
  }

  Future<void> _runWarmup(String tenantIdRaw) async {
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (_) {}

    String tenantId = tenantIdRaw;
    try {
      final r = await TenantResolverService
          .resolveEffectiveTenantIdPreferringUserBinding(
        tenantIdRaw,
        userUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (r.trim().isNotEmpty) tenantId = r.trim();
    } catch (_) {}

    final db = FirebaseFirestore.instance;
    final church = db.collection('igrejas').doc(tenantId);

    Future<void> safe(String label, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('OfflineWarmup[$label] $e\n$st');
        }
      }
    }

    await safe('igreja_doc', () async {
      await church.get();
    });

    await safe('membros', () async {
      await church.collection('membros').limit(400).get();
    });

    await safe('members_legacy', () async {
      await church.collection('members').limit(120).get();
    });

    await safe('avisos', () async {
      await church.collection('avisos').limit(100).get();
    });

    await safe('noticias', () async {
      try {
        await church
            .collection('noticias')
            .orderBy('startAt', descending: true)
            .limit(150)
            .get();
      } catch (_) {
        await church.collection('noticias').limit(150).get();
      }
    });

    await safe('patrimonio', () async {
      await church.collection('patrimonio').limit(250).get();
    });

    await safe('users_tenant', () async {
      await db
          .collection('users')
          .where(Filter.or(
            Filter('tenantId', isEqualTo: tenantId),
            Filter('igrejaId', isEqualTo: tenantId),
          ))
          .limit(200)
          .get();
    });
  }
}
