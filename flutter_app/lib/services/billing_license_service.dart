import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Controle de licença no painel admin (Gestão Yahweh).
/// Igrejas: prorrogar prazo, alterar plano, remover/reativar.
/// Usuários (app): remover/reativar.
class BillingLicenseService {
  BillingLicenseService();

  final FirebaseFirestore _db = firebaseDefaultFirestore;

  static const int licensePeriodDaysMonthly = 30;
  static const int licensePeriodDaysAnnual = 365;

  /// Calcula vencimento após pagamento ou aplicação manual (30 ou 365 dias).
  static DateTime licensePeriodEndFrom(DateTime from, String billingCycle) {
    final cycle = billingCycle.toLowerCase().trim();
    final days = cycle == 'annual' || cycle == 'yearly'
        ? licensePeriodDaysAnnual
        : licensePeriodDaysMonthly;
    return from.add(Duration(days: days));
  }

  static DateTime _startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static Timestamp _tsNow() => Timestamp.now();

  Future<void> _runLicenseWrite(Future<void> Function() fn) async {
    await FirestoreWebGuard.prepareForCriticalWrite();
    await FirestoreWebGuard.runWithWebRecovery(fn, maxAttempts: 4);
  }

  // --- IGREJAS (licença por igreja) ---

  /// Prorroga o prazo da licença da igreja em [dias].
  Future<void> prorrogarPrazoIgreja(String igrejaId, int dias) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(igrejaId);
      final ref = ChurchOperationalPaths.churchDoc(op);
      final doc = await ref.get();
      final data = doc.data() ?? {};
      DateTime base = DateTime.now();
      final existing = data['licenseExpiresAt'];
      if (existing is Timestamp) {
        final dt = existing.toDate();
        if (dt.isAfter(DateTime.now())) base = dt;
      }
      await ref.update({
        'licenseExpiresAt': Timestamp.fromDate(base.add(Duration(days: dias))),
        'status': 'ativa',
        'updatedAt': _tsNow(),
      });
    });
  }

  /// Define o plano da igreja (free, premium, etc.).
  Future<void> setIgrejaPlano(String igrejaId, String plan) async {
    if (plan == 'free') {
      await setTenantFreeMaster(igrejaId);
      return;
    }
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(igrejaId);
      await ChurchOperationalPaths.churchDoc(op).update({
        'plano': plan,
        'status': 'ativa',
        'updatedAt': _tsNow(),
        'removedByAdminAt': FieldValue.delete(),
      });
    });
  }

  /// Marca igreja como removida/desativada (perde acesso). Pode reativar depois.
  Future<void> removerIgreja(String igrejaId) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(igrejaId);
      await ChurchOperationalPaths.churchDoc(op).update({
        'status': 'inativa',
        'updatedAt': _tsNow(),
        'removedByAdminAt': _tsNow(),
      });
    });
  }

  Future<DocumentReference<Map<String, dynamic>>> igrejaRef(String igrejaId) async =>
      ChurchOperationalPaths.churchDoc(
        await ChurchOperationalPaths.resolveCached(igrejaId),
      );

  Future<void> reativarIgreja(String igrejaId) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(igrejaId);
      await ChurchOperationalPaths.churchDoc(op).update({
        'status': 'ativa',
        'updatedAt': _tsNow(),
        'removedByAdminAt': FieldValue.delete(),
      });
    });
  }

  // --- TENANTS (painel master) ---

  Future<DocumentReference<Map<String, dynamic>>> tenantRef(String tenantId) async =>
      ChurchOperationalPaths.churchDoc(
        await ChurchOperationalPaths.resolveCached(tenantId),
      );

  Future<void> setTenantPlano(String tenantId, String plan,
      {DateTime? licenseExpiresAt}) async {
    if (plan == 'free') {
      await setTenantFreeMaster(tenantId);
      return;
    }
    await setTenantPlanAndLicenseExpiry(
      tenantId,
      plan,
      licenseExpiresAt: licenseExpiresAt,
    );
  }

  Future<void> setTenantLicenseExpiresAt(String tenantId, DateTime? date) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(tenantId);
      final ref = ChurchOperationalPaths.churchDoc(op);
      final patch = <String, dynamic>{
        'updatedAt': _tsNow(),
      };
      if (date == null) {
        patch['licenseExpiresAt'] = FieldValue.delete();
        patch['expiresAt'] = FieldValue.delete();
        patch['data_vencimento'] = FieldValue.delete();
      } else {
        final ts = Timestamp.fromDate(date);
        patch['licenseExpiresAt'] = ts;
        patch['expiresAt'] = ts;
        patch['data_vencimento'] = ts;
        patch['data_bloqueio'] = Timestamp.fromDate(
          date.add(const Duration(days: AppConstants.subscriptionGraceDays)),
        );
      }
      await ref.set(patch, SetOptions(merge: true));
    });
  }

  Future<void> removerTenant(String tenantId) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(tenantId);
      await ChurchOperationalPaths.churchDoc(op).set({
        'status': 'inativa',
        'updatedAt': _tsNow(),
        'removedByAdminAt': _tsNow(),
      }, SetOptions(merge: true));
    });
    try {
      await removerIgreja(tenantId);
    } catch (_) {}
  }

  Future<void> reativarTenant(String tenantId) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(tenantId);
      await ChurchOperationalPaths.churchDoc(op).set({
        'status': 'ativa',
        'updatedAt': _tsNow(),
        'removedByAdminAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    });
    try {
      await reativarIgreja(tenantId);
    } catch (_) {}
  }

  Future<void> excluirTenant(String tenantId) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(tenantId);
      await ChurchOperationalPaths.churchDoc(op).delete();
    });
  }

  Future<void> setTenantAdminBlocked(String tenantId, bool blocked) async {
    await applyMasterLicenseConfig(
      tenantId,
      isFreeMode: null,
      adminBlocked: blocked,
      touchBlockOnly: true,
    );
  }

  /// Painel master: igreja gratuita (sem bloqueio por licença).
  Future<void> setTenantFreeMaster(String tenantId, {bool adminBlocked = false}) async {
    await applyMasterLicenseConfig(
      tenantId,
      isFreeMode: true,
      adminBlocked: adminBlocked,
    );
  }

  /// Painel master: plano pago manual + vencimento e ciclo.
  Future<void> setTenantPlanAndLicenseExpiry(
    String tenantId,
    String planId, {
    DateTime? licenseExpiresAt,
    String? billingCycle,
    bool adminBlocked = false,
  }) async {
    await applyMasterLicenseConfig(
      tenantId,
      isFreeMode: false,
      planId: planId,
      licenseExpiresAt: licenseExpiresAt,
      billingCycle: billingCycle,
      adminBlocked: adminBlocked,
    );
  }

  /// Grava licença/plano/bloqueio via Cloud Function (Admin SDK — sem assert Firestore Web).
  ///
  /// [isFreeMode]: `true` = FREE, `false` = plano pago, `null` = só altera bloqueio.
  Future<void> applyMasterLicenseConfig(
    String tenantId, {
    required bool? isFreeMode,
    String? planId,
    DateTime? licenseExpiresAt,
    String? billingCycle,
    required bool adminBlocked,
    bool touchBlockOnly = false,
  }) async {
    final payload = <String, dynamic>{
      'tenantId': tenantId,
      'adminBlocked': adminBlocked,
      'touchBlockOnly': touchBlockOnly,
    };
    if (!touchBlockOnly && isFreeMode != null) {
      payload['isFreeMode'] = isFreeMode;
    }
    if (planId != null && planId.trim().isNotEmpty) {
      payload['planId'] = planId.trim();
    }
    if (licenseExpiresAt != null) {
      payload['licenseExpiresAtMs'] = licenseExpiresAt.millisecondsSinceEpoch;
    }
    if (billingCycle != null && billingCycle.trim().isNotEmpty) {
      payload['billingCycle'] = billingCycle.trim();
    }

    try {
      final callable =
          FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1')
          .httpsCallable('masterApplyTenantLicense');
      await callable.call(payload);
    } on FirebaseFunctionsException catch (e) {
      throw ArgumentError(
        e.message ?? 'Não foi possível salvar a licença da igreja.',
      );
    }
  }

  Future<void> _syncSubscriptionsBlockFlag(String tenantId, bool blocked) async {
    try {
      final snap = await _db
          .collection('subscriptions')
          .where('igrejaId', isEqualTo: tenantId)
          .limit(8)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.set({
          'adminBlocked': blocked,
          'updatedAt': _tsNow(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _syncSubscriptionsForFreeTenant(
    String tenantId, {
    bool adminBlocked = false,
  }) async {
    try {
      final snap = await _db
          .collection('subscriptions')
          .where('igrejaId', isEqualTo: tenantId)
          .limit(8)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.set({
          'status': 'ACTIVE',
          'status_assinatura': 'active',
          'planId': 'free',
          'plano': 'free',
          'isFree': true,
          'adminBlocked': adminBlocked,
          'updatedAt': _tsNow(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _syncSubscriptionsForPaidTenant(
    String tenantId, {
    required String planId,
    required DateTime expiresAt,
    required String billingCycle,
    bool adminBlocked = false,
  }) async {
    try {
      final snap = await _db
          .collection('subscriptions')
          .where('igrejaId', isEqualTo: tenantId)
          .limit(8)
          .get();
      final ts = Timestamp.fromDate(expiresAt);
      final payload = {
        'status': 'ACTIVE',
        'status_assinatura': 'active',
        'planId': planId,
        'plano': planId,
        'isFree': false,
        'adminBlocked': adminBlocked,
        'billingCycle': billingCycle,
        'data_vencimento': ts,
        'nextChargeAt': ts,
        'currentPeriodEnd': ts,
        'updatedAt': _tsNow(),
      };
      if (snap.docs.isEmpty) {
        await _db.collection('subscriptions').add({
          ...payload,
          'igrejaId': tenantId,
          'createdAt': _tsNow(),
        });
      } else {
        for (final doc in snap.docs) {
          await doc.reference.set(payload, SetOptions(merge: true));
        }
      }
    } catch (_) {}
  }

  Future<void> removerIgrejaELimparDados(String tenantId) async {
    final op = await ChurchOperationalPaths.resolveCached(tenantId);
    final ref = ChurchOperationalPaths.churchDoc(op);
    final batchLimit = 400;

    Future<void> deleteCollection(
      CollectionReference<Map<String, dynamic>> col, {
      Future<void> Function(DocumentReference<Map<String, dynamic>>)?
          beforeDeleteDoc,
    }) async {
      QuerySnapshot<Map<String, dynamic>> snap;
      do {
        snap = await col.limit(batchLimit).get();
        for (final doc in snap.docs) {
          if (beforeDeleteDoc != null) await beforeDeleteDoc(doc.reference);
        }
        final batch = _db.batch();
        for (final doc in snap.docs) batch.delete(doc.reference);
        if (snap.docs.isNotEmpty) await batch.commit();
      } while (snap.docs.length >= batchLimit);
    }

    final root = ref;

    Future<void> deleteNoticiasLike(
        CollectionReference<Map<String, dynamic>> col) async {
      await deleteCollection(col, beforeDeleteDoc: (docRef) async {
        await deleteCollection(docRef.collection('comentarios'));
        await deleteCollection(docRef.collection('comments'));
        await deleteCollection(docRef.collection('curtidas'));
        await deleteCollection(docRef.collection('confirmacoes'));
      });
    }

    await deleteNoticiasLike(root.collection('eventos'));
    await deleteNoticiasLike(root.collection('avisos'));
    await deleteCollection(root.collection('visitantes'),
        beforeDeleteDoc: (docRef) async {
      await deleteCollection(docRef.collection('followups'));
    });
    await deleteCollection(root.collection('cultos'),
        beforeDeleteDoc: (docRef) async {
      await deleteCollection(docRef.collection('presencas'));
    });

    for (final name in [
      'members',
      'membros',
      'event_templates',
      'config',
      'departamentos',
      'patrimonio',
      'finance',
      'categorias_receitas',
      'categorias_despesas',
      'contas',
      'despesas_fixas',
      'receitas_recorrentes',
      'usersIndex',
      'users',
      'fleet_vehicles',
      'fleet_fuelings',
      'fleet_documents',
      'eventos',
      'pedidosOracao',
      'abastecimentos',
      'combustiveis',
      'veiculos',
      'certificados_emitidos',
      'certificados_historico',
    ]) {
      await deleteCollection(root.collection(name));
    }

    await _runLicenseWrite(() async {
      await ref.delete();
    });

    try {
      final subRef = _db.collection('subscriptions');
      final subSnap = await subRef.where('igrejaId', isEqualTo: tenantId).get();
      final batch = _db.batch();
      for (final d in subSnap.docs) batch.delete(d.reference);
      if (subSnap.docs.isNotEmpty) await batch.commit();
    } catch (_) {}
  }

  Future<void> prorrogarTenant(String tenantId, int dias) async {
    await _runLicenseWrite(() async {
      final op = await ChurchOperationalPaths.resolveCached(tenantId);
      final ref = ChurchOperationalPaths.churchDoc(op);
      final doc = await ref.get();
      final data = doc.data() ?? {};
      DateTime base = DateTime.now();
      final existing = data['licenseExpiresAt'];
      if (existing is Timestamp) {
        final dt = existing.toDate();
        if (dt.isAfter(DateTime.now())) base = dt;
      }
      final novaData = base.add(Duration(days: dias));
      final ts = Timestamp.fromDate(novaData);
      await ref.set({
        'licenseExpiresAt': ts,
        'expiresAt': ts,
        'data_vencimento': ts,
        'data_bloqueio': Timestamp.fromDate(
          novaData.add(const Duration(days: AppConstants.subscriptionGraceDays)),
        ),
        'status': 'ativa',
        'updatedAt': _tsNow(),
      }, SetOptions(merge: true));
    });
  }

  // --- USUÁRIOS (app: removido/reativar) ---

  Future<void> removerUsuario(String uid) async {
    await _runLicenseWrite(() async {
      await _db.collection('usuarios').doc(uid).update({
        'updatedAt': _tsNow(),
        'removedByAdminAt': _tsNow(),
      });
    });
  }

  Future<void> reativarUsuario(String uid) async {
    await _runLicenseWrite(() async {
      await _db.collection('usuarios').doc(uid).update({
        'updatedAt': _tsNow(),
        'removedByAdminAt': FieldValue.delete(),
      });
    });
  }
}
