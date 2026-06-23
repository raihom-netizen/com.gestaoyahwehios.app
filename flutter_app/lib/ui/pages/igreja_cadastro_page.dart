// ignore_for_file: unused_element
// (Funções legadas do bloco gestor/meta mantidas até remoção total.)

import 'dart:async' show StreamSubscription, TimeoutException, unawaited;
import 'dart:convert';
import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile, ImageSource;
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/carteirinha_validade_church.dart';
import 'package:gestao_yahweh/core/public_member_signup_navigation.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/gestor_membro_stub_service.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_save_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart'
    show ChurchPanelResilientLoadBanner, openHttpsUrlInBrowser;
import 'package:gestao_yahweh/ui/widgets/church_image_crop_dialog.dart';
import 'package:gestao_yahweh/utils/church_logo_png_encode.dart';
import 'package:gestao_yahweh/utils/image_bytes_to_jpeg.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoUrl,
        imageUrlFromMap,
        sanitizeImageUrl,
        isValidImageUrl,
        isFirebaseStorageHttpUrl,
        firebaseStorageDownloadUrlLooksTokenized;
import 'package:gestao_yahweh/ui/widgets/default_church_logo_asset.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/utils/church_module_query_probe.dart';

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
      .replaceAll(RegExp('[àáâãäåāăą]'), 'a')
      .replaceAll(RegExp('[èéêëēėę]'), 'e')
      .replaceAll(RegExp('[ìíîïīį]'), 'i')
      .replaceAll(RegExp('[òóôõöōő]'), 'o')
      .replaceAll(RegExp('[ùúûüūů]'), 'u')
      .replaceAll(RegExp('[ç]'), 'c')
      .replaceAll(RegExp('[ñ]'), 'n');
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

  /// CPF (11) ou CNPJ (14) da instituição — rodapé e relatórios.
  final _cnpjIgrejaCtrl = TextEditingController();
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

  final _linkMapsCtrl = TextEditingController();
  final _instagramUrlCtrl = TextEditingController();
  final _youtubeUrlCtrl = TextEditingController();
  final _facebookUrlCtrl = TextEditingController();
  final _whatsappChatUrlCtrl = TextEditingController();

  /// Meta ministerial no painel "Saúde ministerial & BI" (Firestore: metaMinisterial*).
  final _metaMinisterialTituloCtrl = TextEditingController();
  final _metaMinisterialValorCtrl = TextEditingController();
  final _metaMinisterialAcumuladoCtrl = TextEditingController();

  /// Validade da carteirinha de membro (aplica-se a todos os membros).
  CarteiraValidadeModo _carteiraValidadeModo = CarteiraValidadeModo.anos3;
  DateTime? _carteiraValidadeDataFixa;

  String? _logoUrl;

  /// Caminho no Storage (renovação de token / cache central).
  String? _logoStoragePath;

  /// Logo em memória (exibido imediatamente ao escolher, antes do upload).
  Uint8List? _logoBytes;

  /// Há logo nova na galeria/corte ainda não publicada no Storage — [Salvar igreja] deve enviar antes do merge.
  bool _logoStagedNotUploaded = false;
  double? _latitude;
  double? _longitude;
  bool _saving = false;
  bool _uploadingLogo = false;
  double _logoUploadProgress = 0;

  /// '' | encoding | uploading — feedback quando o progresso de rede ainda não começou.
  String _logoUploadPhase = '';

  bool _loadingCep = false;
  bool _formHydrated = false;
  String? _hydratedTenantId;
  /// Doc `igrejas/{id}` ainda não existia — não devemos marcar [_formHydrated] só por isso,
  /// senão quando o doc for criado deixamos de correr [_applyData] e a pré-visualização da logo fica em branco.
  bool _notedNonexistentIgrejaDoc = false;
  bool _logoTokenRefreshAttempted = false;

  /// Evita múltiplas resoluções Storage→URL para o mesmo tenant na mesma sessão.
  String? _logoStorageHydrationTenantId;
  String? _operationalTenantId;
  Map<String, dynamic> _tenantLiveData = {};
  bool _cadastroBootstrapDone = false;
  String? _cadastroBootstrapError;
  String? _cadastroSoftSyncWarning;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _igrejaLiveSub;
  int _hydratedProfileScore = 0;

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

  /// ID real do documento em `membros` (padrão: UID do Firebase; legado: CPF).
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

  Widget _buildLogoPlaceholder({
    double? boxWidth,
    double? boxHeight,
    bool showPickHint = true,
  }) {
    final w = boxWidth ?? 280.0;
    final h = boxHeight ?? 158.0;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DefaultChurchLogoAsset(
            width: w,
            height: h * 0.78,
            fractionOfBox: 0.92,
          ),
          if (showPickHint && _canEdit) ...[
            const SizedBox(height: 8),
            Text(
              'Toque para escolher a logo da igreja',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: w > 200 ? 13 : 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canEdit {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  /// Nome legível quando o doc antigo não tem `nome`/`name` (só id tipo `igreja_o_brasil_…`).
  static String _displayNameFromDocId(String docId) {
    var s = docId.trim();
    if (s.isEmpty) return '';
    for (final suf in ['_sistema', '_bpc']) {
      if (s.endsWith(suf)) s = s.substring(0, s.length - suf.length);
    }
    if (s.startsWith('igreja_')) s = s.substring(7);
    if (s.isEmpty) return '';
    return s
        .split('_')
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.length == 1
            ? p.toUpperCase()
            : '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  void _applyChurchDataResult(ChurchDataLoadResult result, {String? softError}) {
    final resolved = result.churchId.trim();
    if (resolved.isEmpty) {
      if (mounted) {
        setState(() {
          _cadastroBootstrapDone = true;
          _cadastroBootstrapError =
              'Igreja não identificada após carregar o cadastro.';
        });
      }
      return;
    }
    _operationalTenantId = resolved;
    _cadastroSoftSyncWarning = softError;
    if (result.logoStoragePath.trim().isNotEmpty) {
      _logoStoragePath = result.logoStoragePath.trim();
    } else {
      _logoStoragePath = ChurchStorageLayout.churchIdentityLogoPath(resolved);
    }
    if (result.data.isNotEmpty) {
      _hydrateFormFromFirestoreDoc(resolved, result.data);
    } else {
      _formHydrated = true;
      _hydratedTenantId = resolved;
      _tenantLiveData = const {};
      if (mounted) setState(() {});
      unawaited(_afterFormHydrated(resolved, const {}));
      _scheduleCadastroDataRetry();
    }
    _bindIgrejaLiveWatch(resolved);
    if (result.readSource == 'local_cache' ||
        result.readSource == 'session_context' ||
        result.readSource == 'session_context_sync') {
      unawaited(_reloadChurchDataInBackground(forceRefresh: true));
    }
    if (mounted) {
      setState(() {
        _cadastroBootstrapDone = true;
        _cadastroBootstrapError = null;
      });
    }
  }


  int _cadastroRetryGen = 0;

  void _scheduleCadastroDataRetry() {
    final gen = ++_cadastroRetryGen;
    for (final delay in const [2, 6, 14]) {
      Future<void>.delayed(Duration(seconds: delay), () async {
        if (!mounted || gen != _cadastroRetryGen) return;
        if (_nameCtrl.text.trim().isNotEmpty &&
            TenantResolverService.churchProfileRichnessScore(_tenantLiveData) >=
                ChurchCadastroLoadService.kMinProfileScore) {
          return;
        }
        await _reloadChurchDataInBackground(forceRefresh: delay >= 6);
      });
    }
  }

  Future<void> _bootstrapCadastro({bool forceRefresh = false}) async {
    if (!forceRefresh && !_formHydrated) {
      final local = await ChurchCadastroLoadService.tryLocalSources(
        seedTenantId: widget.tenantId.trim(),
      );
      if (local != null && local.data.isNotEmpty && mounted) {
        _applyChurchDataResult(
          local.toChurchDataLoadResult(),
          softError: local.softError,
        );
      }
    }
    try {
      await _bootstrapCadastroInner(forceRefresh: forceRefresh).timeout(
        ChurchPanelReadTimeouts.churchDocCap,
        onTimeout: () => throw TimeoutException('cadastro_bootstrap'),
      );
    } on TimeoutException {
      if (!mounted) return;
      final id = (_operationalTenantId ?? ChurchRepository.churchId(widget.tenantId)).trim();
      if (id.isNotEmpty) {
        _operationalTenantId ??= id;
        _logoStoragePath ??= ChurchStorageLayout.churchIdentityLogoPath(id);
        setState(() {
          _cadastroBootstrapDone = true;
          _cadastroBootstrapError = null;
          _cadastroSoftSyncWarning =
              'Tempo esgotado ao sincronizar. Exibindo cadastro local — toque em Atualizar.';
        });
        unawaited(_reloadChurchDataInBackground());
        return;
      }
      setState(() {
        _cadastroBootstrapDone = true;
        _cadastroBootstrapError =
            'Tempo esgotado ao carregar o cadastro. Toque em «Tentar novamente».';
      });
    } catch (e) {
      if (!mounted) return;
      final id = (_operationalTenantId ?? ChurchRepository.churchId(widget.tenantId)).trim();
      if (id.isNotEmpty) {
        _operationalTenantId ??= id;
        _logoStoragePath ??= ChurchStorageLayout.churchIdentityLogoPath(id);
        setState(() {
          _cadastroBootstrapDone = true;
          _cadastroBootstrapError = null;
          _cadastroSoftSyncWarning = e is ChurchRepositoryException
              ? e.message
              : e.toString();
        });
        unawaited(_reloadChurchDataInBackground());
        return;
      }
      setState(() {
        _cadastroBootstrapDone = true;
        _cadastroBootstrapError = e is ChurchRepositoryException
            ? e.message
            : e.toString();
      });
    }
  }

  Future<void> _bootstrapCadastroInner({bool forceRefresh = false}) async {
    final seed = widget.tenantId.trim();
    final churchId = ChurchRepository.churchId(seed);

    if (churchId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _cadastroBootstrapDone = true;
        _cadastroBootstrapError = 'ID da igreja não informado.';
      });
      return;
    }

    _operationalTenantId ??= churchId;
    _logoStoragePath ??= ChurchStorageLayout.churchIdentityLogoPath(churchId);

    final loaded = await ChurchCadastroLoadService.load(
      seedTenantId: seed.isNotEmpty ? seed : churchId,
      forceRefresh: forceRefresh,
    );

    _applyChurchDataResult(
      loaded.toChurchDataLoadResult(),
      softError: loaded.softError,
    );

    if (loaded.data.isNotEmpty) {
      unawaited(ChurchCadastroLoadService.persistAfterLoad(loaded));
      ChurchModuleQueryProbe.logSuccess(
        module: 'Cadastro Igreja',
        churchId: loaded.churchId,
        path: 'igrejas/${loaded.churchId}',
        totalDocs: loaded.data.length,
      );
    } else if (loaded.softError != null) {
      ChurchModuleQueryProbe.logError(
        module: 'Cadastro Igreja',
        churchId: churchId,
        path: 'igrejas/$churchId',
        error: loaded.softError!,
      );
    }

    if (loaded.softError != null &&
        (loaded.data.isEmpty ||
            TenantResolverService.churchProfileRichnessScore(loaded.data) <
                ChurchCadastroLoadService.kMinProfileScore)) {
      _scheduleCadastroDataRetry();
    }
  }

  Future<void> _reloadChurchDataInBackground({bool forceRefresh = false}) async {
    try {
      final loaded = await ChurchCadastroLoadService.load(
        seedTenantId: widget.tenantId.trim(),
        forceRefresh: forceRefresh,
      );
      if (loaded.data.isEmpty || !mounted) return;
      _cadastroSoftSyncWarning = loaded.softError;
      _hydrateFormFromFirestoreDoc(
        loaded.churchId,
        ChurchCadastroLoadService.sliceCadastroFormFields(loaded.data),
      );
      unawaited(ChurchCadastroLoadService.persistAfterLoad(loaded));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _bindIgrejaLiveWatch(String resolvedId) {
    _igrejaLiveSub?.cancel();
    _igrejaLiveSub = null;
    // Cadastro: sempre getDoc único — sem snapshots() (formulário de edição).
    unawaited(_refreshIgrejaDocOnce(resolvedId));
  }

  Future<void> _refreshIgrejaDocOnce(String resolvedId) async {
    final tid = resolvedId.trim().isNotEmpty ? resolvedId.trim() : widget.tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final loaded = await ChurchCadastroLoadService.load(
        seedTenantId: tid,
        forceRefresh: true,
      ).timeout(const Duration(seconds: 12));
      if (!mounted || loaded.data.isEmpty) return;
      _cadastroSoftSyncWarning = loaded.softError;
      final slim = ChurchCadastroLoadService.sliceCadastroFormFields(loaded.data);
      _hydrateFormFromFirestoreDoc(loaded.churchId, slim);
      unawaited(ChurchCadastroLoadService.persistAfterLoad(loaded));
    } catch (e, st) {
      debugPrint('IgrejaCadastro _refreshIgrejaDocOnce falhou: $e\n$st');
    }
  }

  /// Antes de `.set()` na web: cancela watch local e estabiliza sessão Firestore.
  Future<void> _prepareCadastroFirestoreWrite() async {
    await _igrejaLiveSub?.cancel();
    _igrejaLiveSub = null;
    await ChurchCadastroSaveService.prepareForSave();
  }

  bool _slugNeedsUniquenessCheck(String slugRaw) {
    final prior = (_tenantLiveData['slug'] ?? _tenantLiveData['slugId'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return prior != slugRaw;
  }

  void _resetCadastroLoadState() {
    _igrejaLiveSub?.cancel();
    _igrejaLiveSub = null;
    _formHydrated = false;
    _hydratedTenantId = null;
    _hydratedProfileScore = 0;
    _notedNonexistentIgrejaDoc = false;
    _logoTokenRefreshAttempted = false;
    _logoStorageHydrationTenantId = null;
    _operationalTenantId = null;
    _tenantLiveData = {};
    _cadastroBootstrapDone = false;
    _cadastroBootstrapError = null;
    _cadastroSoftSyncWarning = null;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    final resolved = ChurchRepository.churchId(widget.tenantId.trim());
    if (resolved.isNotEmpty) {
      _operationalTenantId = resolved;
      _logoStoragePath = ChurchStorageLayout.churchIdentityLogoPath(resolved);
    }
    final ctxData = ChurchContextService.currentChurchData;
    final ctxId = ChurchContextService.currentChurchId;
    if (ctxData != null &&
        ctxId != null &&
        ctxId.isNotEmpty &&
        ctxData.isNotEmpty &&
        ChurchRepository.churchId(ctxId) == resolved) {
      _applyChurchDataResult(
        ChurchDataLoadResult(
          seedTenantId: widget.tenantId.trim(),
          churchId: resolved,
          firestorePath: 'igrejas/$resolved',
          data: Map<String, dynamic>.from(ctxData),
          fieldCount: ctxData.length,
          loadedAt: DateTime.now(),
          readSource: 'session_context_sync',
          logoStoragePath: ChurchStorageLayout.churchIdentityLogoPath(resolved),
        ),
      );
    } else {
      unawaited(_hydrateCadastroFromLocalCacheFirst());
    }
    unawaited(_bootstrapCadastro());
  }

  Future<void> _hydrateCadastroFromLocalCacheFirst() async {
    final local = await ChurchCadastroLoadService.tryLocalSources(
      seedTenantId: widget.tenantId.trim(),
    );
    if (!mounted || local == null || local.data.isEmpty) return;
    _applyChurchDataResult(
      local.toChurchDataLoadResult(),
      softError: local.softError,
    );
  }

  @override
  void didUpdateWidget(IgrejaCadastroPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId.trim() != widget.tenantId.trim()) {
      _resetCadastroLoadState();
      unawaited(_bootstrapCadastro(forceRefresh: true));
    }
  }

  void _retryResolveTenant() {
    _resetCadastroLoadState();
    setState(() {});
    unawaited(_bootstrapCadastro(forceRefresh: true));
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
    _nameCtrl.dispose();
    _cnpjIgrejaCtrl.dispose();
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
    _linkMapsCtrl.dispose();
    _instagramUrlCtrl.dispose();
    _youtubeUrlCtrl.dispose();
    _facebookUrlCtrl.dispose();
    _whatsappChatUrlCtrl.dispose();
    _metaMinisterialTituloCtrl.dispose();
    _metaMinisterialValorCtrl.dispose();
    _metaMinisterialAcumuladoCtrl.dispose();
    unawaited(_igrejaLiveSub?.cancel());
    _igrejaLiveSub = null;
    super.dispose();
  }

  static String _firstNonEmptyString(
      Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final s = (data[k] ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// WhatsApp no cadastro: só dígitos no campo; migra URLs legadas (`wa.me/...`) para o número.
  static String _whatsappDigitsForCadastro(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower.contains('wa.me') || lower.contains('api.whatsapp.com')) {
      try {
        final normalized =
            s.startsWith(RegExp(r'https?://', caseSensitive: false))
                ? s
                : 'https://$s';
        final u = Uri.parse(normalized);
        final pathDigits = u.path.replaceAll(RegExp(r'[^0-9]'), '');
        if (pathDigits.isNotEmpty) return pathDigits;
      } catch (_) {}
    }
    return s.replaceAll(RegExp(r'[^0-9]'), '');
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
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'R\$\s*', caseSensitive: false), '')
        .trim();
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

  void _applyData(Map<String, dynamic>? data, {String? docIdFallback}) {
    if (data == null) return;
    var nome = (data['name'] ??
            data['nome'] ??
            data['NOME'] ??
            data['NOME_IGREJA'] ??
            data['razaoSocial'] ??
            data['displayName'] ??
            '')
        .toString()
        .trim();
    if (nome.isEmpty) {
      final slug = (data['slug'] ?? data['slugId'] ?? data['alias'] ?? '')
          .toString()
          .trim();
      if (slug.isNotEmpty) {
        nome = slug.replaceAll('-', ' ').replaceAll('_', ' ');
      }
    }
    if (nome.isEmpty && docIdFallback != null) {
      nome = _displayNameFromDocId(docIdFallback);
    }
    _nameCtrl.text = nome;
    _cnpjIgrejaCtrl.text =
        (data['cnpj'] ?? data['CNPJ'] ?? data['cnpjCpf'] ?? data['cpf'] ?? '')
            .toString();
    // Logo: path canónico Storage (`logoPath`) + URL https só em memória.
    final docId = (docIdFallback ?? '').trim();
    _logoStoragePath = ChurchImageFields.logoStoragePath(
          data,
          churchIdHint: docId,
        ) ??
        (docId.isNotEmpty
            ? ChurchStorageLayout.churchIdentityLogoPath(docId)
            : null);
    final urlFromLegacy = sanitizeImageUrl(
      (data['logoUrl'] ?? data['logo_url'] ?? '').toString(),
    );
    final urlFromLogoField =
        sanitizeImageUrl(ChurchImageFields.logoHttpsUrlFromDoc(data) ?? '');
    if (urlFromLegacy.isNotEmpty && isValidImageUrl(urlFromLegacy)) {
      _logoUrl = urlFromLegacy;
      _logoBytes = null;
      _logoStagedNotUploaded = false;
    } else if (urlFromLogoField.isNotEmpty &&
        isValidImageUrl(urlFromLogoField)) {
      _logoUrl = urlFromLogoField;
      _logoBytes = null;
      _logoStagedNotUploaded = false;
    } else {
      _logoUrl = null;
      final b64raw = (data['logoDataBase64'] ?? data['logoBase64'] ?? '')
          .toString()
          .trim();
      if (b64raw.isNotEmpty) {
        try {
          _logoBytes = base64Decode(b64raw);
          _logoStagedNotUploaded = false;
        } catch (_) {
          _logoBytes = null;
        }
      } else {
        _logoBytes = null;
        _logoStagedNotUploaded = false;
      }
    }

    _cidadeCtrl.text = (data['cidade'] ?? data['localidade'] ?? '').toString();
    _estadoCtrl.text = (data['estado'] ?? data['uf'] ?? '').toString();
    _bairroCtrl.text = (data['bairro'] ?? '').toString();
    final enderecoLinha =
        (data['endereco'] ?? data['endereço'] ?? data['addressLine'] ?? '')
            .toString()
            .trim();
    _ruaCtrl.text = (data['rua'] ?? data['address'] ?? enderecoLinha).toString();
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
    _slugCtrl.text = savedSlug.isNotEmpty
        ? savedSlug
        : _slugFromChurchName(_nameCtrl.text.trim());
    _metaMinisterialTituloCtrl.text =
        (data['metaMinisterialTitulo'] ?? '').toString().trim();
    _metaMinisterialValorCtrl.text =
        _metaMoneyDisplayFromFirestore(data['metaMinisterialValor']);
    _metaMinisterialAcumuladoCtrl.text =
        _metaMoneyDisplayFromFirestore(data['metaMinisterialAcumulado']);
    final carteiraCfg = CarteiraValidadeChurch.fromTenant(data);
    _carteiraValidadeModo = carteiraCfg.modo;
    _carteiraValidadeDataFixa = carteiraCfg.dataFixa;
    _gestorEmailCtrl.text =
        (data['gestorEmail'] ?? data['gestor_email'] ?? '').toString();
    _instagramUrlCtrl.text = _firstNonEmptyString(data, const [
      'instagramUrl',
      'instagram',
      'linkInstagram',
      'instagram_link',
    ]);
    _youtubeUrlCtrl.text = _firstNonEmptyString(data, const [
      'youtubeUrl',
      'youtube',
      'linkYoutube',
      'youtube_link',
    ]);
    _facebookUrlCtrl.text = _firstNonEmptyString(data, const [
      'facebookUrl',
      'facebook',
      'linkFacebook',
      'facebook_link',
    ]);
    _whatsappChatUrlCtrl.text = _whatsappDigitsForCadastro(_firstNonEmptyString(
        data,
        const [
          'whatsappChatUrl',
          'whatsapp',
          'socialWhatsappUrl',
          'whatsappLink',
          'linkWhatsapp',
        ]));
    _hydrateAddressFromCompositeEndereco(data);
    _lastHydratedCpf = null;
    _gestorMemberDocId = null;
    _gestorMemberData = null;
  }

  /// `endereco` legado (string única) → CEP, rua, bairro, cidade, UF.
  void _hydrateAddressFromCompositeEndereco(Map<String, dynamic> data) {
    final hasParts = _cepCtrl.text.trim().isNotEmpty ||
        _ruaCtrl.text.trim().isNotEmpty ||
        _bairroCtrl.text.trim().isNotEmpty ||
        _cidadeCtrl.text.trim().isNotEmpty;
    if (hasParts) return;

    final raw = (data['endereco'] ??
            data['ENDERECO'] ??
            data['enderecoCompleto'] ??
            '')
        .toString()
        .trim();
    if (raw.isEmpty) return;

    final cepMatch =
        RegExp(r'CEP\s*(\d{5})-?(\d{3})', caseSensitive: false).firstMatch(raw);
    if (cepMatch != null) {
      _cepCtrl.text = '${cepMatch.group(1)!}-${cepMatch.group(2)!}';
    }

    final cityState = RegExp(
      r',\s*([^,]+?)\s*-\s*([A-Za-z]{2})\s*(?:,|\s*CEP|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (cityState != null) {
      if (_cidadeCtrl.text.trim().isEmpty) {
        _cidadeCtrl.text = cityState.group(1)!.trim();
      }
      if (_estadoCtrl.text.trim().isEmpty) {
        _estadoCtrl.text = cityState.group(2)!.trim().toUpperCase();
      }
    }

    final parts = raw
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2 && _bairroCtrl.text.trim().isEmpty) {
      for (var i = parts.length - 2; i >= 0; i--) {
        final p = parts[i];
        if (RegExp(r'CEP\s*\d', caseSensitive: false).hasMatch(p)) continue;
        if (RegExp(r'-\s*[A-Za-z]{2}$').hasMatch(p)) continue;
        if (p.toUpperCase() == _cidadeCtrl.text.trim().toUpperCase()) continue;
        _bairroCtrl.text = p;
        break;
      }
    }

    if (_ruaCtrl.text.trim().isEmpty) {
      var rua = raw;
      if (cepMatch != null) {
        rua = rua.replaceAll(cepMatch.group(0)!, '').trim();
      }
      rua = rua.replaceAll(RegExp(r',\s*$'), '').trim();
      if (parts.isNotEmpty && _bairroCtrl.text.trim().isNotEmpty) {
        final bairro = _bairroCtrl.text.trim();
        final idx = parts.indexWhere(
          (p) => p.toUpperCase() == bairro.toUpperCase(),
        );
        if (idx > 0) {
          rua = parts.take(idx).join(', ');
        } else if (idx == 0 && parts.length > 1) {
          rua = parts.first;
        }
      }
      _ruaCtrl.text = rua;
    }
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

  /// IDs de documento em `membros` para contas com login = UID do Firebase Auth.
  static bool _looksLikeFirebaseAuthUid(String s) {
    final t = s.trim();
    if (t.length < 20 || t.length > 128) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(t);
  }

  /// CPF canónico (11 dígitos) a partir dos campos do membro.
  static String _cpfDigitsFromMemberData(Map<String, dynamic>? d) {
    if (d == null) return '';
    final raw =
        (d['CPF'] ?? d['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    return raw.length == 11 ? raw : '';
  }

  /// Legado / master: localiza documento por CPF (id ou campo). Com login, o padrão é `membros/{uid}`.
  Future<String> _resolveGestorMembroDocumentId(
      String resolvedId, String cpfDigits) async {
    if (cpfDigits.length != 11) return cpfDigits;
    final col =         ChurchRepository.churchDoc(resolvedId)
        .collection('membros');

    final hinted = (_gestorMemberDocId ?? '').trim();
    if (hinted.isNotEmpty) {
      try {
        final snap = await col.doc(hinted).get();
        if (snap.exists) {
          final d = snap.data();
          if (_cpfDigitsFromMemberData(d) == cpfDigits) return hinted;
        }
      } catch (_) {}
    }

    final byId = await col.doc(cpfDigits).get();
    if (byId.exists) return cpfDigits;

    for (final pair in [
      ('CPF', cpfDigits),
      ('cpf', cpfDigits),
      ('CPF', _cpfFormattedBr11(cpfDigits)),
      ('cpf', _cpfFormattedBr11(cpfDigits)),
    ]) {
      try {
        final q = await col.where(pair.$1, isEqualTo: pair.$2).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first.id;
      } catch (_) {}
    }
    return cpfDigits;
  }

  /// Remove outras fichas do mesmo gestor (mesmo CPF ou mesmo authUid), mantendo [canonicalId].
  Future<void> _deleteDuplicateGestorMembroDocs(
    CollectionReference<Map<String, dynamic>> col,
    String canonicalId,
    String cpfDigits,
    String authUidForMatch,
  ) async {
    final refs = <DocumentReference<Map<String, dynamic>>>{};
    if (cpfDigits.length == 11 && cpfDigits != canonicalId) {
      final s = await col.doc(cpfDigits).get();
      if (s.exists) refs.add(s.reference);
      for (final pair in [
        ('CPF', cpfDigits),
        ('cpf', cpfDigits),
        ('CPF', _cpfFormattedBr11(cpfDigits)),
        ('cpf', _cpfFormattedBr11(cpfDigits)),
      ]) {
        try {
          final q =
              await col.where(pair.$1, isEqualTo: pair.$2).limit(25).get();
          for (final d in q.docs) {
            if (d.id != canonicalId) refs.add(d.reference);
          }
        } catch (_) {}
      }
    }
    if (authUidForMatch.isNotEmpty) {
      try {
        final q = await col
            .where('authUid', isEqualTo: authUidForMatch)
            .limit(25)
            .get();
        for (final d in q.docs) {
          if (d.id != canonicalId) refs.add(d.reference);
        }
      } catch (_) {}
    }
    if (refs.isEmpty) return;
    const chunk = 400;
    final list = refs.toList();
    for (var i = 0; i < list.length; i += chunk) {
      final batch = ChurchRepository.batch();
      final end = (i + chunk > list.length) ? list.length : i + chunk;
      for (var j = i; j < end; j++) {
        batch.delete(list[j]);
      }
      await batch.commit();
    }
  }

  Future<void> _hydrateGestorFromMembros(String resolvedId,
      {bool force = false}) async {
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.length != 11 || !mounted) return;
    if (!force && _lastHydratedCpf == cpf) return;
    final seqAtStart = _gestorHydrateSeq;
    try {
      final col =           ChurchRepository.churchDoc(resolvedId)
          .collection('membros');
      DocumentSnapshot<Map<String, dynamic>>? memDoc;

      if (widget.role.toLowerCase() != 'master') {
        final curUid = FirebaseAuth.instance.currentUser?.uid;
        if (curUid != null && curUid.isNotEmpty) {
          final bySelf = await col.doc(curUid).get();
          if (bySelf.exists) {
            memDoc = bySelf;
          } else {
            try {
              final q =
                  await col.where('authUid', isEqualTo: curUid).limit(1).get();
              if (q.docs.isNotEmpty) memDoc = q.docs.first;
            } catch (_) {}
          }
        }
      }

      if (memDoc == null) {
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
      final resolvedPhoto = ph.isNotEmpty && isValidImageUrl(ph) ? ph : null;

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
        final mirror =
            await FirebaseStorageService.getGestorPublicMirrorPhotoUrl(
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
    final curUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final uidGestorVal =
        (_gestorMemberData?['authUid'] ?? '').toString().trim();
    final docId = (_gestorMemberDocId ?? '').trim();
    final selfGestor =
        curUid.isNotEmpty && (curUid == uidGestorVal || curUid == docId);
    final roleLower = widget.role.toLowerCase();
    final staff =
        roleLower == 'gestor' || roleLower == 'adm' || roleLower == 'admin';
    if (selfGestor && staff) {
      if (_gestorNomeCtrl.text.trim().isEmpty) {
        return 'Preencha o nome completo.';
      }
      final cpfSelf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (cpfSelf.length != 11) {
        return 'Informe seu CPF (11 dígitos).';
      }
      if (_gestorEmailCtrl.text.trim().isEmpty) {
        final em = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
        if (em.isNotEmpty) {
          _gestorEmailCtrl.text = em;
        }
      }
      if (_gestorEmailCtrl.text.trim().isEmpty) {
        return 'E-mail é obrigatório.';
      }
      return null;
    }
    if (_gestorNomeCtrl.text.trim().isEmpty)
      return 'Preencha o nome completo do gestor.';
    final cpf = _gestorCpfCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (cpf.isNotEmpty && cpf.length != 11) {
      return 'CPF do gestor deve ter 11 dígitos ou ficar em branco.';
    }
    final podeSemCpf = uidGestorVal.isNotEmpty ||
        (curUid.isNotEmpty && widget.role.toLowerCase() != 'master');
    if (cpf.length != 11 && !podeSemCpf) {
      return 'Informe o CPF do gestor (11 dígitos) ou edite este cadastro com a conta do gestor.';
    }
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
    final dataAuth = (_gestorMemberData?['authUid'] ?? '').toString().trim();
    if (cpfDigits.length != 11 &&
        dataAuth.isEmpty &&
        (uid.isEmpty || widget.role.toLowerCase() == 'master')) {
      return;
    }

    final slugRaw = _slugCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final col =         ChurchRepository.churchDoc(resolvedId)
        .collection('membros');
    final roleLower = widget.role.toLowerCase();
    final editorIsChurchStaff =
        roleLower == 'gestor' || roleLower == 'adm' || roleLower == 'admin';

    late final String docId;
    if (dataAuth.isNotEmpty) {
      docId = dataAuth;
    } else if (editorIsChurchStaff && uid.isNotEmpty) {
      docId = uid;
    } else if (cpfDigits.length == 11) {
      docId = await _resolveGestorMembroDocumentId(resolvedId, cpfDigits);
    } else if (uid.isNotEmpty) {
      docId = uid;
    } else {
      return;
    }

    final String authUidForPayload;
    if (_looksLikeFirebaseAuthUid(docId)) {
      authUidForPayload = docId;
    } else if (dataAuth.isNotEmpty && _looksLikeFirebaseAuthUid(dataAuth)) {
      authUidForPayload = dataAuth;
    } else if (editorIsChurchStaff && uid.isNotEmpty) {
      authUidForPayload = uid;
    } else {
      authUidForPayload = '';
    }

    final ref = col.doc(docId);
    final existingSnap = await ref.get();

    String? photoUrl = _gestorExistingPhotoUrl;
    if ((photoUrl == null || photoUrl.isEmpty) && docId.isNotEmpty) {
      final authGestor = (authUidForPayload.isNotEmpty
              ? authUidForPayload
              : (_gestorMemberData?['authUid'] ?? uid))
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
    Uint8List? pendingGestorPhotoBytes;
    if (_gPhotoBytes != null) {
      pendingGestorPhotoBytes = Uint8List.fromList(_gPhotoBytes!);
      if (mounted) setState(() => _gPhotoBytes = null);
    }
    if (pendingGestorPhotoBytes == null &&
        (photoUrl == null || photoUrl.isEmpty)) {
      final seed = authUidForPayload.isNotEmpty
          ? authUidForPayload
          : (cpfDigits.isNotEmpty ? cpfDigits : uid);
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
      'MEMBER_ID': docId,
      'CREATED_BY_CPF': cpfDigits,
      'tenantId': resolvedId,
      'igrejaId': resolvedId,
      'churchId': resolvedId,
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
      'GESTOR_SYNC': true,
      'ATUALIZADO_EM': FieldValue.serverTimestamp(),
      'podeVerFinanceiro': false,
      'podeVerPatrimonio': false,
    };
    if (authUidForPayload.isNotEmpty) {
      payload['authUid'] = authUidForPayload;
    }
    if (pendingGestorPhotoBytes != null) {
      payload.addAll(MemberProfilePhotoUpdateService.pendingUploadPatchFields());
    }
    if (!existingSnap.exists) {
      payload['CRIADO_EM'] = FieldValue.serverTimestamp();
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => ref.set(payload, SetOptions(merge: true)),
    );

    if (pendingGestorPhotoBytes != null && pendingGestorPhotoBytes.isNotEmpty) {
      final mergedGestor = Map<String, dynamic>.from(payload);
      MemberProfilePhotoUpdateService.scheduleBackgroundPhotoUpload(
        tenantId: resolvedId,
        memberDocId: docId,
        memberData: mergedGestor,
        rawBytes: pendingGestorPhotoBytes,
        onSuccess: (result) {
          if (!mounted) return;
          setState(() => _gestorExistingPhotoUrl = result.downloadUrl);
        },
      );
    }

    await _deleteDuplicateGestorMembroDocs(
        col, docId, cpfDigits, authUidForPayload);

    final userWriteId = authUidForPayload.isNotEmpty
        ? authUidForPayload
        : (uid.isNotEmpty && editorIsChurchStaff ? uid : '');

    // Gravações em paralelo (menos tempo em "Salvando...").
    final parallel = <Future<void>>[];
    if (userWriteId.isNotEmpty && _looksLikeFirebaseAuthUid(userWriteId)) {
      parallel.add(
        FirestoreWebGuard.runWithWebRecovery(
          () => FirebaseFirestore.instance
              .collection('users')
              .doc(userWriteId)
              .set({
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
          }, SetOptions(merge: true)),
        ).catchError((Object _, StackTrace __) {}),
      );
      parallel.add(
        FirestoreWebGuard.runWithWebRecovery(
          () =>               ChurchRepository.churchDoc(resolvedId)
              .collection('users')
              .doc(userWriteId)
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
          }, SetOptions(merge: true)),
        ),
      );
    }
    if (cpfDigits.length == 11) {
      parallel.add(
        FirestoreWebGuard.runWithWebRecovery(
          () =>               ChurchRepository.churchDoc(resolvedId)
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
            if (authUidForPayload.isNotEmpty) 'uid': authUidForPayload,
            if (authUidForPayload.isNotEmpty) 'authUid': authUidForPayload,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)),
        ),
      );
    }
    if (authUidForPayload.isNotEmpty &&
        _looksLikeFirebaseAuthUid(authUidForPayload) &&
        authUidForPayload != cpfDigits) {
      parallel.add(
        FirestoreWebGuard.runWithWebRecovery(
          () =>               ChurchRepository.churchDoc(resolvedId)
              .collection('usersIndex')
              .doc(authUidForPayload)
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
            'uid': authUidForPayload,
            'authUid': authUidForPayload,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)),
        ),
      );
    }
    await Future.wait<void>(parallel);

    if (mounted) {
      _gestorHydrateSeq++;
      setState(() {
        _gestorMemberDocId = docId;
        _lastHydratedCpf = cpfDigits;
        _gestorMemberData = Map<String, dynamic>.from(payload);
        final pu = (photoUrl ?? '').trim();
        if (pu.isNotEmpty) {
          _gestorExistingPhotoUrl = pu;
        }
      });
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
        _logoStagedNotUploaded = false;
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
      _logoStagedNotUploaded = true;
      _uploadingLogo = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Logo carregada. Use Cortar se quiser; ao Salvar igreja a logo será enviada automaticamente.'),
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
    if (cropped != null && mounted) {
      setState(() {
        _logoBytes = cropped;
        _logoStagedNotUploaded = true;
      });
    }
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

  Future<void> _deleteChurchLogoStorageObjectAndVariants(
      String? storagePath) async {
    final p = storagePath?.trim() ?? '';
    if (p.isEmpty) return;
    await FirebaseStorageCleanupService.deleteByUrlPathOrGs(p);
    final lower = p.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png')) {
      final dot = p.lastIndexOf('.');
      final base = dot < 0 ? p : p.substring(0, dot);
      for (final suffix in <String>['_thumb.jpg', '_card.jpg', '_full.jpg']) {
        await FirebaseStorageCleanupService.deleteByUrlPathOrGs('$base$suffix');
      }
      // Extensão Resize Images: `thumb_<baseDoFicheiro>.jpg` junto a `logo_igreja.png`
      final slash = p.lastIndexOf('/');
      if (slash >= 0 && dot > slash) {
        final dir = p.substring(0, slash);
        final fileBase = p.substring(slash + 1, dot);
        if (fileBase.isNotEmpty) {
          await FirebaseStorageCleanupService.deleteByUrlPathOrGs(
            '$dir/thumb_$fileBase.jpg',
          );
        }
      }
    }
  }

  /// Publica `configuracoes/logo_igreja.png` e grava **somente** [logoPath] no Firestore.
  /// Retorna `false` se tentou enviar e falhou (o chamador pode abortar o resto do save).
  Future<bool> _commitLogoUploadFromPending({
    bool showCommitSuccessSnack = true,
    bool deferFirestorePatch = false,
    bool suppressProgressUi = false,
  }) async {
    if (!_canEdit || _logoBytes == null || !mounted) return true;
    if (!suppressProgressUi) {
      setState(() {
        _uploadingLogo = true;
        _logoUploadProgress = 0;
        _logoUploadPhase = 'encoding';
      });
    } else {
      _uploadingLogo = true;
      _logoUploadPhase = 'uploading';
    }
    try {
      await ensureFirebaseReadyForPublishUpload();
      final resolvedId = await _resolveTenantIdForSave();
      final png =
          await encodeChurchLogoAsPngInIsolate(_logoBytes!, maxSide: 1920);
      if (!mounted) return true;
      if (!suppressProgressUi) {
        setState(() {
          _logoUploadPhase = 'uploading';
          _logoUploadProgress = 0.05;
        });
      }
      await _deleteChurchLogoStorageObjectAndVariants(_logoStoragePath);
      // Mantém só a identidade canónica em PNG: remove legado `.jpg` no mesmo sítio.
      await FirebaseStorageCleanupService.deleteByUrlPathOrGs(
        ChurchStorageLayout.churchIdentityLogoPathJpgLegacy(resolvedId),
      );
      final identityPath =
          ChurchStorageLayout.churchIdentityLogoPath(resolvedId);
      final upload = await MediaUploadService.uploadBytesDetailed(
        storagePath: identityPath,
        bytes: png,
        contentType: 'image/png',
        onProgress: suppressProgressUi
            ? null
            : (p) {
                if (!mounted) return;
                setState(() => _logoUploadProgress = p.clamp(0.0, 1.0));
              },
      );
      final url = upload.downloadUrl;
      if (!mounted) return true;
      setState(() {
        _logoUrl = url;
        _logoBytes = png;
        _logoStoragePath = upload.storagePath;
        _uploadingLogo = false;
        _logoUploadPhase = '';
      });
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
      if (!deferFirestorePatch) {
        await ChurchBrandService.persistLogoPath(
          churchId: resolvedId,
          storagePath: upload.storagePath,
          downloadUrl: upload.downloadUrl,
        );
      }
      _logoStagedNotUploaded = false;
      FirebaseStorageCleanupService.scheduleCleanupAfterChurchConfigImageUpload(
        tenantId: resolvedId,
      );
      unawaited(
          FirebaseStorageCleanupService.deleteLegacyChurchLogoMediaUnderTenant(
              resolvedId));
      if (!mounted) return true;
      setState(() {});
      if (mounted && showCommitSuccessSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Logo enviada (configuracoes/logo_igreja.png). Carteirinha, certificados e relatórios usam este ficheiro.'),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingLogo = false;
          _logoUploadPhase = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao enviar logo: $e'),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _logoUploadProgress = 0;
          if (!_uploadingLogo) _logoUploadPhase = '';
        });
      }
    }
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

  /// Renova URL em memória (exibição) — **não** grava URL no Firestore.
  Future<void> _maybeRefreshStorageLogoUrl() async {
    final resolvedId = (_operationalTenantId ?? widget.tenantId).trim();
    if (resolvedId.isEmpty) return;
    try {
      await ensureFirebaseReadyForPanelRead();
      final fresh = await ChurchBrandService.getLogoUrl(churchId: resolvedId);
      if (!mounted || fresh == null || fresh.isEmpty) return;
      setState(() {
        _logoUrl = fresh;
        _logoBytes = null;
        _logoStagedNotUploaded = false;
      });
    } catch (_) {}
  }

  /// Quando o Firestore não tem URL https mas a logo existe em Storage ([logoPath]).
  Future<void> _hydrateLogoUrlFromStorageIfNeeded(
    String tenantDocId,
    Map<String, dynamic> data,
  ) async {
    if (!mounted) return;
    final existing = (_logoUrl ?? '').trim();
    if (existing.isNotEmpty && isValidImageUrl(sanitizeImageUrl(existing))) {
      return;
    }
    try {
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      }
      final path = ChurchBrandService.logoPathFromData(
            data,
            churchId: tenantDocId,
          ) ??
          ChurchBrandService.canonicalLogoPath(tenantDocId);
      final resolved =
          await AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tenantDocId,
        tenantData: data,
        preferStoragePath: path,
      ).timeout(ChurchPanelReadTimeouts.warmCap);
      if (!mounted) return;
      final clean = sanitizeImageUrl(resolved ?? '');
      if (clean.isEmpty || !isValidImageUrl(clean)) return;
      setState(() {
        _logoUrl = clean;
        _logoStoragePath = path;
        _logoBytes = null;
        _logoStagedNotUploaded = false;
      });
    } catch (_) {}
  }

  Future<String> _resolveTenantIdForSave() async {
    final cached = (_operationalTenantId ?? '').trim();
    if (cached.isNotEmpty) return cached;
    return ChurchRepository.churchId(widget.tenantId);
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ThemeCleanPremium.hapticAction();
    setState(() => _saving = true);
    var savedTenantId = '';
    try {
      await _prepareCadastroFirestoreWrite();
      await FirebaseAuth.instance.currentUser?.getIdToken(false);
      final resolvedId = await _resolveTenantIdForSave();
      savedTenantId = resolvedId;
      if (_canEdit &&
          _logoStagedNotUploaded &&
          _logoBytes != null &&
          !_uploadingLogo) {
        if (kIsWeb) {
          unawaited(_commitLogoUploadFromPending(
            showCommitSuccessSnack: true,
            deferFirestorePatch: false,
            suppressProgressUi: true,
          ));
        } else {
          final logoOk = await _commitLogoUploadFromPending(
            showCommitSuccessSnack: false,
            deferFirestorePatch: true,
          );
          if (!mounted) return;
          if (!logoOk) {
            setState(() => _saving = false);
            return;
          }
        }
      }
      final slugRaw = _slugCtrl.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final cnpjDigits = _cnpjIgrejaCtrl.text.replaceAll(RegExp(r'\D'), '');
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'nome': _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        'igrejaId': resolvedId,
        'tenantId': resolvedId,
        'churchId': resolvedId,
        'churchCanonicalId': resolvedId,
        'canonicalTenantId': resolvedId,
        'registrationComplete': true,
        'alias': FieldValue.delete(),
        'slug': FieldValue.delete(),
        'slugId': FieldValue.delete(),
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
        ...(cnpjDigits.isEmpty
            ? <String, dynamic>{
                'cnpj': FieldValue.delete(),
                'CNPJ': FieldValue.delete(),
                'cnpjCpf': FieldValue.delete(),
              }
            : <String, dynamic>{
                'cnpj': _cnpjIgrejaCtrl.text.trim(),
                'CNPJ': _cnpjIgrejaCtrl.text.trim(),
                'cnpjCpf': _cnpjIgrejaCtrl.text.trim(),
              }),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      void mergeOptionalUrl(
        String trimmed,
        String primaryKey,
        List<String> legacyKeys,
      ) {
        if (trimmed.isEmpty) {
          data[primaryKey] = FieldValue.delete();
          for (final k in legacyKeys) {
            data[k] = FieldValue.delete();
          }
        } else {
          data[primaryKey] = trimmed;
        }
      }

      mergeOptionalUrl(_instagramUrlCtrl.text.trim(), 'instagramUrl', const [
        'instagram',
        'linkInstagram',
      ]);
      mergeOptionalUrl(_youtubeUrlCtrl.text.trim(), 'youtubeUrl', const [
        'youtube',
        'linkYoutube',
      ]);
      mergeOptionalUrl(_facebookUrlCtrl.text.trim(), 'facebookUrl', const [
        'facebook',
        'linkFacebook',
      ]);
      final waDigits =
          _whatsappChatUrlCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      mergeOptionalUrl(waDigits, 'whatsappChatUrl', const [
        'socialWhatsappUrl',
        'whatsappLink',
        'linkWhatsapp',
      ]);
      if (waDigits.isEmpty) {
        data['whatsapp'] = FieldValue.delete();
      } else {
        data['whatsapp'] = waDigits;
      }

      if (_logoUrl != null && _logoUrl!.trim().isNotEmpty) {
        final url = sanitizeImageUrl(_logoUrl!.trim());
        data['logoPath'] = url;
        data['logoUrl'] = url;
        if (_logoStoragePath != null && _logoStoragePath!.trim().isNotEmpty) {
          final normalized = StorageMediaService.normalizeFirestoreStoragePath(
                _logoStoragePath,
              ) ??
              _logoStoragePath!.trim();
          data['logoStoragePath'] = normalized;
        }
      }
      for (final k in ChurchBrandService.legacyLogoUrlFirestoreKeys) {
        if (k == 'logoUrl') continue;
        data[k] = FieldValue.delete();
      }
      final enderecoCompleto = _buildEnderecoCompleto();
      if (enderecoCompleto.isNotEmpty) data['endereco'] = enderecoCompleto;
      if (_latitude != null) data['latitude'] = _latitude;
      if (_longitude != null) data['longitude'] = _longitude;

      final carteiraCfg = CarteiraValidadeChurch(
        modo: _carteiraValidadeModo,
        dataFixa: _carteiraValidadeDataFixa,
      );
      data[CarteiraValidadeChurch.firestoreKeyModo] = carteiraCfg.firestoreModoValue;
      data['carteiraValidadePermanente'] =
          _carteiraValidadeModo == CarteiraValidadeModo.permanente;
      final anosLegado = switch (_carteiraValidadeModo) {
        CarteiraValidadeModo.anos2 => 2,
        CarteiraValidadeModo.anos3 => 3,
        CarteiraValidadeModo.anos5 => 5,
        _ => null,
      };
      if (anosLegado != null) {
        data['carteiraValidadeAnos'] = anosLegado;
      } else {
        data['carteiraValidadeAnos'] = FieldValue.delete();
      }
      if (_carteiraValidadeModo == CarteiraValidadeModo.dataFixa &&
          _carteiraValidadeDataFixa != null) {
        data[CarteiraValidadeChurch.firestoreKeyDataFixa] =
            Timestamp.fromDate(_carteiraValidadeDataFixa!);
      } else {
        data[CarteiraValidadeChurch.firestoreKeyDataFixa] = FieldValue.delete();
      }

      if (slugRaw.isNotEmpty) {
        if (AppConstants.reservedChurchSlugs.contains(slugRaw)) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.feedbackSnackBar(
                'Este link está reservado pelo sistema. Altere o nome da igreja para gerar outro endereço.',
              ),
            );
          }
          return;
        }
        if (!kIsWeb &&
            _slugNeedsUniquenessCheck(slugRaw)) {
          final taken = await FirestoreWebGuard.runWithWebRecovery(
            () => FirestoreReadResilience.getQuery(
              ChurchRepository.churchDoc(resolvedId)
                  .parent
                  .where('slug', isEqualTo: slugRaw)
                  .limit(2),
              cacheKey: 'igrejas_slug_check_$slugRaw',
            ),
            maxAttempts: 4,
          );
          if (taken.docs.any((d) => d.id != resolvedId)) {
            if (mounted) {
              setState(() => _saving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                ThemeCleanPremium.feedbackSnackBar(
                  'O link "$slugRaw" já está em uso por outra igreja. Altere o nome da igreja para gerar outro.',
                ),
              );
            }
            return;
          }
        }
      }

      data['sitePrimaryHex'] = FieldValue.delete();

      await ChurchCadastroSaveService.saveChurchProfile(
        churchId: resolvedId,
        seedTenantId: widget.tenantId,
        data: data,
      );
      if (!mounted) return;
      try {
        await GestorMembroStubService.ensurePreCadastroGestor(
          tenantId: resolvedId,
          role: widget.role,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
              'Cadastro da igreja salvo. Complete sua ficha pessoal em Membros quando quiser.',
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar(
              'Igreja salva. Pré-cadastro em Membros: $e',
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final msg = FirestoreWebGuard.isInternalAssertionError(e)
          ? 'Firestore instável na web. Aguarde 3 segundos e toque em Salvar novamente.'
          : 'Erro ao salvar: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(msg),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      final tid = savedTenantId.trim().isNotEmpty
          ? savedTenantId.trim()
          : (_operationalTenantId ?? _hydratedTenantId ?? '').trim();
      if (tid.isNotEmpty && mounted) {
        if (kIsWeb) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (mounted) unawaited(_refreshIgrejaDocOnce(tid));
        } else {
          _bindIgrejaLiveWatch(tid);
        }
      }
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

  void _hydrateFormFromFirestoreDoc(
    String resolvedId,
    Map<String, dynamic> live,
  ) {
    final slim = ChurchCadastroLoadService.sliceCadastroFormFields(live);
    final incomingScore =
        TenantResolverService.churchProfileRichnessScore(slim);
    if (_hydratedTenantId == resolvedId &&
        _formHydrated &&
        _nameCtrl.text.trim().isNotEmpty &&
        incomingScore <= _hydratedProfileScore) {
      return;
    }
    _applyData(slim, docIdFallback: resolvedId);
    _tenantLiveData = Map<String, dynamic>.from(slim);
    _formHydrated = true;
    _hydratedTenantId = resolvedId;
    _hydratedProfileScore = incomingScore;
    _notedNonexistentIgrejaDoc = false;
    if (mounted) setState(() {});
    unawaited(_afterFormHydrated(resolvedId, slim));
  }

  Future<void> _afterFormHydrated(
    String resolvedId,
    Map<String, dynamic> live,
  ) async {
    if (!_logoTokenRefreshAttempted) {
      _logoTokenRefreshAttempted = true;
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        unawaited(_maybeRefreshStorageLogoUrl());
      });
    }
    if (_canEdit) {
      unawaited(
        FirebaseStorageService.ensureChurchConfigFolderPlaceholderIfAbsent(
          resolvedId,
        ),
      );
    }
    if (!mounted) return;
    final existing = (_logoUrl ?? '').trim();
    final hasHttps =
        existing.isNotEmpty && isValidImageUrl(sanitizeImageUrl(existing));
    if (!hasHttps && _logoStorageHydrationTenantId != resolvedId) {
      _logoStorageHydrationTenantId = resolvedId;
      await _hydrateLogoUrlFromStorageIfNeeded(resolvedId, live);
      if (mounted) setState(() {});
    }
  }

  Widget _buildCadastroFormSkeleton(String resolvedId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: ThemeCleanPremium.spaceMd,
            bottom: ThemeCleanPremium.spaceSm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ThemeCleanPremium.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Carregando igrejas/$resolvedId…',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        YahwehSkeletonLoading.cadastroForm(),
      ],
    );
  }

  Widget _buildCadastroJaExisteChip() {
    if (!_formHydrated || _nameCtrl.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
      child: Material(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cadastro já existe no sistema — dados carregados abaixo. '
                  'Revise e toque em Salvar se alterar algo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade900,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ID canônico = documento em `igrejas/{id}` (membros, mural, eventos, escalas usam este id).
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
            style: TextStyle(
                fontSize: 11, color: Colors.grey.shade600, height: 1.3),
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
                    ThemeCleanPremium.successSnackBar(
                        'ID copiado para a área de transferência.'),
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

  /// Rodapé: salvar cadastro da igreja + lembrete para completar dados pessoais em Membros.
  Widget _buildChurchSaveFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE8EEF5)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.groups_2_rounded,
                  color: ThemeCleanPremium.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sua foto, CPF e demais dados pessoais ficam em Membros (menu Pessoas). Ao salvar aqui, criamos um pré-cadastro mínimo se ainda não existir.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          if (_canEdit)
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label:
                  Text(_saving ? 'Salvando...' : 'Salvar cadastro da igreja'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
              ),
            )
          else
            Text(
              'Apenas gestores podem editar o cadastro da igreja.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                  'IDENTIDADE DA IGREJA',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.15,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cadastro da igreja',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: ThemeCleanPremium.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nome, CPF/CNPJ, logo, endereço com CEP e links públicos. Sua ficha pessoal fica em Membros.',
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

  Widget _buildSoftSyncBanner() {
    final msg = (_cadastroSoftSyncWarning ?? '').trim();
    if (msg.isEmpty) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_sync_rounded,
                color: Colors.orange.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sincronização parcial: $msg Toque em «Atualizar» para tentar de novo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.orange.shade900,
                  height: 1.4,
                ),
              ),
            ),
            TextButton(
              onPressed: _retryResolveTenant,
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_cadastroBootstrapDone &&
        ChurchRepository.churchId(widget.tenantId).isEmpty) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surface,
        appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cadastroBootstrapError != null &&
        (_operationalTenantId ?? '').trim().isEmpty &&
        ChurchRepository.churchId(widget.tenantId).isEmpty) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surface,
        appBar: widget.embeddedInShell ? null : _igrejaCadastroAppBar(),
        body: ChurchPanelResilientLoadBanner(
          hasLocalData: false,
          isSyncing: false,
          errorTitle: 'Não foi possível carregar o cadastro da igreja.',
          error: _cadastroBootstrapError,
          onRetry: _retryResolveTenant,
        ),
      );
    }

    final resolvedId = (_operationalTenantId ?? widget.tenantId).trim().isEmpty
        ? widget.tenantId.trim()
        : (_operationalTenantId ?? widget.tenantId).trim();

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
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: fullWidth > 1200 ? 1000 : fullWidth,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPageIntroHeader(),
                            if (_cadastroSoftSyncWarning != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: ThemeCleanPremium.spaceMd),
                                child: _buildSoftSyncBanner(),
                              ),
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
                                              'Nome, logo, endereço e contatos no painel e no site público.',
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
                                  if (!_formHydrated)
                                    _buildCadastroFormSkeleton(resolvedId)
                                  else ...[
                                  _buildCadastroJaExisteChip(),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  TextFormField(
                                    controller: _nameCtrl,
                                    readOnly: !_canEdit,
                                    decoration: const InputDecoration(
                                      labelText: 'Nome completo da igreja',
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
                                      height: ThemeCleanPremium.spaceMd),
                                  TextFormField(
                                    controller: _cnpjIgrejaCtrl,
                                    readOnly: !_canEdit,
                                    keyboardType: TextInputType.text,
                                    decoration: const InputDecoration(
                                      labelText: 'CPF ou CNPJ da igreja',
                                      hintText:
                                          'Somente números ou com máscara',
                                      helperText:
                                          'Opcional no início; use o mesmo CPF se for MEI.',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) {
                                      final d = (v ?? '')
                                          .replaceAll(RegExp(r'\D'), '');
                                      if (d.isEmpty) return null;
                                      if (d.length != 11 && d.length != 14) {
                                        return 'Informe 11 (CPF) ou 14 (CNPJ) dígitos.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          ThemeCleanPremium.primary
                                              .withValues(alpha: 0.07),
                                          const Color(0xFFF8FAFC),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: ThemeCleanPremium.primary
                                            .withValues(alpha: 0.14),
                                      ),
                                      boxShadow:
                                          ThemeCleanPremium.softUiCardShadow,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.05),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.photo_library_rounded,
                                                color:
                                                    ThemeCleanPremium.primary,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Logo da igreja',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: -0.35,
                                                      color: ThemeCleanPremium
                                                          .onSurface,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Toque na moldura para escolher na galeria. Ao salvar, a imagem é otimizada e enviada automaticamente.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        if (_canEdit &&
                                            _logoBytes != null &&
                                            !_uploadingLogo)
                                          Align(
                                            alignment: Alignment.center,
                                            child: TextButton.icon(
                                              onPressed: _cropPendingLogo,
                                              icon: Icon(
                                                Icons.crop_rounded,
                                                size: 18,
                                                color:
                                                    ThemeCleanPremium.primary,
                                              ),
                                              label: Text(
                                                'Cortar pré-visualização',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      ThemeCleanPremium.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_uploadingLogo) ...[
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: LinearProgressIndicator(
                                              value: _logoUploadPhase ==
                                                          'uploading' &&
                                                      _logoUploadProgress > 0
                                                  ? _logoUploadProgress.clamp(
                                                      0.0, 1.0)
                                                  : null,
                                              minHeight: 8,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.85),
                                              color: ThemeCleanPremium.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _logoUploadPhase == 'encoding'
                                                ? 'A otimizar imagem em segundo plano…'
                                                : 'A enviar para a nuvem: ${(_logoUploadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: ThemeCleanPremium.primary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
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
                                                    : _pickLogoFromGallery,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                child: _igLogoOuterFrame(
                                                  width: previewW,
                                                  height: boxH,
                                                  child: Center(
                                                    child: _logoBytes != null
                                                        ? Image.memory(
                                                            _logoBytes!,
                                                            fit: BoxFit.contain,
                                                            width: previewW,
                                                            height: boxH,
                                                            gaplessPlayback:
                                                                true,
                                                            filterQuality:
                                                                FilterQuality
                                                                    .high,
                                                            isAntiAlias: true,
                                                            errorBuilder: (_,
                                                                    __, ___) =>
                                                                _buildLogoPlaceholder(
                                                              boxWidth: previewW,
                                                              boxHeight: boxH,
                                                            ),
                                                          )
                                                        : resolvedId.isNotEmpty
                                                            ? StableChurchLogo(
                                                                storagePath:
                                                                    _logoStoragePath,
                                                                imageUrl:
                                                                    _logoUrl,
                                                                tenantId:
                                                                    resolvedId,
                                                                tenantData:
                                                                    _tenantLiveData,
                                                                width: previewW,
                                                                height: boxH,
                                                                fit: BoxFit
                                                                    .contain,
                                                                memCacheWidth:
                                                                    (previewW *
                                                                            MediaQuery.devicePixelRatioOf(context))
                                                                        .round()
                                                                        .clamp(
                                                                            128,
                                                                            560),
                                                                memCacheHeight:
                                                                    (boxH *
                                                                            MediaQuery.devicePixelRatioOf(context))
                                                                        .round()
                                                                        .clamp(
                                                                            96,
                                                                            400),
                                                              )
                                                            : SizedBox(
                                                                width: previewW,
                                                                height: boxH,
                                                                child:
                                                                    _buildLogoPlaceholder(
                                                                  boxWidth:
                                                                      previewW,
                                                                  boxHeight:
                                                                      boxH,
                                                                  showPickHint:
                                                                      _canEdit,
                                                                ),
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
                                                        _pickLogoFromGallery,
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
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
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
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _cadastroSectionLabel(
                                      'Carteirinha de membro — validade'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Define a validade exibida em todas as carteirinhas. '
                                    'Para prazos em anos, a data conta a partir da emissão ou assinatura de cada membro.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<CarteiraValidadeModo>(
                                    value: _carteiraValidadeModo,
                                    decoration: const InputDecoration(
                                      labelText: 'Validade da carteirinha',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: CarteiraValidadeModo.permanente,
                                        child: Text('Permanente'),
                                      ),
                                      DropdownMenuItem(
                                        value: CarteiraValidadeModo.anos2,
                                        child: Text('02 anos'),
                                      ),
                                      DropdownMenuItem(
                                        value: CarteiraValidadeModo.anos3,
                                        child: Text('03 anos'),
                                      ),
                                      DropdownMenuItem(
                                        value: CarteiraValidadeModo.anos5,
                                        child: Text('05 anos'),
                                      ),
                                      DropdownMenuItem(
                                        value: CarteiraValidadeModo.dataFixa,
                                        child: Text('Data fixa (escolher)'),
                                      ),
                                    ],
                                    onChanged: !_canEdit
                                        ? null
                                        : (v) {
                                            if (v == null) return;
                                            setState(() {
                                              _carteiraValidadeModo = v;
                                              if (v != CarteiraValidadeModo.dataFixa) {
                                                _carteiraValidadeDataFixa = null;
                                              }
                                            });
                                          },
                                  ),
                                  if (_carteiraValidadeModo ==
                                      CarteiraValidadeModo.dataFixa) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: !_canEdit
                                          ? null
                                          : () async {
                                              final now = DateTime.now();
                                              final picked = await showDatePicker(
                                                context: context,
                                                locale: const Locale('pt', 'BR'),
                                                initialDate:
                                                    _carteiraValidadeDataFixa ??
                                                        DateTime(
                                                          now.year + 3,
                                                          now.month,
                                                          now.day,
                                                        ),
                                                firstDate: now,
                                                lastDate: DateTime(now.year + 30),
                                              );
                                              if (picked != null && mounted) {
                                                setState(() =>
                                                    _carteiraValidadeDataFixa =
                                                        picked);
                                              }
                                            },
                                      icon: const Icon(Icons.event_rounded),
                                      label: Text(
                                        _carteiraValidadeDataFixa == null
                                            ? 'Escolher data de validade'
                                            : 'Validade até: ${_carteiraValidadeDataFixa!.day.toString().padLeft(2, '0')}/${_carteiraValidadeDataFixa!.month.toString().padLeft(2, '0')}/${_carteiraValidadeDataFixa!.year}',
                                      ),
                                    ),
                                  ],
                                  const SizedBox(
                                      height: ThemeCleanPremium.spaceLg),
                                  _cadastroSectionLabel(
                                      'Site público — redes sociais'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Aparecem na área de contato do site público. Instagram, YouTube e Facebook: links completos (https://…). WhatsApp: apenas o número com DDI (ex.: 5562999999999), sem link.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _instagramUrlCtrl,
                                    readOnly: !_canEdit,
                                    decoration: _premiumInputDeco(
                                      'Instagram',
                                      'https://instagram.com/suaigreja',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _youtubeUrlCtrl,
                                    readOnly: !_canEdit,
                                    decoration: _premiumInputDeco(
                                      'YouTube',
                                      'https://youtube.com/@canal',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _facebookUrlCtrl,
                                    readOnly: !_canEdit,
                                    decoration: _premiumInputDeco(
                                      'Facebook',
                                      'https://facebook.com/suaigreja',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _whatsappChatUrlCtrl,
                                    readOnly: !_canEdit,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: _premiumInputDeco(
                                      'WhatsApp — número com DDI (opcional)',
                                      '5562999999999',
                                    ),
                                  ),
                                  if (_slugCtrl.text.trim().isNotEmpty) ...[
                                    const SizedBox(
                                        height: ThemeCleanPremium.spaceLg),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(
                                          ThemeCleanPremium.spaceMd),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            ThemeCleanPremium.primary
                                                .withValues(alpha: 0.06),
                                            const Color(0xFFF8FAFC),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(
                                            ThemeCleanPremium.radiusMd),
                                        border: Border.all(
                                          color: ThemeCleanPremium.primary
                                              .withValues(alpha: 0.18),
                                        ),
                                        boxShadow:
                                            ThemeCleanPremium.softUiCardShadow,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.public_rounded,
                                                  size: 22,
                                                  color: ThemeCleanPremium
                                                      .primary),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Seus links públicos',
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.3,
                                                    color: ThemeCleanPremium
                                                        .primary),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Gerados a partir do nome da igreja. Use para divulgar o site e o cadastro de membros.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                height: 1.35),
                                          ),
                                          const SizedBox(height: 14),
                                          Builder(builder: (ctx) {
                                            final slug =
                                                _slugCtrl.text.trim();
                                            final homeUrl = slug.isEmpty
                                                ? AppConstants.publicWebBaseUrl
                                                : '${AppConstants.publicWebBaseUrl}/igreja/${Uri.encodeComponent(slug)}';
                                            final cadUrl = slug.isEmpty
                                                ? AppConstants.publicWebBaseUrl
                                                : AppConstants
                                                    .publicChurchMemberSignupUrl(
                                                        slug);
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                _LinkRow(
                                                  label:
                                                      'Site público (eventos e informações)',
                                                  url: homeUrl,
                                                  onOpen: () =>
                                                      openHttpsUrlInBrowser(
                                                          ctx, homeUrl),
                                                  onCopy: () => _copyAndSnack(
                                                      context, homeUrl),
                                                ),
                                                const SizedBox(height: 10),
                                                _LinkRow(
                                                  label:
                                                      'Cadastro de membros (público)',
                                                  url: cadUrl,
                                                  onOpen: () {
                                                    if (!PublicMemberSignupNavigation
                                                        .tryOpenInAppFromUrl(
                                                            ctx, cadUrl)) {
                                                      openHttpsUrlInBrowser(
                                                          ctx, cadUrl);
                                                    }
                                                  },
                                                  onCopy: () => _copyAndSnack(
                                                      context, cadUrl),
                                                ),
                                              ],
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                  ],
                                ],
                              ),
                            ),
                            if (_formHydrated) ...[
                            const SizedBox(height: ThemeCleanPremium.spaceMd),
                            _buildChurchSaveFooter(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  const _LinkRow({
    required this.label,
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

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
        const SizedBox(width: 4),
        IconButton.filled(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_browser_rounded, size: 20),
          tooltip: 'Abrir',
          style: IconButton.styleFrom(
            backgroundColor: ThemeCleanPremium.primary,
            foregroundColor: Colors.white,
          ),
        ),
        IconButton.filled(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 20),
          tooltip: 'Copiar link',
          style: IconButton.styleFrom(
            backgroundColor:
                ThemeCleanPremium.primary.withValues(alpha: 0.12),
            foregroundColor: ThemeCleanPremium.primary,
          ),
        ),
      ],
    );
  }
}
