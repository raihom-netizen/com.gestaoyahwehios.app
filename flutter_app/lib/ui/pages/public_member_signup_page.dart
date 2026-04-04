import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/city_autocomplete_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/members_limit_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoUrl,
        FreshFirebaseStorageImage,
        isValidImageUrl,
        memCacheExtentForLogicalSize,
        sanitizeImageUrl;
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:skeletonizer/skeletonizer.dart';

class PublicMemberSignupPage extends StatefulWidget {
  /// Slug da igreja (para link público). Se null, use [tenantId].
  final String? slug;

  /// ID do tenant (para abrir a partir do painel quando a igreja não tem slug).
  final String? tenantId;
  const PublicMemberSignupPage({super.key, this.slug, this.tenantId})
      : assert(slug != null || tenantId != null, 'Informe slug ou tenantId');

  @override
  State<PublicMemberSignupPage> createState() => _PublicMemberSignupPageState();
}

class _PublicMemberSignupPageState extends State<PublicMemberSignupPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _quadraLoteNumeroCtrl = TextEditingController();
  final _estadoCtrl = TextEditingController();
  final _estadoCivilCtrl = TextEditingController();
  final _escolaridadeCtrl = TextEditingController();
  final _conjugeCtrl = TextEditingController();
  final _filiacaoPaiCtrl = TextEditingController();
  final _filiacaoMaeCtrl = TextEditingController();

  String? _tenantId;
  String _tenantName = 'Igreja';
  String? _tenantLogoUrl;
  /// Snapshot do doc `igrejas/{id}` para resolver logo via path/Storage (igual ao site público).
  Map<String, dynamic>? _tenantChurchData;
  String _tenantEndereco = '';

  /// Alias e slug da igreja para amarrar o membro ao tenant (segurança: outra igreja não vê esses membros).
  String _tenantAlias = '';
  String _tenantSlug = '';

  DateTime? _birthDate;
  String _sexo = 'Masculino';

  XFile? _photoFile;
  Uint8List? _photoBytes;
  bool _loading = true;
  bool _saving = false;
  bool _loadingCep = false;
  bool _submittedSuccess = false;
  bool _tenantBlocked = false;
  String _submittedMemberName = '';
  String? _lastSubmittedDocId;
  bool _editModeAfterSubmit = false;
  bool _loadingCitySuggestions = false;
  List<CitySuggestion> _citySuggestions = const [];
  int _citySearchToken = 0;

  /// Wizard: 0 dados pessoais, 1 endereço, 2 família/foto/envio.
  int _signupStep = 0;

  /// Altura da logo no topo do formulário (cadastro público).
  static const double _kPublicSignupLogoHeight = 80;

  InputDecoration _modernInput({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
    String? counterText,
  }) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      suffixIcon: suffixIcon,
      counterText: counterText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.6),
      ),
    );
  }

  /// UFs do Brasil para seleção manual (quando não sabe o CEP).
  static const List<String> _ufs = [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  ];
  static const List<String> _escolaridadeOptions = [
    'Ensino Fundamental',
    'Ensino Médio',
    'Superior',
  ];

  static const List<String> _estadoCivilOptions = [
    'casado (a)',
    'solteiro (a)',
    'viúvo (a)',
  ];

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      PublicSiteMediaAuth.ensureWebAnonymousForStorage();
    }
    _loadTenant();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cpfCtrl.dispose();
    _cepCtrl.dispose();
    _cityCtrl.dispose();
    _bairroCtrl.dispose();
    _enderecoCtrl.dispose();
    _quadraLoteNumeroCtrl.dispose();
    _estadoCtrl.dispose();
    _estadoCivilCtrl.dispose();
    _escolaridadeCtrl.dispose();
    _conjugeCtrl.dispose();
    _filiacaoPaiCtrl.dispose();
    _filiacaoMaeCtrl.dispose();
    super.dispose();
  }

  String _onlyDigits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  String _formatCpfMask(String raw) {
    final d = _onlyDigits(raw);
    final p1 = d.length > 3 ? d.substring(0, 3) : d;
    final p2 =
        d.length > 6 ? d.substring(3, 6) : (d.length > 3 ? d.substring(3) : '');
    final p3 =
        d.length > 9 ? d.substring(6, 9) : (d.length > 6 ? d.substring(6) : '');
    final p4 = d.length > 11
        ? d.substring(9, 11)
        : (d.length > 9 ? d.substring(9) : '');
    final b = StringBuffer()..write(p1);
    if (p2.isNotEmpty)
      b
        ..write('.')
        ..write(p2);
    if (p3.isNotEmpty)
      b
        ..write('.')
        ..write(p3);
    if (p4.isNotEmpty)
      b
        ..write('-')
        ..write(p4);
    return b.toString();
  }

  String _formatPhoneMask(String raw) {
    final d = _onlyDigits(raw);
    if (d.isEmpty) return '';
    final ddd = d.length >= 2 ? d.substring(0, 2) : d;
    final rest = d.length > 2 ? d.substring(2) : '';
    final b = StringBuffer()
      ..write('(')
      ..write(ddd);
    if (d.length >= 2) b.write(')');
    if (rest.isEmpty) return b.toString();
    if (rest.length <= 4) return '${b.toString()} $rest';
    if (rest.length <= 8) {
      return '${b.toString()} ${rest.substring(0, rest.length - 4)}-${rest.substring(rest.length - 4)}';
    }
    final prefix = rest.substring(0, 5);
    final suffix = rest.substring(5, rest.length > 9 ? 9 : rest.length);
    return '${b.toString()} $prefix-$suffix';
  }

  static String _buildFiliacaoLegado(String pai, String mae) {
    if (pai.isEmpty && mae.isEmpty) return '';
    if (pai.isEmpty) return mae;
    if (mae.isEmpty) return pai;
    return '$pai e $mae';
  }

  static String _buildEndereco({
    required String rua,
    required String bairro,
    required String cidade,
    required String estado,
    required String cep,
  }) {
    final parts = <String>[];
    if (rua.isNotEmpty) parts.add(rua);
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cep.isNotEmpty) parts.add('CEP $cep');
    return parts.join(', ');
  }

  /// Marca padrão quando não há logo ou falha 403/rede (padding adapta em telas baixas).
  Widget _fallbackGestaoYahwehLogo(double maxHeight) {
    final pad = maxHeight < 96 ? 6.0 : 14.0;
    final imgH = (maxHeight - pad * 2).clamp(24.0, maxHeight);
    return Center(
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Image.asset(
          'assets/LOGO_GESTAO_YAHWEH.png',
          height: imgH,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Mesmo pipeline do site público: `logoPath` + URL HTTPS renovada para visitante anônimo na web.
  Widget _publicSignupChurchLogo({
    required double maxHeight,
    double? width,
    BoxFit fit = BoxFit.contain,
  }) {
    final tid = _tenantId?.trim();
    final tenantMap = _tenantChurchData;
    final fallback = _fallbackGestaoYahwehLogo(maxHeight);
    if (tid == null || tid.isEmpty) return fallback;

    final preferRaw = _tenantLogoUrl?.trim();
    final prefer =
        (preferRaw != null && preferRaw.isNotEmpty) ? preferRaw : null;
    final sp = ChurchImageFields.logoStoragePath(tenantMap);

    Widget loadingBox() {
      if (width != null) {
        return SizedBox(
          width: width,
          height: maxHeight,
          child: ColoredBox(
            color: Colors.white,
            child: Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue.shade200,
                ),
              ),
            ),
          ),
        );
      }
      return SizedBox(
        height: maxHeight,
        width: double.infinity,
        child: ColoredBox(
          color: Colors.white,
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue.shade200,
              ),
            ),
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      key: ValueKey<String>(
          'pubmemlogo_${tid}_${prefer}_${sp}_${maxHeight}_${width}_$fit'),
      future: AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tid,
        tenantData: tenantMap,
        preferImageUrl: prefer,
        preferStoragePath: sp,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            snap.data == null &&
            !snap.hasError) {
          return loadingBox();
        }
        var clean = (!snap.hasError && snap.data != null)
            ? sanitizeImageUrl(snap.data!)
            : '';
        if (clean.isEmpty || !isValidImageUrl(clean)) {
          if (prefer != null) {
            final z = sanitizeImageUrl(prefer);
            if (isValidImageUrl(z)) clean = z;
          }
        }
        if (clean.isEmpty || !isValidImageUrl(clean)) return fallback;

        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cachePx =
            memCacheExtentForLogicalSize(maxHeight, dpr, maxPx: 512);

        return SizedBox(
          width: width ?? double.infinity,
          height: maxHeight,
          child: FreshFirebaseStorageImage(
            imageUrl: clean,
            fit: fit,
            width: width,
            height: maxHeight,
            memCacheWidth: cachePx,
            memCacheHeight: cachePx,
            placeholder: loadingBox(),
            errorWidget: fallback,
          ),
        );
      },
    );
  }

  /// Mesma resolução de URL do cadastro da igreja / site público ([logoProcessedUrl], [logoUrl], etc.).
  static String? _logoUrlFromChurchDoc(Map<String, dynamic> data) {
    final u = churchTenantLogoUrl(data);
    if (u.isEmpty) return null;
    final s = sanitizeImageUrl(u);
    return isValidImageUrl(s) ? s : null;
  }

  /// Busca CEP via ViaCEP e preenche endereço, bairro, cidade e estado automaticamente.
  Future<void> _buscarCep() async {
    final cep = _onlyDigits(_cepCtrl.text);
    if (cep.length != 8) return;
    setState(() => _loadingCep = true);
    try {
      final result = await fetchCep(_cepCtrl.text.trim());
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'CEP não encontrado. Preencha os campos manualmente ou tente outro CEP.')),
        );
        setState(() => _loadingCep = false);
        return;
      }
      if (result.logradouro != null && result.logradouro!.isNotEmpty)
        _enderecoCtrl.text = result.logradouro!;
      if (result.bairro != null && result.bairro!.isNotEmpty)
        _bairroCtrl.text = result.bairro!;
      if (result.localidade != null && result.localidade!.isNotEmpty)
        _cityCtrl.text = result.localidade!;
      if (result.uf != null && result.uf!.isNotEmpty)
        _estadoCtrl.text = result.uf!;
      if (result.cep != null && result.cep!.isNotEmpty)
        _cepCtrl.text = result.cep!;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Endereço preenchido automaticamente pelo CEP.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar CEP: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingCep = false);
    }
  }

  Future<void> _searchCitySuggestions(String raw) async {
    final query = raw.trim();
    final token = ++_citySearchToken;
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _loadingCitySuggestions = false;
        _citySuggestions = const [];
      });
      return;
    }
    setState(() => _loadingCitySuggestions = true);
    final list = await searchBrazilCities(query, limit: 8);
    if (!mounted || token != _citySearchToken) return;
    setState(() {
      _loadingCitySuggestions = false;
      _citySuggestions = list;
    });
  }

  void _applyCitySuggestion(CitySuggestion s) {
    _cityCtrl.text = s.city;
    _estadoCtrl.text = s.state;
    setState(() {
      _citySuggestions = const [];
      _loadingCitySuggestions = false;
    });
  }

  Future<void> _loadTenant() async {
    try {
      if (widget.tenantId != null && widget.tenantId!.isNotEmpty) {
        final d = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId!)
            .get();
        if (d.exists) {
          final data = d.data() ?? {};
          final endereco = (data['endereco'] ?? '').toString().trim();
          final rua = (data['rua'] ?? '').toString().trim();
          final bairro = (data['bairro'] ?? '').toString().trim();
          final cidade = (data['cidade'] ?? '').toString().trim();
          final estado = (data['estado'] ?? '').toString().trim();
          final cep = (data['cep'] ?? '').toString().trim();
          final enderecoCompleto = endereco.isNotEmpty
              ? endereco
              : _buildEndereco(
                  rua: rua,
                  bairro: bairro,
                  cidade: cidade,
                  estado: estado,
                  cep: cep);
          setState(() {
            _tenantId = d.id;
            _tenantChurchData = data;
            _tenantName = (data['name'] ?? data['nome'] ?? 'Igreja').toString();
            _tenantBlocked = SubscriptionGuard.evaluate(church: data).blocked;
            _tenantLogoUrl = _logoUrlFromChurchDoc(data);
            _tenantEndereco = enderecoCompleto;
            _tenantAlias =
                (data['alias'] ?? data['slug'] ?? d.id).toString().trim();
            _tenantSlug =
                (data['slug'] ?? data['alias'] ?? d.id).toString().trim();
            if (_tenantAlias.isEmpty) _tenantAlias = d.id;
            if (_tenantSlug.isEmpty) _tenantSlug = d.id;
            _loading = false;
          });
          return;
        }
      }
      if (widget.slug != null && widget.slug!.trim().isNotEmpty) {
        final slugTrim = widget.slug!.trim();
        // Primeiro tenta por 'slug'; se não achar, tenta por 'alias' (igreja correta)
        var q = await FirebaseFirestore.instance
            .collection('igrejas')
            .where('slug', isEqualTo: slugTrim)
            .limit(1)
            .get();
        if (q.docs.isEmpty) {
          q = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('alias', isEqualTo: slugTrim)
              .limit(1)
              .get();
        }
        if (q.docs.isNotEmpty) {
          final d = q.docs.first;
          final data = d.data();
          final endereco = (data['endereco'] ?? '').toString().trim();
          final rua = (data['rua'] ?? '').toString().trim();
          final bairro = (data['bairro'] ?? '').toString().trim();
          final cidade = (data['cidade'] ?? '').toString().trim();
          final estado = (data['estado'] ?? '').toString().trim();
          final cep = (data['cep'] ?? '').toString().trim();
          final enderecoCompleto = endereco.isNotEmpty
              ? endereco
              : _buildEndereco(
                  rua: rua,
                  bairro: bairro,
                  cidade: cidade,
                  estado: estado,
                  cep: cep);
          setState(() {
            _tenantId = d.id;
            _tenantChurchData = data;
            _tenantName = (data['name'] ?? data['nome'] ?? 'Igreja').toString();
            _tenantBlocked = SubscriptionGuard.evaluate(church: data).blocked;
            _tenantLogoUrl = _logoUrlFromChurchDoc(data);
            _tenantEndereco = enderecoCompleto;
            _tenantAlias =
                (data['alias'] ?? data['slug'] ?? d.id).toString().trim();
            _tenantSlug =
                (data['slug'] ?? data['alias'] ?? d.id).toString().trim();
            if (_tenantAlias.isEmpty) _tenantAlias = d.id;
            if (_tenantSlug.isEmpty) _tenantSlug = d.id;
            _loading = false;
          });
          return;
        }
      }
      setState(() => _loading = false);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  int? _calcAge(DateTime? birth) {
    if (birth == null) return null;
    final now = DateTime.now();
    int age = now.year - birth.year;
    final hasHadBirthday = (now.month > birth.month) ||
        (now.month == birth.month && now.day >= birth.day);
    if (!hasHadBirthday) age -= 1;
    return age;
  }

  String _ageRange(int? age) {
    if (age == null) return '';
    if (age <= 12) return '0-12';
    if (age <= 17) return '13-17';
    if (age <= 25) return '18-25';
    if (age <= 35) return '26-35';
    if (age <= 50) return '36-50';
    return '51+';
  }

  String? _req(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo obrigatorio';
    return null;
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _statusTrackPath(String protocol) {
    final slug = _tenantSlug.trim().isNotEmpty
        ? _tenantSlug.trim()
        : (_tenantId ?? 'igreja');
    return '/igreja/$slug/acompanhar-cadastro?protocolo=$protocol';
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 150,
                  child: Lottie.network(
                    'https://assets3.lottiefiles.com/packages/lf20_at6mub9m.json',
                    repeat: true,
                  ),
                ),
                const SizedBox(height: 10),
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: ClipOval(
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _publicSignupChurchLogo(
                        maxHeight: 72,
                        width: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Bem-vindo à família!',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Bem-vindo à $_tenantName!',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '${_submittedMemberName.trim().isEmpty ? 'Seu cadastro' : '${_submittedMemberName.trim()}, seu cadastro'} foi enviado para aprovação da liderança.',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey.shade600, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                if ((_lastSubmittedDocId ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Acompanhamento do cadastro',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Protocolo: ${_lastSubmittedDocId!}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () {
                                final protocol = _lastSubmittedDocId!;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PublicSignupStatusPage(
                                      slug: _tenantSlug.isNotEmpty
                                          ? _tenantSlug
                                          : (_tenantId ?? ''),
                                      protocolo: protocol,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.visibility_rounded,
                                  size: 18),
                              label: const Text('Acompanhar agora'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final protocol = _lastSubmittedDocId!;
                                final path = _statusTrackPath(protocol);
                                await Clipboard.setData(
                                    ClipboardData(text: path));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Link de acompanhamento copiado.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('Copiar link'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _submittedSuccess = false;
                          _lastSubmittedDocId = null;
                          _editModeAfterSubmit = false;
                          _nameCtrl.clear();
                          _emailCtrl.clear();
                          _phoneCtrl.clear();
                          _cpfCtrl.clear();
                          _cepCtrl.clear();
                          _cityCtrl.clear();
                          _bairroCtrl.clear();
                          _enderecoCtrl.clear();
                          _quadraLoteNumeroCtrl.clear();
                          _estadoCtrl.clear();
                          _estadoCivilCtrl.clear();
                          _escolaridadeCtrl.clear();
                          _conjugeCtrl.clear();
                          _filiacaoPaiCtrl.clear();
                          _filiacaoMaeCtrl.clear();
                          _birthDate = null;
                          _photoFile = null;
                          _photoBytes = null;
                        });
                      },
                      icon: const Icon(Icons.person_add_rounded, size: 20),
                      label: const Text('Voltar ao início'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (kIsWeb) {
                          VersionService.reloadWeb();
                        } else {
                          Navigator.maybePop(context);
                        }
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Recarregar'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, '/igreja/login', (_) => false),
                      icon: const Icon(Icons.login_rounded, size: 20),
                      label: const Text('Ir para login da igreja'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto({bool fromCamera = false}) async {
    final picked = await MediaHandlerService.instance.pickAndProcessImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted)
      setState(() {
        _photoFile = picked;
        _photoBytes = bytes;
      });
  }

  /// `igrejas/{tenant}/membros/{memberDocId}/foto_perfil.jpg` — id do documento Firestore.
  Future<String> _uploadPhoto(
      String tenantId, String memberDocId, XFile file) async {
    final raw = await file.readAsBytes();
    final bytes = await ImageHelper.compressMemberProfileForUpload(raw);
    final mid = memberDocId.trim().isEmpty
        ? 'membro_${DateTime.now().millisecondsSinceEpoch}'
        : memberDocId.trim();
    final full = ChurchStorageLayout.memberCanonicalProfilePhotoPath(tenantId, mid);
    final slash = full.lastIndexOf('/');
    final folder = full.substring(0, slash);
    final fileName = full.substring(slash + 1);
    final uploaded = await FirebaseStorageService.instance.uploadBytes(
      folder,
      bytes,
      fileName: fileName,
      contentType: file.mimeType ?? 'image/jpeg',
    );
    if (uploaded == null || uploaded.isEmpty) {
      throw Exception('Falha ao enviar foto para o Storage.');
    }
    unawaited(
      FirebaseStorageCleanupService.deleteGeneratedMemberProfileThumbnails(
        tenantId: tenantId,
        memberId: mid,
      ),
    );
    return uploaded;
  }

  /// Avatar automático quando o membro não envia foto.
  String _buildAutoAvatarUrl(String memberDocId) {
    final name =
        _nameCtrl.text.trim().isEmpty ? 'Membro' : _nameCtrl.text.trim();
    final seed = _onlyDigits(_cpfCtrl.text).isNotEmpty
        ? _onlyDigits(_cpfCtrl.text)
        : memberDocId;
    return 'https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent('$name-$seed')}&backgroundColor=e2e8f0,bae6fd,c7d2fe,d9f99d&fontWeight=700';
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data de nascimento.')),
      );
      return;
    }
    if (_tenantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Igreja nao encontrada.')),
      );
      return;
    }
    if (_tenantBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O cadastro público desta igreja está temporariamente indisponível por assinatura suspensa.',
          ),
        ),
      );
      return;
    }

    if (_tenantId == null) return;
    // Verifica limite apenas se autenticado (checkLimit exige leitura em members que precisa auth)
    final isAnonymous = FirebaseAuth.instance.currentUser == null;
    if (!isAnonymous) {
      final limitService = MembersLimitService();
      final limitResult = await limitService.checkLimit(_tenantId!);
      if (limitResult.isBlocked) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Limite do plano'),
            content: Text(limitResult.blockedDialogMessage),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendi')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RenewPlanPage()));
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (_tenantId == null || _tenantId!.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Igreja não identificada. Recarregue a página ou use o link correto da igreja.')),
        );
      return;
    }
    if (_tenantBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Cadastro temporariamente indisponível para esta igreja.'),
          ),
        );
      }
      return;
    }
    final cpfDigits = _onlyDigits(_cpfCtrl.text);
    final emailNorm = _emailCtrl.text.trim().toLowerCase();
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(_tenantId!)
        .collection('membros');
    final editingDocId = _editModeAfterSubmit ? _lastSubmittedDocId : null;

    // Impedir cadastro duplo: mesmo CPF ou mesmo e-mail na mesma igreja (ao criar; ao editar, ignora o próprio doc)
    if (cpfDigits.length == 11) {
      final byCpf = await col.where('CPF', isEqualTo: cpfDigits).limit(2).get();
      final byCpfLower =
          await col.where('cpf', isEqualTo: cpfDigits).limit(2).get();
      final conflictCpf =
          byCpf.docs.where((d) => d.id != editingDocId).isNotEmpty ||
              byCpfLower.docs.where((d) => d.id != editingDocId).isNotEmpty;
      if (conflictCpf) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Já existe um cadastro com este CPF nesta igreja.')),
        );
        return;
      }
    }
    if (emailNorm.isNotEmpty) {
      final byEmail =
          await col.where('EMAIL', isEqualTo: emailNorm).limit(2).get();
      final byEmailLower =
          await col.where('email', isEqualTo: emailNorm).limit(2).get();
      final conflictEmail =
          byEmail.docs.where((d) => d.id != editingDocId).isNotEmpty ||
              byEmailLower.docs.where((d) => d.id != editingDocId).isNotEmpty;
      if (conflictEmail) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Já existe um cadastro com este e-mail nesta igreja.')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final ref = editingDocId != null
          ? col.doc(editingDocId)
          : (cpfDigits.length == 11 ? col.doc(cpfDigits) : col.doc());
      final docPhotoId = cpfDigits.isNotEmpty ? cpfDigits : ref.id;
      String? photoStoragePathField;
      final photoUrl = _photoFile != null
          ? await _uploadPhoto(_tenantId!, ref.id, _photoFile!)
          : _buildAutoAvatarUrl(docPhotoId);
      if (_photoFile != null) {
        photoStoragePathField = ChurchStorageLayout.memberCanonicalProfilePhotoPath(
            _tenantId!, ref.id);
      }
      final age = _calcAge(_birthDate) ?? 0;
      final ageRange = _ageRange(age);

      final alias = _tenantAlias.isNotEmpty ? _tenantAlias : _tenantId;
      final slug = _tenantSlug.isNotEmpty ? _tenantSlug : _tenantId;
      // Grava na igreja correta (igrejas/{tenantId}/membros); status pendente até o gestor aprovar; login já criado abaixo.
      final data = {
        'MEMBER_ID': ref.id,
        'CREATED_BY_CPF': cpfDigits.isNotEmpty ? cpfDigits : ref.id,
        'alias': alias,
        'slug': slug,
        'tenantId': _tenantId,
        'NOME_COMPLETO': _nameCtrl.text.trim(),
        'EMAIL': _emailCtrl.text.trim(),
        'DATA_NASCIMENTO': Timestamp.fromDate(_birthDate!),
        'TELEFONES': _phoneCtrl.text.trim(),
        'SEXO': _sexo,
        'FAIXA_ETARIA': ageRange,
        'IDADE': age,
        'ENDERECO': _enderecoCtrl.text.trim(),
        'QUADRA_LOTE_NUMERO': _quadraLoteNumeroCtrl.text.trim(),
        'CEP': _cepCtrl.text.trim(),
        'CIDADE': _cityCtrl.text.trim(),
        'BAIRRO': _bairroCtrl.text.trim(),
        'ESTADO': _estadoCtrl.text.trim(),
        'CPF': cpfDigits,
        'ESTADO_CIVIL': _estadoCivilCtrl.text.trim(),
        'ESCOLARIDADE': _escolaridadeCtrl.text.trim(),
        'NOME_CONJUGE': _conjugeCtrl.text.trim(),
        'DEPARTAMENTOS': <String>[],
        'foto_url': photoUrl,
        'FOTO_URL_OU_ID': photoUrl,
        'fotoUrl': photoUrl,
        'photoURL': photoUrl,
        'avatarUrl': photoUrl,
        if (photoStoragePathField != null)
          'photoStoragePath': photoStoragePathField,
        'PUBLIC_SIGNUP': true,
        'STATUS': 'pendente',
        'status': 'pendente',
        'role': 'membro',
        'CARGO': 'Membro',
        'FUNCAO': 'Membro',
        'FUNCOES': <String>['membro'],
        'CRIADO_EM': FieldValue.serverTimestamp(),
        if (_photoFile != null)
          'fotoUrlCacheRevision': DateTime.now().millisecondsSinceEpoch,
        'FILIACAO_PAI': _filiacaoPaiCtrl.text.trim(),
        'FILIACAO_MAE': _filiacaoMaeCtrl.text.trim(),
        'FILIACAO': _buildFiliacaoLegado(
            _filiacaoPaiCtrl.text.trim(), _filiacaoMaeCtrl.text.trim()),
      };
      if (_editModeAfterSubmit) {
        final updateData = Map<String, dynamic>.from(data);
        updateData.remove('CRIADO_EM');
        await ref.update(updateData);
      } else {
        await ref.set(data);
      }

      // Cria login do sistema (e-mail + senha 123456) para acessar o painel após aprovação do gestor
      try {
        final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
        await functions.httpsCallable('createMemberLoginFromPublic').call({
          'tenantId': _tenantId,
          'memberId': ref.id,
        });
        try {
          await functions.httpsCallable('setMemberPassword').call({
            'tenantId': _tenantId,
            'memberId': ref.id,
            'newPassword': '123456',
          });
        } catch (_) {}
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Cadastro salvo na igreja, mas o login pode não ter sido criado. Avise o gestor: $e')),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _submittedSuccess = true;
        _submittedMemberName = _nameCtrl.text.trim();
        _lastSubmittedDocId = ref.id;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('permission-denied') &&
              FirebaseAuth.instance.currentUser == null
          ? 'Não foi possível gravar. Verifique os dados e tente novamente, ou entre em contato com a igreja.'
          : 'Erro ao cadastrar: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snackWizard(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  bool _validateWizardStep0() {
    if (_nameCtrl.text.trim().isEmpty) {
      _snackWizard('Preencha o nome completo.');
      return false;
    }
    if (_onlyDigits(_cpfCtrl.text).length != 11) {
      _snackWizard('CPF deve ter 11 dígitos.');
      return false;
    }
    if (_birthDate == null) {
      _snackWizard('Selecione a data de nascimento.');
      return false;
    }
    final p = _req(_phoneCtrl.text);
    if (p != null) {
      _snackWizard(p);
      return false;
    }
    final e = _req(_emailCtrl.text);
    if (e != null) {
      _snackWizard(e);
      return false;
    }
    return true;
  }

  bool _validateWizardStep1() {
    final r1 = _req(_enderecoCtrl.text);
    if (r1 != null) {
      _snackWizard(r1);
      return false;
    }
    final r2 = _req(_bairroCtrl.text);
    if (r2 != null) {
      _snackWizard(r2);
      return false;
    }
    if (_cityCtrl.text.trim().isEmpty) {
      _snackWizard('Informe a cidade.');
      return false;
    }
    if (_estadoCtrl.text.trim().isEmpty) {
      _snackWizard('Selecione o estado (UF).');
      return false;
    }
    return true;
  }

  void _onWizardNext() {
    if (_signupStep == 0) {
      if (!_validateWizardStep0()) return;
    } else if (_signupStep == 1) {
      if (!_validateWizardStep1()) return;
    }
    setState(() => _signupStep = (_signupStep + 1).clamp(0, 2));
  }

  Widget _signupWizardHeader() {
    const labels = ['Seus dados', 'Endereço', 'Família e foto'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Passo ${_signupStep + 1} de 3',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(3, (i) {
            final active = i == _signupStep;
            final done = i < _signupStep;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 4,
                      decoration: BoxDecoration(
                        color: done || active
                            ? const Color(0xFF2563EB)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? const Color(0xFF1D4ED8)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFFDBEAFE), Colors.white],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Skeletonizer(
                enabled: true,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                          height: 14,
                          width: 220,
                          color: const Color(0xFFE2E8F0)),
                      const SizedBox(height: 14),
                      Container(
                          height: 52,
                          width: double.infinity,
                          color: const Color(0xFFE2E8F0)),
                      const SizedBox(height: 10),
                      Container(
                          height: 52,
                          width: double.infinity,
                          color: const Color(0xFFE2E8F0)),
                      const SizedBox(height: 10),
                      Container(
                          height: 52,
                          width: double.infinity,
                          color: const Color(0xFFE2E8F0)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_tenantId == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.maybePop(context),
              tooltip: 'Voltar'),
          title: const Text('Cadastro de membro'),
        ),
        body: const Center(child: Text('Igreja nao encontrada.')),
      );
    }

    if (_submittedSuccess) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar'),
        title: Text(
          'Cadastro de membro — $_tenantName',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFDBEAFE),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Topo: dados da igreja — logo, nome e localização
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      margin: const EdgeInsets.only(bottom: 20),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                width: double.infinity,
                                constraints: const BoxConstraints(
                                    maxHeight: _kPublicSignupLogoHeight + 24),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.06),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: _publicSignupChurchLogo(
                                  maxHeight: _kPublicSignupLogoHeight,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _tenantName,
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1a1a2e),
                                height: 1.25,
                              ),
                            ),
                            if (_tenantEndereco.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 18, color: Colors.grey.shade600),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _tenantEndereco,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _signupWizardHeader(),
                    const SizedBox(height: 18),
                    if (_signupStep == 0) ...[
                    const Text(
                      'Preencha todos os dados para entrar no cadastro da igreja.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    _Section(title: 'Dados pessoais'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: _modernInput(
                          label: 'Nome completo', icon: Icons.person_rounded),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoMaeCtrl,
                      decoration: _modernInput(
                          label: 'Filiação (mãe)',
                          icon: Icons.family_restroom_rounded),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoPaiCtrl,
                      decoration: _modernInput(
                          label: 'Filiação (pai)',
                          icon: Icons.family_restroom_rounded),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cpfCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                              TextInputFormatter.withFunction(
                                  (oldValue, newValue) {
                                final masked = _formatCpfMask(newValue.text);
                                return TextEditingValue(
                                  text: masked,
                                  selection: TextSelection.collapsed(
                                      offset: masked.length),
                                );
                              }),
                            ],
                            decoration: _modernInput(
                                label: 'CPF', icon: Icons.badge_rounded),
                            validator: (v) {
                              final msg = _req(v);
                              if (msg != null) return msg;
                              final digits = _onlyDigits(v!);
                              if (digits.length != 11) return 'CPF invalido';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: _modernInput(
                              label: 'Data nascimento',
                              icon: Icons.event_rounded,
                              hint: _birthDate == null
                                  ? 'Selecione'
                                  : _formatDate(_birthDate!),
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(DateTime.now().year - 100),
                                lastDate: DateTime(DateTime.now().year),
                                initialDate: _birthDate ?? DateTime(2000, 1, 1),
                              );
                              if (picked != null) {
                                setState(() => _birthDate = picked);
                              }
                            },
                            validator: (_) =>
                                _birthDate == null ? 'Campo obrigatorio' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sexo,
                            decoration: _modernInput(
                                label: 'Sexo', icon: Icons.wc_rounded),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Masculino', child: Text('Masculino')),
                              DropdownMenuItem(
                                  value: 'Feminino', child: Text('Feminino')),
                              DropdownMenuItem(
                                  value: 'Outro', child: Text('Outro')),
                            ],
                            onChanged: (v) =>
                                setState(() => _sexo = v ?? 'Masculino'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                              TextInputFormatter.withFunction(
                                  (oldValue, newValue) {
                                final masked = _formatPhoneMask(newValue.text);
                                return TextEditingValue(
                                  text: masked,
                                  selection: TextSelection.collapsed(
                                      offset: masked.length),
                                );
                              }),
                            ],
                            decoration: _modernInput(
                                label: 'Telefone', icon: Icons.phone_rounded),
                            validator: _req,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _modernInput(
                          label: 'Email', icon: Icons.alternate_email_rounded),
                      validator: _req,
                    ),
                    ],
                    if (_signupStep == 1) ...[
                    _Section(title: 'Endereço'),
                    const SizedBox(height: 10),
                    Text(
                      'Digite o CEP e saia do campo para preencher os dados automaticamente.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cepCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: _modernInput(
                        label: 'CEP',
                        icon: Icons.pin_drop_rounded,
                        hint: '00000-000',
                        counterText: '',
                        suffixIcon: _loadingCep
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (v) {
                        if (_onlyDigits(v).length == 8) _buscarCep();
                      },
                      onEditingComplete: _buscarCep,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _enderecoCtrl,
                      decoration: _modernInput(
                        label: 'Logradouro (rua, avenida)',
                        icon: Icons.home_rounded,
                        hint: 'Rua, avenida, alameda',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quadraLoteNumeroCtrl,
                      decoration: _modernInput(
                        label: 'Quadra, Lote e Número',
                        icon: Icons.tag_rounded,
                        hint: 'Qd 1, Lt 5, Nº 123',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bairroCtrl,
                      decoration: _modernInput(
                          label: 'Bairro', icon: Icons.location_city_rounded),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cityCtrl,
                            decoration: _modernInput(
                                label: 'Cidade', icon: Icons.apartment_rounded),
                            onChanged: _searchCitySuggestions,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<String>(
                            value: _ufs.contains(_estadoCtrl.text.trim())
                                ? _estadoCtrl.text.trim()
                                : null,
                            decoration: _modernInput(
                                label: 'Estado', icon: Icons.map_rounded),
                            isExpanded: true,
                            items: _ufs
                                .map((uf) => DropdownMenuItem(
                                    value: uf, child: Text(uf)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) _estadoCtrl.text = v;
                              setState(() {});
                            },
                            onSaved: (v) {
                              if (v != null) _estadoCtrl.text = v;
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_loadingCitySuggestions ||
                        _citySuggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: _loadingCitySuggestions
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                    SizedBox(width: 10),
                                    Text('Buscando cidades...'),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _citySuggestions.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = _citySuggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(
                                        Icons.location_city_rounded,
                                        size: 20),
                                    title: Text(s.city),
                                    subtitle: Text(s.state),
                                    onTap: () => _applyCitySuggestion(s),
                                  );
                                },
                              ),
                      ),
                    ],
                    ],
                    if (_signupStep == 2) ...[
                    const SizedBox(height: 16),
                    _Section(title: 'Familia e escolaridade'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _estadoCivilOptions
                              .contains(_estadoCivilCtrl.text.trim())
                          ? _estadoCivilCtrl.text.trim()
                          : null,
                      decoration: _modernInput(
                          label: 'Estado civil',
                          icon: Icons.favorite_outline_rounded),
                      hint: const Text('Opcional'),
                      items: _estadoCivilOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _estadoCivilCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _escolaridadeOptions
                              .contains(_escolaridadeCtrl.text.trim())
                          ? _escolaridadeCtrl.text.trim()
                          : null,
                      decoration: _modernInput(
                          label: 'Escolaridade', icon: Icons.school_rounded),
                      hint: const Text('Opcional'),
                      items: _escolaridadeOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _escolaridadeCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conjugeCtrl,
                      decoration: _modernInput(
                          label: 'Nome conjuge',
                          icon: Icons.people_alt_rounded),
                    ),
                    const SizedBox(height: 16),
                    _Section(title: 'Foto do membro'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: _photoBytes == null
                              ? null
                              : MemoryImage(_photoBytes!),
                          child: _photoBytes == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickPhoto(fromCamera: false),
                                  icon: const Icon(Icons.photo_library),
                                  label: const Text('Galeria'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickPhoto(fromCamera: true),
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Selfie'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A foto será usada para emissão do cartão de membro e no painel da igreja.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _signupStep = 1),
                          child: const Text('Voltar'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_circle),
                              label: Text(
                                _saving
                                    ? 'Enviando...'
                                    : 'Finalizar cadastro',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ],
                    if (_signupStep < 2) ...[
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_signupStep > 0)
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _signupStep--),
                              child: const Text('Voltar'),
                            ),
                          if (_signupStep > 0) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _onWizardNext,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _signupStep == 0
                                    ? 'Continuar para endereço'
                                    : 'Continuar para família e foto',
                                textAlign: TextAlign.center,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
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

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    );
  }
}

