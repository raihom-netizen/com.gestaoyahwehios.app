import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
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
import 'package:image_picker/image_picker.dart';

/// Tela interna do sistema para o gestor/adm cadastrar um novo membro.
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
  final _conjugeCtrl = TextEditingController();
  final _filiacaoPaiCtrl = TextEditingController();
  final _filiacaoMaeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _tenantName = 'Igreja';
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
  bool _loadingCitySuggestions = false;
  List<CitySuggestion> _citySuggestions = const [];
  int _citySearchToken = 0;

  static const List<String> _ufs = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
    'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];
  static const List<String> _escolaridadeOptions = [
    'Ensino Fundamental',
    'Ensino Médio',
    'Superior',
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
    _conjugeCtrl.dispose();
    _filiacaoPaiCtrl.dispose();
    _filiacaoMaeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _onlyDigits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

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

  Future<void> _pickPhoto({bool fromCamera = false}) async {
    final picked = await MediaHandlerService.instance.pickAndProcessImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() {
      _photoFile = picked;
      _photoBytes = bytes;
    });
  }

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

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
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

      final ref = cpfDigits.length == 11 ? col.doc(cpfDigits) : col.doc();
      final docPhotoId = cpfDigits.isNotEmpty ? cpfDigits : ref.id;
      String? photoStoragePathField;
      final photoUrl = _photoFile != null
          ? await _uploadPhoto(widget.tenantId, ref.id, _photoFile!)
          : _buildAutoAvatarUrl(docPhotoId);
      if (_photoFile != null) {
        photoStoragePathField = ChurchStorageLayout.memberCanonicalProfilePhotoPath(
            widget.tenantId, ref.id);
      }
      final age = _calcAge(_birthDate) ?? 0;
      final ageRange = _ageRange(age);
      final alias = _tenantAlias.isNotEmpty ? _tenantAlias : widget.tenantId;
      final slug = _tenantSlug.isNotEmpty ? _tenantSlug : widget.tenantId;

      final data = {
        'MEMBER_ID': ref.id,
        'CREATED_BY_CPF': cpfDigits.isNotEmpty ? cpfDigits : ref.id,
        'alias': alias,
        'slug': slug,
        'tenantId': widget.tenantId,
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
        final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
        await functions.httpsCallable('createMemberLoginFromPublic').call({
          'tenantId': widget.tenantId,
          'memberId': ref.id,
        });
        final senha = _passwordCtrl.text.trim();
        final senhaFinal = senha.length >= 6 ? senha : '123456';
        try {
          await functions.httpsCallable('setMemberPassword').call({
            'tenantId': widget.tenantId,
            'memberId': ref.id,
            'newPassword': senhaFinal,
          });
        } catch (_) {}
      } catch (_) {}

      if (!mounted) return;
      setState(() => _submittedSuccess = true);
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
      _conjugeCtrl.clear();
      _filiacaoPaiCtrl.clear();
      _filiacaoMaeCtrl.clear();
      _birthDate = null;
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
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.person_add_rounded, size: 48, color: ThemeCleanPremium.primary.withOpacity(0.8)),
                            const SizedBox(height: 12),
                            Text(
                              _tenantName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cadastro interno — o membro será salvo como ativo.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _Section(title: 'Dados pessoais'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                        border: OutlineInputBorder(),
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoMaeCtrl,
                      decoration: const InputDecoration(labelText: 'Filiação (mãe)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _filiacaoPaiCtrl,
                      decoration: const InputDecoration(labelText: 'Filiação (pai)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cpfCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'CPF', border: OutlineInputBorder()),
                            validator: (v) {
                              final msg = _req(v);
                              if (msg != null) return msg;
                              if (_onlyDigits(v!).length != 11) return 'CPF inválido';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Data nascimento',
                              border: const OutlineInputBorder(),
                              suffixIcon: const Icon(Icons.calendar_today_rounded),
                              hintText: _birthDate == null ? 'Selecione' : _formatDate(_birthDate!),
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime(DateTime.now().year - 100),
                                lastDate: DateTime.now(),
                                initialDate: _birthDate ?? DateTime(2000, 1, 1),
                              );
                              if (picked != null) setState(() => _birthDate = picked);
                            },
                            validator: (_) => _birthDate == null ? 'Campo obrigatório' : null,
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
                            decoration: const InputDecoration(labelText: 'Sexo', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Masculino', child: Text('Masculino')),
                              DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                              DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                            ],
                            onChanged: (v) => setState(() => _sexo = v ?? 'Masculino'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(labelText: 'Telefone', border: OutlineInputBorder()),
                            validator: _req,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha (opcional)',
                        hintText: 'Mín. 6 caracteres — para o membro acessar o app',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: 20),
                    _Section(title: 'Endereço'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _cepCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 9,
                      decoration: InputDecoration(
                        labelText: 'CEP',
                        border: const OutlineInputBorder(),
                        hintText: '00000-000',
                        counterText: '',
                        suffixIcon: _loadingCep
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                      decoration: const InputDecoration(
                        labelText: 'Logradouro (rua, avenida)',
                        border: OutlineInputBorder(),
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quadraLoteNumeroCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quadra, Lote e Número',
                        border: OutlineInputBorder(),
                        hintText: 'Qd 1, Lt 5, Nº 123',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bairroCtrl,
                      decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cityCtrl,
                            decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()),
                            onChanged: _searchCitySuggestions,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<String>(
                            value: _ufs.contains(_estadoCtrl.text.trim()) ? _estadoCtrl.text.trim() : null,
                            decoration: const InputDecoration(labelText: 'UF', border: OutlineInputBorder()),
                            isExpanded: true,
                            items: _ufs.map((uf) => DropdownMenuItem(value: uf, child: Text(uf))).toList(),
                            onChanged: (v) {
                              if (v != null) _estadoCtrl.text = v;
                              setState(() {});
                            },
                          ),
                        ),
                      ],
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
                    _Section(title: 'Família e escolaridade'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _estadoCivilCtrl,
                      decoration: const InputDecoration(labelText: 'Estado civil', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _escolaridadeOptions.contains(_escolaridadeCtrl.text.trim())
                          ? _escolaridadeCtrl.text.trim()
                          : null,
                      decoration: const InputDecoration(labelText: 'Escolaridade', border: OutlineInputBorder()),
                      hint: const Text('Opcional'),
                      items: _escolaridadeOptions
                          .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _escolaridadeCtrl.text = (v ?? '').trim()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _conjugeCtrl,
                      decoration: const InputDecoration(labelText: 'Nome cônjuge', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    _Section(title: 'Foto do membro'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _photoBytes == null ? null : MemoryImage(_photoBytes!),
                          child: _photoBytes == null ? Icon(Icons.person_rounded, size: 40, color: Colors.grey.shade500) : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickPhoto(fromCamera: false),
                                  icon: const Icon(Icons.photo_library_rounded, size: 20),
                                  label: const Text('Galeria'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _pickPhoto(fromCamera: true),
                                  icon: const Icon(Icons.camera_alt_rounded, size: 20),
                                  label: const Text('Câmera'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 22),
                        label: Text(_saving ? 'Salvando...' : 'Cadastrar membro'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
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
