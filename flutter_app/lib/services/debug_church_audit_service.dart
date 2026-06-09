import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/services/church_finance_aggregates_service.dart';
import 'package:gestao_yahweh/services/church_repository.dart';

/// Snapshot de auditoria — mesma consulta em Web / Android / iOS.
class DebugChurchAuditSnapshot {
  const DebugChurchAuditSnapshot({
    required this.platform,
    required this.churchId,
    required this.firestorePath,
    required this.storagePath,
    required this.seedHint,
    required this.contextBound,
    required this.probes,
    required this.legacyHitsInLogs,
    required this.capturedAt,
    this.nome,
    this.cidade,
    this.estado,
    this.telefone,
    this.email,
    this.logoPath,
    this.churchFieldCount = 0,
    this.loadError,
    this.moduleFingerprints = const {},
    this.financeSaldo,
  });

  final String platform;
  final String churchId;
  final String firestorePath;
  final String storagePath;
  final String seedHint;
  final bool contextBound;
  final List<ChurchModuleProbeResult> probes;
  final List<String> legacyHitsInLogs;
  final DateTime capturedAt;
  final String? nome;
  final String? cidade;
  final String? estado;
  final String? telefone;
  final String? email;
  final String? logoPath;
  final int churchFieldCount;
  final String? loadError;
  final Map<String, List<String>> moduleFingerprints;
  final double? financeSaldo;

  List<String> fingerprintsFor(String module) => moduleFingerprints[module] ?? const [];

  int? countFor(String module) {
    for (final p in probes) {
      if (p.module == module) return p.count;
    }
    return null;
  }

  ChurchModuleProbeResult? probeFor(String module) {
    for (final p in probes) {
      if (p.module == module) return p;
    }
    return null;
  }

  bool get allProbesOk =>
      probes.isNotEmpty && probes.every((p) => p.ok && !p.usedLegacyPath);

  bool get hasLegacyInLogs => legacyHitsInLogs.isNotEmpty;

