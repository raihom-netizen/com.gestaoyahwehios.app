import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_caches.dart';
import 'package:gestao_yahweh/data/yahweh_data_repository.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/public_church_slug_resolver.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Bootstrap único — site público + cadastro membro (Web = Android = iOS).
abstract final class PublicChurchSiteBootstrap {
  PublicChurchSiteBootstrap._();

  static FirebaseFunctions get _functionsSa =>
      FirebaseFunctions.instanceFor(
        app: firebaseDefaultApp,
        region: 'southamerica-east1',
      );

  static String normalizeSlugInput(String raw) =>
      PublicChurchSlugResolver.normalizePublicSlugInput(raw);

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
    final slug = normalizeSlugInput(rawSlug);
    if (slug.isEmpty) {
      yield null;
      return;
    }

    // RAM — primeiro frame sem esperar rede.
    final peek = PublicChurchSlugResolver.peek(slug);
    if (peek != null) {
      warmCaches(peek.churchId);
      yield peek;
    }

    // Não bloquear first paint do site público.
    unawaited(prepareVisit());

    PublicChurchResolved? fast = peek;
    if (peek == null || peek.fromIndexOnly) {
      try {
        fast = await PublicChurchSlugResolver.resolveFast(slug).timeout(
          const Duration(seconds: 4),
        );
      } catch (_) {
        fast = peek;
      }
    }
    if (fast != null &&
        (peek == null ||
            fast.churchId != peek.churchId ||
            (peek.fromIndexOnly && !fast.fromIndexOnly))) {
      warmCaches(fast.churchId);
      yield fast;
    }

    if (fast == null) {
      try {
        final resolvedChurchId =
            await TenantResolverService.resolveIgrejaDocIdFromPublicSlug(slug)
                .timeout(const Duration(seconds: 4));
        if (resolvedChurchId != null && resolvedChurchId.isNotEmpty) {
          final hit = await IgrejaDirectFirestoreReads.readIgrejaPublicProfile(
            resolvedChurchId,
          ).timeout(const Duration(seconds: 6));
          if (hit != null && hit.data.isNotEmpty) {
            final direct = PublicChurchResolved(
              churchId: hit.docId,
              profile: hit.data,
              slugKey: slug,
              fromIndexOnly: false,
            );
            warmCaches(direct.churchId);
            yield direct;
            fast = direct;
          }
        }
      } catch (_) {}
    }

    final full = await PublicChurchSlugResolver.resolveEnrich(
      slug,
      seed: fast,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => fast,
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

    final slugTrim = normalizeSlugInput(slug ?? '');
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

  /// Aquece cache mural + `_panel_cache/public_site` + módulos P0 públicos — todas as plataformas.
  static void warmCaches(String churchId) {
    final id = churchId.trim();
    if (id.isEmpty) return;
    unawaited(YahwehModuleCaches.warmPublicSiteModules(id));
    unawaited(
      YahwehPublicFeedRepository.readInstantFeed(
        id,
        refreshServerCacheInBackground: true,
      ),
    );
    // Eventos fixos / horários — cache Firestore para first paint do site.
    unawaited(_warmEventTemplates(id));
    unawaited(_warmPublicSiteCallable(id));
  }

  static Future<void> _warmEventTemplates(String churchId) async {
    try {
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(churchId)
          .collection('event_templates')
          .where('active', isEqualTo: true)
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  static Future<void> _warmPublicSiteCallable(String churchId) async {
    try {
      final call = _functionsSa.httpsCallable('warmPublicSiteAndSignupCache');
      await call.call(<String, dynamic>{'churchId': churchId}).timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {}
  }
}
