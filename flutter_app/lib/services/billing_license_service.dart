import 'package:cloud_firestore/cloud_firestore.dart';

/// Controle de licença no painel admin (Gestão Yahweh).
/// Igrejas: prorrogar prazo, alterar plano, remover/reativar.
/// Usuários (app): remover/reativar.
class BillingLicenseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- IGREJAS (licença por igreja) ---

  /// Prorroga o prazo da licença da igreja em [dias].
  Future<void> prorrogarPrazoIgreja(String igrejaId, int dias) async {
    final ref = _db.collection('igrejas').doc(igrejaId);
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Define o plano da igreja (free, premium, etc.).
  Future<void> setIgrejaPlano(String igrejaId, String plan) async {
    final ref = _db.collection('igrejas').doc(igrejaId);
    if (plan == 'free') {
      await ref.update({
        'plano': 'free',
        'status': 'ativa',
        'updatedAt': FieldValue.serverTimestamp(),
        'licenseExpiresAt': FieldValue.delete(),
      });
    } else {
      await ref.update({
        'plano': plan,
        'status': 'ativa',
        'updatedAt': FieldValue.serverTimestamp(),
        'removedByAdminAt': FieldValue.delete(),
      });
    }
  }

  /// Marca igreja como removida/desativada (perde acesso). Pode reativar depois.
  Future<void> removerIgreja(String igrejaId) async {
    await _db.collection('igrejas').doc(igrejaId).update({
      'status': 'inativa',
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.serverTimestamp(),
    });
  }

  /// Retorna referência da igreja (para recarregar lista após alteração).
  DocumentReference<Map<String, dynamic>> igrejaRef(String igrejaId) =>
      _db.collection('igrejas').doc(igrejaId);

  /// Reativa igreja removida.
  Future<void> reativarIgreja(String igrejaId) async {
    await _db.collection('igrejas').doc(igrejaId).update({
      'status': 'ativa',
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.delete(),
    });
  }

  // --- TENANTS (painel master: lista igrejas/gestores; edição de licença) ---

  /// Retorna referência do tenant.
  DocumentReference<Map<String, dynamic>> tenantRef(String tenantId) =>
      _db.collection('igrejas').doc(tenantId);

  /// Define plano do tenant (free, premium, etc.) e opcionalmente data de vencimento.
  Future<void> setTenantPlano(String tenantId, String plan, {DateTime? licenseExpiresAt}) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    if (plan == 'free') {
      await ref.update({
        'plano': 'free',
        'status': 'ativa',
        'updatedAt': FieldValue.serverTimestamp(),
        'removedByAdminAt': FieldValue.delete(),
        'licenseExpiresAt': FieldValue.delete(),
      });
    } else {
      final data = <String, dynamic>{
        'plano': plan,
        'status': 'ativa',
        'updatedAt': FieldValue.serverTimestamp(),
        'removedByAdminAt': FieldValue.delete(),
      };
      if (licenseExpiresAt != null) data['licenseExpiresAt'] = Timestamp.fromDate(licenseExpiresAt);
      await ref.set(data, SetOptions(merge: true));
    }
    try {
      if (plan == 'free') {
        await _db.collection('igrejas').doc(tenantId).update({
          'plano': 'free', 'status': 'ativa', 'updatedAt': FieldValue.serverTimestamp(),
          'removedByAdminAt': FieldValue.delete(), 'licenseExpiresAt': FieldValue.delete(),
        });
      } else {
        final data = <String, dynamic>{
          'plano': plan, 'status': 'ativa', 'updatedAt': FieldValue.serverTimestamp(),
          'removedByAdminAt': FieldValue.delete(),
        };
        if (licenseExpiresAt != null) data['licenseExpiresAt'] = Timestamp.fromDate(licenseExpiresAt);
        await _db.collection('igrejas').doc(tenantId).set(data, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  /// Define apenas a data de vencimento da licença do tenant.
  Future<void> setTenantLicenseExpiresAt(String tenantId, DateTime? date) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    if (date == null) {
      await ref.update({
        'licenseExpiresAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.set({
        'licenseExpiresAt': Timestamp.fromDate(date),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    try {
      await _db.collection('igrejas').doc(tenantId).set({
        'licenseExpiresAt': date != null ? Timestamp.fromDate(date) : FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Marca tenant como removido (soft). Pode reativar depois.
  Future<void> removerTenant(String tenantId) async {
    await _db.collection('igrejas').doc(tenantId).set({
      'status': 'inativa',
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await removerIgreja(tenantId);
    } catch (_) {}
  }

  /// Reativa tenant removido.
  Future<void> reativarTenant(String tenantId) async {
    await _db.collection('igrejas').doc(tenantId).set({
      'status': 'ativa',
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.delete(),
    }, SetOptions(merge: true));
    try {
      await reativarIgreja(tenantId);
    } catch (_) {}
  }

  /// Exclui permanentemente o documento do tenant (limpar banco quando igreja não quer mais). Use com confirmação.
  Future<void> excluirTenant(String tenantId) async {
    await _db.collection('igrejas').doc(tenantId).delete();
  }

  /// Painel master: bloquear/desbloquear igreja (só tela de renovação no app).
  Future<void> setTenantAdminBlocked(String tenantId, bool blocked) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final lic = Map<String, dynamic>.from(data['license'] is Map ? data['license'] as Map : {});
    lic['adminBlocked'] = blocked;
    lic['updatedAt'] = FieldValue.serverTimestamp();
    await ref.set({
      'adminBlocked': blocked,
      'license': lic,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Painel master: igreja gratuita (sem bloqueio por licença).
  Future<void> setTenantFreeMaster(String tenantId) async {
    await _db.collection('igrejas').doc(tenantId).set({
      'plano': 'free',
      'planId': 'free',
      'adminBlocked': false,
      'status': 'ativa',
      'license': {
        'isFree': true,
        'active': true,
        'status': 'active',
        'adminBlocked': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'billing': {'status': 'paid', 'provider': 'master_manual'},
      'licenseExpiresAt': FieldValue.delete(),
      'removedByAdminAt': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Painel master: plano pago manual + opcional vencimento e ciclo.
  Future<void> setTenantPlanAndLicenseExpiry(
    String tenantId,
    String planId, {
    DateTime? licenseExpiresAt,
    String? billingCycle,
  }) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    final lic = <String, dynamic>{
      'isFree': false,
      'active': true,
      'status': 'active',
      'adminBlocked': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final patch = <String, dynamic>{
      'plano': planId,
      'planId': planId,
      'adminBlocked': false,
      'status': 'ativa',
      'license': lic,
      'billing': {'status': 'paid', 'provider': 'master_manual'},
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.delete(),
    };
    if (billingCycle != null && billingCycle.isNotEmpty) {
      patch['billingCycle'] = billingCycle;
    }
    if (licenseExpiresAt != null) {
      final ts = Timestamp.fromDate(licenseExpiresAt);
      patch['licenseExpiresAt'] = ts;
      lic['expiresAt'] = ts;
    }
    await ref.set(patch, SetOptions(merge: true));
  }

  /// Remove a igreja e limpa todos os dados vinculados (subcoleções do tenant) para liberar espaço no banco. Irreversível.
  Future<void> removerIgrejaELimparDados(String tenantId) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    final batchLimit = 400;

    Future<void> deleteCollection(CollectionReference<Map<String, dynamic>> col, {Future<void> Function(DocumentReference<Map<String, dynamic>>)? beforeDeleteDoc}) async {
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

    Future<void> deleteNoticiasLike(CollectionReference<Map<String, dynamic>> col) async {
      await deleteCollection(col, beforeDeleteDoc: (docRef) async {
        await deleteCollection(docRef.collection('comentarios'));
        await deleteCollection(docRef.collection('comments'));
        await deleteCollection(docRef.collection('curtidas'));
        await deleteCollection(docRef.collection('confirmacoes'));
      });
    }

    await deleteNoticiasLike(root.collection('noticias'));
    await deleteNoticiasLike(root.collection('avisos'));
    await deleteCollection(root.collection('visitantes'), beforeDeleteDoc: (docRef) async {
      await deleteCollection(docRef.collection('followups'));
    });
    await deleteCollection(root.collection('cultos'), beforeDeleteDoc: (docRef) async {
      await deleteCollection(docRef.collection('presencas'));
    });

    for (final name in [
      'members', 'membros', 'event_templates', 'config', 'departamentos', 'patrimonio',
      'finance', 'categorias_receitas', 'categorias_despesas', 'contas', 'despesas_fixas',
      'usersIndex', 'users', 'fleet_vehicles', 'fleet_fuelings', 'fleet_documents',
      'eventos', 'pedidosOracao',
      'abastecimentos', 'combustiveis', 'veiculos',
      'certificados_emitidos', 'certificados_historico',
    ]) {
      await deleteCollection(root.collection(name));
    }

    await ref.delete();

    try {
      final subRef = _db.collection('subscriptions');
      final subSnap = await subRef.where('igrejaId', isEqualTo: tenantId).get();
      final batch = _db.batch();
      for (final d in subSnap.docs) batch.delete(d.reference);
      if (subSnap.docs.isNotEmpty) await batch.commit();
    } catch (_) {}
  }

  /// Prorroga o prazo da licença do tenant em [dias].
  Future<void> prorrogarTenant(String tenantId, int dias) async {
    final ref = _db.collection('igrejas').doc(tenantId);
    final doc = await ref.get();
    final data = doc.data() ?? {};
    DateTime base = DateTime.now();
    final existing = data['licenseExpiresAt'];
    if (existing is Timestamp) {
      final dt = existing.toDate();
      if (dt.isAfter(DateTime.now())) base = dt;
    }
    final novaData = base.add(Duration(days: dias));
    await ref.set({
      'licenseExpiresAt': Timestamp.fromDate(novaData),
      'status': 'ativa',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _db.collection('igrejas').doc(tenantId).set({
        'licenseExpiresAt': Timestamp.fromDate(novaData),
        'status': 'ativa',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // --- USUÁRIOS (app: removido/reativar) ---

  /// Marca usuário como removido (perde acesso ao app).
  Future<void> removerUsuario(String uid) async {
    await _db.collection('usuarios').doc(uid).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reativa usuário removido.
  Future<void> reativarUsuario(String uid) async {
    await _db.collection('usuarios').doc(uid).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'removedByAdminAt': FieldValue.delete(),
    });
  }
}
