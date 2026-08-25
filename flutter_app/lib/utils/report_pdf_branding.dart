import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';

/// Dados visuais da igreja para PDFs de relatórios (logo + nome + cor de destaque).
class ReportPdfBranding {
  final String churchName;
  final Uint8List? logoBytes;
  final PdfColor accent;
  /// CNPJ, endereço, telefone — linhas do cabeçalho (dados da igreja).
  final List<String> churchDetailLines;
  /// true quando [logoBytes] é a logo da igreja (não o escudo Gestão YAHWEH).
  final bool logoIsChurch;

  const ReportPdfBranding({
    required this.churchName,
    this.logoBytes,
    required this.accent,
    this.churchDetailLines = const [],
    this.logoIsChurch = false,
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

/// Evita repetir Firestore/Storage ao gerar várias carteirinhas no mesmo lote.
final Map<String, Future<ReportPdfBranding>> _loadReportPdfBrandingMemo = {};

/// Carrega nome, cor e bytes da logo da igreja (Firestore + Storage + config de certificados).
Future<ReportPdfBranding> loadReportPdfBranding(String tenantId) async {
  final seed = tenantId.trim();
  if (seed.isEmpty) {
    return ReportPdfBranding(
      churchName: '',
      logoBytes: null,
      accent: ReportPdfBranding.defaultAccent,
      churchDetailLines: const [],
      logoIsChurch: false,
    );
  }
  return _loadReportPdfBrandingMemo.putIfAbsent(
    seed,
    () => _loadReportPdfBrandingUncached(seed),
  );
}

Future<ReportPdfBranding> _loadReportPdfBrandingUncached(String seed) async {
  final tid = ChurchRepository.churchId(seed).isNotEmpty
      ? ChurchRepository.churchId(seed)
      : seed.trim();
  if (kIsWeb) {
    await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
  }

  final op = ChurchRepository.churchId(tid).isNotEmpty
      ? ChurchRepository.churchId(tid)
      : tid.trim();
  Map<String, dynamic> tenant = {};
  try {
    final cadastro = await ChurchCadastroLoadService.load(
      seedTenantId: op,
    ).timeout(const Duration(seconds: 12));
    tenant = cadastro.data;
  } catch (_) {}

  final name = churchTaxIdChurchNameFromMap(tenant);
  final accent = _accentFromTenant(tenant);
  final detailLines = _churchDetailLinesFromTenant(tenant);

  Map<String, dynamic> cert = {};
  try {
    final c = await ChurchOperationalPaths.churchDoc(op)
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
  // Os cadastros antigos podem ter várias URLs/paths equivalentes. Consultar
  // uma por vez fazia o relatório acumular timeouts. Resolve em pequenos lotes
  // paralelos e conserva a prioridade da lista canônica.
  for (var start = 0; start < candidates.length && bytes == null; start += 4) {
    final end = start + 4 < candidates.length ? start + 4 : candidates.length;
    final batch = candidates.sublist(start, end);
    final resolved = await Future.wait(batch.map(_fetchOneLogoCandidate));
    for (final candidate in resolved) {
      if (candidate != null) {
        bytes = candidate;
        break;
      }
    }
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

  // Cabeçalho financeiro = logo da igreja. Escudo GY fica só no rodapé (autoria).
  var logoIsChurch = bytes != null;
  if (bytes == null) {
    logoIsChurch = false;
  }

  return ReportPdfBranding(
    churchName: name,
    logoBytes: bytes,
    accent: accent,
    churchDetailLines: detailLines,
    logoIsChurch: logoIsChurch,
  );
}

List<String> _churchDetailLinesFromTenant(Map<String, dynamic> tenant) {
  String s(dynamic v) => (v ?? '').toString().trim();
  final out = <String>[];

  final digits = churchTaxIdDigitsFromMap(tenant);
  if (digits.length == 14) {
    out.add(
      'CNPJ ${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}',
    );
  } else if (digits.length == 11) {
    out.add(
      'CPF ${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}',
    );
  } else {
    final rawCnpj = s(tenant['cnpj'] ?? tenant['CNPJ'] ?? tenant['cnpjCpf']);
    if (rawCnpj.isNotEmpty) out.add('CNPJ/CPF $rawCnpj');
  }

  final rua = s(tenant['rua'] ?? tenant['address'] ?? tenant['logradouro']);
  final qd = s(tenant['quadraLoteNumero'] ?? tenant['quadra_lote_numero']);
  final ruaCompleta =
      rua.isEmpty ? qd : (qd.isEmpty ? rua : '$rua, $qd');
  final bairro = s(tenant['bairro'] ?? tenant['BAIRRO']);
  final cidade = s(
      tenant['cidade'] ?? tenant['CIDADE'] ?? tenant['localidade']);
  final estado =
      s(tenant['estado'] ?? tenant['ESTADO'] ?? tenant['uf'] ?? tenant['UF']);
  final cep = s(tenant['cep'] ?? tenant['CEP']);
  final cidadeEstado = cidade.isNotEmpty && estado.isNotEmpty
      ? '$cidade - $estado'
      : (cidade.isNotEmpty ? cidade : estado);
  final addrParts = <String>[
    if (ruaCompleta.isNotEmpty) ruaCompleta,
    if (bairro.isNotEmpty) bairro,
    if (cidadeEstado.isNotEmpty) cidadeEstado,
    if (cep.isNotEmpty) 'CEP $cep',
  ];
  if (addrParts.isNotEmpty) {
    out.add(addrParts.join(', '));
  } else {
    final legacy = s(tenant['endereco'] ?? tenant['ENDERECO']);
    if (legacy.isNotEmpty) out.add(legacy);
  }

  final phone = s(tenant['whatsappIgreja'] ??
      tenant['whatsapp'] ??
      tenant['telefoneIgreja'] ??
      tenant['telefone'] ??
      tenant['phone']);
  if (phone.isNotEmpty) out.add('Tel./WhatsApp $phone');

  final email = s(tenant['emailIgreja'] ?? tenant['email'] ?? tenant['EMAIL']);
  if (email.isNotEmpty) out.add(email);

  return out;
}
