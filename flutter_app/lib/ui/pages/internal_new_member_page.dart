import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctions, FirebaseFunctionsException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/services/cep_service.dart';
import 'package:gestao_yahweh/services/city_autocomplete_service.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/members_limit_service.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/member_signup_premium_ui.dart';
import 'package:image_picker/image_picker.dart';

/// Tela interna do sistema para o gestor/adm cadastrar um novo membro.
/// Fluxo: cria Firebase Auth (UID) → `membros/{uid}` — CPF só como campo, não como id do documento.
/// Salva direto como ativo (não usa o formulário público).
class InternalNewMemberPage extends StatefulWidget {
  final String tenantId;

  const InternalNewMemberPage({super.key, required this.tenantId});

  @override
  State<InternalNewMemberPage> createState() => _InternalNewMemberPageState();
}

class _InternalNewMemberPageState extends State<InternalNewMemberPage> {
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
  final _profissaoCtrl = TextEditingController();
  final _conjugeCtrl = TextEditingController();
  final _filiacaoPaiCtrl = TextEditingController();
  final _filiacaoMaeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _tenantName = 'Igreja';
  String _tenantAlias = '';
  String _tenantSlug = '';

  DateTime? _birthDate;
  final _birthDateCtrl = TextEditingController();
  String _sexo = 'Masculino';

  XFile? _photoFile;
  Uint8List? _photoBytes;
  bool _loading = true;
  bool _saving = false;
  bool _loadingCep = false;
  bool _submittedSuccess = false;
  bool _loadingCitySuggestions = false;
  List<CitySuggestion> _citySuggestions = const [];
  int _citySearchToken = 0;

