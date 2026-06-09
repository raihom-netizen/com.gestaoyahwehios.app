import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Migração silenciosa ao abrir o app — sem UI «Sincronizando».
///
/// - Redireciona seeds legados → doc canónico
/// - Copia subcoleções legadas (`noticias` → `eventos`) se destino vazio
/// - Valida alinhamento Firestore ↔ Storage
abstract final class TenantMigrationService {
  TenantMigrationService._();

  static const int _batchLimit = 80;
  static final Set<String> _migratedThisSession = {};

  static const _legacyPathTokens = <String>[
    'tenants/',
    'church_aliases',
    'church_roots',
    'organizations/',
    'organizationId',
    'companyId',
    'siteId',
  ];

  /// Chamado após [ChurchContext.bind] — idempotente por sessão/churchId.
  static Future<TenantMigrationReport> runAfterBind({
    String? churchIdHint,
    String? seedHint,
  }) async {
    final churchId = ChurchContext.resolveChurchId(churchIdHint);
    if (churchId.isEmpty) {
      return TenantMigrationReport(
        churchId: '',
        skipped: true,
        reason: 'churchId vazio',
      );
    }
    if (_migratedThisSession.contains(churchId)) {
      return TenantMigrationReport(
        churchId: churchId,
        skipped: true,
        reason: 'já migrado nesta sessão',
      );
    }

    final seed = (seedHint ?? ChurchContext.seedId ?? churchId).trim();
    final canonical = TenantResolverService.syncStorageTenantId(seed);
    final report = TenantMigrationReport(
      churchId: churchId,
      canonicalId: canonical.isNotEmpty ? canonical : churchId,
      seed: seed,
    );

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    try {
      if (seed != churchId && TenantResolverService.kBpcLegacyTenantIds.contains(seed)) {
        report.legacySeedRedirected = true;
        debugPrint(
          'TENANT_MIGRATION legacy seed=$seed → churchId=$churchId',
        );
      }

      await _migrateNoticiasToEventosIfNeeded(churchId, report);
      await _probeCanonicalCollections(churchId, report);
      report.storageAligned = ChurchContext.storageRoot == 'igrejas/$churchId';
      report.completedAt = DateTime.now();
      _migratedThisSession.add(churchId);
    } catch (e, st) {
      report.error = '$e';
      debugPrint('TENANT_MIGRATION error churchId=$churchId: $e\n$st');
    }

    debugPrint(report.summaryLine());
    return report;
  }

  static Future<void> _migrateNoticiasToEventosIfNeeded(
    String churchId,
    TenantMigrationReport report,
  ) async {
    final eventosSnap = await ChurchFirestoreAccess.listOnce(
      module: 'TenantMigration-eventos',
      churchId: churchId,
      subcollectionName: ChurchDataPaths.eventos,
      limit: 1,
    );
    if (eventosSnap.docs.isNotEmpty) return;

    final legacySnap = await ChurchFirestoreAccess.listOnce(
      module: 'TenantMigration-noticias',
      churchId: churchId,
      subcollectionName: ChurchDataPaths.legacyEventosNoticias,
      limit: _batchLimit,
    );
    if (legacySnap.docs.isEmpty) return;

    var copied = 0;
    for (final doc in legacySnap.docs) {
      final data = doc.data();
      await ChurchFirestoreAccess.setDocument(
        module: 'TenantMigration-copy-evento',
        churchId: churchId,
        subcollectionName: ChurchDataPaths.eventos,
        docId: doc.id,
        data: {
          ...data,
          '_migratedFrom': ChurchDataPaths.legacyEventosNoticias,
          '_migratedAt': FieldValue.serverTimestamp(),
        },
      );
      copied++;
    }
    report.noticiasCopiedToEventos = copied;
    if (copied > 0) {
      debugPrint('TENANT_MIGRATION noticias→eventos copied=$copied churchId=$churchId');
    }
  }

  static Future<void> _probeCanonicalCollections(
    String churchId,
    TenantMigrationReport report,
  ) async {
    final probes = <String, int>{};
    for (final sub in ChurchDataPaths.allSubcollections) {
      try {
        final snap = await ChurchFirestoreAccess.listOnce(
          module: 'TenantMigration-probe',
          churchId: churchId,
          subcollectionName: sub,
          limit: 3,
        );
        probes[sub] = snap.docs.length;
      } catch (_) {
        probes[sub] = 0;
      }
      if (kIsWeb) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    report.collectionSamples = probes;
  }

  static bool pathLooksLegacy(String path) {
    final p = path.toLowerCase();
    for (final token in _legacyPathTokens) {
      if (p.contains(token.toLowerCase())) return true;
    }
    return false;
  }
}

class TenantMigrationReport {
  TenantMigrationReport({
    required this.churchId,
    this.canonicalId,
    this.seed,
    this.skipped = false,
    this.reason,
    this.legacySeedRedirected = false,
    this.noticiasCopiedToEventos = 0,
    this.storageAligned = false,
    this.collectionSamples = const {},
    this.completedAt,
    this.error,
  });

  final String churchId;
  final String? canonicalId;
  final String? seed;
  final bool skipped;
  final String? reason;
  bool legacySeedRedirected;
  int noticiasCopiedToEventos;
  bool storageAligned;
  Map<String, int> collectionSamples;
  DateTime? completedAt;
  String? error;

  bool get ok => error == null && !skipped;

  String summaryLine() => 'TENANT_MIGRATION churchId=$churchId '
      'canonical=$canonicalId storageAligned=$storageAligned '
      'noticiasCopied=$noticiasCopiedToEventos legacySeed=$legacySeedRedirected '
      'err=${error ?? "-"}';
}
