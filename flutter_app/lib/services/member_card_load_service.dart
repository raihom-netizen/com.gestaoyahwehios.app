import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/member_document_resolve.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show churchTenantLogoUrl;
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Pedido de carga da carteirinha digital (membro ou gestor com alvo explÃ­cito).
class MemberCardLoadRequest {
  const MemberCardLoadRequest({
    required this.churchIdHint,
    this.memberId,
    this.cpf,
    this.memberSeedData,
    this.restrictedMember = false,
  });

  final String churchIdHint;
  final String? memberId;
  final String? cpf;
  final Map<String, dynamic>? memberSeedData;
  final bool restrictedMember;
}

/// Dados mÃ­nimos para pintar o cartÃ£o CNH (tenant + membro).
class MemberCardLoadPayload {
  const MemberCardLoadPayload({
    required this.igrejaDocId,
    required this.memberId,
    required this.member,
    required this.tenant,
  });

  final String igrejaDocId;
  final String memberId;
  final Map<String, dynamic> member;
  final Map<String, dynamic> tenant;
}

/// Cache-first + seed da lista â€” timeouts alinhados ao painel (90s web).
abstract final class MemberCardLoadService {
  MemberCardLoadService._();

  static Duration get _attempt => ChurchPanelReadTimeouts.attempt;
  static Duration get _queryCap => ChurchPanelReadTimeouts.queryCap;

  static String resolveChurchId(String hint) =>
      ChurchRepository.churchId(hint.trim());