  String get verdict =>
      hasLegacyInLogs || loadError != null ? 'REPROVADO' : (allProbesOk ? 'APROVADO' : 'REPROVADO');

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'churchId': churchId,
        'firestorePath': firestorePath,
        'storagePath': storagePath,
        'seedHint': seedHint,
        'contextBound': contextBound,
        'probes': probes.map((p) => p.toJson()).toList(),
        'legacyHitsInLogs': legacyHitsInLogs,
        'capturedAt': capturedAt.toIso8601String(),
        if (nome != null) 'nome': nome,
        if (cidade != null) 'cidade': cidade,
        if (estado != null) 'estado': estado,
        if (telefone != null) 'telefone': telefone,
        if (email != null) 'email': email,
        if (logoPath != null) 'logoPath': logoPath,
        'churchFieldCount': churchFieldCount,
        if (loadError != null) 'loadError': loadError,
        'moduleFingerprints': moduleFingerprints,
        if (financeSaldo != null) 'financeSaldo': financeSaldo,
      };

  factory DebugChurchAuditSnapshot.fromJson(Map<String, dynamic> json) {
    final rawProbes = json['probes'];
    final probes = <ChurchModuleProbeResult>[];
    if (rawProbes is List) {
      for (final item in rawProbes) {
        if (item is Map<String, dynamic>) {
          probes.add(ChurchModuleProbeResult.fromJson(item));
        } else if (item is Map) {
          probes.add(ChurchModuleProbeResult.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final legacy = json['legacyHitsInLogs'];
    return DebugChurchAuditSnapshot(
      platform: (json['platform'] ?? '').toString(),
      churchId: (json['churchId'] ?? '').toString(),
      firestorePath: (json['firestorePath'] ?? '').toString(),
      storagePath: (json['storagePath'] ?? '').toString(),
      seedHint: (json['seedHint'] ?? '').toString(),
      contextBound: json['contextBound'] == true,
      probes: probes,
      legacyHitsInLogs: legacy is List
          ? legacy.map((e) => e.toString()).toList()
          : const [],
      capturedAt: DateTime.tryParse((json['capturedAt'] ?? '').toString()) ?? DateTime.now(),
      nome: json['nome']?.toString(),
      cidade: json['cidade']?.toString(),
      estado: json['estado']?.toString(),
      telefone: json['telefone']?.toString(),
      email: json['email']?.toString(),
      logoPath: json['logoPath']?.toString(),
      churchFieldCount: json['churchFieldCount'] is int ? json['churchFieldCount'] as int : 0,
      loadError: json['loadError']?.toString(),
      moduleFingerprints: _fingerprintsFromJson(json['moduleFingerprints']),
      financeSaldo: json['financeSaldo'] is num ? (json['financeSaldo'] as num).toDouble() : null,
    );
  }

  static Map<String, List<String>> _fingerprintsFromJson(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    raw.forEach((key, value) {
      if (value is List) {
        out[key.toString()] = value.map((e) => e.toString()).toList();
      }
    });
    return out;
  }

  String toClipboardText() {
    final b = StringBuffer()
      ..writeln('=== DEBUG CHURCH ===')
      ..writeln('PLATAFORMA: $platform')
      ..writeln('churchId: $churchId')
      ..writeln('Firestore Path: $firestorePath')
      ..writeln('Storage Path: $storagePath')
      ..writeln('Nome: ${nome ?? "-"}')
      ..writeln('Cidade: ${cidade ?? "-"}')
      ..writeln('Estado: ${estado ?? "-"}')
      ..writeln('Telefone: ${telefone ?? "-"}')
      ..writeln('Email: ${email ?? "-"}')
      ..writeln('LogoPath: ${logoPath ?? "-"}')
      ..writeln('VEREDITO: $verdict')
      ..writeln('--- MÓDULOS ---');
    for (final p in probes) {
      b.writeln(
        '${p.module} | PATH=${p.collectionPath} | count=${p.count ?? "-"} | '
        'ok=${p.ok} | legacy=${p.usedLegacyPath} | ${p.durationMs ?? 0}ms',
      );
      if (p.error != null) b.writeln('  ERRO: ${p.error}');
    }
    if (legacyHitsInLogs.isNotEmpty) {
      b.writeln('--- LEGADO NOS LOGS ---');
      for (final l in legacyHitsInLogs) {
        b.writeln(l);
      }
    }
    return b.toString();
  }
}

/// Comparação objetiva WEB = ANDROID = IOS (prova obrigatória).
class DebugChurchCrossPlatformProof {
  const DebugChurchCrossPlatformProof({
    required this.churchId,
    required this.byPlatform,
    required this.moduleRows,
    required this.verdict,
    required this.missingPlatforms,
    required this.mismatchModules,
    required this.legacyPlatforms,
  });

  final String churchId;
  final Map<String, DebugChurchAuditSnapshot?> byPlatform;
  final List<DebugChurchModuleProveRow> moduleRows;
  final String verdict;
  final List<String> missingPlatforms;
  final List<String> mismatchModules;
  final List<String> legacyPlatforms;

  bool get isComplete => missingPlatforms.isEmpty;

  bool get isApproved =>
      isComplete &&
      mismatchModules.isEmpty &&
      legacyPlatforms.isEmpty &&
      moduleRows.every((r) => r.match);

  String toAcceptanceReportTable() {
    const modules = DebugChurchAuditService.moduleProveLabels;
    final b = StringBuffer()
      ..writeln('=== RELATÓRIO DE ACEITE — GESTÃO YAHWEH ===')
      ..writeln('churchId: $churchId')
      ..writeln('VEREDITO GERAL: $verdict')
      ..writeln('')
      ..writeln('| Módulo | Path Firestore | Path Storage | Web | Android | iOS | Status |');
    for (final entry in modules.entries) {
      final module = entry.key;
      final label = entry.value;
      final fs = byPlatform['WEB']?.probeFor(module)?.collectionPath ??
          byPlatform['ANDROID']?.probeFor(module)?.collectionPath ??
          'igrejas/$churchId/...';
      final storage = DebugChurchAuditService.storagePathForModule(churchId, module);
      final web = _platformCell('WEB', module);
      final android = _platformCell('ANDROID', module);
      final ios = _platformCell('IOS', module);
      final rowOk = missingPlatforms.isEmpty &&
          !mismatchModules.contains(label) &&
          legacyPlatforms.isEmpty;
      final status = missingPlatforms.isNotEmpty
          ? 'INCOMPLETO'
          : (rowOk ? 'APROVADO' : 'REPROVADO');
      b.writeln('| $label | $fs | $storage | $web | $android | $ios | $status |');
    }
    b.writeln('');
    b.writeln('TESTE 1 Cadastro — Web:${_cadastroCell("WEB")} Android:${_cadastroCell("ANDROID")} iOS:${_cadastroCell("IOS")}');
    if (legacyPlatforms.isNotEmpty) {
      b.writeln('LEGADO: ${legacyPlatforms.join(", ")}');
    }
    return b.toString().trimRight();
  }

  String _platformCell(String platform, String module) {
    final snap = byPlatform[platform];
    if (snap == null) return '(ausente)';
    final count = snap.countFor(module);
    if (module == 'Financeiro') {
      final saldo = snap.financeSaldo;
      return 'n=$count saldo=${saldo?.toStringAsFixed(2) ?? "-"}';
    }
    if (module == 'Cadastro Igreja') {
      return snap.firestorePath;
    }
    final fps = snap.fingerprintsFor(module);
    if (fps.isEmpty) return 'n=${count ?? "-"}';
    final preview = fps.take(3).join(', ');
    final suffix = fps.length > 3 ? '…' : '';
    return 'n=${count ?? "-"} [$preview$suffix]';
  }

  String _cadastroCell(String platform) {
    final s = byPlatform[platform];
    if (s == null) return '(ausente)';
    return 'nome=${s.nome ?? "-"} tel=${s.telefone ?? "-"} email=${s.email ?? "-"} '
        'cidade=${s.cidade ?? "-"} uf=${s.estado ?? "-"} logo=${s.logoPath ?? "-"}';
  }

  String toMandatoryProveText() {
    final b = StringBuffer()
      ..writeln('=== PROVA OBRIGATÓRIA ===')
      ..writeln('churchId: $churchId')
      ..writeln('VEREDITO: $verdict');
    if (missingPlatforms.isNotEmpty) {
      b.writeln('FALTAM: ${missingPlatforms.join(", ")}');
    }
    b.writeln('');
    for (final row in moduleRows) {
      b.writeln('${row.label}:');
      b.writeln('WEB:${row.webPath}');
      b.writeln('ANDROID:${row.androidPath}');
      b.writeln('IOS:${row.iosPath}');
      b.writeln('MATCH:${row.match ? "SIM" : "NÃO"}');
      b.writeln('');
    }
    b.writeln('STORAGE:');
    b.writeln('WEB:${_pathOrMissing(byPlatform['WEB']?.storagePath)}');
    b.writeln('ANDROID:${_pathOrMissing(byPlatform['ANDROID']?.storagePath)}');
    b.writeln('IOS:${_pathOrMissing(byPlatform['IOS']?.storagePath)}');
    if (legacyPlatforms.isNotEmpty) {
      b.writeln('');
      b.writeln('LEGADO NOS LOGS: ${legacyPlatforms.join(", ")} → REPROVADO');
    }
    return b.toString().trimRight();
  }

  static String _pathOrMissing(String? path) =>
      path == null || path.isEmpty ? '(ausente)' : path;
}

class DebugChurchModuleProveRow {
  const DebugChurchModuleProveRow({
    required this.label,
    required this.webPath,
    required this.androidPath,
    required this.iosPath,
    required this.match,
  });

  final String label;
  final String webPath;
  final String androidPath;
  final String iosPath;
  final bool match;
}

abstract final class DebugChurchAuditService {
  DebugChurchAuditService._();

  static const platformKeys = <String>['WEB', 'ANDROID', 'IOS'];

  static const moduleProveLabels = <String, String>{
    'Cadastro Igreja': 'CADASTRO',
    'Departamentos': 'DEPARTAMENTOS',
    'Cargos': 'CARGOS',
    'Membros': 'MEMBROS',
    'Fornecedores': 'FORNECEDORES',
    'Financeiro': 'FINANCEIRO',
    'Eventos': 'EVENTOS',
    'Avisos': 'AVISOS',
    'Chat': 'CHAT',
    'Patrimônio': 'PATRIMONIO',
  };

  static const _legacyTokens = <String>[
    'tenants',
    'church_aliases',
    'church_roots',
    'slug',
    'alias',
    'tenantResolver',
    'aliasResolver',
    'canonicalTenant',
    'operationalTenant',
    'churchRoot',
    'syncStorageTenantId',
  ];

  static String platformLabel() {
    if (kIsWeb) return 'WEB';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'IOS';
    if (defaultTargetPlatform == TargetPlatform.android) return 'ANDROID';
    try {
      return Platform.operatingSystem.toUpperCase();
    } catch (_) {
      return defaultTargetPlatform.name.toUpperCase();
    }
  }

  static Future<DebugChurchAuditSnapshot> runFullAudit(String seedHint) async {
    final seed = seedHint.trim();
    final churchId = ChurchRepository.churchId(seed).isNotEmpty
        ? ChurchRepository.churchId(seed)
        : (ChurchContextService.currentChurchId ?? seed);
    final firestorePath = 'igrejas/$churchId';
    final storagePath = ChurchStorageLayout.churchRoot(churchId);

    ChurchOperationalFirestoreTrace.clear();
    final probes = <ChurchModuleProbeResult>[];
    final fingerprints = <String, List<String>>{};
    String? loadError;
    Map<String, dynamic> churchData = {};
    var fieldCount = 0;
    double? financeSaldo;

    Future<void> probeDoc(String module) async {
      final sw = Stopwatch()..start();
      try {
        final r = await ChurchModuleFirestoreAudit.traceQuery(
          module: module,
          churchId: churchId,
          path: firestorePath,
          run: () => ChurchRepository.loadByChurchId(
            churchId,
            seedTenantId: seed,
          ),
        );
        sw.stop();
        churchData = r.data;
        fieldCount = r.fieldCount;
        probes.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: firestorePath,
          documentPath: r.firestorePath,
          ok: r.data.isNotEmpty,
          count: r.fieldCount,
          durationMs: sw.elapsedMilliseconds,
        ));
      } catch (e) {
        sw.stop();
        loadError ??= '$e';
        probes.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: firestorePath,
          durationMs: sw.elapsedMilliseconds,
          error: '$e',
        ));
      }
    }

    List<String> _extractNames(
      QuerySnapshot<Map<String, dynamic>> snap, {
      List<String> extraKeys = const [],
    }) {
      final names = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        var name = '';
        for (final key in ['nome', 'name', 'NOME', 'NOME_COMPLETO', 'titulo', ...extraKeys]) {
          final v = data[key];
          if (v != null && v.toString().trim().isNotEmpty) {
            name = v.toString().trim();
            break;
          }
        }
        if (name.isEmpty) name = d.id;
        names.add(name);
      }
      names.sort();
      return names;
    }

    Future<void> probeQuery(
      String module,
      String subcollection,
      Future<QuerySnapshot<Map<String, dynamic>>> Function() fetch, {
      bool captureNames = false,
      List<String> nameKeys = const [],
    }) async {
      final path = '$firestorePath/$subcollection';
      final sw = Stopwatch()..start();
      try {
        final snap = await ChurchModuleFirestoreAudit.traceQuery(
          module: module,
          churchId: churchId,
          path: path,
          run: fetch,
        );
        sw.stop();
        if (captureNames) {
          fingerprints[module] = _extractNames(snap, extraKeys: nameKeys);
        }
        probes.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: path,
          ok: true,
          count: snap.docs.length,
          durationMs: sw.elapsedMilliseconds,
        ));
      } catch (e) {
        sw.stop();
        probes.add(ChurchModuleProbeResult(
          module: module,
          churchId: churchId,
          collectionPath: path,
          durationMs: sw.elapsedMilliseconds,
          error: '$e',
        ));
      }
    }

    await probeDoc('Cadastro Igreja');

    await probeQuery(
      'Departamentos',
      'departamentos',
      () => ChurchRepository.departamentos(churchIdHint: churchId, limit: 200),
      captureNames: true,
    );
    await probeQuery(
      'Cargos',
      'cargos',
      () => ChurchRepository.cargos(churchIdHint: churchId, limit: 200),
      captureNames: true,
    );
    await probeQuery(
      'Membros',
      'membros',
      () => ChurchRepository.membros(churchIdHint: churchId, limit: 500),
      captureNames: true,
      nameKeys: const ['NOME_COMPLETO'],
    );
    await probeQuery(
      'Fornecedores',
      'fornecedores',
      () => ChurchRepository.fornecedores(churchIdHint: churchId, limit: 200),
    );
    await probeQuery(
      'Financeiro',
      'finance',
      () => ChurchRepository.financeiro(churchIdHint: churchId, limit: 500),
    );
    try {
      final agg = await ChurchFinanceAggregatesService.readOnce(churchId);
      financeSaldo = agg.saldoAtual;
    } catch (_) {}
    await probeQuery(
      'Eventos',
      'noticias',
      () => ChurchRepository.eventos(churchIdHint: churchId, limit: 200),
    );
    await probeQuery(
      'Avisos',
      'avisos',
      () => ChurchRepository.avisos(churchIdHint: churchId, limit: 200),
    );
    await probeQuery(
      'Chat',
      'chats',
      () => ChurchRepository.chat(churchIdHint: churchId, limit: 50),
    );
    await probeQuery(
      'Patrimônio',
      'patrimonio',
      () => ChurchRepository.patrimonio(churchIdHint: churchId, limit: 200),
    );

    final traces = ChurchOperationalFirestoreTrace.recent;
    final legacyHits = <String>[];
    for (final t in traces) {
      final blob = '${t.origin}|${t.firestorePath}|${t.churchId}|${t.error ?? ""}'
          .toLowerCase();
      for (final token in _legacyTokens) {
        if (blob.contains(token.toLowerCase())) {
          legacyHits.add('TRACE $token → ${t.origin} path=${t.firestorePath}');
        }
      }
    }

    final logoPath = ChurchImageFields.logoStoragePath(churchData) ??
        ChurchStorageLayout.churchIdentityLogoPath(churchId);

    final snap = DebugChurchAuditSnapshot(
      platform: platformLabel(),
      churchId: churchId,
      firestorePath: firestorePath,
      storagePath: storagePath,
      seedHint: seed,
      contextBound: ChurchContextService.currentChurchId != null,
      probes: probes,
      legacyHitsInLogs: legacyHits,
      capturedAt: DateTime.now(),
      nome: (churchData['nome'] ?? churchData['name'] ?? '').toString(),
      cidade: (churchData['cidade'] ?? churchData['localidade'] ?? '').toString(),
      estado: (churchData['estado'] ?? churchData['uf'] ?? '').toString(),
      telefone: (churchData['telefone'] ?? churchData['phone'] ?? '').toString(),
      email: (churchData['email'] ?? '').toString(),
      logoPath: logoPath,
      churchFieldCount: fieldCount,
      loadError: loadError,
      moduleFingerprints: fingerprints,
      financeSaldo: financeSaldo,
    );
    return snap;
  }

  static String storagePathForModule(String churchId, String module) {
    final root = ChurchStorageLayout.churchRoot(churchId);
    return switch (module) {
      'Cadastro Igreja' => ChurchStorageLayout.churchIdentityLogoPath(churchId),
      'Membros' => '${root}membros/',
      'Eventos' => '${root}eventos/',
      'Avisos' => '${root}avisos/',
      'Chat' => '${root}chat/',
      'Financeiro' => ChurchStorageLayout.financeiroFolderPlaceholderPath(churchId),
      _ => root,
    };
  }

  static Future<void> publishPlatformProof(DebugChurchAuditSnapshot snap) async {
    final platform = snap.platform.toUpperCase();
    if (!platformKeys.contains(platform)) {
      throw StateError('Plataforma inválida para prova: $platform');
    }
    await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(snap.churchId)
        .collection('_debug_platform_audit')
        .doc(platform)
        .set({
      ...snap.toJson(),
      'publishedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, DebugChurchAuditSnapshot?>> loadCrossPlatformProof(
    String churchId,
  ) async {
    final out = <String, DebugChurchAuditSnapshot?>{};
    for (final key in platformKeys) {
      out[key] = null;
    }
    final col = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(churchId)
        .collection('_debug_platform_audit')
        .get();
    for (final doc in col.docs) {
      final key = doc.id.toUpperCase();
      if (!platformKeys.contains(key)) continue;
      out[key] = DebugChurchAuditSnapshot.fromJson(doc.data());
    }
    return out;
  }

  static DebugChurchCrossPlatformProof buildCrossPlatformProof(
    String churchId,
    Map<String, DebugChurchAuditSnapshot?> byPlatform,
  ) {
    final missing = <String>[];
    final legacyPlatforms = <String>[];
    for (final key in platformKeys) {
      final snap = byPlatform[key];
      if (snap == null) {
        missing.add(key);
        continue;
      }
      if (snap.hasLegacyInLogs || snap.loadError != null) {
        legacyPlatforms.add(key);
      }
    }

    final moduleOrder = moduleProveLabels.keys.toList();
    final rows = <DebugChurchModuleProveRow>[];
    final mismatches = <String>{};

    for (final module in moduleOrder) {
      final label = moduleProveLabels[module] ?? module.toUpperCase();
      final paths = <String?, String?>{
        'WEB': byPlatform['WEB']?.probeFor(module)?.collectionPath,
        'ANDROID': byPlatform['ANDROID']?.probeFor(module)?.collectionPath,
        'IOS': byPlatform['IOS']?.probeFor(module)?.collectionPath,
      };
      final present = paths.entries.where((e) => e.value != null).map((e) => e.value!).toList();
      final match = missing.isEmpty &&
          present.length == 3 &&
          present.toSet().length == 1 &&
          !present.first.contains('tenant') &&
          !present.first.contains('alias');
      final fpWeb = byPlatform['WEB']?.fingerprintsFor(module) ?? const [];
      final fpAndroid = byPlatform['ANDROID']?.fingerprintsFor(module) ?? const [];
      final fpIos = byPlatform['IOS']?.fingerprintsFor(module) ?? const [];
      final fpMatch = missing.isEmpty &&
          fpWeb.join('|') == fpAndroid.join('|') &&
          fpAndroid.join('|') == fpIos.join('|');
      if (module == 'Financeiro' && missing.isEmpty) {
        final sWeb = byPlatform['WEB']?.financeSaldo;
        final sAndroid = byPlatform['ANDROID']?.financeSaldo;
        final sIos = byPlatform['IOS']?.financeSaldo;
        if (sWeb != sAndroid || sAndroid != sIos) mismatches.add(label);
      } else if (!fpMatch && missing.isEmpty && fpWeb.isNotEmpty) {
        mismatches.add(label);
      }
      if (!match && missing.isEmpty) mismatches.add(label);
      rows.add(DebugChurchModuleProveRow(
        label: label,
        webPath: paths['WEB'] ?? '(ausente)',
        androidPath: paths['ANDROID'] ?? '(ausente)',
        iosPath: paths['IOS'] ?? '(ausente)',
        match: match,
      ));
    }

    String verdict;
    if (missing.isNotEmpty) {
      verdict = 'INCOMPLETO';
    } else if (legacyPlatforms.isNotEmpty || mismatches.isNotEmpty) {
      verdict = 'REPROVADO';
    } else {
      verdict = 'APROVADO';
    }

    return DebugChurchCrossPlatformProof(
      churchId: churchId,
      byPlatform: byPlatform,
      moduleRows: rows,
      verdict: verdict,
      missingPlatforms: missing,
      mismatchModules: mismatches.toList(),
      legacyPlatforms: legacyPlatforms,
    );
  }
}
