import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile, ImageSource;
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_image_crop_dialog.dart';
import 'package:gestao_yahweh/utils/church_logo_png_encode.dart';
import 'package:gestao_yahweh/utils/image_bytes_to_jpeg.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        ResilientNetworkImage,
        churchTenantLogoUrl,
        imageUrlFromMap,
        sanitizeImageUrl,
        isValidImageUrl,
        isFirebaseStorageHttpUrl;
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';

/// Gera slug (link/domínio) a partir do nome da igreja: normaliza, remove acentos e palavras comuns, usa hífens.
String _slugFromChurchName(String name) {
  if (name.trim().isEmpty) return '';
  const stopWords = {
    'igreja',
    'e',
    'de',
    'da',
    'do',
    'das',
    'dos',
    'para',
    'em',
    'no',
    'na',
    'nos',
    'nas'
  };
  final normalized = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäåāăą]'), 'a')
      .replaceAll(RegExp(r'[èéêëēėę]'), 'e')
      .replaceAll(RegExp(r'[ìíîïīį]'), 'i')
      .replaceAll(RegExp(r'[òóôõöōő]'), 'o')
      .replaceAll(RegExp(r'[ùúûüūů]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[ñ]'), 'n');
  final words = normalized
      .split(RegExp(r'[\s\-_]+'))
      .where((w) => w.isNotEmpty && !stopWords.contains(w))
      .toList();
  if (words.isEmpty) return '';
  final slug = words
      .join('-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty
      ? words
          .join('-')
          .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '')
      : slug;
}

