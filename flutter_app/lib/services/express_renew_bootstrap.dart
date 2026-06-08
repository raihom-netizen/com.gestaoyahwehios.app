import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/plan_price_service.dart'
    show EffectivePlanConfig, PlanPriceService;

/// Pré-aquece tenant, igreja e catálogo de planos antes de [RenewPlanPage]
/// (web, Android, `/atualizar-plano`) para checkout anual + cartão mais rápido.
class ExpressRenewBootstrap {
  ExpressRenewBootstrap._();
  static final ExpressRenewBootstrap instance = ExpressRenewBootstrap._();

  String? _cachedTenantId;
  Map<String, dynamic>? _cachedChurchData;
  Map<String, EffectivePlanConfig>? _cachedPlans;
  Future<void>? _warmInFlight;

  Map<String, dynamic>? get cachedChurchData => _cachedChurchData;
  Map<String, EffectivePlanConfig>? get cachedPlans => _cachedPlans;
  String? get cachedTenantId => _cachedTenantId;

  static String tenantFromClaims(Map<dynamic, dynamic>? claims) {
    return (claims?['igrejaId'] ?? claims?['tenantId'] ?? '')
        .toString()
        .trim();
  }

  void rememberTenantId(String id) {
    final t = id.trim();
    if (t.isNotEmpty) _cachedTenantId = t;
  }

  /// Claims em cache; só força refresh se [forceRefresh] ou ainda vazio.
  Future<String?> resolveTenantId({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedTenantId != null &&
        _cachedTenantId!.isNotEmpty) {
      return _cachedTenantId;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    var tr = await user.getIdTokenResult(false);
    var id = tenantFromClaims(tr.claims);
    if (id.isEmpty) {
      tr = await user.getIdTokenResult(true);
      id = tenantFromClaims(tr.claims);
    }
    if (id.isNotEmpty) {
      _cachedTenantId = id;
      return id;
    }
    return null;
  }

  /// Paraleliza preços + tenant + doc da igreja (cache Firestore quando possível).
  Future<void> warmUp() {
    final existing = _warmInFlight;
    if (existing != null) return existing;
    final job = _doWarmUp();
    _warmInFlight = job;
    return job.whenComplete(() {
      if (identical(_warmInFlight, job)) _warmInFlight = null;
    });
  }

  Future<void> _doWarmUp() async {
    final plansFuture = PlanPriceService.getEffectivePlanConfigs();
    final tenantFuture = resolveTenantId();
    try {
      _cachedPlans = await plansFuture;
    } catch (_) {}
    final tenantId = await tenantFuture;
    if (tenantId == null || tenantId.isEmpty) return;
    try {
      final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
      final snap = await           ChurchOperationalPaths.churchDoc(op)
          .get(const GetOptions(source: Source.serverAndCache));
      _cachedChurchData = snap.data();
    } catch (_) {}
  }

  void clear() {
    _cachedTenantId = null;
    _cachedChurchData = null;
    _cachedPlans = null;
    _warmInFlight = null;
  }
}