class PublicSignupStatusPage extends StatelessWidget {
  final String slug;
  final String protocolo;
  const PublicSignupStatusPage({
    super.key,
    required this.slug,
    required this.protocolo,
  });

  Future<({String churchName, Map<String, dynamic>? memberData, String? error})>
      _loadStatus() async {
    final db = FirebaseFirestore.instance;
    final slugTrim = slug.trim();
    if (slugTrim.isEmpty || protocolo.trim().isEmpty) {
      return (churchName: 'Igreja', memberData: null, error: 'Link inválido.');
    }

    QuerySnapshot<Map<String, dynamic>> q = await db
        .collection('igrejas')
        .where('slug', isEqualTo: slugTrim)
        .limit(1)
        .get();
    if (q.docs.isEmpty) {
      q = await db
          .collection('igrejas')
          .where('alias', isEqualTo: slugTrim)
          .limit(1)
          .get();
    }
    if (q.docs.isEmpty) {
      return (
        churchName: 'Igreja',
        memberData: null,
        error: 'Igreja não encontrada para este link.'
      );
    }
    final churchDoc = q.docs.first;
    final churchName =
        (churchDoc.data()['name'] ?? churchDoc.data()['nome'] ?? 'Igreja')
            .toString();

    final memberDoc = await db
        .collection('igrejas')
        .doc(churchDoc.id)
        .collection('membros')
        .doc(protocolo.trim())
        .get();
    if (!memberDoc.exists) {
      return (
        churchName: churchName,
        memberData: null,
        error: 'Cadastro não localizado para o protocolo informado.'
      );
    }
    return (churchName: churchName, memberData: memberDoc.data(), error: null);
  }

  static ({String label, Color color}) _statusUi(String raw) {
    final s = raw.toLowerCase().trim();
    if (s == 'ativo' || s == 'aprovado') {
      return (label: 'Aprovado', color: const Color(0xFF16A34A));
    }
    if (s == 'reprovado' || s == 'negado') {
      return (label: 'Não aprovado', color: const Color(0xFFDC2626));
    }
    return (label: 'Em análise', color: const Color(0xFFD97706));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Acompanhar cadastro'),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<
          ({
            String churchName,
            Map<String, dynamic>? memberData,
            String? error
          })>(
        future: _loadStatus(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          if (data.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  data.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            );
          }
          final member = data.memberData!;
          final nome = (member['NOME_COMPLETO'] ?? member['nome'] ?? 'Membro')
              .toString();
          final statusRaw =
              (member['status'] ?? member['STATUS'] ?? 'pendente').toString();
          final status = _statusUi(statusRaw);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        data.churchName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nome,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: status.color.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          'Status: ${status.label}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: status.color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Protocolo: $protocolo',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
