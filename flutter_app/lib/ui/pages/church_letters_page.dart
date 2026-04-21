import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/pdf/church_transfer_letter_pdf.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/module_header_premium.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;
import 'package:intl/intl.dart';

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
  final _searchCtrl = TextEditingController();

  /// Doc ids em `membros` — obrigatório 1º; 2º opcional (segunda assinatura).
  String? _signer1MemberId;
  String? _signer2MemberId;

  Map<String, dynamic>? _tenant;
  bool _loading = true;
  bool _savingTpl = false;
  bool _pdfBusy = false;
  _LetterSignatureMode _signatureMode = _LetterSignatureMode.digital;
  String _memberFilter = '';
  final Set<String> _selectedIds = {};
  late Future<QuerySnapshot<Map<String, dynamic>>> _membersFuture;

  /// Ao editar a partir do histórico, atualiza este doc em vez de criar outro.
  String? _historyEditDocId;

  int _histYear = DateTime.now().year;
  DateTimeRange? _histCustomRange;

  DocumentReference<Map<String, dynamic>> get _configRef =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('config')
          .doc('cartas');

  CollectionReference<Map<String, dynamic>> get _historicoCol =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .collection('cartas_historico');

  String _effectiveTenantId = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _effectiveTenantId = widget.tenantId.trim();
    _membersFuture = _loadMembers();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final tid =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      if (tid.isNotEmpty && mounted) {
        setState(() => _effectiveTenantId = tid);
        _refreshMembers();
      }
    } catch (_) {}

    try {
      final ch = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(_effectiveTenantId)
          .get();
      final d = ch.data() ?? {};
      if (!mounted) return;
      setState(() => _tenant = d);
      final missao = (d['missao'] ??
              d['descricao'] ??
              d['sobre'] ??
              'evangelizar, discipular e servir a comunidade')
          .toString()
          .trim();
      _missionCtrl.text = missao;

      final cfg = await _configRef.get();
      final c = cfg.data() ?? {};
      final a = (c['modeloApresentacao'] ?? '').toString().trim();
      final t = (c['modeloTransferencia'] ?? '').toString().trim();
      final g = (c['modeloAgradecimento'] ?? '').toString().trim();
      _tplApresentacaoCtrl.text =
          a.isNotEmpty ? a : kDefaultChurchLetterApresentacaoTemplate.trim();
      _tplTransferCtrl.text =
          t.isNotEmpty ? t : kDefaultChurchLetterTransferenciaTemplate.trim();
      _tplAgradecimentoCtrl.text =
          g.isNotEmpty ? g : kDefaultChurchLetterAgradecimentoTemplate.trim();

      await _defaultSignerFromMembro();
    } catch (_) {
      _tplApresentacaoCtrl.text = kDefaultChurchLetterApresentacaoTemplate.trim();
      _tplTransferCtrl.text = kDefaultChurchLetterTransferenciaTemplate.trim();
      _tplAgradecimentoCtrl.text =
          kDefaultChurchLetterAgradecimentoTemplate.trim();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _defaultSignerFromMembro() async {
    final tid = _effectiveTenantId.trim();
    if (tid.isEmpty) return;

    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('membros');

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
    var tid = _effectiveTenantId.isNotEmpty ? _effectiveTenantId : widget.tenantId;
    try {
      tid = await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    } catch (_) {}
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('membros')
        .get(const GetOptions(source: Source.serverAndCache));
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = _loadMembers();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _destIgrejaCtrl.dispose();
    _missionCtrl.dispose();
    _tplApresentacaoCtrl.dispose();
    _tplTransferCtrl.dispose();
    _tplAgradecimentoCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _nomeIgreja =>
      (_tenant?['name'] ?? _tenant?['nome'] ?? 'Igreja').toString().trim();

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
      (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString().trim();

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
            m['signatureUrl'] ??
            '')
        .toString()
        .trim();
  }

  String _contactoPdf(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final m1 = _memberData(snap, _signer1MemberId);
    final m2 = _memberData(snap, _signer2MemberId);
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

  Future<void> _saveTemplates() async {
    if (!AppPermissions.canAccessChurchLetters(widget.role,
        permissions: widget.permissions)) {
      return;
    }
    setState(() => _savingTpl = true);
    try {
      await _configRef.set(
        {
          'modeloApresentacao': _tplApresentacaoCtrl.text,
          'modeloTransferencia': _tplTransferCtrl.text,
          'modeloAgradecimento': _tplAgradecimentoCtrl.text,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
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
      await _historicoCol.doc(_historyEditDocId!).set(
            payload,
            SetOptions(merge: true),
          );
    } else {
      payload['createdAt'] = FieldValue.serverTimestamp();
      await _historicoCol.add(payload);
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

    setState(() => _pdfBusy = true);
    try {
      final snap = await _membersFuture;
      final byId = {for (final d in snap.docs) d.id: d.data()};
      final lines = <ChurchLetterMemberLine>[];
      for (final id in _selectedIds) {
        final m = byId[id];
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

      final contactPdf = _contactoPdf(snap);
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

      Uint8List? signatureImageBytes;
      if (_signatureMode == _LetterSignatureMode.digital) {
        final rawUrl = _signatureUrlFromMember(m1);
        final url = sanitizeImageUrl(rawUrl);
        if (url.isNotEmpty) {
          signatureImageBytes = await ImageHelper.getBytesFromUrlOrNull(
            url,
            timeout: const Duration(seconds: 14),
          );
        }
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

      final branding = await loadReportPdfBranding(_effectiveTenantId);
      final title = switch (kind) {
        _CartaKind.apresentacao => 'Carta de apresentação ministerial',
        _CartaKind.transferencia => 'CARTA DE MUDANÇA',
        _CartaKind.agradecimento => 'CARTA DE AGRADECIMENTO',
      };

      final bytes = await buildChurchTransferLetterPdf(
        branding: branding,
        documentTitle: title,
        bodyAfterReplacements: filled,
        churchData: _tenant ?? {},
        signatureImageBytes: signatureImageBytes,
        reserveManualSignatureSpace: _signatureMode == _LetterSignatureMode.manual,
      );

      if (saveHistorico) {
        await _persistHistorico(
          kind: kind,
          templateText: tpl,
        );
        if (mounted) {
          setState(() => _historyEditDocId = null);
        }
      }

      if (!mounted) return;
      final slug = (_tenant?['slug'] ?? _effectiveTenantId)
          .toString()
          .replaceAll(RegExp(r'[^\w\-]'), '_');
      final kindSlug = kind.firestoreKind;
      unawaited(
        showPdfActions(
          context,
          bytes: bytes,
          filename: '${slug}_carta_${kindSlug}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao gerar PDF: $e'),
        );
      }
    } finally {
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

  Query<Map<String, dynamic>> _historyQuery() {
    late final DateTime a;
    late final DateTime b;
    if (_histCustomRange != null) {
      a = DateTime(
        _histCustomRange!.start.year,
        _histCustomRange!.start.month,
        _histCustomRange!.start.day,
      );
      b = DateTime(
        _histCustomRange!.end.year,
        _histCustomRange!.end.month,
        _histCustomRange!.end.day,
        23,
        59,
        59,
      );
    } else {
      a = DateTime(_histYear, 1, 1);
      b = DateTime(_histYear, 12, 31, 23, 59, 59);
    }
    return _historicoCol
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(a))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(b))
        .orderBy('createdAt', descending: true)
        .limit(120);
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
                                  final docs = msnap.hasData
                                      ? (msnap.data!.docs.toList()
                                        ..sort((a, b) => _memberName(a.data())
                                            .toLowerCase()
                                            .compareTo(
                                                _memberName(b.data()).toLowerCase())))
                                      : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                                  final activeDocs = docs
                                      .where((d) => _memberAtivo(d.data()))
                                      .toList();

                                  Widget signerRow({
                                    required String label,
                                    required String? value,
                                    required ValueChanged<String?> onChanged,
                                    required bool isSecond,
                                  }) {
                                    final items = <DropdownMenuItem<String>>[
                                      if (!isSecond)
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('— Selecione o assinante —'),
                                        ),
                                      if (isSecond)
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('— Nenhum —'),
                                        ),
                                      ...activeDocs.map((d) {
                                        final m = d.data();
                                        final n = _memberName(m);
                                        return DropdownMenuItem<String>(
                                          value: d.id,
                                          child: Text(
                                            n.isEmpty ? d.id : n,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                    ];
                                    final safeVal =
                                        value != null &&
                                                items.any((e) => e.value == value)
                                            ? value
                                            : null;
                                    return DropdownButtonFormField<String>(
                                      value: safeVal,
                                      isExpanded: true,
                                      decoration: premiumField(
                                        label,
                                        helper:
                                            'Dados do cadastro Membros — não editáveis aqui',
                                      ),
                                      items: items,
                                      onChanged: onChanged,
                                    );
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      signerRow(
                                        label: '1.º assinante (cadastro membro) *',
                                        value: _signer1MemberId,
                                        isSecond: false,
                                        onChanged: (v) {
                                          setState(() {
                                            _signer1MemberId = v;
                                            if (_signer2MemberId == _signer1MemberId) {
                                              _signer2MemberId = null;
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      signerRow(
                                        label: '2.º assinante (opcional)',
                                        value: _signer2MemberId,
                                        isSecond: true,
                                        onChanged: (v) => setState(() {
                                          _signer2MemberId =
                                              v == _signer1MemberId ? null : v;
                                        }),
                                      ),
                                      const SizedBox(height: 12),
                                      if (msnap.hasData)
                                        InputDecorator(
                                          decoration: premiumField(
                                            'Contato no documento (automático)',
                                            helper:
                                                'Unão dos contactos dos assinantes no cadastro',
                                          ),
                                          child: Text(
                                            _contactoPdf(msnap.data!),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ),
                                      if (msnap.hasData &&
                                          _contactoPdf(msnap.data!).isEmpty)
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
                                            ? 'Digital: usa a imagem de assinatura do 1.º assinante (cadastro Membros).'
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
                Row(
                  children: [
                    Text(
                      'Membros',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _refreshMembers,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Atualizar lista'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _memberFilter = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Filtrar por nome ou CPF…',
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final snap = await _membersFuture;
                        final next = <String>{};
                        for (final d in snap.docs) {
                          final m = d.data();
                          if (!_memberAtivo(m)) continue;
                          final n = _memberName(m);
                          final cpf = _memberCpf(m);
                          final q = _memberFilter;
                          if (q.isNotEmpty &&
                              !n.toLowerCase().contains(q) &&
                              !cpf.contains(q)) {
                            continue;
                          }
                          next.add(d.id);
                        }
                        setState(() {
                          _selectedIds
                            ..clear()
                            ..addAll(next);
                        });
                      },
                      child: const Text('Selecionar filtrados'),
                    ),
                    TextButton(
                      onPressed: () => setState(_selectedIds.clear),
                      child: const Text('Limpar seleção'),
                    ),
                    const Spacer(),
                    Text(
                      '${_selectedIds.length} selecionado(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: _membersFuture,
                  builder: (context, snap) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snap.hasError) {
                      return Text('Erro: ${snap.error}');
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs.where((d) {
                      final m = d.data();
                      if (!_memberAtivo(m)) return false;
                      final n = _memberName(m).toLowerCase();
                      final cpf = _memberCpf(m);
                      final q = _memberFilter;
                      if (q.isEmpty) return true;
                      return n.contains(q) || cpf.contains(q);
                    }).toList()
                      ..sort((a, b) => _memberName(a.data())
                          .toLowerCase()
                          .compareTo(_memberName(b.data()).toLowerCase()));

                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Nenhum membro ativo com este filtro.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final m = d.data();
                        final name = _memberName(m);
                        final cpf = _memberCpf(m);
                        final sel = _selectedIds.contains(d.id);
                        final authUidRaw =
                            (m['authUid'] ?? '').toString().trim();
                        final authUidOpt =
                            authUidRaw.isEmpty ? null : authUidRaw;
                        return Material(
                          color:
                              sel ? accent.withValues(alpha: 0.06) : Colors.white,
                          child: CheckboxListTile(
                            value: sel,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIds.add(d.id);
                                } else {
                                  _selectedIds.remove(d.id);
                                }
                              });
                            },
                            title: Text(
                              name.isEmpty ? '(sem nome)' : name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: cpf.isNotEmpty
                                ? Text('CPF: $cpf',
                                    style: const TextStyle(fontSize: 12))
                                : null,
                            secondary: SizedBox(
                              width: 40,
                              height: 40,
                              child: FotoMembroWidget(
                                tenantId: _effectiveTenantId.isNotEmpty
                                    ? _effectiveTenantId
                                    : null,
                                memberId: d.id,
                                memberData: m,
                                cpfDigits: cpf.length == 11 ? cpf : null,
                                authUid: authUidOpt,
                                size: 40,
                                backgroundColor: accent.withValues(alpha: 0.15),
                                fallbackChild: CircleAvatar(
                                  backgroundColor:
                                      accent.withValues(alpha: 0.15),
                                  child: Text(
                                    name.isNotEmpty
                                        ? name.characters.first.toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        if (_pdfBusy)
          Container(
            color: Colors.black26,
            alignment: Alignment.center,
            child: const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('A gerar PDF…',
                        style: TextStyle(fontWeight: FontWeight.w700)),
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
          Text(
            'Filtro por ano ou período',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int>(
                  value: _histYear,
                  decoration: premiumField('Ano'),
                  items: years
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: _histCustomRange != null
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => _histYear = v);
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
                  onPressed: () => setState(() => _histCustomRange = null),
                  child: const Text('Limpar período'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _historyQuery().snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Erro: ${snap.error}');
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Nenhum registo neste filtro.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  final kind = (d['kind'] ?? '').toString();
                  final labelKind = switch (kind) {
                    'transferencia' => 'Transferência',
                    'agradecimento' => 'Agradecimento',
                    _ => 'Apresentação',
                  };
                  final ts = d['createdAt'];
                  DateTime? dt;
                  if (ts is Timestamp) dt = ts.toDate();
                  final dataStr =
                      dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '—';
                  final dest = (d['destIgreja'] ?? '').toString();
                  return Material(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    labelKind,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: accent,
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
                            const SizedBox(height: 8),
                            Text(
                              dest.isEmpty ? '(sem destinatário)' : dest,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () => _reprintFromDoc(doc),
                                  icon: const Icon(Icons.picture_as_pdf_rounded,
                                      size: 18),
                                  label: const Text('Reimprimir'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _loadForEdit(doc),
                                  icon:
                                      const Icon(Icons.edit_rounded, size: 18),
                                  label: const Text('Editar'),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Excluir',
                                  onPressed: () => _confirmDelete(doc),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
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
