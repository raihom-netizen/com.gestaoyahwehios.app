import 'dart:async' show Timer, unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/pdf/church_transfer_letter_pdf.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/module_header_premium.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/ui/widgets/church_letters_member_pickers.dart';
import 'package:gestao_yahweh/utils/member_signature_eligibility.dart';
import 'package:gestao_yahweh/utils/church_department_list.dart'
    show churchDepartmentNameFromDoc;
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/church_cartas_modelos_service.dart';

enum _CartaKind {
  apresentacao,
  transferencia,
  agradecimento,
}

enum _LetterSignatureMode { digital, manual }

extension _CartaKindFirestore on _CartaKind {
  String get firestoreKind => switch (this) {
        _CartaKind.apresentacao => 'apresentacao',
        _CartaKind.transferencia => 'transferencia',
        _CartaKind.agradecimento => 'agradecimento',
      };
}

_CartaKind _cartaKindFromFirestore(String raw) {
  final s = raw.trim();
  if (s == 'transferencia') return _CartaKind.transferencia;
  if (s == 'agradecimento') return _CartaKind.agradecimento;
  return _CartaKind.apresentacao;
}

/// Cartas de apresentação, transferência e agradecimento — assinaturas do cadastro de membros (até 2), histórico na nuvem.
class ChurchLettersPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cpf;
  final List<String>? permissions;
  final bool embeddedInShell;

  const ChurchLettersPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf = '',
    this.permissions,
    this.embeddedInShell = false,
  });

  @override
  State<ChurchLettersPage> createState() => _ChurchLettersPageState();
}