/// Iniciais da igreja: primeira letra de cada palavra (ex.: "Igreja Brasil para Cristo" -> "ibpc").
String _iniciaisFromChurchName(String name) {
  if (name.trim().isEmpty) return '';
  final words = name
      .trim()
      .split(RegExp(r'[\s\-_]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  return words.map((w) => w.substring(0, 1).toLowerCase()).join();
}

/// Cor do site público (#RRGGBB). Retorna null se vazio ou inválido.
String? _normalizeSitePrimaryHex(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  t = t.replaceFirst('#', '').trim();
  if (t.length == 6 && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(t)) {
    return '#${t.toUpperCase()}';
  }
  return null;
}

String _buildFiliacaoLegadoGestor(String pai, String mae) {
  if (pai.isEmpty && mae.isEmpty) return '';
  if (pai.isEmpty) return 'Mãe: $mae';
  if (mae.isEmpty) return 'Pai: $pai';
  return 'Pai: $pai | Mãe: $mae';
}

int? _calcAgeGestor(DateTime? birth) {
  if (birth == null) return null;
  final now = DateTime.now();
  var age = now.year - birth.year;
  final had = now.month > birth.month ||
      (now.month == birth.month && now.day >= birth.day);
  if (!had) age -= 1;
  return age;
}

String _ageRangeGestor(int? age) {
  if (age == null) return '';
  if (age <= 12) return '0-12';
  if (age <= 17) return '13-17';
  if (age <= 25) return '18-25';
  if (age <= 35) return '26-35';
  if (age <= 50) return '36-50';
  return '51+';
}

/// Cadastro da Igreja — dados do tenant (nome, logo da galeria, endereço completo, dados do gestor).
/// Edição apenas para gestor/admin/master.
class IgrejaCadastroPage extends StatefulWidget {
  final String tenantId;
  final String role;

  /// No painel embutido ([IgrejaCleanShell]) evita AppBar duplicada com o [ModuleHeaderPremium].
  final bool embeddedInShell;

  const IgrejaCadastroPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<IgrejaCadastroPage> createState() => _IgrejaCadastroPageState();
}

class _IgrejaCadastroPageState extends State<IgrejaCadastroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _ruaCtrl = TextEditingController();
  final _quadraLoteNumeroCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _gestorNomeCtrl = TextEditingController();
  final _gestorCpfCtrl = TextEditingController();
  final _gestorTelefoneCtrl = TextEditingController();
  final _gestorEmailCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();

  /// Cor principal do site público (#RRGGBB) — botões e degradês.
  final _sitePrimaryHexCtrl = TextEditingController();
  final _linkMapsCtrl = TextEditingController();

  /// Meta ministerial no painel "Saúde ministerial & BI" (Firestore: metaMinisterial*).
  final _metaMinisterialTituloCtrl = TextEditingController();
  final _metaMinisterialValorCtrl = TextEditingController();
  final _metaMinisterialAcumuladoCtrl = TextEditingController();

  /// URL exibida / colada (fluxo EcoFire).
  final _logoUrlFieldCtrl = TextEditingController();

  String? _logoUrl;

  /// Caminho no Storage (renovação de token / cache central).
  String? _logoStoragePath;

  /// Logo em memória (exibido imediatamente ao escolher, antes do upload).
  Uint8List? _logoBytes;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  bool _uploadingLogo = false;
  double _logoUploadProgress = 0;
  /// Pré-visualização local antes do upload para `configuracoes/assinatura.png`.
  Uint8List? _pastorSigBytes;
  bool _uploadingPastorSig = false;
  bool _loadingCep = false;
  bool _formHydrated = false;
  bool _logoTokenRefreshAttempted = false;
  /// Evita múltiplas resoluções Storage→URL para o mesmo tenant na mesma sessão.
  String? _logoStorageHydrationTenantId;
  late Future<String> _resolvedIdFuture;

  /// Ficha completa do gestor (espelha cadastro de Membros — função administrador).
  final _gFiliacaoMaeCtrl = TextEditingController();
  final _gFiliacaoPaiCtrl = TextEditingController();
  final _gEstadoCivilCtrl = TextEditingController();
  final _gEscolaridadeCtrl = TextEditingController();
  final _gConjugeCtrl = TextEditingController();
  DateTime? _gBirthDate;
  String _gSexo = 'Masculino';
  Uint8List? _gPhotoBytes;
  String? _gestorExistingPhotoUrl;

  /// Snapshot do doc `membros` do gestor — usado por [FotoMembroWidget] (path/`gs://` sem URL https).
  Map<String, dynamic>? _gestorMemberData;

  /// ID real do documento em `membros` (pode ser CPF ou ID auto).
  String? _gestorMemberDocId;
  String? _lastHydratedCpf;

  /// Invalida [setState] de hidratações antigas (ex.: concluem depois do salvar e zeravam a foto).
  int _gestorHydrateSeq = 0;

  void _onNameChanged() {
    final slug = _slugFromChurchName(_nameCtrl.text);
    if (slug.isNotEmpty && mounted) {
      _slugCtrl.text = slug;
      setState(() {});
    }
  }

  Widget _buildLogoPlaceholder({double iconSize = 56}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_rounded,
              size: iconSize, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'Toque para escolher a logo',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: iconSize > 50 ? 14 : 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  bool get _canEdit {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  void _onGestorCpfListener() {
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.length == 11) {
      _resolvedTenantId.then((id) {
        if (mounted) _hydrateGestorFromMembros(id);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _gestorCpfCtrl.addListener(_onGestorCpfListener);
    _resolvedIdFuture =
        TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
  }

  void _retryResolveTenant() {
    setState(() {
      _formHydrated = false;
      _logoTokenRefreshAttempted = false;
      _logoStorageHydrationTenantId = null;
      _resolvedIdFuture =
          TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    });
  }

  void _copyAndSnack(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Link copiado para a área de transferência.'),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _gestorCpfCtrl.removeListener(_onGestorCpfListener);
    _nameCtrl.dispose();
    _cidadeCtrl.dispose();
    _estadoCtrl.dispose();
    _bairroCtrl.dispose();
    _ruaCtrl.dispose();
    _quadraLoteNumeroCtrl.dispose();
    _cepCtrl.dispose();
    _telefoneCtrl.dispose();
    _gestorNomeCtrl.dispose();
    _gestorCpfCtrl.dispose();
    _gestorTelefoneCtrl.dispose();
    _gestorEmailCtrl.dispose();
    _gFiliacaoMaeCtrl.dispose();
    _gFiliacaoPaiCtrl.dispose();
    _gEstadoCivilCtrl.dispose();
    _gEscolaridadeCtrl.dispose();
    _gConjugeCtrl.dispose();
    _slugCtrl.dispose();
    _sitePrimaryHexCtrl.dispose();
    _linkMapsCtrl.dispose();
    _metaMinisterialTituloCtrl.dispose();
    _metaMinisterialValorCtrl.dispose();
    _metaMinisterialAcumuladoCtrl.dispose();
    _logoUrlFieldCtrl.dispose();
    super.dispose();
  }

  /// Exibe valor numérico de meta como texto (pt-BR simples).
  static String _metaMoneyDisplayFromFirestore(dynamic v) {
    if (v == null) return '';
    final d = v is num
        ? v.toDouble()
        : double.tryParse(v.toString().replaceAll(',', '.'));
    if (d == null) return '';
    return d.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Interpreta campo monetário (ex.: 1500, 1.500,50 1500,50).
  static double? _parseMetaMoneyField(String raw) {
    final cleaned =
        raw.trim().replaceAll(RegExp(r'R\$\s*', caseSensitive: false), '').trim();
    if (cleaned.isEmpty) return null;
    var n = cleaned.replaceAll(' ', '');
    if (n.contains(',') && n.contains('.')) {
      n = n.replaceAll('.', '').replaceAll(',', '.');
    } else if (n.contains(',')) {
      n = n.replaceAll(',', '.');
    }
    return double.tryParse(n);
  }

  /// Extrai latitude e longitude de um link do Google Maps.
  static ({double? lat, double? lng}) _parseGoogleMapsLink(String url) {
    final u = url.trim();
    if (u.isEmpty) return (lat: null, lng: null);
    // Formato @lat,lng (ex.: .../maps/@-16.3281,-48.9534,17z)
    final atMatch = RegExp(r'/@(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(u);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1) ?? '');
      final lng = double.tryParse(atMatch.group(2) ?? '');
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    // Formato ?q=lat,lng ou &q=lat,lng
    final qMatch = RegExp(r'[?&]q=(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(u);
    if (qMatch != null) {
      final lat = double.tryParse(qMatch.group(1) ?? '');
      final lng = double.tryParse(qMatch.group(2) ?? '');
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    // Formato query=lat,lng
    final queryMatch =
        RegExp(r'query=(-?\d+\.?\d*),(-?\d+\.?\d*)').firstMatch(u);
    if (queryMatch != null) {
      final lat = double.tryParse(queryMatch.group(1) ?? '');
      final lng = double.tryParse(queryMatch.group(2) ?? '');
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    return (lat: null, lng: null);
  }

  /// Usa o link do Google Maps colado para definir a localização.
  void _usarLinkGoogleMaps() {
    if (!_canEdit) return;
    final parsed = _parseGoogleMapsLink(_linkMapsCtrl.text);
    if (parsed.lat == null || parsed.lng == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(ThemeCleanPremium.successSnackBar(
        'Cole um link do Google Maps com localização (ex.: maps.google.com ou goo.gl/maps com @lat,lng ou ?q=lat,lng).',
      ));
      return;
    }
    setState(() {
      _latitude = parsed.lat;
      _longitude = parsed.lng;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar(
          'Localização definida: ${parsed.lat?.toStringAsFixed(5)}, ${parsed.lng?.toStringAsFixed(5)}'),
    );
  }

  void _applyData(Map<String, dynamic>? data) {
    if (data == null) return;
    _nameCtrl.text = (data['name'] ?? data['nome'] ?? '').toString();
    // Logo: URL do Storage (vários campos) ou, se vazio, Base64 gravado no doc (legado / export).
    final url = churchTenantLogoUrl(data);
    _logoUrl = url.isEmpty ? null : url;
    _logoStoragePath = ChurchImageFields.logoStoragePath(data);
    if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      _logoBytes = null;
    } else {
      final b64raw = (data['logoDataBase64'] ?? data['logoBase64'] ?? '')
          .toString()
          .trim();
      if (b64raw.isNotEmpty) {
        try {
          _logoBytes = base64Decode(b64raw);
        } catch (_) {
          _logoBytes = null;
        }
      } else {
        _logoBytes = null;
      }
    }

    _cidadeCtrl.text = (data['cidade'] ?? data['localidade'] ?? '').toString();
    _estadoCtrl.text = (data['estado'] ?? data['uf'] ?? '').toString();
    _bairroCtrl.text = (data['bairro'] ?? '').toString();
    _ruaCtrl.text =
        (data['rua'] ?? data['address'] ?? data['endereco'] ?? '').toString();
    _quadraLoteNumeroCtrl.text = (data['quadraLoteNumero'] ??
            data['quadra_lote_numero'] ??
            data['qdLtNumero'] ??
            '')
        .toString();
    _cepCtrl.text = (data['cep'] ?? '').toString();
    _telefoneCtrl.text =
        (data['phone'] ?? data['telefone'] ?? data['fone'] ?? '').toString();
    final lat = data['latitude'];
    final lng = data['longitude'];
    _latitude = lat is num
        ? lat.toDouble()
        : (lat != null ? double.tryParse(lat.toString()) : null);
    _longitude = lng is num
        ? lng.toDouble()
        : (lng != null ? double.tryParse(lng.toString()) : null);

    _gestorNomeCtrl.text =
        (data['gestorNome'] ?? data['gestor_nome'] ?? '').toString();
    _gestorCpfCtrl.text =
        (data['gestorCpf'] ?? data['gestor_cpf'] ?? '').toString();
    _gestorTelefoneCtrl.text =
        (data['gestorTelefone'] ?? data['gestor_telefone'] ?? '').toString();
    final savedSlug = (data['slug'] ?? data['slugId'] ?? '').toString().trim();
    final nome = (data['name'] ?? data['nome'] ?? '').toString().trim();
    _slugCtrl.text =
        savedSlug.isNotEmpty ? savedSlug : _slugFromChurchName(nome);
    _sitePrimaryHexCtrl.text =
        (data['sitePrimaryHex'] ?? data['sitePrimaryColor'] ?? '')
            .toString()
            .trim();
    _metaMinisterialTituloCtrl.text =
        (data['metaMinisterialTitulo'] ?? '').toString().trim();
    _metaMinisterialValorCtrl.text = _metaMoneyDisplayFromFirestore(
        data['metaMinisterialValor']);
    _metaMinisterialAcumuladoCtrl.text = _metaMoneyDisplayFromFirestore(
        data['metaMinisterialAcumulado']);
    _gestorEmailCtrl.text =
        (data['gestorEmail'] ?? data['gestor_email'] ?? '').toString();
    _lastHydratedCpf = null;
    _gestorMemberDocId = null;
    _gestorMemberData = null;
  }

  String _effectiveGestorMemberDocId() {
    final mid = (_gestorMemberDocId ?? '').trim();
    if (mid.isNotEmpty) return mid;
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    return cpf.length == 11 ? cpf : '';
  }

  String? _gestorAuthUidFromMemberData() {
    final v = _gestorMemberData?['authUid'];
    final s = (v ?? '').toString().trim();
    return s.isNotEmpty ? s : null;
  }

  static String _cpfFormattedBr11(String digits) {
    if (digits.length != 11) return digits;
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
  }

  Future<void> _hydrateGestorFromMembros(String resolvedId,
      {bool force = false}) async {
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11 || !mounted) return;
    if (!force && _lastHydratedCpf == cpf) return;
    final seqAtStart = _gestorHydrateSeq;
    try {
      final col = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(resolvedId)
          .collection('membros');
      DocumentSnapshot<Map<String, dynamic>>? memDoc;

      final byId = await col.doc(cpf).get();
      if (byId.exists) {
        memDoc = byId;
      } else {
        QuerySnapshot<Map<String, dynamic>>? found;
        for (final pair in [
          ('CPF', cpf),
          ('cpf', cpf),
          ('CPF', _cpfFormattedBr11(cpf)),
          ('cpf', _cpfFormattedBr11(cpf)),
        ]) {
          try {
            final q =
                await col.where(pair.$1, isEqualTo: pair.$2).limit(1).get();
            if (q.docs.isNotEmpty) {
              found = q;
              break;
            }
          } catch (_) {}
        }
        if (found != null && found.docs.isNotEmpty) {
          memDoc = found.docs.first;
        }
      }

      if (!mounted || seqAtStart != _gestorHydrateSeq) return;
      if (memDoc == null || !memDoc.exists) {
        setState(() {
          _lastHydratedCpf = cpf;
          _gestorExistingPhotoUrl = null;
          _gestorMemberDocId = null;
          _gestorMemberData = null;
        });
        return;
      }

      final d = memDoc.data()!;
      Timestamp? ts;
      final raw = d['DATA_NASCIMENTO'] ?? d['dataNascimento'];
      if (raw is Timestamp) ts = raw;
      final fromMap = imageUrlFromMap(d);
      final legacy =
          (d['FOTO_URL_OU_ID'] ?? d['foto_url'] ?? '').toString().trim();
      final phRaw = fromMap.isNotEmpty ? fromMap : legacy;
      final ph = phRaw.isEmpty ? '' : sanitizeImageUrl(phRaw);
      final gestorDocId = memDoc.id;
      final resolvedPhoto =
          ph.isNotEmpty && isValidImageUrl(ph) ? ph : null;

      if (!mounted || seqAtStart != _gestorHydrateSeq) return;

      setState(() {
        _lastHydratedCpf = cpf;
        _gestorMemberDocId = gestorDocId;
        _gFiliacaoMaeCtrl.text =
            (d['FILIACAO_MAE'] ?? d['filiacaoMae'] ?? '').toString();
        _gFiliacaoPaiCtrl.text =
            (d['FILIACAO_PAI'] ?? d['filiacaoPai'] ?? '').toString();
        if (_gFiliacaoPaiCtrl.text.isEmpty && _gFiliacaoMaeCtrl.text.isEmpty) {
          final leg = (d['FILIACAO'] ?? d['filiacao'] ?? '').toString();
          if (leg.isNotEmpty) _gFiliacaoPaiCtrl.text = leg;
        }
        _gEstadoCivilCtrl.text =
            (d['ESTADO_CIVIL'] ?? d['estadoCivil'] ?? '').toString();
        _gEscolaridadeCtrl.text =
            (d['ESCOLARIDADE'] ?? d['escolaridade'] ?? '').toString();
        _gConjugeCtrl.text =
            (d['NOME_CONJUGE'] ?? d['nomeConjuge'] ?? '').toString();
        final sx = (d['SEXO'] ?? d['sexo'] ?? 'Masculino').toString();
        _gSexo = (sx == 'Feminino' || sx == 'Outro') ? sx : 'Masculino';
        _gBirthDate = ts?.toDate();
        _gestorMemberData = Map<String, dynamic>.from(d);
        _gestorExistingPhotoUrl = resolvedPhoto;
      });

      if (!mounted || seqAtStart != _gestorHydrateSeq) return;
      if (resolvedPhoto == null || resolvedPhoto.isEmpty) {
        final mirror = await FirebaseStorageService.getGestorPublicMirrorPhotoUrl(
            resolvedId);
        if (mirror != null &&
            mirror.isNotEmpty &&
            mounted &&
            seqAtStart == _gestorHydrateSeq) {
          setState(() => _gestorExistingPhotoUrl = mirror);
        }
      }

      if (!mounted || seqAtStart != _gestorHydrateSeq) return;
      if ((_gestorExistingPhotoUrl ?? '').trim().isEmpty) {
        final nomeGestor = _gestorNomeCtrl.text.trim().isNotEmpty
            ? _gestorNomeCtrl.text.trim()
            : (d['NOME_COMPLETO'] ?? '').toString();
        final authU = (d['authUid'] ?? '').toString().trim();
        final url =
            await FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
          tenantId: resolvedId,
          memberId: gestorDocId,
          cpfDigits: cpf,
          authUid: authU.isEmpty ? null : authU,
          nomeCompleto: nomeGestor,
        );
        if (url != null &&
            url.isNotEmpty &&
            mounted &&
            seqAtStart == _gestorHydrateSeq) {
          setState(() => _gestorExistingPhotoUrl = url);
        }
      }
    } catch (_) {}
  }

  Future<void> _pickGestorPhoto({bool camera = false}) async {
    if (!_canEdit) return;
    try {
      final picked = await MediaHandlerService.instance.pickAndProcessImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (mounted) setState(() => _gPhotoBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao escolher foto: $e'));
      }
    }
  }

  String? _validateGestorMembroFields() {
    if (!_canEdit) return null;
    if (_gestorNomeCtrl.text.trim().isEmpty)
      return 'Preencha o nome completo do gestor.';
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11) return 'CPF do gestor deve ter 11 dígitos.';
    if (_gestorEmailCtrl.text.trim().isEmpty)
      return 'E-mail do gestor é obrigatório.';
    if (_gestorTelefoneCtrl.text.trim().isEmpty)
      return 'Telefone do gestor é obrigatório.';
    if (_gBirthDate == null) return 'Informe a data de nascimento do gestor.';
    if (_gEstadoCivilCtrl.text.trim().isEmpty)
      return 'Informe o estado civil do gestor.';
    if (_gEscolaridadeCtrl.text.trim().isEmpty)
      return 'Informe a escolaridade do gestor.';
    final hasNet = _gestorExistingPhotoUrl != null &&
        isValidImageUrl(sanitizeImageUrl(_gestorExistingPhotoUrl!));
    final hasStorageFallback =
        _gestorMemberDocId != null && _gestorMemberDocId!.trim().isNotEmpty;
    final hasPhoto = _gPhotoBytes != null || hasNet || hasStorageFallback;
    if (!hasPhoto)
      return 'Envie a foto do gestor (mesmo padrão do cadastro de membros).';
    return null;
  }

  Future<void> _syncGestorToMembros(
      String resolvedId, Map<String, dynamic>? tenantLive) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !_canEdit) return;
    final cpfDigits = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpfDigits.length != 11) return;

    final slugRaw = _slugCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final al = (tenantLive?['alias'] ?? slugRaw).toString().trim();
    final sl = (tenantLive?['slug'] ?? slugRaw).toString().trim();
    final alias = al.isEmpty ? resolvedId : al;
    final slug = sl.isEmpty ? resolvedId : sl;

    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(resolvedId)
        .collection('membros');
    final docId =
        (_gestorMemberDocId != null && _gestorMemberDocId!.trim().isNotEmpty)
            ? _gestorMemberDocId!.trim()
            : cpfDigits;
    final ref = col.doc(docId);
    final existingSnap = await ref.get();

    String? photoUrl = _gestorExistingPhotoUrl;
    if ((photoUrl == null || photoUrl.isEmpty) && docId.isNotEmpty) {
      final authGestor = (_gestorMemberData?['authUid'] ?? uid ?? '')
          .toString()
          .trim();
      final nomeGestor = _gestorNomeCtrl.text.trim().isNotEmpty
          ? _gestorNomeCtrl.text.trim()
          : (_gestorMemberData?['NOME_COMPLETO'] ?? '').toString();
      photoUrl = await FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
        tenantId: resolvedId,
        memberId: docId,
        cpfDigits: cpfDigits,
        authUid: authGestor.isEmpty ? null : authGestor,
        nomeCompleto: nomeGestor,
      );
      if (photoUrl != null && photoUrl.isNotEmpty && mounted) {
        setState(() => _gestorExistingPhotoUrl = photoUrl);
      }
    }
    if (_gPhotoBytes != null) {
      final jpg = await ensureJpegBytes(
        _gPhotoBytes!,
        quality: 70,
        minWidth: 800,
        minHeight: 800,
      );
      final oldGestorPhoto = (_gestorExistingPhotoUrl ?? '').trim();
      if (oldGestorPhoto.isNotEmpty) {
        await FirebaseStorageCleanupService.deleteObjectAtDownloadUrl(
            sanitizeImageUrl(oldGestorPhoto));
      }
      photoUrl = await MediaUploadService.uploadBytesWithRetry(
        storagePath:
            ChurchStorageLayout.gestorMemberPhotoPath(resolvedId, docId),
        bytes: jpg,
        contentType: 'image/jpeg',
      );
      try {
        await MediaUploadService.uploadBytesWithRetry(
          storagePath:
              ChurchStorageLayout.gestorPublicProfilePhotoPath(resolvedId),
          bytes: jpg,
          contentType: 'image/jpeg',
        );
      } catch (_) {}
      if (mounted) {
        setState(() {
          _gestorExistingPhotoUrl = photoUrl;
          _gPhotoBytes = null;
        });
        FirebaseStorageService.invalidateMemberPhotoCache(
          tenantId: resolvedId,
          memberId: docId,
        );
        AppStorageImageService.instance
            .invalidateStoragePrefix('igrejas/$resolvedId/membros/$docId');
        AppStorageImageService.instance
            .invalidateStoragePrefix('igrejas/$resolvedId/gestor');
      }
    }
    if (photoUrl == null || photoUrl.isEmpty) {
      final seed = cpfDigits.isNotEmpty ? cpfDigits : uid;
      photoUrl =
          'https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent(seed)}&backgroundColor=EAF2FF,DDEBFF,CFE3FF';
    }

    final age = _calcAgeGestor(_gBirthDate);
    final ageRange = _ageRangeGestor(age);
    final nome = _gestorNomeCtrl.text.trim();
    final email = _gestorEmailCtrl.text.trim().toLowerCase();

    final isMaster = widget.role.toLowerCase() == 'master';
    final funcaoKey = isMaster ? 'master' : 'adm';
    final funcoes = <String>[funcaoKey];
    final cargoLabel = isMaster ? 'Master' : 'Administrador';

    final payload = <String, dynamic>{
      'MEMBER_ID': cpfDigits,
      'CREATED_BY_CPF': cpfDigits,
      'alias': alias,
      'slug': slug,
      'tenantId': resolvedId,
      'NOME_COMPLETO': nome,
      'EMAIL': email,
      'TELEFONES': _gestorTelefoneCtrl.text.trim(),
      'CPF': cpfDigits,
      'SEXO': _gSexo,
      'DATA_NASCIMENTO': Timestamp.fromDate(_gBirthDate!),
      'FAIXA_ETARIA': ageRange,
      'IDADE': age ?? 0,
      'ENDERECO': _buildEnderecoCompleto(),
      'CEP': _cepCtrl.text.trim(),
      'BAIRRO': _bairroCtrl.text.trim(),
      'CIDADE': _cidadeCtrl.text.trim(),
      'ESTADO': _estadoCtrl.text.trim(),
      'QUADRA_LOTE_NUMERO': _quadraLoteNumeroCtrl.text.trim(),
      'ESTADO_CIVIL': _gEstadoCivilCtrl.text.trim(),
      'ESCOLARIDADE': _gEscolaridadeCtrl.text.trim(),
      'NOME_CONJUGE': _gConjugeCtrl.text.trim(),
      'FILIACAO_PAI': _gFiliacaoPaiCtrl.text.trim(),
      'FILIACAO_MAE': _gFiliacaoMaeCtrl.text.trim(),
      'FILIACAO': _buildFiliacaoLegadoGestor(
          _gFiliacaoPaiCtrl.text.trim(), _gFiliacaoMaeCtrl.text.trim()),
      'FOTO_URL_OU_ID': photoUrl,
      'FUNCAO': funcaoKey,
      'FUNCOES': funcoes,
      'CARGO': cargoLabel,
      'role': funcaoKey,
      'STATUS': 'ativo',
      'status': 'ativo',
      'authUid': uid,
      'GESTOR_SYNC': true,
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
      'podeVerFinanceiro': false,
      'podeVerPatrimonio': false,
    };
    if (!existingSnap.exists) {
      payload['CRIADO_EM'] = FieldValue.serverTimestamp();
    }
    await ref.set(payload, SetOptions(merge: true));

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'role': funcaoKey,
        'roles': funcoes,
        'nome': nome,
        'displayName': nome,
        'name': nome,
        'email': email,
        'tenantId': resolvedId,
        'igrejaId': resolvedId,
        'FUNCOES': funcoes,
        'funcao': funcaoKey,
        'cargo': cargoLabel,
        'CARGO': cargoLabel,
        'photoURL': photoUrl,
        'fotoUrl': photoUrl,
        'FOTO_URL_OU_ID': photoUrl,
      }, SetOptions(merge: true));
    } catch (_) {
      // Regras podem bloquear create em /users; a sincronização na igreja continua.
    }

    await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(resolvedId)
        .collection('users')
        .doc(uid)
        .set({
      'role': funcaoKey,
      'roles': funcoes,
      'nome': nome,
      'displayName': nome,
      'email': email,
      'FUNCOES': funcoes,
      'funcao': funcaoKey,
      'cargo': cargoLabel,
      'CARGO': cargoLabel,
      'photoURL': photoUrl,
      'fotoUrl': photoUrl,
      'FOTO_URL_OU_ID': photoUrl,
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(resolvedId)
        .collection('usersIndex')
        .doc(cpfDigits)
        .set({
      'email': email,
      'cpf': cpfDigits,
      'nome': nome,
      'name': nome,
      'tenantId': resolvedId,
      'role': funcaoKey,
      'cargo': cargoLabel,
      'CARGO': cargoLabel,
      'FUNCOES': funcoes,
      'authUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      _gestorHydrateSeq++;
      await _hydrateGestorFromMembros(resolvedId, force: true);
    }
  }

  /// Galeria ou câmera: alta resolução → bytes locais; use [Cortar] e [Enviar logo] para publicar.
  Future<void> _pickLogoFromGallery() async {
    if (!_canEdit) return;
    try {
      final file =
          await MediaHandlerService.instance.pickAndProcessLogoFromGallery();
      await _stageLogoFromPickedFile(file);
    } catch (e) {
      _onLogoPickError(e);
    }
  }

  Future<void> _pickLogoFromCamera() async {
    if (!_canEdit) return;
    try {
      final file =
          await MediaHandlerService.instance.pickAndProcessLogoFromCamera();
      await _stageLogoFromPickedFile(file);
    } catch (e) {
      _onLogoPickError(e);
    }
  }

  void _onLogoPickError(Object e) {
    if (mounted) {
      setState(() {
        _logoBytes = null;
        _uploadingLogo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao selecionar logo: $e'),
      );
    }
  }

  Future<void> _stageLogoFromPickedFile(XFile? file) async {
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _logoBytes = bytes;
      _uploadingLogo = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Logo carregada. Opcional: Cortar. Depois toque em Enviar logo.'),
      );
    }
  }

  Future<void> _cropPendingLogo() async {
    final b = _logoBytes;
    if (b == null || !mounted || !_canEdit) return;
    final cropped = await showChurchPhotoCropDialog(
      context,
      imageBytes: b,
      title: 'Cortar logo',
      circleUi: false,
      aspectRatio: 1,
    );
    if (cropped != null && mounted) setState(() => _logoBytes = cropped);
  }

  Future<void> _cropPendingGestorPhoto() async {
    final b = _gPhotoBytes;
    if (b == null || !mounted || !_canEdit) return;
    final cropped = await showChurchPhotoCropDialog(
      context,
      imageBytes: b,
      title: 'Cortar foto do gestor',
      circleUi: true,
    );
    if (cropped != null && mounted) setState(() => _gPhotoBytes = cropped);
  }

  Future<void> _deleteChurchLogoStorageObjectAndVariants(String? storagePath) async {
    final p = storagePath?.trim() ?? '';
    if (p.isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(p).delete();
    } catch (_) {}
    final lower = p.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      final dot = p.lastIndexOf('.');
      final base = dot < 0 ? p : p.substring(0, dot);
      for (final suffix in <String>['_thumb.jpg', '_card.jpg', '_full.jpg']) {
        try {
          await FirebaseStorage.instance.ref('$base$suffix').delete();
        } catch (_) {}
      }
    }
  }

  /// Publica `configuracoes/logo_igreja.png` (sobrescreve sempre) e grava [logo_url] no Firestore.
  Future<void> _commitLogoUploadFromPending() async {
    if (!_canEdit || _logoBytes == null || !mounted) return;
    setState(() {
      _uploadingLogo = true;
      _logoUploadProgress = 0;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final resolvedId =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final png = await encodeChurchLogoAsPng(_logoBytes!);
      await _deleteChurchLogoStorageObjectAndVariants(_logoStoragePath);
      await FirebaseStorageCleanupService.deleteLegacyChurchLogoMediaUnderTenant(
          resolvedId);
      final identityPath =
          ChurchStorageLayout.churchIdentityLogoPath(resolvedId);
      final upload = await MediaUploadService.uploadBytesDetailed(
        storagePath: identityPath,
        bytes: png,
        contentType: 'image/png',
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _logoUploadProgress = p);
        },
      );
      final url = upload.downloadUrl;
      if (!mounted) return;
      setState(() {
        _logoUrl = url;
        _logoBytes = png;
        _logoStoragePath = upload.storagePath;
        _uploadingLogo = false;
      });
      _logoUrlFieldCtrl.text = url;
      await CachedNetworkImage.evictFromCache(url);
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$resolvedId/logo');
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$resolvedId/branding');
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$resolvedId/configuracoes');
      FirebaseStorageService.invalidateChurchLogoCache(resolvedId);
      AppStorageImageService.instance.invalidate(
        storagePath: upload.storagePath,
        imageUrl: url,
      );
      await _saveLogoUrl(
        url,
        storagePath: upload.storagePath,
        removeLogoVariants: true,
      );
      if (!mounted) return;
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Logo enviada (configuracoes/logo_igreja.png). Carteirinha, certificados e relatórios usam este ficheiro.'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao enviar logo: $e'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _logoUploadProgress = 0);
      }
    }
  }

  Future<void> _pickPastorSigFromGallery() async {
    if (!_canEdit) return;
    try {
      final file =
          await MediaHandlerService.instance.pickAndProcessFromGallery();
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pastorSigBytes = bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Assinatura carregada. Toque em Enviar para aplicar nos certificados.'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao selecionar imagem: $e'),
        );
      }
    }
  }

  Future<void> _pickPastorSigFromCamera() async {
    if (!_canEdit) return;
    try {
      final file =
          await MediaHandlerService.instance.pickAndProcessFromCamera();
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pastorSigBytes = bytes);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Assinatura carregada. Toque em Enviar para aplicar nos certificados.'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao capturar imagem: $e'),
        );
      }
    }
  }

  Future<void> _openPastorSignatureSheet() async {
    if (!_canEdit || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.draw_rounded,
                          color: ThemeCleanPremium.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Assinatura do pastor (certificados)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Galeria'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPastorSigFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Câmera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPastorSigFromCamera();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.cloud_upload_rounded,
                      color: (_pastorSigBytes == null || _uploadingPastorSig)
                          ? Colors.grey
                          : ThemeCleanPremium.primary),
                  title: Text(
                      _uploadingPastorSig ? 'Enviando…' : 'Enviar ao Storage'),
                  enabled: _pastorSigBytes != null && !_uploadingPastorSig,
                  onTap: _pastorSigBytes == null || _uploadingPastorSig
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _commitPastorSignatureUpload();
                        },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _commitPastorSignatureUpload() async {
    if (!_canEdit || _pastorSigBytes == null || !mounted) return;
    setState(() => _uploadingPastorSig = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final resolvedId =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final png = await encodeChurchLogoAsPng(_pastorSigBytes!);
      final paths = ChurchStorageLayout.pastorSignatureConfigPaths(resolvedId);
      final path = paths.first;
      await MediaUploadService.uploadBytesDetailed(
        storagePath: path,
        bytes: png,
        contentType: 'image/png',
      );
      if (paths.length > 1) {
        try {
          await FirebaseStorage.instance.ref(paths[1]).delete();
        } catch (_) {}
      }
      FirebaseStorageService.invalidatePastorSignatureCache(resolvedId);
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$resolvedId/configuracoes');
      if (!mounted) return;
      setState(() {
        _uploadingPastorSig = false;
        _pastorSigBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Assinatura guardada em configuracoes/assinatura.png — usada nos certificados PDF.'),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPastorSig = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao enviar assinatura: $e'),
        );
      }
    }
  }

  Future<void> _removePastorSignatureFromStorage() async {
    if (!_canEdit || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover assinatura institucional?'),
        content: const Text(
            'O ficheiro configuracoes/assinatura.png será apagado. Os certificados deixam de incluir esta imagem até enviar outra.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      final resolvedId =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      for (final p
          in ChurchStorageLayout.pastorSignatureConfigPaths(resolvedId)) {
        try {
          await FirebaseStorage.instance.ref(p).delete();
        } catch (_) {}
      }
      FirebaseStorageService.invalidatePastorSignatureCache(resolvedId);
      AppStorageImageService.instance
          .invalidateStoragePrefix('igrejas/$resolvedId/configuracoes');
      if (mounted) {
        setState(() => _pastorSigBytes = null);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Assinatura removida do Storage.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao remover: $e'),
        );
      }
    }
  }

  Widget _buildPastorSignatureCertCard(String resolvedTenantId) {
    final tid = resolvedTenantId.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  size: 20, color: ThemeCleanPremium.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assinatura do pastor (certificados)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Imagem aplicada automaticamente no rodapé dos certificados quando a opção de assinatura institucional estiver ativa (PDF). '
            'Recomendado: PNG com fundo transparente e traço escuro — o PDF ajusta a escala para não desproporcionar. '
            'Guardada em configuracoes/assinatura.png.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280, minHeight: 72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: _pastorSigBytes != null
                  ? Image.memory(_pastorSigBytes!, fit: BoxFit.contain)
                  : tid.isEmpty
                      ? Text(
                          'ID da igreja indisponível.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        )
                      : FutureBuilder<String?>(
                          future: FirebaseStorageService
                              .getPastorSignatureConfigDownloadUrl(tid),
                          builder: (context, snap) {
                            final url = snap.data;
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )),
                              );
                            }
                            if (url == null || url.isEmpty) {
                              return Text(
                                'Nenhuma assinatura enviada.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              );
                            }
                            return ResilientNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              width: 260,
                              height: 100,
                            );
                          },
                        ),
            ),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _uploadingPastorSig ? null : _openPastorSignatureSheet,
                  icon: Icon(Icons.add_photo_alternate_rounded,
                      size: 18, color: ThemeCleanPremium.primary),
                  label: Text(
                    _uploadingPastorSig ? 'A enviar…' : 'Carregar assinatura',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _uploadingPastorSig ? null : _removePastorSignatureFromStorage,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.red.shade700),
                  label: Text(
                    'Remover',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Busca CEP via ViaCEP e preenche rua, bairro, cidade, estado.
  Future<void> _buscarCep() async {
    final cep = _cepCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Informe um CEP válido (8 dígitos).'));
      }
      return;
    }
    if (!_canEdit) return;
    setState(() => _loadingCep = true);
    try {
      final result = await fetchCep(cep);
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'CEP não encontrado. Verifique e tente novamente.'));
        setState(() => _loadingCep = false);
        return;
      }
      if (result.logradouro != null) _ruaCtrl.text = result.logradouro!;
      if (result.bairro != null) _bairroCtrl.text = result.bairro!;
      if (result.localidade != null) _cidadeCtrl.text = result.localidade!;
      if (result.uf != null) _estadoCtrl.text = result.uf!;
      if (result.cep != null) _cepCtrl.text = result.cep!;
      setState(() => _loadingCep = false);
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Endereço preenchido pelo CEP.'));
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCep = false);
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao buscar CEP: $e'));
      }
    }
  }

  /// Monta o endereço completo para exibição e para o site público.
  String _buildEnderecoCompleto() {
    final rua = _ruaCtrl.text.trim();
    final qdLt = _quadraLoteNumeroCtrl.text.trim();
    final ruaCompleta =
        rua.isEmpty ? qdLt : (qdLt.isEmpty ? rua : '$rua, $qdLt');
    final parts = <String>[
      ruaCompleta.isNotEmpty ? ruaCompleta : '',
      _bairroCtrl.text.trim(),
      _cidadeCtrl.text.trim(),
      _estadoCtrl.text.trim(),
      _cepCtrl.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final cidadeEstado = _cidadeCtrl.text.trim().isNotEmpty &&
            _estadoCtrl.text.trim().isNotEmpty
        ? '${_cidadeCtrl.text.trim()} - ${_estadoCtrl.text.trim()}'
        : (_cidadeCtrl.text.trim().isNotEmpty ? _cidadeCtrl.text.trim() : '');
    final lista = <String>[];
    if (ruaCompleta.isNotEmpty) lista.add(ruaCompleta);
    if (_bairroCtrl.text.trim().isNotEmpty) lista.add(_bairroCtrl.text.trim());
    if (cidadeEstado.isNotEmpty) lista.add(cidadeEstado);
    if (_cepCtrl.text.trim().isNotEmpty)
      lista.add('CEP ${_cepCtrl.text.trim()}');
    return lista.join(', ');
  }

  Future<void> _saveLogoUrl(
    String url, {
    String? storagePath,
    bool removeLogoVariants = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Faça login para salvar a logo.'));
      return;
    }
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await user.getIdToken(true);
      final resolvedId =
          await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final data = {
        'logoUrl': url,
        'logo_url': url,
        'logoProcessedUrl': url,
        'logoProcessed': url,
        if (storagePath != null && storagePath.isNotEmpty)
          'logoPath': storagePath,
        if (removeLogoVariants) 'logoVariants': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(resolvedId)
          .set(data, SetOptions(merge: true));
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Logo atualizado e disponível.'));
      }
    } catch (e) {
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await user.getIdToken(true);
        final resolvedId = await TenantResolverService.resolveEffectiveTenantId(
            widget.tenantId);
        final data = {
          'logoUrl': url,
          'logo_url': url,
          'logoProcessedUrl': url,
          'logoProcessed': url,
          if (storagePath != null && storagePath.isNotEmpty)
            'logoPath': storagePath,
          if (removeLogoVariants) 'logoVariants': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(resolvedId)
            .set(data, SetOptions(merge: true));
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Logo atualizado e disponível.'));
        }
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar('Erro ao salvar logo: $e2'));
        }
      }
    }
  }

  /// Token do Firebase Storage expira: renova URL e grava no Firestore (logo “sempre disponível”).
  Future<void> _maybeRefreshStorageLogoUrl() async {
    final u = _logoUrl;
    if (u == null || u.isEmpty) return;
    final s = sanitizeImageUrl(u);
    if (!isFirebaseStorageHttpUrl(s)) return;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final ref = FirebaseStorage.instance.refFromURL(s);
      final fresh = await ref.getDownloadURL();
      if (!mounted || fresh.isEmpty || fresh == s) return;
      setState(() {
        _logoUrl = fresh;
        _logoUrlFieldCtrl.text = fresh;
        _logoBytes = null;
      });
      await _saveLogoUrl(fresh);
    } catch (_) {}
  }

  /// Quando o Firestore não tem URL https mas a logo existe em Storage (path ou `logo_principal`).
  Future<void> _hydrateLogoUrlFromStorageIfNeeded(
    String tenantDocId,
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;
    final existing = (_logoUrl ?? '').trim();
    if (existing.isNotEmpty &&
        isValidImageUrl(sanitizeImageUrl(existing))) {
      return;
    }
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      for (final path in [
        ChurchStorageLayout.churchIdentityLogoPath(tenantDocId),
        ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(tenantDocId),
      ]) {
        try {
          final ref = FirebaseStorage.instance.ref(path);
          final md = await ref.getMetadata();
          final sz = md.size ?? 0;
          if (sz <
              ChurchStorageLayout.kChurchIdentityLogoMinBytesForFirestoreSync) {
            continue;
          }
          final url = await ref.getDownloadURL();
          if (!mounted) return;
          final clean = sanitizeImageUrl(url);
          if (clean.isEmpty || !isValidImageUrl(clean)) continue;
          setState(() {
            _logoUrl = clean;
            _logoStoragePath = path;
            if (_logoUrlFieldCtrl.text.trim().isEmpty) {
              _logoUrlFieldCtrl.text = clean;
            }
            _logoBytes = null;
          });
          await _saveLogoUrl(clean, storagePath: path);
          await _maybeRefreshStorageLogoUrl();
          return;
        } catch (_) {}
      }

      final resolved =
          await AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tenantDocId,
        tenantData: data,
        preferImageUrl: existing.isNotEmpty ? existing : null,
        preferStoragePath: ChurchImageFields.logoStoragePath(data),
        preferGsUrl: null,
      );
      if (!mounted) return;
      final clean = sanitizeImageUrl(resolved ?? '');
      if (clean.isEmpty || !isValidImageUrl(clean)) return;
      setState(() {
        _logoUrl = clean;
        if (_logoUrlFieldCtrl.text.trim().isEmpty) {
          _logoUrlFieldCtrl.text = clean;
        }
        _logoBytes = null;
      });
      await _maybeRefreshStorageLogoUrl();
    } catch (_) {}
  }

  Future<void> _pasteLogoUrlFromClipboard() async {
    if (!_canEdit) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Área de transferência vazia. Copie a URL da imagem primeiro.'),
        );
      }
      return;
    }
    _logoUrlFieldCtrl.text = t;
    await _applyLogoUrlFromField();
  }

  Future<void> _applyLogoUrlFromField() async {
    if (!_canEdit) return;
    final raw = _logoUrlFieldCtrl.text.trim();
    final u = sanitizeImageUrl(raw);
    if (!isValidImageUrl(u)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Cole uma URL https válida da logo (ex.: link do Firebase Storage).'),
        );
      }
      return;
    }
    setState(() {
      _logoUrl = u;
      _logoBytes = null;
    });
    await _saveLogoUrl(u);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Logo atualizada pela URL.'),
      );
    }
  }

  Future<String> get _resolvedTenantId =>
      TenantResolverService.resolveEffectiveTenantId(widget.tenantId);

  Future<void> _save() async {
    if (!_canEdit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final gestorErr = _validateGestorMembroFields();
    if (gestorErr != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.feedbackSnackBar(gestorErr));
      }
      return;
    }
    ThemeCleanPremium.hapticAction();
    setState(() => _saving = true);
    try {
      // Atualiza token para Firestore/Storage enxergarem role e tenantId nas claims
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final resolvedId = await _resolvedTenantId;
      final slugRaw = _slugCtrl.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'nome': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'igrejaId': resolvedId,
        'tenantId': resolvedId,
        'churchId': resolvedId,
        'registrationComplete': true,
        'slug': slugRaw.isEmpty ? null : slugRaw,
        'slugId': slugRaw.isEmpty ? null : slugRaw,
        'cidade':
            _cidadeCtrl.text.trim().isEmpty ? null : _cidadeCtrl.text.trim(),
        'estado':
            _estadoCtrl.text.trim().isEmpty ? null : _estadoCtrl.text.trim(),
        'bairro':
            _bairroCtrl.text.trim().isEmpty ? null : _bairroCtrl.text.trim(),
        'rua': _ruaCtrl.text.trim().isEmpty ? null : _ruaCtrl.text.trim(),
        'quadraLoteNumero': _quadraLoteNumeroCtrl.text.trim().isEmpty
            ? null
            : _quadraLoteNumeroCtrl.text.trim(),
        'cep': _cepCtrl.text.trim().isEmpty ? null : _cepCtrl.text.trim(),
        'phone': _telefoneCtrl.text.trim().isEmpty
            ? null
            : _telefoneCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim().isEmpty
            ? null
            : _telefoneCtrl.text.trim(),
        'gestorNome': _gestorNomeCtrl.text.trim().isEmpty
            ? null
            : _gestorNomeCtrl.text.trim(),
        'gestorCpf': _gestorCpfCtrl.text.trim().isEmpty
            ? null
            : _gestorCpfCtrl.text.trim(),
        'gestorTelefone': _gestorTelefoneCtrl.text.trim().isEmpty
            ? null
            : _gestorTelefoneCtrl.text.trim(),
        'gestorEmail': _gestorEmailCtrl.text.trim().isEmpty
            ? null
            : _gestorEmailCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_logoUrl != null && _logoUrl!.isNotEmpty) {
        data['logoUrl'] = _logoUrl;
        data['logo_url'] = _logoUrl;
        data['logoProcessedUrl'] = _logoUrl;
        data['logoProcessed'] = _logoUrl;
      }
      final enderecoCompleto = _buildEnderecoCompleto();
      if (enderecoCompleto.isNotEmpty) data['endereco'] = enderecoCompleto;
      if (_latitude != null) data['latitude'] = _latitude;
      if (_longitude != null) data['longitude'] = _longitude;

      if (slugRaw.isNotEmpty) {
        if (AppConstants.reservedChurchSlugs.contains(slugRaw)) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Este link está reservado pelo sistema. Ajuste o slug (link do site).',
              ),
            );
          }
          return;
        }
        final taken = await FirebaseFirestore.instance
            .collection('igrejas')
            .where('slug', isEqualTo: slugRaw)
            .limit(2)
            .get();
        if (taken.docs.any((d) => d.id != resolvedId)) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'O link "$slugRaw" já está em uso por outra igreja. Escolha outro.',
              ),
            );
          }
          return;
        }
      }

      final hexNorm = _normalizeSitePrimaryHex(_sitePrimaryHexCtrl.text);
      if (_sitePrimaryHexCtrl.text.trim().isNotEmpty && hexNorm == null) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
              'Cor do site inválida. Use o formato #RRGGBB (ex.: #2563EB).',
            ),
          );
        }
        return;
      }
      data['sitePrimaryHex'] = hexNorm ?? FieldValue.delete();

      final metaTitulo = _metaMinisterialTituloCtrl.text.trim();
      final metaValorRaw = _metaMinisterialValorCtrl.text.trim();
      final metaAcuRaw = _metaMinisterialAcumuladoCtrl.text.trim();
      double? metaValor;
      double? metaAcu;
      if (metaValorRaw.isNotEmpty) {
        metaValor = _parseMetaMoneyField(metaValorRaw);
        if (metaValor == null) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Valor da meta ministerial inválido. Use números (ex.: 5000 ou 5.000,00).',
              ),
            );
          }
          return;
        }
      }
      if (metaAcuRaw.isNotEmpty) {
        metaAcu = _parseMetaMoneyField(metaAcuRaw);
        if (metaAcu == null) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Valor acumulado da meta inválido. Use números (ex.: 1200 ou 1.200,50).',
              ),
            );
          }
          return;
        }
      }
      data['metaMinisterialTitulo'] =
          metaTitulo.isEmpty ? FieldValue.delete() : metaTitulo;
      data['metaMinisterialValor'] =
          metaValor == null ? FieldValue.delete() : metaValor;
      data['metaMinisterialAcumulado'] =
          metaAcu == null ? FieldValue.delete() : metaAcu;

      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(resolvedId)
          .set(data, SetOptions(merge: true));
      if (!mounted) return;
      try {
        final tenantSnap = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(resolvedId)
            .get();
        await _syncGestorToMembros(resolvedId, tenantSnap.data());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Dados da igreja e ficha do gestor em Membros (administrador) atualizados.'),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
                'Igreja salva. Ajuste a ficha do gestor e tente novamente: $e'),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao salvar: $e'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static InputDecoration _premiumInputDeco(String label, [String? hint]) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFAFBFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        borderSide: BorderSide(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
            width: 1.4),
      ),
    );
  }

  Widget _cadastroSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  String _formatGestorDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Future<void> _pickGestorBirthDate() async {
    if (!_canEdit) return;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime(DateTime.now().year),
      initialDate: _gBirthDate ?? DateTime(1985, 1, 1),
    );
    if (picked != null && mounted) setState(() => _gBirthDate = picked);
  }

  /// Prévia compacta — alinhada ao tamanho usado no cadastro de membros (~120px).
  Widget _gestorPhotoPlaceholder(double side, {bool circular = true}) {
    final inner = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF8FAFC),
            const Color(0xFFEFF6FF).withValues(alpha: 0.9),
          ],
        ),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            circular ? null : BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_rounded,
              size: side * 0.36, color: Colors.grey.shade300),
          if (side >= 72) ...[
            const SizedBox(height: 4),
            Text(
              side >= 100 ? 'Toque para foto' : 'Foto',
              style: TextStyle(
                fontSize: side >= 100 ? 11 : 9,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
    if (circular) {
      return ClipOval(child: inner);
    }
    return inner;
  }

  static const _igStoryRingGradient = LinearGradient(
    colors: [
      Color(0xFFE879F9),
      Color(0xFFF472B6),
      Color(0xFF38BDF8),
      Color(0xFF2563EB),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  Widget _igLogoOuterFrame({
    required double width,
    required double height,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: _igStoryRingGradient,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  Widget _igGestorRing({
    required double diameter,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _igStoryRingGradient,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipOval(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: child,
        ),
      ),
    );
  }

  Future<void> _openLogoInstagramSheet() async {
    if (!_canEdit || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.domain_rounded,
                          color: ThemeCleanPremium.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Logo da igreja',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Galeria'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickLogoFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Câmera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickLogoFromCamera();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.crop_rounded,
                      color: _logoBytes == null ? Colors.grey : null),
                  title: const Text('Cortar prévia'),
                  enabled: _logoBytes != null && !_uploadingLogo,
                  onTap: _logoBytes == null || _uploadingLogo
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _cropPendingLogo();
                        },
                ),
                ListTile(
                  leading: Icon(Icons.cloud_upload_rounded,
                      color: (_logoBytes == null || _uploadingLogo)
                          ? Colors.grey
                          : ThemeCleanPremium.primary),
                  title: Text(
                      _uploadingLogo ? 'Enviando…' : 'Enviar ao Storage'),
                  enabled: _logoBytes != null && !_uploadingLogo,
                  onTap: _logoBytes == null || _uploadingLogo
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _commitLogoUploadFromPending();
                        },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGestorInstagramSheet() async {
    if (!_canEdit || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.person_rounded,
                          color: ThemeCleanPremium.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Foto do gestor',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Galeria'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGestorPhoto(camera: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Câmera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickGestorPhoto(camera: true);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.crop_rounded,
                      color: _gPhotoBytes == null ? Colors.grey : null),
                  title: const Text('Cortar foto'),
                  enabled: _gPhotoBytes != null,
                  onTap: _gPhotoBytes == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _cropPendingGestorPhoto();
                        },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIdentidadeVisualCard(
      String resolvedTenantId, Map<String, dynamic>? tenantLive) {
    final liveLogoUrl = churchTenantLogoUrl(tenantLive ?? {}).trim();
    final liveLogoPath =
        (ChurchImageFields.logoStoragePath(tenantLive) ?? '').trim();
    /// OK só com dados persistidos no Firestore ou bytes locais pendentes de envio (não só URL em memória).
    final hasLogo = _logoBytes != null ||
        liveLogoUrl.isNotEmpty ||
        liveLogoPath.isNotEmpty;
    final gestorPhotoUrl = (_gestorExistingPhotoUrl ?? '').trim();
    final md = _gestorMemberData;
    final mdPhoto = md != null ? imageUrlFromMap(md).trim() : '';
    final mdLegacy = md != null
        ? (md['FOTO_URL_OU_ID'] ?? md['foto_url'] ?? '').toString().trim()
        : '';
    final mdUrlOk = (mdPhoto.isNotEmpty &&
            isValidImageUrl(sanitizeImageUrl(mdPhoto))) ||
        (mdLegacy.isNotEmpty && isValidImageUrl(sanitizeImageUrl(mdLegacy)));
    final hasGestorPhoto = _gPhotoBytes != null ||
        gestorPhotoUrl.isNotEmpty ||
        mdUrlOk;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 20, color: ThemeCleanPremium.primary),
              const SizedBox(width: 8),
              Text(
                'Identidade visual ativa',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A logo da igreja e a foto do gestor aparecem no painel e no fluxo de membros.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _identityTile(
                  title: 'Logo da igreja',
                  ok: hasLogo,
                  child: SizedBox(
                    height: 100,
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final maxW =
                            c.maxWidth > 0 ? c.maxWidth : 160.0;
                        final iw = min(maxW - 10, 152.0);
                        const ih = 74.0;
                        return Center(
                          child: _igLogoOuterFrame(
                            width: iw,
                            height: ih,
                            child: _logoBytes != null
                                ? Image.memory(_logoBytes!,
                                    fit: BoxFit.contain)
                                : (resolvedTenantId.isNotEmpty
                                    ? StableChurchLogo(
                                        storagePath: _logoStoragePath,
                                        imageUrl: _logoUrl,
                                        tenantId: resolvedTenantId,
                                        tenantData: tenantLive,
                                        width: iw,
                                        height: ih,
                                        fit: BoxFit.contain,
                                      )
                                    : _buildLogoPlaceholder(iconSize: 28)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _identityTile(
                  title: 'Foto do gestor',
                  ok: hasGestorPhoto,
                  child: SizedBox(
                    height: 100,
                    child: Center(
                      child: _igGestorRing(
                        diameter: 72,
                        child: _gPhotoBytes != null
                            ? Image.memory(
                                _gPhotoBytes!,
                                fit: BoxFit.cover,
                                width: 72,
                                height: 72,
                              )
                            : Builder(
                                builder: (ctx) {
                                  final tid = resolvedTenantId.trim();
                                  final mid = _effectiveGestorMemberDocId();
                                  final cpf = _gestorCpfCtrl.text
                                      .replaceAll(RegExp(r'\D'), '');
                                  final dpr =
                                      MediaQuery.devicePixelRatioOf(ctx);
                                  final mc =
                                      (72 * dpr).round().clamp(120, 400);
                                  return FotoMembroWidget(
                                    key: ValueKey<String>(
                                        'ig_idviz_${tid}_$mid'),
                                    imageUrl: gestorPhotoUrl.isNotEmpty
                                        ? gestorPhotoUrl
                                        : null,
                                    size: 72,
                                    tenantId:
                                        tid.isNotEmpty ? tid : null,
                                    memberId:
                                        mid.isNotEmpty ? mid : null,
                                    cpfDigits: cpf.length == 11 ? cpf : null,
                                    authUid: _gestorAuthUidFromMemberData(),
                                    memberData: _gestorMemberData,
                                    memCacheWidth: mc,
                                    memCacheHeight: mc,
                                    backgroundColor: ThemeCleanPremium.primary
                                        .withValues(alpha: 0.12),
                                    fallbackChild: _gestorPhotoPlaceholder(
                                        72,
                                        circular: false),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.link_rounded,
                    size: 18, color: Color(0xFF1D4ED8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A foto do gestor será usada também no cadastro de membros como Administrador.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ID canónico = documento em `igrejas/{id}` (membros, mural, eventos, escalas usam este id).
  Widget _buildChurchFirestoreIdBanner(String churchId) {
    final id = churchId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ID único da igreja (Firestore)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            id,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: ThemeCleanPremium.onSurface,
              fontFamily: 'monospace',
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mural, eventos, escalas e demais dados ficam vinculados a este ID.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: id));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    ThemeCleanPremium.successSnackBar('ID copiado para a área de transferência.'),
                  );
                },
                icon: Icon(Icons.copy_rounded,
                    size: 18, color: ThemeCleanPremium.primary),
                label: Text(
                  'Copiar ID',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _identityTile({
    required String title,
    required bool ok,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                ok ? 'OK' : 'PENDENTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: ok ? const Color(0xFF166534) : const Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  /// Ficha do gestor: mesmos blocos do cadastro público de membros + gravação em Membros como administrador.
  Widget _buildGestorFichaCard(String resolvedTenantId) {
    const preview = 120.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9).withValues(alpha: 0.55),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(Icons.groups_rounded,
                    color: Colors.green.shade800, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestor — mesma ficha de Membros',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Os mesmos campos do cadastro público de membros. Ao salvar, o gestor entra automaticamente em Membros como Administrador.',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.home_work_outlined,
                      size: 20, color: Colors.grey.shade600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Endereço do gestor na lista de Membros replica o endereço da igreja (bloco “Endereço” acima).',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _cadastroSectionLabel('Dados pessoais'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _gestorNomeCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco('Nome completo', 'Nome do gestor'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _gFiliacaoMaeCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco('Filiação (mãe)'),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _gFiliacaoPaiCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco('Filiação (pai)'),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 420;
              final cpfField = TextFormField(
                controller: _gestorCpfCtrl,
                readOnly: !_canEdit,
                keyboardType: TextInputType.number,
                decoration: _premiumInputDeco('CPF', '000.000.000-00'),
                validator: (v) {
                  final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  if (d.length != 11) return 'CPF com 11 dígitos';
                  return null;
                },
              );
              final birthField = TextFormField(
                readOnly: true,
                decoration: _premiumInputDeco(
                  'Data de nascimento',
                  _gBirthDate == null
                      ? 'Toque para selecionar'
                      : _formatGestorDate(_gBirthDate!),
                ).copyWith(
                  suffixIcon: const Icon(Icons.event_rounded),
                ),
                onTap: _pickGestorBirthDate,
                validator: (_) => _gBirthDate == null ? 'Obrigatório' : null,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    cpfField,
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    birthField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cpfField),
                  const SizedBox(width: 12),
                  Expanded(child: birthField),
                ],
              );
            },
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 420;
              final sexo = DropdownButtonFormField<String>(
                value: ['Masculino', 'Feminino', 'Outro'].contains(_gSexo)
                    ? _gSexo
                    : 'Masculino',
                decoration: _premiumInputDeco('Sexo'),
                items: const [
                  DropdownMenuItem(
                      value: 'Masculino', child: Text('Masculino')),
                  DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                  DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                ],
                onChanged: !_canEdit
                    ? null
                    : (v) => setState(() => _gSexo = v ?? 'Masculino'),
              );
              final tel = TextFormField(
                controller: _gestorTelefoneCtrl,
                readOnly: !_canEdit,
                keyboardType: TextInputType.phone,
                decoration:
                    _premiumInputDeco('Telefone / WhatsApp', '(00) 00000-0000'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sexo,
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    tel,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sexo),
                  const SizedBox(width: 12),
                  Expanded(child: tel),
                ],
              );
            },
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _gestorEmailCtrl,
            readOnly: !_canEdit,
            keyboardType: TextInputType.emailAddress,
            decoration: _premiumInputDeco('E-mail', 'gestor@exemplo.com'),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Obrigatório';
              if (!t.contains('@')) return 'E-mail inválido';
              return null;
            },
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          _cadastroSectionLabel('Família e escolaridade'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _gEstadoCivilCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco('Estado civil'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _gEscolaridadeCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco('Escolaridade'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          TextFormField(
            controller: _gConjugeCtrl,
            readOnly: !_canEdit,
            decoration: _premiumInputDeco(
                'Nome do cônjuge', 'Se não houver, informe "—" ou "N/A"'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null,
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          _cadastroSectionLabel('Foto do gestor'),
          const SizedBox(height: 8),
          Text(
            'Prévia circular estilo perfil — toque para galeria ou câmera. Exibição resiliente (Storage), igual membros e galeria.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (_canEdit)
            Center(
              child: TextButton.icon(
                onPressed: _openGestorInstagramSheet,
                icon: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: ThemeCleanPremium.primary,
                ),
                label: Text(
                  'Opções da foto (galeria, câmera, cortar…)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final memImg = (preview * dpr).round().clamp(120, 400);
              final tid = resolvedTenantId.trim();
              final mid = _effectiveGestorMemberDocId();
              final cpf =
                  _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');

              Widget gestorPreview() {
                if (_gPhotoBytes != null) {
                  return Image.memory(
                    _gPhotoBytes!,
                    width: preview,
                    height: preview,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    isAntiAlias: true,
                  );
                }
                final url = sanitizeImageUrl(_gestorExistingPhotoUrl ?? '');
                if (tid.isNotEmpty && mid.isNotEmpty) {
                  return FotoMembroWidget(
                    key: ValueKey<String>('ig_gestor_prev_${tid}_$mid'),
                    imageUrl: isValidImageUrl(url) ? url : null,
                    size: preview,
                    tenantId: tid,
                    memberId: mid,
                    cpfDigits: cpf.length == 11 ? cpf : null,
                    authUid: _gestorAuthUidFromMemberData(),
                    memberData: _gestorMemberData,
                    memCacheWidth: memImg,
                    memCacheHeight: memImg,
                    backgroundColor:
                        ThemeCleanPremium.primary.withValues(alpha: 0.12),
                    fallbackChild:
                        _gestorPhotoPlaceholder(preview, circular: false),
                  );
                }
                if (isValidImageUrl(url)) {
                  return ResilientNetworkImage(
                    key: ValueKey(url),
                    imageUrl: url,
                    width: preview,
                    height: preview,
                    fit: BoxFit.cover,
                    memCacheWidth: memImg,
                    memCacheHeight: memImg,
                    placeholder: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget:
                        _gestorPhotoPlaceholder(preview, circular: false),
                  );
                }
                return _gestorPhotoPlaceholder(preview, circular: false);
              }

              return Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: !_canEdit ? null : _openGestorInstagramSheet,
                    child: _igGestorRing(
                      diameter: preview,
                      child: gestorPreview(),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          if (_canEdit)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving
                    ? 'Salvando...'
                    : 'Salvar igreja e ficha do gestor'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Apenas gestores podem editar o cadastro da igreja e a ficha do gestor.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _igrejaCadastroAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: Colors.white,
      foregroundColor: ThemeCleanPremium.onSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.maybePop(context),
        tooltip: 'Voltar',
        style: IconButton.styleFrom(
            minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                ThemeCleanPremium.minTouchTarget)),
      ),
      title: Text(
        'Cadastro da Igreja',
        style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.35,
            color: ThemeCleanPremium.onSurface),
      ),
    );
  }

  Widget _buildPageIntroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
            const Color(0xFFF1F5F9).withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              border: Border.all(color: const Color(0xFFE8EEF5)),
              boxShadow: [
                BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Icon(Icons.auto_awesome_rounded,
                color: ThemeCleanPremium.primary.withValues(alpha: 0.9),
                size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IDENTIDADE & GESTOR',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.15,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cadastro premium',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: ThemeCleanPremium.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  'Logo em prévia compacta, dados da igreja e a mesma ficha do cadastro de membros para o gestor — salvo em Membros como Administrador.',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolvedIdFuture,
      builder: (context, idSnap) {
        if (idSnap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surface,
            appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (idSnap.hasError) {
          return Scaffold(
            backgroundColor: ThemeCleanPremium.surface,
            appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Não foi possível identificar a igreja.',
                        style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retryResolveTenant,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final rid = (idSnap.data ?? widget.tenantId).toString().trim();
        final resolvedId = rid.isEmpty ? widget.tenantId : rid;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey<String>('igreja_doc_$resolvedId'),
          stream: FirebaseFirestore.instance
              .collection('igrejas')
              .doc(resolvedId)
              .snapshots(),
          builder: (context, docSnap) {
            if (docSnap.hasError) {
              return Scaffold(
                backgroundColor: ThemeCleanPremium.surface,
                appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Erro ao carregar dados da igreja.',
                            style: TextStyle(color: Colors.red.shade800)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _retryResolveTenant,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final doc = docSnap.data;
            final live = doc?.data();
            if (live != null && doc != null && doc.exists) {
              if (!_formHydrated) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted || _formHydrated) return;
                  _applyData(live);
                  final logo = churchTenantLogoUrl(live);
                  _logoUrlFieldCtrl.text = logo;
                  _formHydrated = true;
                  if (!_logoTokenRefreshAttempted) {
                    _logoTokenRefreshAttempted = true;
                    unawaited(_maybeRefreshStorageLogoUrl());
                  }
                  if (_canEdit) {
                    await FirebaseStorageService
                        .ensureChurchConfigFolderPlaceholderIfAbsent(
                            resolvedId);
                  }
                  if (!mounted) return;
                  if (logo.isEmpty &&
                      _logoStorageHydrationTenantId != resolvedId) {
                    _logoStorageHydrationTenantId = resolvedId;
                    await _hydrateLogoUrlFromStorageIfNeeded(resolvedId, live);
                  }
                  if (mounted) setState(() {});
                  unawaited(_hydrateGestorFromMembros(resolvedId));
                });
              } else if (!_uploadingLogo) {
                final serverLogo = churchTenantLogoUrl(live);
                final nu = serverLogo.isEmpty ? null : serverLogo;
                if (nu != null && nu != _logoUrl) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _uploadingLogo) return;
                    setState(() {
                      _logoUrl = nu;
                      _logoBytes = null;
                      if (_logoUrlFieldCtrl.text != nu) {
                        _logoUrlFieldCtrl.text = nu;
                      }
                    });
                  });
                }
              }
            } else if (doc != null && !doc.exists && !_formHydrated) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _formHydrated) return;
                _formHydrated = true;
                setState(() {});
              });
            }

            final padding = ThemeCleanPremium.pagePadding(context);
            final fullWidth = MediaQuery.sizeOf(context).width;
            final viewPadding = MediaQuery.viewPaddingOf(context);
            final viewInsets = MediaQuery.viewInsetsOf(context);
            final bottomPadding =
                padding.bottom + viewPadding.bottom + viewInsets.bottom + 32;
            return Scaffold(
              backgroundColor: ThemeCleanPremium.surface,
              appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
              body: SafeArea(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      padding.left, padding.top, padding.right, bottomPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: fullWidth > 700 ? 700 : double.infinity),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPageIntroHeader(),
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusLg),
                                border:
                                    Border.all(color: const Color(0xFFF1F5F9)),
                                boxShadow: ThemeCleanPremium.softUiCardShadow,
                              ),
                              padding: const EdgeInsets.all(
                                  ThemeCleanPremium.spaceLg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: ThemeCleanPremium.primary
                                              .withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm),
                                        ),
                                        child: Icon(Icons.domain_rounded,
                                            color: ThemeCleanPremium.primary,
                                            size: 24),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Dados da igreja',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.4,
                                                color:
                                                    ThemeCleanPremium.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Nome, logo (prévia compacta) e contatos no painel e no site público.',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                  height: 1.35),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _buildChurchFirestoreIdBanner(resolvedId),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _buildIdentidadeVisualCard(resolvedId, live),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _buildPastorSignatureCertCard(resolvedId),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  TextFormField(
                                    controller: _nameCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Nome da igreja',
                                      hintText:
                                          'Ex.: Igreja Brasil para Cristo',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) {
                                      if ((v ?? '').trim().isEmpty)
                                        return 'Informe o nome da igreja.';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  Text(
                                    'Logo da igreja',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Estilo galeria: toque na prévia ou no botão da câmera — Galeria, Câmera, Cortar e Enviar ao Storage. Mesmo pipeline resiliente do Firebase que o mural.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                        height: 1.35),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_canEdit)
                                    Align(
                                      alignment: Alignment.center,
                                      child: TextButton.icon(
                                        onPressed: _uploadingLogo
                                            ? null
                                            : _openLogoInstagramSheet,
                                        icon: Icon(
                                          Icons.tune_rounded,
                                          size: 18,
                                          color: ThemeCleanPremium.primary,
                                        ),
                                        label: Text(
                                          _uploadingLogo
                                              ? 'Enviando logo…'
                                              : 'Opções da logo (galeria, câmera, cortar…)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: ThemeCleanPremium.primary,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  if (_uploadingLogo) ...[
                                    const SizedBox(height: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: _logoUploadProgress <= 0
                                            ? null
                                            : _logoUploadProgress.clamp(
                                                0.0, 1.0),
                                        minHeight: 8,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Upload da logo: ${(_logoUploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final maxUsable =
                                          constraints.maxWidth.isFinite &&
                                                  constraints.maxWidth > 0
                                              ? constraints.maxWidth
                                              : 320.0;
                                      const kLogoPreviewMaxW = 280.0;
                                      final previewW =
                                          min(maxUsable, kLogoPreviewMaxW);
                                      final boxH = (previewW * 9 / 16)
                                          .clamp(100.0, 158.0);
                                      return Center(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: (!_canEdit ||
                                                        _uploadingLogo)
                                                    ? null
                                                    : _openLogoInstagramSheet,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                child: _igLogoOuterFrame(
                                                  width: previewW,
                                                  height: boxH,
                                                  child: Center(
                                                    child: _logoBytes != null
                                                        ? Image.memory(
                                                            _logoBytes!,
                                                            fit: BoxFit
                                                                .contain,
                                                            width: previewW,
                                                            height: boxH,
                                                            gaplessPlayback:
                                                                true,
                                                            filterQuality:
                                                                FilterQuality
                                                                    .high,
                                                            isAntiAlias: true,
                                                            errorBuilder: (_,
                                                                    __,
                                                                    ___) =>
                                                                _buildLogoPlaceholder(),
                                                          )
                                                        : resolvedId
                                                                .isNotEmpty
                                                            ? StableChurchLogo(
                                                                storagePath:
                                                                    _logoStoragePath,
                                                                imageUrl:
                                                                    _logoUrl,
                                                                tenantId:
                                                                    resolvedId,
                                                                tenantData:
                                                                    live,
                                                                width:
                                                                    previewW,
                                                                height: boxH,
                                                                fit: BoxFit
                                                                    .contain,
                                                              )
                                                            : SizedBox(
                                                                width:
                                                                    previewW,
                                                                height: boxH,
                                                                child:
                                                                    _buildLogoPlaceholder(),
                                                              ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_canEdit && !_uploadingLogo)
                                              Positioned(
                                                right: 2,
                                                bottom: 2,
                                                child: Material(
                                                  elevation: 6,
                                                  shadowColor: Colors.black26,
                                                  color:
                                                      ThemeCleanPremium.primary,
                                                  shape: const CircleBorder(),
                                                  child: InkWell(
                                                    customBorder:
                                                        const CircleBorder(),
                                                    onTap:
                                                        _openLogoInstagramSheet,
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.all(11),
                                                      child: Icon(
                                                        Icons
                                                            .camera_alt_rounded,
                                                        color: Colors.white,
                                                        size: 22,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  if (_canEdit) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Toque na moldura ou no ícone da câmera. URL do Storage abaixo (Ctrl+V) — mesma resiliência da galeria.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                          height: 1.3),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _logoUrlFieldCtrl,
                                      decoration: InputDecoration(
                                        labelText:
                                            'URL da logo (Firebase Storage ou https)',
                                        hintText:
                                            'https://firebasestorage.googleapis.com/...',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      maxLines: 2,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _uploadingLogo
                                              ? null
                                              : _pasteLogoUrlFromClipboard,
                                          icon: const Icon(
                                              Icons.content_paste_rounded,
                                              size: 18),
                                          label: const Text('Colar (Ctrl+V)'),
                                        ),
                                        FilledButton.tonal(
                                          onPressed: _uploadingLogo
                                              ? null
                                              : _applyLogoUrlFromField,
                                          child: const Text('Aplicar URL'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  TextFormField(
                                    controller: _slugCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Link do site público (slug)',
                                      hintText: 'ex.: jardim-goiano',
                                      helperText:
                                          'Gerado pelo nome; você pode editar. URL: ${AppConstants.publicWebBaseUrl}/seu-slug — deve ser único.',
                                      suffixIcon: _slugCtrl.text.isEmpty
                                          ? null
                                          : Icon(Icons.link_rounded,
                                              size: 20,
                                              color: Colors.grey.shade500),
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceMd),
                                  TextFormField(
                                    controller: _sitePrimaryHexCtrl,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Cor principal do site (#RRGGBB)',
                                      hintText: '#2563EB',
                                      helperText:
                                          'Opcional. Usada nos botões e degradês do site público da igreja.',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _cadastroSectionLabel(
                                      'Meta ministerial (painel)'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Alimenta a barra de progresso em Saúde ministerial & BI no dashboard. Opcional; pode atualizar o acumulado quando quiser.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                        height: 1.35),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _metaMinisterialTituloCtrl,
                                    readOnly: !_canEdit,
                                    decoration: _premiumInputDeco(
                                      'Título da meta',
                                      'ex.: Arrecadação anual — reforma',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller:
                                              _metaMinisterialValorCtrl,
                                          readOnly: !_canEdit,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: _premiumInputDeco(
                                            'Valor da meta (R\$)',
                                            'ex.: 50000 ou 50.000,00',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller:
                                              _metaMinisterialAcumuladoCtrl,
                                          readOnly: !_canEdit,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: _premiumInputDeco(
                                            'Já arrecadado / acumulado (R\$)',
                                            'ex.: 12500',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_nameCtrl.text.trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.text_fields_rounded,
                                            size: 16,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Iniciais: ${_iniciaisFromChurchName(_nameCtrl.text).toUpperCase()}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: ThemeCleanPremium.primary),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_slugCtrl.text.trim().isNotEmpty) ...[
                                    const SizedBox(
                                        height: ThemeCleanPremium.spaceMd),
                                    Container(
                                      padding: const EdgeInsets.all(
                                          ThemeCleanPremium.spaceMd),
                                      decoration: BoxDecoration(
                                        color: ThemeCleanPremium.primary
                                            .withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(
                                            ThemeCleanPremium.radiusSm),
                                        border: Border.all(
                                            color: ThemeCleanPremium.primary
                                                .withOpacity(0.2)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.public_rounded,
                                                  size: 20,
                                                  color: ThemeCleanPremium
                                                      .primary),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Seus links públicos',
                                                style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: ThemeCleanPremium
                                                        .primary),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Use estes links para divulgar o site da igreja e o cadastro de membros.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700),
                                          ),
                                          const SizedBox(height: 12),
                                          _LinkRow(
                                            label:
                                                'Site público (eventos e informações)',
                                            url: AppConstants
                                                .publicChurchHomeUrl(
                                                    _slugCtrl.text.trim()),
                                            onCopy: () => _copyAndSnack(
                                                context,
                                                AppConstants
                                                    .publicChurchHomeUrl(
                                                        _slugCtrl.text.trim())),
                                          ),
                                          const SizedBox(height: 8),
                                          _LinkRow(
                                            label:
                                                'Cadastro de membros (público)',
                                            url: AppConstants
                                                .publicChurchMemberSignupUrl(
                                                    _slugCtrl.text.trim()),
                                            onCopy: () => _copyAndSnack(
                                                context,
                                                AppConstants
                                                    .publicChurchMemberSignupUrl(
                                                        _slugCtrl.text.trim())),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceMd),
                                  Text(
                                    'Endereço (Estado, Cidade, Bairro, CEP e localização)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Use "Buscar por CEP" para preencher o endereço. Para o mapa no site, cole o link do Google Maps abaixo.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: _cepCtrl,
                                          readOnly: !_canEdit,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'CEP',
                                            hintText: '00000-000',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (_canEdit)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: SizedBox(
                                            height: 48,
                                            child: FilledButton.tonalIcon(
                                              onPressed: _loadingCep
                                                  ? null
                                                  : _buscarCep,
                                              icon: _loadingCep
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2),
                                                    )
                                                  : const Icon(
                                                      Icons.search_rounded,
                                                      size: 20),
                                              label: Text(_loadingCep
                                                  ? 'Buscando...'
                                                  : 'Buscar por CEP'),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceSm),
                                  TextFormField(
                                    controller: _ruaCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Rua / Logradouro',
                                      hintText: 'Ex.: R. Bela Vista, 100',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceSm),
                                  TextFormField(
                                    controller: _quadraLoteNumeroCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Quadra, Lote e Número',
                                      hintText: 'Qd 1, Lt 5, Nº 123',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceSm),
                                  TextFormField(
                                    controller: _bairroCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Bairro',
                                      hintText: 'Ex.: São João',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceSm),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isNarrow =
                                          constraints.maxWidth < 400;
                                      if (isNarrow) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            TextFormField(
                                              controller: _cidadeCtrl,
                                              readOnly: !_canEdit,
                                              decoration: const InputDecoration(
                                                labelText: 'Cidade',
                                                hintText: 'Ex.: Anápolis',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(
                                                height:
                                                    ThemeCleanPremium.spaceSm),
                                            TextFormField(
                                              controller: _estadoCtrl,
                                              readOnly: !_canEdit,
                                              decoration: const InputDecoration(
                                                labelText: 'Estado (UF)',
                                                hintText: 'GO',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _cidadeCtrl,
                                              readOnly: !_canEdit,
                                              decoration: const InputDecoration(
                                                labelText: 'Cidade',
                                                hintText: 'Ex.: Anápolis',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          SizedBox(
                                            width: 100,
                                            child: TextFormField(
                                              controller: _estadoCtrl,
                                              readOnly: !_canEdit,
                                              decoration: const InputDecoration(
                                                labelText: 'Estado (UF)',
                                                hintText: 'GO',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  if (_canEdit) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      'Cole o link do Google Maps',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: ThemeCleanPremium.onSurface),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _linkMapsCtrl,
                                            decoration: const InputDecoration(
                                              hintText:
                                                  'Ex.: https://maps.google.com/... ou https://goo.gl/maps/...',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: FilledButton.icon(
                                            onPressed: _usarLinkGoogleMaps,
                                            icon: const Icon(Icons.link,
                                                size: 18),
                                            label: const Text('Usar link'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_latitude != null &&
                                      _longitude != null) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.my_location_rounded,
                                            size: 18,
                                            color: Colors.green.shade700),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Localização: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceSm),
                                  TextFormField(
                                    controller: _telefoneCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Telefone / WhatsApp contato',
                                      hintText: '(00) 00000-0000',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                            _buildGestorFichaCard(resolvedId),
                          ],
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
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onCopy;

  const _LinkRow(
      {required this.label, required this.url, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              SelectableText(url,
                  style:
                      const TextStyle(fontSize: 13, fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 20),
          tooltip: 'Copiar link',
          style: IconButton.styleFrom(
            backgroundColor: ThemeCleanPremium.primary.withOpacity(0.12),
            foregroundColor: ThemeCleanPremium.primary,
          ),
        ),
      ],
    );
  }
}
