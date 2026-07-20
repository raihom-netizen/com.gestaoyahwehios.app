import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_binding_repair_coordinator.dart';

/// Garante vínculo Auth → `users/{uid}` → claims antes de leituras do painel.
///
/// Sem isto, regras `canAccessTenant` devolvem `permission-denied` em **todos**
/// os módulos (membros, dept, cargos, financeiro, …).
abstract final class ChurchPanelAccessBootstrap {
  ChurchPanelAccessBootstrap._();

  static DateTime? _lastOkAt;
  static Completer<void>? _repairFlight;
  static const Duration _sessionOkTtl = Duration(minutes: 30);

  /// Limpa cache de sessão (ex.: «Trocar de conta») para forçar repair no próximo login.
  static void resetSession() {
    _lastOkAt = null;
  }

  /// Repara claims + doc `users/{uid}` via Cloud Function (gestor/membro).
  static Future<void> ensureFirestoreAccess({
    bool force = false,
    String? churchIdHint,
  }) async {
    if (EcoFireFlow.disableRepairMyChurchBinding) return;
    if (!AppConnectivityService.instance.isOnline) return;

    final user = firebaseDefaultAuth.currentUser;
    if (user == null || user.isAnonymous) return;

    if (!force &&
        _lastOkAt != null &&
        DateTime.now().difference(_lastOkAt!) < _sessionOkTtl) {
      return;
    }

    if (!force &&
        await ChurchBindingRepairCoordinator.conservativeChurchBindingLooksOk(
          user,
        )) {
      _lastOkAt = DateTime.now();
      return;
    }

    if (!force &&
        await ChurchBindingRepairCoordinator.shouldSkipRepairDueToRecentSuccess(
          user.uid,
        )) {
      _lastOkAt = DateTime.now();
      return;
    }

    // Vários callers (shell + Membros) aguardam o **mesmo** repair — não retornar cedo.
    if (_repairFlight != null) {
      return _repairFlight!.future;
    }

    _repairFlight = Completer<void>();
    try {
      final fn = FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'us-central1',
      ).httpsCallable(
        'repairMyChurchBinding',
        options: HttpsCallableOptions(
          // Web: cap curto — não bloquear painel 35s+ no login.
          timeout: Duration(seconds: kIsWeb ? 12 : 30),
        ),
      );
      await fn.call(<String, dynamic>{}).timeout(
        Duration(seconds: kIsWeb ? 12 : 32),
      );
      // Happy path: força token novo na Web (claims alinhados às regras).
      await user.getIdToken(kIsWeb);
      await ChurchBindingRepairCoordinator.recordRepairSuccess(user.uid);
      _lastOkAt = DateTime.now();
      debugPrint(
        'ChurchPanelAccessBootstrap: repair OK uid=${user.uid} '
        'churchHint=${churchIdHint ?? ''}',
      );
    } on FirebaseFunctionsException catch (e, st) {
      debugPrint(
        'ChurchPanelAccessBootstrap: repair fail ${e.code} ${e.message}\n$st',
      );
    } on TimeoutException catch (e) {
      debugPrint('ChurchPanelAccessBootstrap: repair timeout $e');
    } catch (e, st) {
      debugPrint('ChurchPanelAccessBootstrap: $e\n$st');
    } finally {
      if (_repairFlight != null && !_repairFlight!.isCompleted) {
        _repairFlight!.complete();
      }
      _repairFlight = null;
    }
  }
}
