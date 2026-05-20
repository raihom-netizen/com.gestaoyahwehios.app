import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart';

/// Resultado da verificação de limite de membros para o tenant.
class MembersLimitResult {
  final int currentCount;
  final int planLimit;
  final int hardLimit; // planLimit + membersGraceOverLimit
  final String planId;
  final String planName;

  const MembersLimitResult({
    required this.currentCount,
    required this.planLimit,
    required this.hardLimit,
    required this.planId,
    required this.planName,
  });

  /// Ainda pode cadastrar (dentro do limite + 5).
  bool get canAdd => currentCount < hardLimit;

  /// Está bloqueado: passou do limite + 5.
  bool get isBlocked => !canAdd;

  /// Está no aviso: passou do limite do plano mas ainda dentro da tolerância de 5.
  bool get isOverLimitWarning => currentCount >= planLimit && currentCount < hardLimit;

  /// Quantas vagas restam antes de bloquear (pode ser negativo se já bloqueado).
  int get slotsLeftBeforeBlock => hardLimit - currentCount;

  /// Quantas vagas restam dentro do plano (sem contar os 5 de tolerância).
  int get slotsLeftInPlan => planLimit - currentCount;

  /// Mensagem curta para banner/aviso.
  /// Em iOS sob o gate (Apple 3.1.3), texto orienta a "atualizar plano"
  /// (que leva ao site externo) sem call-to-action interno de compra.
  String get shortMessage {
    final iosReader = IosPaymentsGate.shouldHidePayments;
    if (isBlocked) {
      return iosReader
          ? 'Limite do plano atingido. Atualize seu plano para cadastrar novos membros.'
          : 'Limite do plano atingido. Faça upgrade para cadastrar novos membros.';
    }
    if (isOverLimitWarning) {
      final rest = slotsLeftBeforeBlock;
      return 'Você está $rest cadastro(s) do bloqueio. Atualize seu plano.';
    }
    if (planLimit > 0 && slotsLeftInPlan <= 10 && slotsLeftInPlan > 0) {
      return 'Faltam $slotsLeftInPlan membros para o limite do plano.';
    }
    if (planLimit > 0) {
      return '$currentCount de $planLimit membros (plano $planName).';
    }
    return '$currentCount membros cadastrados.';
  }

  /// Mensagem para diálogo quando bloqueado.
  /// Em iOS sob o gate, evita o termo "Assinatura" (menu interno) e orienta
  /// o usuario a usar o botao "Atualizar plano" — que leva ao site externo.
  String get blockedDialogMessage {
    if (IosPaymentsGate.shouldHidePayments) {
      return 'Seu plano ($planName) permite até $planLimit membros. '
          'Você já utilizou a tolerância de '
          '${AppConstants.membersGraceOverLimit} membros a mais. '
          'Para cadastrar novos membros, atualize seu plano.';
    }
    return 'Seu plano ($planName) permite até $planLimit membros. '
        'Você já utilizou a tolerância de ${AppConstants.membersGraceOverLimit} membros a mais. '
        'Para cadastrar novos membros, faça upgrade do plano em Assinatura.';
  }
}

/// Serviço para verificar limite de membros por plano e exibir avisos/bloqueio.
class MembersLimitService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Obtém o limite do plano pelo id (planos oficiais).
  static int getPlanLimit(String planId) {
    try {
      final p = planosOficiais.firstWhere((x) => x.id == planId);
      return p.maxMembers;
    } catch (_) {
      return 0;
    }
  }

  static String getPlanName(String planId) {
    try {
      final p = planosOficiais.firstWhere((x) => x.id == planId);
      return p.name;
    } catch (_) {
      return planId;
    }
  }

  /// Total em `_panel_cache` (dashboard ou members_directory) — evita varrer coleções na abertura.
  Future<int?> _cachedMembersTotalCount(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    try {
      final snap = await _db
          .collection('igrejas')
          .doc(tid)
          .collection('_panel_cache')
          .doc('dashboard_summary')
          .get();
      final n = snap.data()?['membersTotalCount'];
      if (n is num && n >= 0) return n.toInt();
    } catch (_) {}
    try {
      final snap = await _db
          .collection('igrejas')
          .doc(tid)
          .collection('_panel_cache')
          .doc('members_directory')
          .get();
      final n = snap.data()?['totalCount'];
      if (n is num && n >= 0) return n.toInt();
    } catch (_) {}
    return null;
  }

  /// Conta membros do tenant: igrejas/tenantId/membros + igrejas/tenantId/members (legado, até migração) + users.
  /// [maxPerSource] limita a leitura por coleção para não carregar milhares de docs (ex.: planLimit + 200).
  Future<int> countMembers(String tenantId, {int? maxPerSource}) async {
    final limit = maxPerSource ?? 2500;
    final ids = <String>{};
    try {
      final membrosSnap = await _db
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .limit(limit)
          .get();
      for (final d in membrosSnap.docs) ids.add(d.id);
    } catch (_) {}
    try {
      final membersSnap = await _db
          .collection('igrejas')
          .doc(tenantId)
          .collection('members')
          .limit(limit)
          .get();
      for (final d in membersSnap.docs) ids.add(d.id);
    } catch (_) {}
    try {
      final usersByTenant = await _db
          .collection('users')
          .where('tenantId', isEqualTo: tenantId)
          .limit(limit)
          .get();
      final usersByIgreja = await _db
          .collection('users')
          .where('igrejaId', isEqualTo: tenantId)
          .limit(limit)
          .get();
      for (final d in usersByTenant.docs) ids.add(d.id);
      for (final d in usersByIgreja.docs) ids.add(d.id);
    } catch (_) {}
    return ids.length;
  }

  /// Obtém planId do tenant (tenant doc ou subscription).
  Future<String> getPlanIdForTenant(String tenantId) async {
    final tenantSnap = await _db.collection('igrejas').doc(tenantId).get();
    final tenantData = tenantSnap.data();
    String planId = (tenantData?['planId'] ?? tenantData?['plan'] ?? '').toString().trim();
    if (planId.isNotEmpty) return planId;
    try {
      final subSnap = await _db
          .collection('subscriptions')
          .where('igrejaId', isEqualTo: tenantId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (subSnap.docs.isNotEmpty) {
        planId = (subSnap.docs.first.data()['planId'] ?? '').toString().trim();
      }
    } catch (_) {
      // Visitante / papel sem leitura em `subscriptions` — não bloquear fluxos que só precisam de um planId fallback.
    }
    return planId.isNotEmpty ? planId : 'inicial';
  }

  /// Verifica limite e retorna resultado para avisos e bloqueio.
  Future<MembersLimitResult> checkLimit(
    String tenantId, {
    String? planIdOverride,
  }) async {
    final planId = planIdOverride ?? await getPlanIdForTenant(tenantId);
    final configs = await PlanPriceService.getEffectivePlanConfigs();
    final cfg = configs[planId];
    final planLimit = cfg?.maxMembers ?? getPlanLimit(planId);
    final maxPerSource = planLimit > 0 ? planLimit + 200 : 2500;
    final cached = await _cachedMembersTotalCount(tenantId);
    final currentCount = cached ??
        await countMembers(tenantId, maxPerSource: maxPerSource);
    final hardLimit = planLimit > 0 ? planLimit + AppConstants.membersGraceOverLimit : 99999;
    final planName = cfg?.name ?? getPlanName(planId);
    return MembersLimitResult(
      currentCount: currentCount,
      planLimit: planLimit,
      hardLimit: hardLimit,
      planId: planId,
      planName: planName,
    );
  }
}