  static Future<MemberCardLoadPayload?> load(MemberCardLoadRequest req) async {
    final igrejaDocId = resolveChurchId(req.churchIdHint);
    if (igrejaDocId.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    Map<String, dynamic> tenant = _minimalTenant(igrejaDocId);
    ({String id, Map<String, dynamic> data})? memberHit;

    try {
      final results = await Future.wait<Object?>([
        _loadTenant(igrejaDocId),
        _resolveMember(req, igrejaDocId),
      ]).timeout(
        _queryCap,
        onTimeout: () => throw TimeoutException(
          'Tempo esgotado ao carregar a carteirinha. Verifique a conexÃ£o.',
        ),
      );
      final t = results[0];
      if (t is Map<String, dynamic> && t.isNotEmpty) {
        tenant = t;
      }
      memberHit =
          results[1] as ({String id, Map<String, dynamic> data})?;
    } on TimeoutException {
      if (!_canUseSeed(req)) rethrow;
    } catch (_) {
      if (!_canUseSeed(req)) return null;
    }

    if (memberHit == null && _canUseSeed(req)) {
      memberHit = (
        id: req.memberId!.trim(),
        data: Map<String, dynamic>.from(req.memberSeedData!),
      );
    }

    if (memberHit == null) return null;

    if (tenant.length <= 2) {
      tenant = _minimalTenant(igrejaDocId);
    }

    return MemberCardLoadPayload(
      igrejaDocId: igrejaDocId,
      memberId: memberHit.id,
      member: memberHit.data,
      tenant: tenant,
    );
  }

  static Map<String, dynamic> _minimalTenant(String igrejaDocId) {
    final logoPath = ChurchBrandService.canonicalLogoPath(igrejaDocId);
    return {
      'id': igrejaDocId,
      '_carteiraLogoStoragePath': logoPath,
    };
  }

  static bool _canUseSeed(MemberCardLoadRequest req) {
    final seed = req.memberSeedData;
    final mid = req.memberId?.trim() ?? '';
    if (seed == null || seed.isEmpty || mid.isEmpty) return false;
    final nome =
        (seed['NOME_COMPLETO'] ?? seed['nome'] ?? '').toString().trim();
    return nome.isNotEmpty;
  }

  static List<String> _memberHints(MemberCardLoadRequest req) {
    final out = <String>[];
    final seen = <String>{};
    void add(String? raw) {
      final h = (raw ?? '').trim();
      if (h.isEmpty || seen.contains(h)) return;
      seen.add(h);
      out.add(h);
    }

    add(req.memberId);
    final cpf = (req.cpf ?? '').replaceAll(RegExp(r'\D'), '');
    if (cpf.length >= 11) add(cpf);
    final seed = req.memberSeedData;
    if (seed != null) {
      add((seed['authUid'] ?? seed['firebaseUid'] ?? seed['uid'] ?? '')
          .toString());
      add((seed['EMAIL'] ?? seed['email'] ?? '').toString());
      final seedCpf =
          (seed['CPF'] ?? seed['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (seedCpf.length >= 11) add(seedCpf);
    }
    return out;
  }

  static Future<Map<String, dynamic>> _loadTenant(String igrejaDocId) async {
    Map<String, dynamic> tenant = {};

    try {
      final hit = await IgrejaDirectFirestoreReads.readIgrejaDoc(igrejaDocId)
          .timeout(ChurchPanelReadTimeouts.churchDocCap);
      if (hit != null && hit.data.isNotEmpty) {
        tenant = Map<String, dynamic>.from(hit.data)..['id'] = hit.docId;
      }
    } catch (_) {}

    if (tenant.isEmpty) {
      try {
        Future<DocumentSnapshot<Map<String, dynamic>>> read() =>
            FirestoreReadResilience.getDocument(
              ChurchRepository.churchDoc(igrejaDocId),
              cacheKey: 'card_igreja_$igrejaDocId',
              maxAttempts: kIsWeb ? 4 : 2,
              attemptTimeout: _attempt,
            );
        final snap = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                read,
                maxAttempts: 4,
              )
            : await read();
        if (snap.exists) {
          tenant = Map<String, dynamic>.from(snap.data() ?? {})
            ..['id'] = igrejaDocId;
        }
      } catch (_) {}
    }

    if (tenant.isEmpty) return _minimalTenant(igrejaDocId);

    final logoFromDoc = churchTenantLogoUrl(tenant);
    final logoPath = ChurchBrandService.logoPathFromData(
          tenant,
          churchId: igrejaDocId,
        ) ??
        ChurchBrandService.canonicalLogoPath(igrejaDocId);
    tenant['_carteiraLogoStoragePath'] = logoPath;
    if (logoFromDoc.isNotEmpty) {
      tenant['_carteiraLogoUrl'] = logoFromDoc;
    }

    return tenant;
  }

  static Future<({String id, Map<String, dynamic> data})?> _resolveMember(
    MemberCardLoadRequest req,
    String igrejaDocId,
  ) async {
    if (_canUseSeed(req)) {
      return (
        id: req.memberId!.trim(),
        data: Map<String, dynamic>.from(req.memberSeedData!),
      );
    }

    final col = ChurchRepository.collection(
      ChurchDataPaths.membros,
      churchIdHint: igrejaDocId,
    );
    final cpfDigits = (req.cpf ?? '').replaceAll(RegExp(r'\D'), '');
    final cpfArg = cpfDigits.length >= 11 ? cpfDigits : null;
    final user = firebaseDefaultAuth.currentUser;

    Future<DocumentSnapshot<Map<String, dynamic>>?> docById(String id) async {
      if (id.isEmpty) return null;
      try {
        Future<DocumentSnapshot<Map<String, dynamic>>> read() =>
            FirestoreReadResilience.getDocument(
              col.doc(id),
              cacheKey: '${col.path}/card_member_$id',
              maxAttempts: kIsWeb ? 4 : 2,
              attemptTimeout: _attempt,
            );
        final snap = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(read, maxAttempts: 4)
            : await read();
        if (snap.exists) return snap;
      } catch (_) {}
      return null;
    }

    final explicitId = req.memberId?.trim() ?? '';
    if (explicitId.isNotEmpty) {
      final direct = await docById(explicitId);
      if (direct != null) {
        return (id: direct.id, data: direct.data() ?? {});
      }
    }

    if (req.restrictedMember) {
      if (user?.uid != null) {
        final uid = user!.uid;
        try {
          final cached = await col
              .where('authUid', isEqualTo: uid)
              .limit(1)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 5));
          if (cached.docs.isNotEmpty) {
            final d = cached.docs.first;
            return (id: d.id, data: d.data());
          }
        } catch (_) {}

        try {
          Future<QuerySnapshot<Map<String, dynamic>>> read() => col
              .where('authUid', isEqualTo: uid)
              .limit(1)
              .get(const GetOptions(source: Source.serverAndCache));
          final live = kIsWeb
              ? await FirestoreWebGuard.runWithWebRecovery(
                  read,
                  maxAttempts: 4,
                ).timeout(_queryCap)
              : await read().timeout(_queryCap);
          if (live.docs.isNotEmpty) {
            final d = live.docs.first;
            return (id: d.id, data: d.data());
          }
        } catch (_) {}
      }

      if (cpfArg != null) {
        final byCpf = await docById(cpfArg);
        if (byCpf != null) {
          return (id: byCpf.id, data: byCpf.data() ?? {});
        }
      }

      final email = user?.email?.trim() ?? '';
      if (email.isNotEmpty) {
        try {
          final snap = await MemberDocumentResolve.findByHint(
            col,
            email,
            cpfDigits: cpfArg,
          ).timeout(_queryCap);
          if (snap != null && snap.exists) {
            return (id: snap.id, data: snap.data() ?? {});
          }
        } catch (_) {}
      }
      return null;
    }

    for (final hint in _memberHints(req).take(6)) {
      try {
        final snap = await MemberDocumentResolve.findByHint(
          col,
          hint,
          cpfDigits: cpfArg,
        ).timeout(_queryCap);
        if (snap != null && snap.exists) {
          return (id: snap.id, data: snap.data() ?? {});
        }
      } catch (_) {}
    }
    return null;
  }
}

