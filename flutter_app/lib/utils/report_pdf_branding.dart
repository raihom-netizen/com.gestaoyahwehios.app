import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Dados visuais da igreja para PDFs de relatórios (logo + nome + cor de destaque).
class ReportPdfBranding {
  final String churchName;
  final Uint8List? logoBytes;
  final PdfColor accent;

  const ReportPdfBranding({
    required this.churchName,
    this.logoBytes,
    required this.accent,
  });

  static PdfColor get defaultAccent => PdfColor.fromInt(0xFF475569);
}

PdfColor _accentFromTenant(Map<String, dynamic> tenant) {
  final hex = (tenant['corPrimaria'] ?? '').toString().trim();
  if (hex.isEmpty) return ReportPdfBranding.defaultAccent;
  var s = hex.replaceFirst('#', '').replaceAll(RegExp(r'\s'), '');
  try {
    if (s.length == 6) {
      return PdfColor.fromInt(int.parse('FF$s', radix: 16));
    }
    if (s.length == 8) {
      return PdfColor.fromInt(int.parse(s, radix: 16));
    }
  } catch (_) {}
  return ReportPdfBranding.defaultAccent;
}

Future<Uint8List?> _fetchOneLogoCandidate(String raw) async {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.toLowerCase().startsWith('gs://')) {
    try {
      final ref = FirebaseStorage.instance.refFromURL(trimmed);
      final b = await ref.getData(8 * 1024 * 1024);
      if (b != null && b.length > 32) return Uint8List.fromList(b);
    } catch (_) {}
    return null;
  }
  if (!trimmed.toLowerCase().startsWith('http') && trimmed.contains('/')) {
    try {
      final path = normalizeFirebaseStorageObjectPath(
          trimmed.replaceFirst(RegExp(r'^/+'), ''));
      if (path.isNotEmpty) {
        final b =
            await FirebaseStorage.instance.ref(path).getData(8 * 1024 * 1024);
        if (b != null && b.length > 32) return Uint8List.fromList(b);
      }
    } catch (_) {}
  }
  final u = sanitizeImageUrl(trimmed);
  if (isValidImageUrl(u)) {
    try {
      final b =
          await firebaseStorageBytesFromDownloadUrl(u, maxBytes: 4 * 1024 * 1024);
      if (b != null && b.length > 32) return b;
    } catch (_) {}
  }
  return null;
}

/// Carrega nome, cor e bytes da logo da igreja (Firestore + Storage + config de certificados).
Future<ReportPdfBranding> loadReportPdfBranding(String tenantId) async {
  final tid = tenantId.trim();
  if (tid.isEmpty) {
    return ReportPdfBranding(
      churchName: '',
      logoBytes: null,
      accent: ReportPdfBranding.defaultAccent,
    );
  }
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }

  Map<String, dynamic> tenant = {};
  try {
    final snap =
        await FirebaseFirestore.instance.collection('igrejas').doc(tid).get();
    tenant = snap.data() ?? {};
  } catch (_) {}

  final name = (tenant['name'] ?? tenant['nome'] ?? '').toString().trim();
  final accent = _accentFromTenant(tenant);

  Map<String, dynamic> cert = {};
  try {
    final c = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('config')
        .doc('certificados')
        .get();
    cert = c.data() ?? {};
  } catch (_) {}

  final candidates = <String>[];
  void push(String? s) {
    final t = (s ?? '').trim();
    if (t.isNotEmpty && !candidates.contains(t)) candidates.add(t);
  }

  for (final u in churchTenantLogoUrlCandidates(tenant)) {
    push(u);
  }
  push(ChurchStorageLayout.churchIdentityLogoPath(tid));
  push(ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(tid));

  push((cert['logoPath'] ?? cert['storagePath'])?.toString());
  push(cert['logoUrl']?.toString());
  push(cert['logoCertificado']?.toString());
  final variants = cert['logoVariants'];
  if (variants is Map) {
    for (final v in variants.values) {
      if (v is Map) {
        push((v['path'] ?? v['storagePath'])?.toString());
        push((v['url'] ?? v['downloadUrl'])?.toString());
      } else {
        push(v?.toString());
      }
    }
  }
  for (final key in [
    'logoPath',
    'logo_path',
    'storagePath',
    'brandLogoPath',
    'churchLogoPath',
  ]) {
    push(tenant[key]?.toString());
  }

  Uint8List? bytes;
  for (final raw in candidates) {
    bytes = await _fetchOneLogoCandidate(raw);
    if (bytes != null) break;
  }
  if (bytes == null) {
    final url = await FirebaseStorageService.getChurchLogoDownloadUrl(
      tid,
      tenantData: tenant,
    );
    if (url != null && url.isNotEmpty) {
      bytes = await _fetchOneLogoCandidate(url);
    }
  }
  if (bytes == null) {
    final pathList =
        await FirebaseStorageService.getChurchLogoCandidateStoragePaths(
      tid,
      tenantData: tenant,
    );
    for (final p in pathList) {
      try {
        final b = await FirebaseStorage.instance
            .ref(p)
            .getData(6 * 1024 * 1024)
            .timeout(const Duration(seconds: 16), onTimeout: () => null);
        if (b != null && b.length > 32) {
          bytes = Uint8List.fromList(b);
          break;
        }
      } catch (_) {}
    }
  }

  return ReportPdfBranding(
    churchName: name,
    logoBytes: bytes,
    accent: accent,
  );
}