  static const List<String> _ufs = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
    'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];
  @override
  void initState() {
    super.initState();
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
    _profissaoCtrl.dispose();
    _birthDateCtrl.dispose();
    _conjugeCtrl.dispose();
    _filiacaoPaiCtrl.dispose();
    _filiacaoMaeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _onlyDigits(String v) => memberSignupOnlyDigits(v);

  static String _buildFiliacaoLegado(String pai, String mae) {
    if (pai.isEmpty && mae.isEmpty) return '';
    if (pai.isEmpty) return mae;
    if (mae.isEmpty) return pai;
    return '$pai e $mae';
  }

  Future<void> _loadTenant() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final d = await FirebaseFirestore.instance.collection('igrejas').doc(tid).get();
      if (d.exists) {
        final data = d.data() ?? {};
        setState(() {
          _tenantName = (data['name'] ?? data['nome'] ?? 'Igreja').toString();
          _tenantAlias = (data['alias'] ?? data['slug'] ?? tid).toString().trim();
          _tenantSlug = (data['slug'] ?? data['alias'] ?? tid).toString().trim();
          if (_tenantAlias.isEmpty) _tenantAlias = tid;
          if (_tenantSlug.isEmpty) _tenantSlug = tid;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _buscarCep() async {
    if (_onlyDigits(_cepCtrl.text).length != 8) return;
    setState(() => _loadingCep = true);
    try {
      final result = await fetchCep(_cepCtrl.text.trim());
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CEP não encontrado. Preencha manualmente ou tente outro CEP.')),
        );
      } else {
        if (result.logradouro != null && result.logradouro!.isNotEmpty) _enderecoCtrl.text = result.logradouro!;
        if (result.bairro != null && result.bairro!.isNotEmpty) _bairroCtrl.text = result.bairro!;
        if (result.localidade != null && result.localidade!.isNotEmpty) _cityCtrl.text = result.localidade!;
        if (result.uf != null && result.uf!.isNotEmpty) _estadoCtrl.text = result.uf!;
        if (result.cep != null && result.cep!.isNotEmpty) _cepCtrl.text = result.cep!;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Endereço preenchido pelo CEP.')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao buscar CEP: $e')));
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

  Future<void> _pickBirthDate() async {
    final initial = _birthDate ??
        memberSignupParseBirthDateBr(_birthDateCtrl.text.trim()) ??
        DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime.now(),
      initialDate: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _birthDateCtrl.text = memberSignupFormatBirthDateBr(picked);
      });
    }
  }

  Future<void> _pickPhoto({bool fromCamera = false}) async {
    final picked = await MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      webCropContext: context,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() {
      _photoFile = picked;
      _photoBytes = bytes;
    });
  }

  /// Path canónico `foto_perfil.jpg` (sobrescreve). Novo membro: sem artefactos antigos.
  Future<String> _uploadPhoto(String tenantId, String memberDocId, XFile file) async {
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
    FirebaseStorageCleanupService.scheduleCleanupAfterMemberProfilePhotoUpload(
      tenantId: tenantId,
      memberId: mid,
    );
    return uploaded;
  }

  /// Avatar automático quando não há upload de foto.
  String _buildAutoAvatarUrl(String docId) {
    final name = _nameCtrl.text.trim().isEmpty ? 'Membro' : _nameCtrl.text.trim();
    final seed = _onlyDigits(_cpfCtrl.text).isNotEmpty ? _onlyDigits(_cpfCtrl.text) : docId;
    return 'https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent('$name-$seed')}&backgroundColor=e2e8f0,bae6fd,c7d2fe,d9f99d&fontWeight=700';
  }

  int? _calcAge(DateTime? birth) {
    if (birth == null) return null;
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
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
    if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final birthParsed = memberSignupParseBirthDateBr(_birthDateCtrl.text.trim());
    if (birthParsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Informe a data de nascimento (DD/MM/AAAA).')),
      );
      return;
    }
    final today = DateTime.now();
    if (birthParsed
        .isAfter(DateTime(today.year, today.month, today.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data de nascimento inválida.')),
      );
      return;
    }
    final limitService = MembersLimitService();
    final limitResult = await limitService.checkLimit(widget.tenantId);
    if (limitResult.isBlocked) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Limite do plano'),
          content: Text(limitResult.blockedDialogMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RenewPlanPage()));
              },
              child: const Text('Ver planos'),
            ),
          ],
        ),
      );
      return;
    }

    final cpfDigits = _onlyDigits(_cpfCtrl.text);
    final emailNorm = _emailCtrl.text.trim().toLowerCase();
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros');

    // Impedir cadastro duplo: mesmo CPF ou mesmo e-mail na mesma igreja
    if (cpfDigits.length == 11) {
      final byCpf = await col.where('CPF', isEqualTo: cpfDigits).limit(1).get();
      if (byCpf.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um cadastro com este CPF nesta igreja.')),
        );
        return;
      }
      final byCpfLower = await col.where('cpf', isEqualTo: cpfDigits).limit(1).get();
      if (byCpfLower.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um cadastro com este CPF nesta igreja.')),
        );
        return;
      }
    }
    if (emailNorm.isNotEmpty) {
      final byEmail = await col.where('EMAIL', isEqualTo: emailNorm).limit(1).get();
      if (byEmail.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um cadastro com este e-mail nesta igreja.')),
        );
        return;
      }
      final byEmailLower = await col.where('email', isEqualTo: emailNorm).limit(1).get();
      if (byEmailLower.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um cadastro com este e-mail nesta igreja.')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final emailForAuth = emailNorm.isNotEmpty
          ? emailNorm
          : (cpfDigits.length == 11
              ? '$cpfDigits@membro.gestaoyahweh.com.br'
              : '');
      if (emailForAuth.isEmpty) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Informe e-mail ou CPF com 11 dígitos para criar o login do membro.',
              ),
            ),
          );
        }
        return;
      }
      final pwd = _passwordCtrl.text.trim();
      final authRes =
          await functions.httpsCallable('createMemberAuthAccountForGestor').call({
        'tenantId': widget.tenantId,
        'email': emailForAuth,
        'password': pwd.length >= 6 ? pwd : '123456',
        'displayName': _nameCtrl.text.trim(),
        'cpf': cpfDigits,
      });
      final authMap = Map<String, dynamic>.from(authRes.data as Map? ?? {});
      final uid = (authMap['uid'] ?? '').toString().trim();
      if (uid.isEmpty) {
        throw Exception('UID do login não retornado pelo servidor.');
      }

      final ref = col.doc(uid);
      String? photoStoragePathField;
      final photoUrl = _photoFile != null
          ? await _uploadPhoto(widget.tenantId, ref.id, _photoFile!)
          : _buildAutoAvatarUrl(ref.id);
      if (_photoFile != null) {
        photoStoragePathField = ChurchStorageLayout.memberCanonicalProfilePhotoPath(
            widget.tenantId, ref.id);
      }
      final age = _calcAge(birthParsed) ?? 0;
      final ageRange = _ageRange(age);
      final alias = _tenantAlias.isNotEmpty ? _tenantAlias : widget.tenantId;
      final slug = _tenantSlug.isNotEmpty ? _tenantSlug : widget.tenantId;

      final data = {
        'MEMBER_ID': uid,
        'authUid': uid,
        'CREATED_BY_CPF': cpfDigits.isNotEmpty ? cpfDigits : uid,
        'alias': alias,
        'slug': slug,
        'tenantId': widget.tenantId,
        'NOME_COMPLETO': _nameCtrl.text.trim(),
        'EMAIL': _emailCtrl.text.trim(),
        'DATA_NASCIMENTO': Timestamp.fromDate(birthParsed),
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
        'PROFISSAO': _profissaoCtrl.text.trim(),
        'NOME_CONJUGE': _conjugeCtrl.text.trim(),
        'DEPARTAMENTOS': <String>[],
        'foto_url': photoUrl,
        'FOTO_URL_OU_ID': photoUrl,
        'fotoUrl': photoUrl,
        'photoURL': photoUrl,
        'avatarUrl': photoUrl,
        if (photoStoragePathField != null)
          'photoStoragePath': photoStoragePathField,
        'PUBLIC_SIGNUP': false,
        'STATUS': 'ativo',
        'status': 'ativo',
        'FUNCAO': 'membro',
        'CARGO': 'membro',
        'role': 'membro',
        'CRIADO_EM': FieldValue.serverTimestamp(),
        if (_photoFile != null)
          'fotoUrlCacheRevision': DateTime.now().millisecondsSinceEpoch,
        'FILIACAO_PAI': _filiacaoPaiCtrl.text.trim(),
        'FILIACAO_MAE': _filiacaoMaeCtrl.text.trim(),
        'FILIACAO': _buildFiliacaoLegado(_filiacaoPaiCtrl.text.trim(), _filiacaoMaeCtrl.text.trim()),
      };

      await ref.set(data);
      FirebaseStorageService.invalidateMemberPhotoCache(
        tenantId: widget.tenantId,
        memberId: ref.id,
      );
      AppStorageImageService.instance.invalidateStoragePrefix(
          'igrejas/${widget.tenantId}/membros/${ref.id}');

      try {
        await functions.httpsCallable('createMemberLoginFromPublic').call({
          'tenantId': widget.tenantId,
          'memberId': ref.id,
        });
      } catch (_) {}

      if (!mounted) return;
      setState(() => _submittedSuccess = true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao criar login: $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cadastrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _clearAndNew() {
    setState(() {
      _submittedSuccess = false;
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
      _profissaoCtrl.clear();
      _conjugeCtrl.clear();
      _filiacaoPaiCtrl.clear();
      _filiacaoMaeCtrl.clear();
      _birthDate = null;
      _birthDateCtrl.clear();
      _photoFile = null;
      _photoBytes = null;
      _passwordCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar',
          ),
          title: const Text('Novo membro'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_submittedSuccess) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar',
          ),
          title: const Text('Novo membro'),
        ),
        body: SafeArea(
          child: Padding(
            padding: ThemeCleanPremium.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 72, color: Colors.green.shade600),
                    const SizedBox(height: 24),
                    Text(
                      'Membro cadastrado',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green.shade800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'O membro foi cadastrado como ativo e já pode aparecer na lista.',
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.people_rounded, size: 20),
                          label: const Text('Voltar aos membros'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _clearAndNew,
                          icon: const Icon(Icons.person_add_rounded, size: 20),
                          label: const Text('Cadastrar outro'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
        ),
        title: const Text('Novo membro'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InternalMemberSignupHeroCard(churchName: _tenantName),
                    const SizedBox(height: 20),
                    MemberSignupSectionTitle(title: 'Dados pessoais'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Nome completo',
                        icon: Icons.person_rounded,
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoMaeCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Filiação (mãe)',
                        icon: Icons.family_restroom_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoPaiCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Filiação (pai)',
                        icon: Icons.family_restroom_rounded,
                      ),
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
                              LengthLimitingTextInputFormatter(14),
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) {
                                  final masked =
                                      memberSignupFormatCpfMask(newValue.text);
                                  return TextEditingValue(
                                    text: masked,
                                    selection: TextSelection.collapsed(
                                        offset: masked.length),
                                  );
                                },
                              ),
                            ],
                            decoration: memberSignupInputDecoration(
                              label: 'CPF',
                              icon: Icons.badge_rounded,
                            ),
                            validator: (v) {
                              final msg = _req(v);
                              if (msg != null) return msg;
                              if (_onlyDigits(v!).length != 11) {
                                return 'CPF inválido';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _birthDateCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              MemberSignupBirthDateInputFormatter(),
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: memberSignupInputDecoration(
                              label: 'Data de nascimento',
                              icon: Icons.cake_rounded,
                              hint: 'DD/MM/AAAA',
                              suffixIcon: IconButton(
                                icon: Icon(Icons.calendar_month_rounded,
                                    color: ThemeCleanPremium.primary),
                                tooltip: 'Calendário',
                                onPressed: _pickBirthDate,
                              ),
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return 'Campo obrigatório';
                              final p = memberSignupParseBirthDateBr(t);
                              if (p == null) return 'Use DD/MM/AAAA';
                              final now = DateTime.now();
                              if (p.isAfter(
                                  DateTime(now.year, now.month, now.day))) {
                                return 'Data inválida';
                              }
                              return null;
                            },
                            onChanged: (v) {
                              final p = memberSignupParseBirthDateBr(v);
                              if (p != null) {
                                setState(() => _birthDate = p);
                              }
                            },
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
                            decoration: memberSignupInputDecoration(
                              label: 'Sexo',
                              icon: Icons.wc_rounded,
                            ),
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
                              LengthLimitingTextInputFormatter(15),
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) {
                                  final masked = memberSignupFormatPhoneMask(
                                      newValue.text);
                                  return TextEditingValue(
                                    text: masked,
                                    selection: TextSelection.collapsed(
                                        offset: masked.length),
                                  );
                                },
                              ),
                            ],
                            decoration: memberSignupInputDecoration(
                              label: 'Telefone',
                              icon: Icons.phone_rounded,
                            ),
                            validator: _req,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: memberSignupInputDecoration(
                        label: 'E-mail',
                        icon: Icons.alternate_email_rounded,
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: MemberSignupPremiumUi.escolaridadeOptions
                              .contains(_escolaridadeCtrl.text.trim())
                          ? _escolaridadeCtrl.text.trim()
                          : null,
                      decoration: memberSignupInputDecoration(
                        label: 'Escolaridade',
                        icon: Icons.school_rounded,
                      ),
                      hint: const Text('Opcional'),
                      isExpanded: true,
                      items: MemberSignupPremiumUi.escolaridadeOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _escolaridadeCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _profissaoCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Profissão',
                        icon: Icons.work_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: memberSignupInputDecoration(
                        label: 'Senha (opcional)',
                        hint:
                            'Mín. 6 caracteres — para o membro acessar o app',
                        icon: Icons.lock_outline_rounded,
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 20),
                    MemberSignupSectionTitle(title: 'Endereço'),
                    const SizedBox(height: 10),
                    Text(
                      'Digite o CEP e saia do campo para preencher automaticamente.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _cepCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: memberSignupInputDecoration(
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
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
                      decoration: memberSignupInputDecoration(
                        label: 'Logradouro (rua, avenida)',
                        icon: Icons.home_rounded,
                        hint: 'Rua, avenida, alameda',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quadraLoteNumeroCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Quadra, Lote e Número',
                        icon: Icons.tag_rounded,
                        hint: 'Qd 1, Lt 5, Nº 123',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bairroCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Bairro',
                        icon: Icons.location_city_rounded,
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cityCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Cidade',
                        icon: Icons.apartment_rounded,
                      ),
                      onChanged: _searchCitySuggestions,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _ufs.contains(_estadoCtrl.text.trim())
                          ? _estadoCtrl.text.trim()
                          : null,
                      decoration: memberSignupInputDecoration(
                        label: 'Estado (UF)',
                        icon: Icons.map_rounded,
                      ),
                      isExpanded: true,
                      items: _ufs
                          .map((uf) =>
                              DropdownMenuItem(value: uf, child: Text(uf)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _estadoCtrl.text = v;
                        setState(() {});
                      },
                    ),
                    if (_loadingCitySuggestions || _citySuggestions.isNotEmpty) ...[
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
                                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 10),
                                    Text('Buscando cidades...'),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _citySuggestions.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = _citySuggestions[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.location_city_rounded, size: 20),
                                    title: Text(s.city),
                                    subtitle: Text(s.state),
                                    onTap: () => _applyCitySuggestion(s),
                                  );
                                },
                              ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    MemberSignupSectionTitle(title: 'Família'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: MemberSignupPremiumUi.estadoCivilOptions
                              .contains(_estadoCivilCtrl.text.trim())
                          ? _estadoCivilCtrl.text.trim()
                          : null,
                      decoration: memberSignupInputDecoration(
                        label: 'Estado civil',
                        icon: Icons.favorite_outline_rounded,
                      ),
                      hint: const Text('Opcional'),
                      isExpanded: true,
                      items: MemberSignupPremiumUi.estadoCivilOptions
                          .map((e) => DropdownMenuItem<String>(
                              value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(
                          () => _estadoCivilCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conjugeCtrl,
                      decoration: memberSignupInputDecoration(
                        label: 'Nome cônjuge',
                        icon: Icons.people_alt_rounded,
                      ),
                    ),
                    const SizedBox(height: 20),
                    MemberSignupSectionTitle(title: 'Foto do membro'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFFF1F5F9),
                          backgroundImage: _photoBytes == null
                              ? null
                              : MemoryImage(_photoBytes!),
                          child: _photoBytes == null
                              ? Icon(Icons.person_rounded,
                                  size: 40, color: Colors.grey.shade400)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickPhoto(fromCamera: false),
                                  icon: const Icon(Icons.photo_library_outlined,
                                      size: 20),
                                  label: const Text('Galeria'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusLg),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _pickPhoto(fromCamera: true),
                                  icon: const Icon(Icons.photo_camera_outlined,
                                      size: 20),
                                  label: const Text('Câmera'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          ThemeCleanPremium.radiusLg),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A foto será usada na carteirinha e no painel da igreja.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.verified_rounded, size: 22),
                        label: Text(
                          _saving ? 'Salvando...' : 'Cadastrar membro',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusLg),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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