class _ChurchLettersPageState extends State<ChurchLettersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _destIgrejaCtrl = TextEditingController();
  final _missionCtrl = TextEditingController();
  final _tplApresentacaoCtrl = TextEditingController();
  final _tplTransferCtrl = TextEditingController();
  final _tplAgradecimentoCtrl = TextEditingController();

  /// Doc ids em `membros` — obrigatório 1º; 2º opcional (segunda assinatura).
  String? _signer1MemberId;
  String? _signer2MemberId;

  Map<String, dynamic>? _tenant;
  bool _membersSyncing = false;
  bool _savingTpl = false;
  bool _pdfBusy = false;
  _LetterSignatureMode _signatureMode = _LetterSignatureMode.digital;
  final Set<String> _selectedIds = {};
  final Map<String, ChurchLetterMemberEntry> _selectedMembersCache = {};
  List<({String id, String name})> _deptFilterItems = [];
  late Future<QuerySnapshot<Map<String, dynamic>>> _membersFuture;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _seedMemberDocs = [];
  int _membersQueryLimit = 600;
  Future<ReportPdfBranding>? _brandingFuture;
  ReportPdfBranding? _brandingReady;
  final Map<String, Uint8List?> _signatureBytesCache = <String, Uint8List?>{};

  /// Ao editar a partir do histórico, atualiza este doc em vez de criar outro.
  String? _historyEditDocId;

  int _histYear = DateTime.now().year;
  DateTimeRange? _histCustomRange;
  int _historicoStreamGen = 0;

  DocumentReference<Map<String, dynamic>> get _configRef {
    final id = ChurchRepository.churchId(
      _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId,
    );
    return ChurchUiCollections.config(id).doc('cartas');
  }

  CollectionReference<Map<String, dynamic>> get _historicoCol {
    final id = ChurchRepository.churchId(
      _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId,
    );
    return ChurchUiCollections.transferencias(id);
  }

  String _effectiveTenantId = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) {
        setState(() {});
      }
    });
    _effectiveTenantId = ChurchRepository.churchId(widget.tenantId);
    _missionCtrl.text = 'evangelizar, discipular e servir a comunidade';
    _tplApresentacaoCtrl.text =
        kDefaultChurchLetterApresentacaoTemplate.trim();
    _tplTransferCtrl.text = kDefaultChurchLetterTransferenciaTemplate.trim();
    _tplAgradecimentoCtrl.text =
        kDefaultChurchLetterAgradecimentoTemplate.trim();
    final ctxData = ChurchContextService.currentChurchData;
    if (ctxData != null && ctxData.isNotEmpty) {
      _tenant = Map<String, dynamic>.from(ctxData);
    }
    final ram = _effectiveTenantId.isNotEmpty
        ? _ChurchLettersMembersRamCache.peek(_effectiveTenantId)
        : null;
    if (ram != null && ram.isNotEmpty) {
      _seedMemberDocs = List.from(ram);
      _membersFuture = Future.value(_LettersMembersListSnapshot(_seedMemberDocs));
      _applyDefaultSignerFromLoadedMembers(_seedMemberDocs);
    } else {
      _membersFuture = Future.value(_LettersMembersListSnapshot(const []));
    }
    unawaited(_openChurchLettersFast());
    unawaited(_bootstrap());
    unawaited(_loadDepartmentsForLetters());
    unawaited(_prewarmPdfEmitAssets());
  }

  Future<void> _loadDepartmentsForLetters({bool forceRefresh = false}) async {
    final churchId = ChurchRepository.churchId(
      _effectiveTenantId.isNotEmpty
          ? _effectiveTenantId
          : widget.tenantId.trim(),
    );
    if (churchId.isEmpty) return;

    if (!forceRefresh) {
      final ram = ChurchDepartmentsLoadService.peekRam(churchId);
      if (ram != null && ram.isNotEmpty) {
        _applyDepartmentFilterItems(ram);
      }
    }

    try {
      final result = await ChurchDepartmentsLoadService.load(
        seedTenantId: churchId,
        forceRefresh: forceRefresh,
      );
      if (result.docs.isEmpty) return;
      _applyDepartmentFilterItems(result.docs);
    } catch (_) {}
  }

  void _applyDepartmentFilterItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = docs
        .map((d) => (
              id: d.id,
              name: churchDepartmentNameFromDoc(d),
            ))
        .where((e) => e.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) setState(() => _deptFilterItems = list);
  }

  Future<Map<String, dynamic>> _ensureTenantProfileLoaded() async {
    if (_tenant != null && _tenant!.isNotEmpty) {
      return Map<String, dynamic>.from(_tenant!);
    }
    final ctx = ChurchContextService.currentChurchData;
    if (ctx != null && ctx.isNotEmpty) {
      if (mounted) setState(() => _tenant = Map<String, dynamic>.from(ctx));
      return Map<String, dynamic>.from(ctx);
    }
    final churchId = ChurchRepository.churchId(
      _effectiveTenantId.isNotEmpty
          ? _effectiveTenantId
          : widget.tenantId.trim(),
    );
    if (churchId.isEmpty) return const {};

    try {
      final direct = await IgrejaDirectFirestoreReads.readIgrejaDoc(churchId);
      if (direct != null && direct.data.isNotEmpty) {
        if (mounted) {
          setState(() {
            _tenant = Map<String, dynamic>.from(direct.data);
            if (_missionCtrl.text.trim().isEmpty) {
              _missionCtrl.text = _defaultMissionText();
            }
          });
        }
        return Map<String, dynamic>.from(direct.data);
      }
    } catch (_) {}

    try {
      final loaded = await ChurchRepository.loadByChurchId(churchId);
      if (loaded.data.isNotEmpty) {
        if (mounted) {
          setState(() {
            _tenant = Map<String, dynamic>.from(loaded.data);
            if (_missionCtrl.text.trim().isEmpty) {
              _missionCtrl.text = _defaultMissionText();
            }
          });
        }
        ChurchContextService.bindChurchData(
          churchId: loaded.churchId,
          data: loaded.data,
        );
        return Map<String, dynamic>.from(loaded.data);
      }
    } catch (_) {}

    return const {};
  }

  List<ChurchLetterMemberEntry> _memberEntriesFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs
        .map(
          (d) => _entryFromDoc(d),
        )
        .toList();
  }

  ChurchLetterMemberEntry _entryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    return ChurchLetterMemberEntry(
      id: d.id,
      name: _memberName(data),
      cpfDigits: _memberCpf(data),
      data: data,
      active: _memberAtivo(data),
    );
  }

  ChurchLetterMemberEntry? _entryById(String? id) {
    if (id == null || id.isEmpty) return null;
    final cached = _selectedMembersCache[id];
    if (cached != null && cached.name.isNotEmpty) return cached;
    for (final d in _seedMemberDocs) {
      if (_docMatchesMemberId(d, id)) {
        return _entryFromDoc(d);
      }
    }
    return cached;
  }

  bool _docMatchesMemberId(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String id,
  ) {
    if (d.id == id) return true;
    final data = d.data();
    final auth =
        (data['authUid'] ?? data['firebaseUid'] ?? data['uid'] ?? '')
            .toString()
            .trim();
    if (auth.isNotEmpty && auth == id) return true;
    final cpf = _memberCpf(data);
    final idDigits = id.replaceAll(RegExp(r'\D'), '');
    if (cpf.isNotEmpty && idDigits.length == 11 && cpf == idDigits) {
      return true;
    }
    return false;
  }

  Map<String, Map<String, dynamic>> _memberDataById(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <String, Map<String, dynamic>>{};
    for (final d in docs) {
      final data = d.data();
      out[d.id] = data;
      final auth =
          (data['authUid'] ?? data['firebaseUid'] ?? data['uid'] ?? '')
              .toString()
              .trim();
      if (auth.isNotEmpty) out[auth] = data;
      final cpf = _memberCpf(data);
      if (cpf.length == 11) out[cpf] = data;
    }
    return out;
  }

  void _syncSelectedMembersCache() {
    for (final id in _selectedIds) {
      final hit = _entryById(id);
      if (hit != null) {
        _selectedMembersCache[id] = hit;
      }
    }
    _selectedMembersCache.removeWhere((k, _) => !_selectedIds.contains(k));
  }

  List<ChurchLetterMemberEntry> get _selectedMemberEntries {
    _syncSelectedMembersCache();
    return _selectedIds
        .map((id) => _selectedMembersCache[id] ?? _entryById(id))
        .whereType<ChurchLetterMemberEntry>()
        .toList();
  }

  Future<void> _pickSigner({
    required bool second,
  }) async {
    final entries = _memberEntriesFromDocs(_seedMemberDocs);
    final picked = await showChurchLetterSignerPicker(
      context,
      title: second ? '2.º assinante (opcional)' : '1.º assinante *',
      tenantId: _effectiveTenantId.isNotEmpty
          ? _effectiveTenantId
          : widget.tenantId.trim(),
      signers: entries,
      selectedId: second ? _signer2MemberId : _signer1MemberId,
      excludeId: second ? _signer1MemberId : null,
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (second) {
        _signer2MemberId = picked == _signer1MemberId ? null : picked;
      } else {
        _signer1MemberId = picked;
        if (_signer2MemberId == _signer1MemberId) _signer2MemberId = null;
      }
    });
    if (!second && _signer1MemberId != null) {
      final m = _entryById(_signer1MemberId!)?.data;
      if (m != null) {
        unawaited(_getSignatureBytesCached(_signatureUrlFromMember(m)));
      }
    }
  }

  Future<void> _openRecipientsPicker() async {
    final entries = _memberEntriesFromDocs(_seedMemberDocs);
    final picked = await showChurchLetterRecipientsPicker(
      context,
      tenantId: _effectiveTenantId.isNotEmpty
          ? _effectiveTenantId
          : widget.tenantId.trim(),
      members: entries,
      initialSelected: _selectedIds,
      departments: _deptFilterItems,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(picked);
      _selectedMembersCache
        ..clear()
        ..addEntries(
          entries
              .where((e) => picked.contains(e.id))
              .map((e) => MapEntry(e.id, e)),
        );
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _memberDocsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    if (snap != null && snap.docs.isNotEmpty) return snap.docs;
    if (_seedMemberDocs.isNotEmpty) return _seedMemberDocs;
    return const [];
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchMemberDocs() async {
    final tid = _effectiveTenantId.isNotEmpty
        ? _effectiveTenantId
        : widget.tenantId.trim();
    if (tid.isEmpty) return const [];

    try {
      final dir = await MembersDirectorySnapshotService.readOnce(tid);
      if (dir.hasEntries) {
        final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final e in dir.entries) {
          if (out.length >= _membersQueryLimit) break;
          out.add(_LettersCachedMemberQueryDoc(
            id: e.memberDocId,
            data: e.toMemberDataMap(),
          ));
        }
        if (out.isNotEmpty) {
          unawaited(
              MembersDirectorySnapshotService.warmFromCallableIfStale(tid));
          return out;
        }
      }
    } catch (_) {}

    final snap = await ChurchTenantResilientReads.membrosRecent(
      tid,
      limit: _membersQueryLimit,
    );
    return snap.docs;
  }

  Future<void> _openChurchLettersFast() async {
    final tid = _effectiveTenantId.isNotEmpty
        ? _effectiveTenantId
        : widget.tenantId.trim();
    if (tid.isEmpty) return;
    if (mounted) setState(() => _membersSyncing = true);
    try {
      final docs = await _fetchMemberDocs();
      if (!mounted || docs.isEmpty) return;
      _ChurchLettersMembersRamCache.put(tid, docs);
      setState(() {
        _seedMemberDocs = docs;
        _membersFuture = Future.value(_LettersMembersListSnapshot(docs));
        _applyDefaultSignerFromLoadedMembers(docs);
        _syncSelectedMembersCache();
        _membersSyncing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _membersSyncing = false);
    }
  }

  Future<void> _bootstrap() async {
    final churchId = ChurchRepository.churchId(widget.tenantId.trim());
    if (churchId.isNotEmpty && mounted) {
      setState(() => _effectiveTenantId = churchId);
    }

    await _ensureTenantProfileLoaded();

    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final cfg = await FirestoreWebGuard.runWithWebRecovery(
        () => _configRef.get(const GetOptions(source: Source.serverAndCache)),
        maxAttempts: 4,
      );
      final c = cfg.data() ?? {};
      final a = (c['modeloApresentacao'] ?? '').toString().trim();
      final t = (c['modeloTransferencia'] ?? '').toString().trim();
      final g = (c['modeloAgradecimento'] ?? '').toString().trim();
      if (mounted) {
        setState(() {
          _tplApresentacaoCtrl.text =
              a.isNotEmpty ? a : kDefaultChurchLetterApresentacaoTemplate.trim();
          _tplTransferCtrl.text =
              t.isNotEmpty ? t : kDefaultChurchLetterTransferenciaTemplate.trim();
          _tplAgradecimentoCtrl.text = g.isNotEmpty
              ? g
              : kDefaultChurchLetterAgradecimentoTemplate.trim();
          if (_missionCtrl.text.trim().isEmpty) {
            _missionCtrl.text = _defaultMissionText();
          }
        });
      }
      if (c['modelosNuvem'] is Map &&
          (c['modelosNuvem'] as Map).isNotEmpty) {
        unawaited(
          ChurchCartasModelosService.migrateLegacyFromConfig(
            seedTenantId: churchId,
            modelosNuvem: Map<String, dynamic>.from(c['modelosNuvem'] as Map),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tplApresentacaoCtrl.text =
              kDefaultChurchLetterApresentacaoTemplate.trim();
          _tplTransferCtrl.text =
              kDefaultChurchLetterTransferenciaTemplate.trim();
          _tplAgradecimentoCtrl.text =
              kDefaultChurchLetterAgradecimentoTemplate.trim();
          if (_missionCtrl.text.trim().isEmpty) {
            _missionCtrl.text = _defaultMissionText();
          }
        });
      }
    }

    if (_seedMemberDocs.isNotEmpty) {
      _applyDefaultSignerFromLoadedMembers(_seedMemberDocs);
    } else {
      await _defaultSignerFromMembro();
    }
    unawaited(_getBrandingCached());
    await _loadDepartmentsForLetters();
    if (mounted && _missionCtrl.text.trim().isEmpty) {
      setState(() => _missionCtrl.text = _defaultMissionText());
    }
  }

  void _applyDefaultSignerFromLoadedMembers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_signer1MemberId != null &&
        docs.any((d) => d.id == _signer1MemberId)) {
      return;
    }

    final gestorNome = (_tenant?['gestorNome'] ??
            _tenant?['gestor_nome'] ??
            _tenant?['responsavel'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (gestorNome.isNotEmpty) {
      for (final d in docs) {
        if (!_memberAtivo(d.data())) continue;
        if (!memberCanSignChurchDocuments(d.data())) continue;
        final n = _memberName(d.data()).toLowerCase();
        if (n == gestorNome || n.contains(gestorNome)) {
          _signer1MemberId = d.id;
          return;
        }
      }
    }

    for (final d in docs) {
      final m = d.data();
      if (!_memberAtivo(m)) continue;
      if (!memberCanSignChurchDocuments(m)) continue;
      final funcoes = m['FUNCOES'];
      if (funcoes is List) {
        for (final f in funcoes) {
          final fn = f.toString().toLowerCase();
          if (fn.contains('pastor') ||
              fn.contains('gestor') ||
              fn.contains('presidente')) {
            _signer1MemberId = d.id;
            return;
          }
        }
      }
      final cargo = _cargoFromMember(m).toLowerCase();
      if (cargo.contains('pastor') ||
          cargo.contains('gestor') ||
          cargo.contains('presidente')) {
        _signer1MemberId = d.id;
        return;
      }
    }
  }

  Future<void> _defaultSignerFromMembro() async {
    final tid = _effectiveTenantId.trim();
    if (tid.isEmpty) return;

    final op = ChurchRepository.churchId(tid.trim());
    final col =         ChurchUiCollections.membros(op);

    DocumentSnapshot<Map<String, dynamic>>? memDoc;
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final bySelf = await col.doc(user.uid).get();
        if (bySelf.exists) memDoc = bySelf;
      } catch (_) {}
      if (memDoc == null) {
        try {
          final q =
              await col.where('authUid', isEqualTo: user.uid).limit(1).get();
          if (q.docs.isNotEmpty) memDoc = q.docs.first;
        } catch (_) {}
      }
      if (memDoc == null) {
        try {
          final q = await col
              .where('firebaseUid', isEqualTo: user.uid)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) memDoc = q.docs.first;
        } catch (_) {}
      }
      if (memDoc == null) {
        final email = user.email?.trim();
        if (email != null && email.isNotEmpty) {
          for (final v in <String>{email, email.toLowerCase()}) {
            try {
              final q = await col.where('email', isEqualTo: v).limit(1).get();
              if (q.docs.isNotEmpty) {
                memDoc = q.docs.first;
                break;
              }
            } catch (_) {}
            try {
              final q = await col.where('EMAIL', isEqualTo: v).limit(1).get();
              if (q.docs.isNotEmpty) {
                memDoc = q.docs.first;
                break;
              }
            } catch (_) {}
          }
        }
      }
    }

    final cpfDigits = widget.cpf.replaceAll(RegExp(r'\D'), '');
    if (memDoc == null && cpfDigits.length == 11) {
      try {
        final byId = await col.doc(cpfDigits).get();
        if (byId.exists) memDoc = byId;
      } catch (_) {}
      if (memDoc == null) {
        for (final field in ['CPF', 'cpf']) {
          try {
            final q =
                await col.where(field, isEqualTo: cpfDigits).limit(1).get();
            if (q.docs.isNotEmpty) {
              memDoc = q.docs.first;
              break;
            }
          } catch (_) {}
        }
      }
    }

    if (memDoc != null && memDoc.exists && mounted) {
      setState(() => _signer1MemberId = memDoc!.id);
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadMembers() async {
    final docs = await _fetchMemberDocs();
    final tid = _effectiveTenantId.isNotEmpty
        ? _effectiveTenantId
        : widget.tenantId.trim();
    if (tid.isNotEmpty && docs.isNotEmpty) {
      _ChurchLettersMembersRamCache.put(tid, docs);
    }
    if (mounted) {
      setState(() {
        _seedMemberDocs = docs;
        _applyDefaultSignerFromLoadedMembers(docs);
      });
    }
    return _LettersMembersListSnapshot(docs);
  }

  void _refreshMembers() {
    final prev = _seedMemberDocs;
    setState(() {
      _membersSyncing = true;
      _membersFuture = prev.isNotEmpty
          ? Future.value(_LettersMembersListSnapshot(prev))
          : _loadMembers();
    });
    unawaited(() async {
      try {
        final snap = await _loadMembers();
        if (!mounted) return;
        setState(() {
          _seedMemberDocs = snap.docs;
          _membersFuture = Future.value(_LettersMembersListSnapshot(_seedMemberDocs));
          _membersSyncing = false;
        });
      } catch (_) {
        if (mounted) setState(() => _membersSyncing = false);
      }
    }());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _destIgrejaCtrl.dispose();
    _missionCtrl.dispose();
    _tplApresentacaoCtrl.dispose();
    _tplTransferCtrl.dispose();
    _tplAgradecimentoCtrl.dispose();
    super.dispose();
  }

  String get _nomeIgreja {
    final t = _tenant;
    if (t != null) {
      final n = (t['nome'] ?? t['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    final ctx = ChurchContextService.currentChurchData;
    if (ctx != null) {
      final n = (ctx['nome'] ?? ctx['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    final brand = _brandingReady?.churchName.trim() ?? '';
    if (brand.isNotEmpty) return brand;
    return 'Igreja';
  }

  String get _gestorNomeExibicao =>
      (_tenant?['gestorNome'] ??
              _tenant?['gestor_nome'] ??
              _tenant?['responsavel'] ??
              '')
          .toString()
          .trim();

  String get _gestorCargoExibicao =>
      (_tenant?['gestorCargo'] ?? _tenant?['gestor_cargo'] ?? 'Pastor(a) Presidente')
          .toString()
          .trim();

  String _enderecoCompletoLine() {
    final d = _tenant;
    if (d == null) return '';
    final rua = (d['rua'] ?? d['address'] ?? '').toString().trim();
    final qd = (d['quadraLoteNumero'] ?? '').toString().trim();
    final ruaC = rua.isEmpty ? qd : (qd.isEmpty ? rua : '$rua, $qd');
    final bairro = (d['bairro'] ?? '').toString().trim();
    final parts = <String>[
      if (ruaC.isNotEmpty) ruaC,
      if (bairro.isNotEmpty) bairro,
    ];
    return parts.join(' · ');
  }

  String _telefoneIgrejaLine() {
    final d = _tenant;
    if (d == null) return '';
    return (d['telefoneIgreja'] ??
            d['telefone'] ??
            d['whatsappIgreja'] ??
            d['whatsapp'] ??
            '')
        .toString()
        .trim();
  }

  String _cepLine() {
    final d = _tenant;
    if (d == null) return '';
    final raw = (d['cep'] ?? d['CEP'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) {
      return 'CEP ${digits.substring(0, 5)}-${digits.substring(5)}';
    }
    return 'CEP $raw';
  }

  Widget _buildChurchIdentityCard(Color accent) {
    final igreja = _nomeIgreja;
    final local = _cityStateLine();
    final gestor = _gestorNomeExibicao;
    final cargo = _gestorCargoExibicao;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.08),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.church_rounded, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  igreja,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_membersSyncing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          if (local.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              local,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          if (_enderecoCompletoLine().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _enderecoCompletoLine(),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
          if (_cepLine().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _cepLine(),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
          if (_telefoneIgrejaLine().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Tel.: ${_telefoneIgrejaLine()}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
          if (gestor.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '$cargo: $gestor',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersListSkeleton() {
    Widget row() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EDF3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [row(), row(), row(), row(), row()]),
    );
  }

  String _cityStateLine() {
    final d = _tenant;
    if (d == null) return '';
    final cidade =
        (d['cidade'] ?? d['CIDADE'] ?? d['localidade'] ?? '').toString().trim();
    final uf = (d['estado'] ?? d['UF'] ?? d['uf'] ?? '').toString().trim();
    if (cidade.isEmpty && uf.isEmpty) return '';
    if (cidade.isEmpty) return uf;
    if (uf.isEmpty) return cidade;
    return '$cidade/$uf';
  }

  String _memberName(Map<String, dynamic> m) =>
      ChurchLetterMemberEntry.nameFromData(m);

  String _memberCpf(Map<String, dynamic> m) {
    final raw = (m['CPF'] ?? m['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    return raw;
  }

  String _cargoFromMember(Map<String, dynamic> m) {
    return (m['CARGO'] ??
            m['FUNCAO'] ??
            m['funcao'] ??
            m['FUNCAO_PERMISSOES'] ??
            m['cargo'] ??
            '')
        .toString()
        .trim();
  }

  String _contactLineFromMember(Map<String, dynamic> m) {
    final tel = (m['TELEFONES'] ??
            m['telefone'] ??
            m['CELULAR'] ??
            m['celular'] ??
            m['whatsapp'] ??
            '')
        .toString()
        .trim();
    final mail = (m['EMAIL'] ?? m['email'] ?? '').toString().trim();
    if (tel.isNotEmpty && mail.isNotEmpty) return '$tel · $mail';
    if (tel.isNotEmpty) return tel;
    return mail;
  }

  Map<String, dynamic>? _memberData(
    QuerySnapshot<Map<String, dynamic>> snap,
    String? docId,
  ) {
    if (docId == null || docId.isEmpty) return null;
    for (final d in snap.docs) {
      if (d.id == docId) return d.data();
    }
    return null;
  }

  String _signatureUrlFromMember(Map<String, dynamic> m) {
    return (m['assinaturaUrl'] ??
            m['assinatura_url'] ??
            '')
        .toString()
        .trim();
  }

  Future<ReportPdfBranding> _getBrandingCached() {
    if (_brandingReady != null) {
      return Future.value(_brandingReady!);
    }
    _brandingFuture ??= loadReportPdfBranding(
      ChurchRepository.churchId(_effectiveTenantId),
    ).then((b) {
      _brandingReady = b;
      return b;
    });
    return _brandingFuture!;
  }

  /// Emissão expressa — só cache RAM (pré-aquecido ao abrir / trocar assinante).
  Future<Uint8List?> _signatureBytesForEmit(Map<String, dynamic> signerData) async {
    if (_signatureMode != _LetterSignatureMode.digital) return null;
    final url = sanitizeImageUrl(_signatureUrlFromMember(signerData));
    if (url.isEmpty) return null;
    return _signatureBytesCache[url];
  }

  Future<void> _prewarmPdfEmitAssets() async {
    await warmChurchLetterPdfAssets();
    try {
      await _getBrandingCached().timeout(const Duration(seconds: 8));
    } catch (_) {}
    final sid = _signer1MemberId;
    if (sid != null) {
      final m = _entryById(sid)?.data ??
          _memberDataById(_seedMemberDocs)[sid];
      if (m != null) {
        unawaited(_getSignatureBytesCached(_signatureUrlFromMember(m)));
      }
    }
  }

  Future<Uint8List?> _getSignatureBytesCached(String rawUrl) async {
    final url = sanitizeImageUrl(rawUrl);
    if (url.isEmpty) return null;
    if (_signatureBytesCache.containsKey(url)) return _signatureBytesCache[url];
    try {
      final bytes = await ImageHelper.getBytesFromUrlOrNull(
        url,
        timeout: const Duration(seconds: 6),
      );
      _signatureBytesCache[url] = bytes;
      return bytes;
    } catch (_) {
      _signatureBytesCache[url] = null;
      return null;
    }
  }

  String _contactoPdf(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) =>
      _contactoPdfFromMaps(_memberDataById(snap.docs));

  String _contactoPdfFromMaps(Map<String, Map<String, dynamic>> byId) {
    final m1 = _signer1MemberId != null ? byId[_signer1MemberId!] : null;
    final m2 = _signer2MemberId != null ? byId[_signer2MemberId!] : null;
    final c1 = m1 != null ? _contactLineFromMember(m1) : '';
    final c2 = m2 != null ? _contactLineFromMember(m2) : '';
    if (c1.isEmpty) return c2;
    if (c2.isEmpty || c1 == c2) return c1;
    return '$c1 · $c2';
  }

  String _defaultMissionText() {
    final d = _tenant;
    if (d == null) {
      return 'evangelizar, discipular e servir a comunidade';
    }
    final m = (d['missao'] ??
            d['descricao'] ??
            d['sobre'] ??
            'evangelizar, discipular e servir a comunidade')
        .toString()
        .trim();
    return m.isNotEmpty
        ? m
        : 'evangelizar, discipular e servir a comunidade';
  }

  String get _tenantKey =>
      _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId;

  Color _accentForCartaKind(_CartaKind kind) => switch (kind) {
        _CartaKind.apresentacao => const Color(0xFF2563EB),
        _CartaKind.transferencia => const Color(0xFFEA580C),
        _CartaKind.agradecimento => const Color(0xFF16A34A),
      };

  /// Botões do histórico — coloridos; empilham no mobile e alinham em linha no web/tablet.
  Widget _buildHistoricoActionBar({
    required VoidCallback onReprint,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    required bool stackVertical,
  }) {
    ButtonStyle pill(Color bg, Color fg) => FilledButton.styleFrom(
          backgroundColor: bg.withValues(alpha: 0.14),
          foregroundColor: fg,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(
            horizontal: stackVertical ? 14 : 16,
            vertical: 12,
          ),
          minimumSize: Size(
            stackVertical ? double.infinity : ThemeCleanPremium.minTouchTarget,
            ThemeCleanPremium.minTouchTarget,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        );

    final reprint = FilledButton.icon(
      onPressed: onReprint,
      style: pill(const Color(0xFF2563EB), const Color(0xFF1D4ED8)),
      icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
      label: const Text(
        'Reimprimir',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final edit = FilledButton.icon(
      onPressed: onEdit,
      style: pill(const Color(0xFF16A34A), const Color(0xFF15803D)),
      icon: const Icon(Icons.edit_rounded, size: 20),
      label: const Text(
        'Editar',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final delete = FilledButton.icon(
      onPressed: onDelete,
      style: pill(const Color(0xFFDC2626), const Color(0xFFB91C1C)),
      icon: const Icon(Icons.delete_outline_rounded, size: 20),
      label: const Text(
        'Excluir',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    if (stackVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          reprint,
          const SizedBox(height: 8),
          edit,
          const SizedBox(height: 8),
          delete,
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        reprint,
        edit,
        delete,
      ],
    );
  }

  ({DateTime start, DateTime end}) _historicoRange() {
    if (_histCustomRange != null) {
      return (
        start: DateTime(
          _histCustomRange!.start.year,
          _histCustomRange!.start.month,
          _histCustomRange!.start.day,
        ),
        end: DateTime(
          _histCustomRange!.end.year,
          _histCustomRange!.end.month,
          _histCustomRange!.end.day,
          23,
          59,
          59,
        ),
      );
    }
    return (
      start: DateTime(_histYear, 1, 1),
      end: DateTime(_histYear, 12, 31, 23, 59, 59),
    );
  }

  void _refreshHistoricoStream() =>
      setState(() => _historicoStreamGen++);

  _CartaKind _currentCartaKindForTabs(
    bool transferenciaTab,
    bool agradecimentoTab,
  ) {
    if (transferenciaTab) return _CartaKind.transferencia;
    if (agradecimentoTab) return _CartaKind.agradecimento;
    return _CartaKind.apresentacao;
  }

  TextEditingController _tplCtrlForKind(_CartaKind k) => switch (k) {
        _CartaKind.apresentacao => _tplApresentacaoCtrl,
        _CartaKind.transferencia => _tplTransferCtrl,
        _CartaKind.agradecimento => _tplAgradecimentoCtrl,
      };

  String _defaultTemplateForKind(_CartaKind k) => switch (k) {
        _CartaKind.apresentacao =>
          kDefaultChurchLetterApresentacaoTemplate.trim(),
        _CartaKind.transferencia =>
          kDefaultChurchLetterTransferenciaTemplate.trim(),
        _CartaKind.agradecimento =>
          kDefaultChurchLetterAgradecimentoTemplate.trim(),
      };

  String _labelCartaKind(_CartaKind k) => switch (k) {
        _CartaKind.apresentacao => 'apresentação',
        _CartaKind.transferencia => 'transferência',
        _CartaKind.agradecimento => 'agradecimento',
      };

  Future<void> _confirmRestoreDefaultTemplate(
    _CartaKind kind,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Restaurar modelo padrão?'),
        content: Text(
          'O texto do modelo de ${_labelCartaKind(kind)} será substituído pelo texto original do sistema. '
          'Esta ação não guarda automaticamente na nuvem — use «Guardar modelos na nuvem» se quiser persistir.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _tplCtrlForKind(kind).text = _defaultTemplateForKind(kind);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Modelo de ${_labelCartaKind(kind)} reposto ao padrão.',
        ),
      );
    }
  }

  void _restoreMissionFromChurch() {
    setState(() => _missionCtrl.text = _defaultMissionText());
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Missão / descrição repostas ao texto do cadastro da igreja.',
      ),
    );
  }

  Future<void> _saveTemplates({bool showSnackOnSuccess = true}) async {
    if (!AppPermissions.canAccessChurchLetters(widget.role,
        permissions: widget.permissions)) {
      return;
    }
    final churchId = ChurchRepository.churchId(
      _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId,
    );
    if (churchId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Igreja não identificada — não foi possível guardar na nuvem.',
          ),
        );
      }
      return;
    }
    setState(() => _savingTpl = true);
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final ref = ChurchUiCollections.config(churchId).doc('cartas');
      await FirestoreWebGuard.runWithWebRecovery(
        () => ref.set(
          {
            'modeloApresentacao': _tplApresentacaoCtrl.text,
            'modeloTransferencia': _tplTransferCtrl.text,
            'modeloAgradecimento': _tplAgradecimentoCtrl.text,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        ),
        maxAttempts: 4,
      );
      if (mounted && showSnackOnSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Modelos guardados na nuvem.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao guardar: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _savingTpl = false);
    }
  }

  Future<void> _persistHistorico({
    required _CartaKind kind,
    required String templateText,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final memberDocIds = _selectedIds.toList()..sort();
    final signers = <String>[];
    if (_signer1MemberId != null) signers.add(_signer1MemberId!);
    if (_signer2MemberId != null &&
        _signer2MemberId!.isNotEmpty &&
        _signer2MemberId != _signer1MemberId) {
      signers.add(_signer2MemberId!);
    }

    final payload = <String, dynamic>{
      'kind': kind.firestoreKind,
      'destIgreja': _destIgrejaCtrl.text.trim(),
      'mission': _missionCtrl.text.trim(),
      'memberDocIds': memberDocIds,
      'signerMemberIds': signers,
      'templateText': templateText,
      'signatureMode':
          _signatureMode == _LetterSignatureMode.digital ? 'digital' : 'manual',
      'updatedAt': FieldValue.serverTimestamp(),
      'emitidoPorUid': uid,
    };

    if (_historyEditDocId != null) {
      await FirestoreWebGuard.runWithWebRecovery(
        () => _historicoCol.doc(_historyEditDocId!).set(
              payload,
              SetOptions(merge: true),
            ),
        maxAttempts: 4,
      );
    } else {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await FirestoreWebGuard.runWithWebRecovery(
        () => _historicoCol.add(payload),
        maxAttempts: 4,
      );
    }
  }

  Future<void> _emitPdf(
    _CartaKind kind, {
    bool saveHistorico = true,
  }) async {
    if (!AppPermissions.canAccessChurchLetters(widget.role,
        permissions: widget.permissions)) {
      return;
    }
    final dest = _destIgrejaCtrl.text.trim();
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          kind == _CartaKind.agradecimento
              ? 'Indique o nome do destinatário (empresa, instituição ou pessoa).'
              : 'Indique o nome da igreja destinatária.',
        ),
      );
      return;
    }
    if (kind != _CartaKind.agradecimento && _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Selecione pelo menos um membro.'),
      );
      return;
    }
    if (_signer1MemberId == null || _signer1MemberId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Selecione o 1.º assinante no cadastro de membros.',
        ),
      );
      return;
    }

    if (_signer1MemberId != null && _signer1MemberId!.isNotEmpty) {
      final m1Early = _entryById(_signer1MemberId!)?.data ??
          _memberDataById(_seedMemberDocs)[_signer1MemberId!];
      if (m1Early != null) {
        unawaited(_getSignatureBytesCached(_signatureUrlFromMember(m1Early)));
      }
    }

    Timer? pdfOverlayTimer;
    if (mounted) {
      pdfOverlayTimer = Timer(const Duration(milliseconds: 160), () {
        if (mounted) setState(() => _pdfBusy = true);
      });
    }
    YahwehFlowLog.cartaStart();
    try {
      await _ensureTenantProfileLoaded();
      final tenantData = _tenant ?? const <String, dynamic>{};

      final byId = _memberDataById(_seedMemberDocs);
      final lines = <ChurchLetterMemberLine>[];
      for (final id in _selectedIds) {
        final m = byId[id] ??
            _entryById(id)?.data ??
            _selectedMembersCache[id]?.data;
        if (m == null) continue;
        final n = _memberName(m);
        if (n.isEmpty) continue;
        final cpf = _memberCpf(m);
        lines.add(ChurchLetterMemberLine(name: n, cpfDigits: cpf.isEmpty ? null : cpf));
      }
      if (lines.isEmpty) {
        final okAgradSemLista =
            kind == _CartaKind.agradecimento && _selectedIds.isEmpty;
        if (!okAgradSemLista) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Membros selecionados inválidos.',
              ),
            );
          }
          return;
        }
      }

      final m1 = byId[_signer1MemberId!];
      if (m1 == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Assinante 1 não encontrado na lista.'),
          );
        }
        return;
      }
      final n1 = _memberName(m1);
      final r1 = _cargoFromMember(m1);
      if (n1.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Nome do assinante 1 em falta no cadastro.'),
          );
        }
        return;
      }

      String n2 = '';
      String r2 = '';
      if (_signer2MemberId != null &&
          _signer2MemberId!.isNotEmpty &&
          _signer2MemberId != _signer1MemberId) {
        final m2 = byId[_signer2MemberId!];
        if (m2 != null) {
          n2 = _memberName(m2);
          r2 = _cargoFromMember(m2);
        }
      }

      final contactPdf = _contactoPdfFromMaps(byId);
      if (contactPdf.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
              'Inclua telefone ou e-mail no cadastro do(s) assinante(s).',
            ),
          );
        }
        return;
      }

      PdfDigitalStampInput? digitalStamp;
      if (_signatureMode == _LetterSignatureMode.digital) {
        final cpf = (m1['CPF'] ?? m1['cpf'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
        digitalStamp = PdfDigitalStampInput.now(
          signerName: n1,
          signerCpfDigits: cpf.length == 11 ? cpf : null,
          churchName: _nomeIgreja,
          churchData: tenantData.isNotEmpty ? tenantData : (_tenant ?? {}),
        );
      }

      final tpl = switch (kind) {
        _CartaKind.apresentacao => _tplApresentacaoCtrl.text,
        _CartaKind.transferencia => _tplTransferCtrl.text,
        _CartaKind.agradecimento => _tplAgradecimentoCtrl.text,
      };
      final membersBlock = churchLetterMembersBlock(lines);
      final membersInline = churchLetterMembersInline(lines);
      final filled = fillChurchLetterTemplate(
        template: tpl,
        destinationChurchName: dest,
        issuingChurchName: _nomeIgreja,
        cityState: _cityStateLine(),
        missionDescription: _missionCtrl.text.trim(),
        membersBlock: membersBlock,
        signer1Name: n1,
        signer1Role: r1,
        signer2Name: n2,
        signer2Role: r2,
        issuerChurchLine: _nomeIgreja,
        issuerContact: contactPdf,
        membersInline: membersInline,
        openingSalutation: (kind == _CartaKind.transferencia ||
                kind == _CartaKind.agradecimento)
            ? 'Atenciosamente'
            : 'Fraternalmente em Cristo,',
      );

      final branding = _brandingReady ??
          await _getBrandingCached().timeout(
            const Duration(milliseconds: 400),
            onTimeout: () => ReportPdfBranding(
              churchName: _nomeIgreja,
              logoBytes: null,
              accent: ReportPdfBranding.defaultAccent,
            ),
          );

      unawaited(warmChurchLetterPdfAssets());

      final title = switch (kind) {
        _CartaKind.apresentacao => 'Carta de apresentação ministerial',
        _CartaKind.transferencia => 'CARTA DE MUDANÇA',
        _CartaKind.agradecimento => 'CARTA DE AGRADECIMENTO',
      };

      final bytes = await buildChurchTransferLetterPdf(
        branding: branding,
        documentTitle: title,
        bodyAfterReplacements: filled,
        churchData: tenantData.isNotEmpty ? tenantData : (_tenant ?? {}),
        reserveManualSignatureSpace: _signatureMode == _LetterSignatureMode.manual,
        digitalStamp: digitalStamp,
      );

      if (!mounted) return;
      YahwehFlowLog.cartaSuccess();
      final slug = (_tenant?['slug'] ?? _effectiveTenantId)
          .toString()
          .replaceAll(RegExp(r'[^\w\-]'), '_');
      final kindSlug = kind.firestoreKind;

      if (saveHistorico) {
        unawaited(() async {
          try {
            await _persistHistorico(kind: kind, templateText: tpl);
            if (mounted) setState(() => _historyEditDocId = null);
          } catch (e, st) {
            YahwehFlowLog.error('CARTA_HIST', e, st);
          }
        }());
      }

      unawaited(
        showPdfActions(
          context,
          bytes: bytes,
          filename: '${slug}_carta_${kindSlug}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        ),
      );
    } catch (e, st) {
      YahwehFlowLog.error('CARTA', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao gerar PDF: $e'),
        );
      }
    } finally {
      pdfOverlayTimer?.cancel();
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _reprintFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data() ?? {};
    final kind = _cartaKindFromFirestore((d['kind'] ?? '').toString());
    _destIgrejaCtrl.text = (d['destIgreja'] ?? '').toString();
    _missionCtrl.text = (d['mission'] ?? '').toString();
    final mids = List<String>.from(d['memberDocIds'] ?? []);
    _selectedIds
      ..clear()
      ..addAll(mids);
    _selectedMembersCache.clear();
    _syncSelectedMembersCache();
    final sigs = List<String>.from(d['signerMemberIds'] ?? []);
    _signer1MemberId = sigs.isNotEmpty ? sigs[0] : null;
    _signer2MemberId = sigs.length > 1 ? sigs[1] : null;
    final ttext = (d['templateText'] ?? '').toString();
    final mode = (d['signatureMode'] ?? 'digital').toString().trim().toLowerCase();
    _signatureMode = mode == 'manual'
        ? _LetterSignatureMode.manual
        : _LetterSignatureMode.digital;
    switch (kind) {
      case _CartaKind.transferencia:
        _tplTransferCtrl.text = ttext;
        break;
      case _CartaKind.agradecimento:
        _tplAgradecimentoCtrl.text = ttext;
        break;
      case _CartaKind.apresentacao:
        _tplApresentacaoCtrl.text = ttext;
        break;
    }
    _historyEditDocId = null;
    setState(() {});
    await _emitPdf(kind, saveHistorico: false);
  }

  void _loadForEdit(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final kind = _cartaKindFromFirestore((d['kind'] ?? '').toString());
    _destIgrejaCtrl.text = (d['destIgreja'] ?? '').toString();
    _missionCtrl.text = (d['mission'] ?? '').toString();
    final mids = List<String>.from(d['memberDocIds'] ?? []);
    _selectedIds
      ..clear()
      ..addAll(mids);
    _selectedMembersCache.clear();
    _syncSelectedMembersCache();
    final sigs = List<String>.from(d['signerMemberIds'] ?? []);
    _signer1MemberId = sigs.isNotEmpty ? sigs[0] : null;
    _signer2MemberId = sigs.length > 1 ? sigs[1] : null;
    final ttext = (d['templateText'] ?? '').toString();
    final mode = (d['signatureMode'] ?? 'digital').toString().trim().toLowerCase();
    _signatureMode = mode == 'manual'
        ? _LetterSignatureMode.manual
        : _LetterSignatureMode.digital;
    switch (kind) {
      case _CartaKind.transferencia:
        _tplTransferCtrl.text = ttext;
        break;
      case _CartaKind.agradecimento:
        _tplAgradecimentoCtrl.text = ttext;
        break;
      case _CartaKind.apresentacao:
        _tplApresentacaoCtrl.text = ttext;
        break;
    }
    _historyEditDocId = doc.id;
    _tabs.animateTo(switch (kind) {
      _CartaKind.apresentacao => 0,
      _CartaKind.transferencia => 1,
      _CartaKind.agradecimento => 2,
    });
  setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Registo carregado. Ajuste e use «Gerar PDF» para gravar alterações.',
      ),
    );
  }

  Future<void> _confirmDelete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registo?'),
        content: const Text(
          'Esta entrada do histórico será removida. O PDF já emitido não é apagado do dispositivo dos destinatários.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await doc.reference.delete();
      if (mounted) {
        setState(() => _historicoStreamGen++);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Registo excluído.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro: $e'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPermissions.canAccessChurchLetters(widget.role,
        permissions: widget.permissions)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sem permissão para este módulo.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final accent = ThemeCleanPremium.primary;
    final fieldRadius = BorderRadius.circular(12);
    final fieldBorder = OutlineInputBorder(borderRadius: fieldRadius);
    InputDecoration premiumField(String label,
            {String? hint, String? helper, int? maxLines}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          border: fieldBorder,
          enabledBorder: fieldBorder,
          focusedBorder: OutlineInputBorder(
            borderRadius: fieldRadius,
            borderSide: BorderSide(color: accent, width: 1.75),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          isDense: true,
          alignLabelWithHint: maxLines != null && maxLines > 1,
        );

    final tabIdx = _tabs.index;
    final isHistorico = tabIdx == 3;
    final transferenciaTab = tabIdx == 1;
    final agradecimentoTab = tabIdx == 2;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.embeddedInShell ? 8 : 16,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.embeddedInShell)
                ModuleHeaderPremium(
                  title: 'Cartas e transferências',
                  icon: Icons.article_rounded,
                  subtitle:
                      'PDF em normas cultas (margens amplas, parágrafos justificados com recuo, assinatura centralizada). Apresentação, transferência e agradecimento — até 2 assinaturas do cadastro e histórico na nuvem.',
                )
              else ...[
                Text(
                  'Emita cartas com a identidade visual do sistema: logo e dados da igreja no topo, texto personalizável e lista de membros.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (widget.embeddedInShell) const SizedBox(height: 12),
              _buildChurchIdentityCard(accent),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusLg + 1),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.82),
                      ThemeCleanPremium.primaryLight,
                    ],
                  ),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Container(
                  margin: const EdgeInsets.all(1.4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ColoredBox(
                        color: accent,
                        child: ChurchPanelPillTabBar(
                          controller: _tabs,
                          dense: true,
                          tabs: const [
                            Tab(text: 'Apresentação'),
                            Tab(text: 'Transferência'),
                            Tab(text: 'Agradecimento'),
                            Tab(text: 'Histórico'),
                          ],
                        ),
                      ),
                      if (isHistorico)
                        _buildHistoricoPanel(accent, premiumField)
                      else
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _destIgrejaCtrl,
                                decoration: premiumField(
                                  agradecimentoTab
                                      ? 'Destinatário *'
                                      : 'Igreja destinatária *',
                                  hint: agradecimentoTab
                                      ? 'Empresa, instituição ou pessoa que receberá a carta'
                                      : 'Nome da igreja que receberá a carta',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _missionCtrl,
                                maxLines: 2,
                                decoration: premiumField(
                                  agradecimentoTab
                                      ? 'Motivo da gratidão / descrição breve'
                                      : 'Missão / descrição breve',
                                  hint: agradecimentoTab
                                      ? 'Substitui [ocasião ou motivo da gratidão] no modelo'
                                      : 'Substitui o marcador de missão no texto',
                                  maxLines: 2,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _restoreMissionFromChurch,
                                  icon: Icon(
                                    Icons.history_rounded,
                                    size: 18,
                                    color: accent,
                                  ),
                                  label: Text(
                                    agradecimentoTab
                                        ? 'Repor motivo (cadastro da entidade)'
                                        : 'Repor missão (cadastro igreja)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                future: _membersFuture,
                                builder: (context, msnap) {
                                  if (msnap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Column(
                                        children: [
                                          Text(
                                            'Erro ao carregar assinantes: ${msnap.error}',
                                            style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          TextButton.icon(
                                            onPressed: _refreshMembers,
                                            icon: const Icon(Icons.refresh_rounded),
                                            label: const Text('Tentar novamente'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final docs =
                                      List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                                    _memberDocsFromSnapshot(msnap.data),
                                  )..sort((a, b) => _memberName(a.data())
                                        .toLowerCase()
                                        .compareTo(
                                            _memberName(b.data()).toLowerCase()));
                                  if (docs.isEmpty &&
                                      (msnap.connectionState ==
                                              ConnectionState.waiting ||
                                          _membersSyncing)) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        LinearProgressIndicator(
                                          minHeight: 3,
                                          color: accent.withValues(alpha: 0.65),
                                          backgroundColor:
                                              accent.withValues(alpha: 0.12),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildMembersListSkeleton(),
                                      ],
                                    );
                                  }
                                  final activeDocs = docs
                                      .where((d) => _memberAtivo(d.data()))
                                      .toList();

                                  if (activeDocs.isEmpty && docs.isNotEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        'Nenhum membro ativo no cadastro. Atualize em Membros ou toque em «Atualizar lista» abaixo.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade800,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }

                                  final signerPool = activeDocs
                                      .where((d) =>
                                          memberCanSignChurchDocuments(d.data()))
                                      .length;
                                  final tid = _effectiveTenantId.isNotEmpty
                                      ? _effectiveTenantId
                                      : widget.tenantId.trim();

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'Quem assina',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.grey.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        signerPool > 0
                                            ? '$signerPool assinante(s) elegível(is): pastor, gestor, secretário, tesoureiro, administrador ou líder de departamento.'
                                            : 'Cadastre liderança em Membros (pastor, gestor, secretário, tesoureiro ou líder).',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ChurchLetterSignerTile(
                                        label: '1.º assinante *',
                                        tenantId: tid,
                                        entry: _entryById(_signer1MemberId),
                                        onTap: () => _pickSigner(second: false),
                                      ),
                                      const SizedBox(height: 10),
                                      ChurchLetterSignerTile(
                                        label: '2.º assinante (opcional)',
                                        tenantId: tid,
                                        entry: _entryById(_signer2MemberId),
                                        optional: true,
                                        onTap: () => _pickSigner(second: true),
                                      ),
                                      if (_signer2MemberId != null)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () => setState(
                                              () => _signer2MemberId = null,
                                            ),
                                            child: const Text('Remover 2.º assinante'),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      if (docs.isNotEmpty)
                                        InputDecorator(
                                          decoration: premiumField(
                                            'Contato no documento (automático)',
                                            helper:
                                                'Unão dos contactos dos assinantes no cadastro',
                                          ),
                                          child: Text(
                                            _contactoPdf(
                                              _LettersMembersListSnapshot(docs),
                                            ),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ),
                                      if (docs.isNotEmpty &&
                                          _contactoPdf(
                                            _LettersMembersListSnapshot(docs),
                                          ).isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            'Adicione telefone ou e-mail no cadastro do assinante.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      SegmentedButton<_LetterSignatureMode>(
                                        segments: const [
                                          ButtonSegment<_LetterSignatureMode>(
                                            value: _LetterSignatureMode.digital,
                                            icon: Icon(Icons.draw_rounded),
                                            label: Text('Assinatura digital'),
                                          ),
                                          ButtonSegment<_LetterSignatureMode>(
                                            value: _LetterSignatureMode.manual,
                                            icon: Icon(Icons.edit_note_rounded),
                                            label: Text('Assinar manualmente'),
                                          ),
                                        ],
                                        selected: {_signatureMode},
                                        onSelectionChanged: (v) {
                                          if (v.isEmpty) return;
                                          setState(() => _signatureMode = v.first);
                                        },
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _signatureMode == _LetterSignatureMode.digital
                                            ? 'Digital: selo compacto de certificado (igreja + assinante + data/hora).'
                                            : 'Manual: gera espaço proporcional para assinatura à caneta no documento impresso.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 18),
                              Text(
                                agradecimentoTab
                                    ? 'Marcadores (neutros): [Nome da entidade destinatária], [Nome da sua entidade], [cidade/estado], [ocasião ou motivo da gratidão], [BLOCO_ASSINATURAS]. Compatível com: [Nome da Igreja Destinatária], [Nome da Sua Igreja]. Legado: [Seu Nome] / [Seu Nome 2].'
                                    : 'Marcadores: [Nome da Igreja Destinatária], [Nome da Sua Igreja], [cidade/estado], [breve descrição: ...], [ocasião ou motivo da gratidão] (agradecimento), [Lista de membros apresentados], [Membros por extenso], [BLOCO_ASSINATURAS] (recomendado) ou legado [Seu Nome] / [Seu Nome 2].',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _savingTpl ? null : _saveTemplates,
                                    style: FilledButton.styleFrom(
                                      foregroundColor: accent,
                                      backgroundColor:
                                          accent.withValues(alpha: 0.12),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: _savingTpl
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: accent,
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload_rounded),
                                    label: Text(_savingTpl
                                        ? 'A guardar…'
                                        : 'Guardar modelos na nuvem'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _confirmRestoreDefaultTemplate(
                                      _currentCartaKindForTabs(
                                        transferenciaTab,
                                        agradecimentoTab,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey.shade800,
                                      side: BorderSide(
                                        color: accent.withValues(alpha: 0.45),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.restore_page_rounded,
                                      color: accent,
                                      size: 20,
                                    ),
                                    label: Text(
                                      transferenciaTab
                                          ? 'Restaurar modelo — transferência'
                                          : agradecimentoTab
                                              ? 'Restaurar modelo — agradecimento'
                                              : 'Restaurar modelo — apresentação',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDFDFB),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  20,
                                  28,
                                  20,
                                ),
                                child: SizedBox(
                                  height: 300,
                                  child: TextField(
                                    controller: transferenciaTab
                                        ? _tplTransferCtrl
                                        : agradecimentoTab
                                            ? _tplAgradecimentoCtrl
                                            : _tplApresentacaoCtrl,
                                    maxLines: null,
                                    expands: true,
                                    textAlign: TextAlign.justify,
                                    textAlignVertical: TextAlignVertical.top,
                                    style: GoogleFonts.libreBaskerville(
                                      fontSize: 14,
                                      height: 1.55,
                                      color: Colors.grey.shade900,
                                    ),
                                    decoration: premiumField(
                                      transferenciaTab
                                          ? 'Modelo — transferência'
                                          : agradecimentoTab
                                              ? 'Modelo — agradecimento'
                                              : 'Modelo — apresentação',
                                      maxLines: 99,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _pdfBusy
                                          ? null
                                          : () => _emitPdf(
                                                transferenciaTab
                                                    ? _CartaKind.transferencia
                                                    : agradecimentoTab
                                                        ? _CartaKind
                                                            .agradecimento
                                                        : _CartaKind
                                                            .apresentacao,
                                              ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        elevation: 2,
                                        shadowColor:
                                            accent.withValues(alpha: 0.45),
                                      ),
                                      icon: const Icon(
                                          Icons.picture_as_pdf_rounded),
                                      label: Text(
                                        transferenciaTab
                                            ? 'Gerar PDF — transferência'
                                            : agradecimentoTab
                                                ? 'Gerar PDF — agradecimento'
                                                : 'Gerar PDF — apresentação',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_historyEditDocId != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'A editar registo do histórico — o PDF irá atualizar a mesma entrada.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!isHistorico) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF2563EB).withValues(alpha: 0.07),
                        const Color(0xFFDB2777).withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    border: Border.all(color: accent.withValues(alpha: 0.14)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.groups_rounded, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Membros da carta',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                Text(
                                  'Seleção múltipla — busca e filtro por departamento (lista suspensa).',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _refreshMembers,
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text('Atualizar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _membersSyncing ? null : _openRecipientsPicker,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(
                          _selectedIds.isEmpty
                              ? 'Selecionar membros'
                              : 'Editar seleção (${_selectedIds.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${_selectedIds.length} selecionado(s) · ${_seedMemberDocs.where((d) => _memberAtivo(d.data())).length} ativo(s)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedIds.isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() {
                                _selectedIds.clear();
                                _selectedMembersCache.clear();
                              }),
                              child: const Text('Limpar'),
                            ),
                        ],
                      ),
                      if (_selectedIds.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ChurchLetterSelectedMembersGrid(
                          tenantId: _effectiveTenantId.isNotEmpty
                              ? _effectiveTenantId
                              : widget.tenantId.trim(),
                          entries: _selectedMemberEntries,
                          onRemove: (id) => setState(() {
                            _selectedIds.remove(id);
                            _selectedMembersCache.remove(id);
                          }),
                        ),
                      ],
                      if (_membersSyncing && _seedMemberDocs.isEmpty) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          minHeight: 3,
                          color: accent.withValues(alpha: 0.65),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_pdfBusy)
          Container(
            color: Colors.black26,
            alignment: Alignment.center,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'A gerar PDF…',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Emissão expressa — histórico grava em segundo plano.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _memberAtivo(Map<String, dynamic> m) {
    final s = (m['STATUS'] ?? m['status'] ?? '').toString().toLowerCase();
    final pendente = s.contains('pendente');
    final inativo = s.contains('inativ');
    return !pendente && !inativo;
  }

  Widget _buildHistoricoPanel(
    Color accent,
    InputDecoration Function(String, {String? hint, String? helper, int? maxLines})
        premiumField,
  ) {
    final years = List.generate(
      6,
      (i) => DateTime.now().year - i,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<int>(
                  segments: years
                      .take(4)
                      .map(
                        (y) => ButtonSegment(
                          value: y,
                          label: Text('$y'),
                        ),
                      )
                      .toList(),
                  selected: _histCustomRange == null ? {_histYear} : {},
                  onSelectionChanged: _histCustomRange != null
                      ? null
                      : (s) {
                          if (s.isEmpty) return;
                          setState(() => _histYear = s.first);
                          _refreshHistoricoStream();
                        },
                ),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                    value: _histYear,
                    decoration: premiumField('Ano'),
                    items: years
                        .map((y) =>
                            DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: _histCustomRange != null
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _histYear = v);
                              _refreshHistoricoStream();
                            }
                          },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 8),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _histCustomRange ??
                          DateTimeRange(
                            start: DateTime(_histYear, 1, 1),
                            end: DateTime(_histYear, 12, 31),
                          ),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: ColorScheme.light(primary: accent),
                        ),
                        child: child!,
                      ),
                    );
                    if (range != null) {
                      setState(() => _histCustomRange = range);
                      _refreshHistoricoStream();
                    }
                  },
                  icon: const Icon(Icons.date_range_rounded, size: 20),
                  label: Text(
                    _histCustomRange == null
                        ? 'Período personalizado'
                        : '${DateFormat('dd/MM/yyyy').format(_histCustomRange!.start)} — ${DateFormat('dd/MM/yyyy').format(_histCustomRange!.end)}',
                  ),
                ),
                if (_histCustomRange != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _histCustomRange = null);
                      _refreshHistoricoStream();
                    },
                    child: const Text('Limpar período'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            key: ValueKey(
              'hist_${_historicoStreamGen}_${_histYear}_${_histCustomRange?.start}_${_histCustomRange?.end}',
            ),
            stream: ChurchCartasModelosService.watchHistorico(_tenantKey),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return ChurchPanelResilientLoadBanner(
                  hasLocalData: false,
                  isSyncing: false,
                  errorTitle: 'Erro ao carregar histórico',
                  error: snap.error,
                  onRetry: _refreshHistoricoStream,
                );
              }
              final range = _historicoRange();
              final filtered =
                  ChurchCartasModelosService.filterHistoricoByRange(
                docs: snap.data ?? const [],
                rangeStart: range.start,
                rangeEnd: range.end,
              );
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Nenhum registo neste filtro. Ao gerar uma carta, ela aparece aqui — use «Editar» para reabrir e alterar.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final doc = filtered[i];
                  final d = doc.data();
                  final kindRaw = (d['kind'] ?? '').toString();
                  final cartaKind = _cartaKindFromFirestore(kindRaw);
                  final kindAccent = _accentForCartaKind(cartaKind);
                  final labelKind = switch (kindRaw) {
                    'transferencia' => 'Transferência',
                    'agradecimento' => 'Agradecimento',
                    _ => 'Apresentação',
                  };
                  final ts = d['createdAt'];
                  DateTime? dt;
                  if (ts is Timestamp) dt = ts.toDate();
                  final dataStr = dt != null
                      ? DateFormat('dd/MM/yyyy HH:mm').format(dt)
                      : '—';
                  final dest = (d['destIgreja'] ?? '').toString();
                  final stackActions = ThemeCleanPremium.isMobile(context) ||
                      MediaQuery.sizeOf(context).width < 560;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _loadForEdit(doc),
                      child: Container(
                        padding: EdgeInsets.all(stackActions ? 14 : 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: kindAccent.withValues(alpha: 0.22),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              kindAccent.withValues(alpha: 0.08),
                              const Color(0xFFF8FAFC),
                            ],
                          ),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kindAccent.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    labelKind,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: kindAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  dataStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              dest.isEmpty ? '(sem destinatário)' : dest,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildHistoricoActionBar(
                              stackVertical: stackActions,
                              onReprint: () => _reprintFromDoc(doc),
                              onEdit: () => _loadForEdit(doc),
                              onDelete: () => _confirmDelete(doc),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Cache RAM — membros instantâneos ao reabrir Cartas e transferências.
abstract final class _ChurchLettersMembersRamCache {
  _ChurchLettersMembersRamCache._();

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _byTenant = {};

  static const Duration _ttl = Duration(minutes: 20);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peek(
      String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    final hit = _byTenant[tid];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byTenant.remove(tid);
      return null;
    }
    return hit.docs;
  }

  static void put(
    String tenantId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final tid = tenantId.trim();
    if (tid.isEmpty || docs.isEmpty) return;
    _byTenant[tid] = (docs: List.from(docs), at: DateTime.now());
  }
}

class _LettersMembersListSnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _LettersMembersListSnapshot(this.docs);

  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => const [];

  @override
  SnapshotMetadata get metadata => const _LettersMembersSnapshotMetadata();

  @override
  int get size => docs.length;
}

class _LettersMembersSnapshotMetadata implements SnapshotMetadata {
  const _LettersMembersSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}

// ignore: subtype_of_sealed_class
class _LettersCachedMemberQueryDoc
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _LettersCachedMemberQueryDoc({required this.id, required Map<String, dynamic> data})
      : _data = data;

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  bool get exists => true;

  @override
  SnapshotMetadata get metadata => const _LettersMembersSnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('cached member doc has no reference');
}
