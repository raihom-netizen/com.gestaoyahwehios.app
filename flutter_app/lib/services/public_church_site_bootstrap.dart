import 'dart:async' show unawaited;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/data/yahweh_data_repository.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/panel_public_site_snapshot_service.dart';
import 'package:gestao_yahweh/services/public_church_slug_resolver.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Bootstrap único — site público + cadastro membro (Web = Android = iOS).
abstract final class PublicChurchSiteBootstrap {
  PublicChurchSiteBootstrap._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  /// Prepara visita pública: auth mídia + Firestore web (só web).
  static Future<void> prepareVisit() async {
    await PublicSiteMediaAuth.ensurePublicVisitorMediaAccess()
        .timeout(const Duration(seconds: 4), onTimeout: () {});
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
  }

  /// Slug → igreja: emite rápido (índice) e depois perfil completo; `null` se não encontrado.
  static Stream<PublicChurchResolved?> watchTenantBySlug(String rawSlug) async* {
    final slug = rawSlug.trim();
    if (slug.isEmpty) {
      yield null;
      return;
    }

    // Não bloquear first paint do site público.
    unawaited(prepareVisit());

    final fast = await PublicChurchSlugResolver.resolveFast(slug);
    if (fast != null) {
      warmCaches(fast.churchId);
      yield fast;
    }

    final full = await PublicChurchSlugResolver.resolveEnrich(
      slug,
      seed: fast,
    );
    if (full != null) {
      warmCaches(full.churchId);
      yield full;
    } else if (fast == null) {
      yield null;
    }
  }

  /// Resolução one-shot para cadastro membro (mesmo caminho em todas as plataformas).
  static Future<PublicChurchResolved?> resolveForSignup({
    String? slug,
    String? tenantIdHint,
  }) async {
    // Cadastro público abre imediatamente; warmup segue em paralelo.
    unawaited(prepareVisit());

    final slugTrim = slug?.trim() ?? '';
    final tenantHint = tenantIdHint?.trim() ?? '';

    if (slugTrim.isNotEmpty) {
      final fast = await PublicChurchSlugResolver.resolveFast(slugTrim);
      if (fast != null) {
        warmCaches(fast.churchId);
        unawaited(
          PublicChurchSlugResolver.resolveEnrich(slugTrim, seed: fast),
        );
        return fast;
      }
      final full = await PublicChurchSlugResolver.resolve(slugTrim);
      if (full != null) {
        warmCaches(full.churchId);
        return full;
      }
    }

    if (tenantHint.isNotEmpty) {
      final hit =
          await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(tenantHint);
      if (hit != null && hit.data.isNotEmpty) {
        warmCaches(hit.docId);
        return PublicChurchResolved(
          churchId: hit.docId,
          profile: hit.data,
          slugKey: PublicChurchSlugResolver.normalizeSlugKey(slugTrim),
        );
      }
    }

    return null;
  }

  /// Aquece cache mural + `_panel_cache/public_site` — todas as plataformas.
  static void warmCaches(String churchId) {
    final id = churchId.trim();
    if (id.isEmpty) return;
    unawaited(PanelPublicSiteSnapshotService.readOnce(id));
    unawaited(
      YahwehPublicFeedRepository.readInstantFeed(
        id,
        refreshServerCacheInBackground: true,
      ),
    );
    // Warmup server-side do cache público/cadastro (best effort).
    unawaited(() async {
      try {
        final call = _functions.httpsCallable('warmPublicSiteAndSignupCache');
        await call.call(<String, dynamic>{'churchId': id}).timeout(
          const Duration(seconds: 6),
        );
      } catch (_) {}
    }());
  }
}
