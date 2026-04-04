import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/members_limit_service.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';

/// Exibida quando o membro entra no app com mustCompleteRegistration = true.
/// Permite completar/alterar dados do cadastro e opcionalmente trocar a senha provisória.
class CompletarCadastroMembroPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final VoidCallback onComplete;
  /// Ex.: "Meu cadastro" quando o membro abre por Configurações (fora do fluxo obrigatório).
  final String? appBarTitle;

  const CompletarCadastroMembroPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.onComplete,
    this.appBarTitle,
  });

  @override
  State<CompletarCadastroMembroPage> createState() => _CompletarCadastroMembroPageState();
}

class _CompletarCadastroMembroPageState extends State<CompletarCadastroMembroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _estadoCivilCtrl = TextEditingController();
  final _escolaridadeCtrl = TextEditingController();
  final _conjugeCtrl = TextEditingController();
  final _filiacaoPaiCtrl = TextEditingController();
  final _filiacaoMaeCtrl = TextEditingController();
  final _senhaAtualCtrl = TextEditingController();
  final _senhaNovaCtrl = TextEditingController();
  final _senhaConfirmCtrl = TextEditingController();

  DateTime? _birthDate;
  String _sexo = 'Masculino';
  bool _loading = true;
  bool _saving = false;
  bool _changePassword = false;

  @override
  void initState() {
    super.initState();
    _loadMember();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cepCtrl.dispose();
    _cityCtrl.dispose();
    _bairroCtrl.dispose();
    _enderecoCtrl.dispose();
    _estadoCivilCtrl.dispose();
    _escolaridadeCtrl.dispose();
    _conjugeCtrl.dispose();
    _filiacaoPaiCtrl.dispose();
    _filiacaoMaeCtrl.dispose();
    _senhaAtualCtrl.dispose();
    _senhaNovaCtrl.dispose();
    _senhaConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMember() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros')
          .doc(widget.cpf)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final d = doc.data() ?? {};
        _nameCtrl.text = (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString();
        _emailCtrl.text = (d['EMAIL'] ?? d['email'] ?? '').toString();
        _phoneCtrl.text = (d['TELEFONES'] ?? d['telefones'] ?? '').toString();
        _cepCtrl.text = (d['CEP'] ?? d['cep'] ?? '').toString();
        _cityCtrl.text = (d['CIDADE'] ?? d['cidade'] ?? '').toString();
        _bairroCtrl.text = (d['BAIRRO'] ?? d['bairro'] ?? '').toString();
        _enderecoCtrl.text = (d['ENDERECO'] ?? d['endereco'] ?? '').toString();
        _estadoCivilCtrl.text = (d['ESTADO_CIVIL'] ?? d['estado_civil'] ?? '').toString();
        _escolaridadeCtrl.text = (d['ESCOLARIDADE'] ?? d['escolaridade'] ?? '').toString();
        _conjugeCtrl.text = (d['NOME_CONJUGE'] ?? d['nome_conjuge'] ?? '').toString();
        final pai = (d['FILIACAO_PAI'] ?? d['filiacaoPai'] ?? '').toString().trim();
        final mae = (d['FILIACAO_MAE'] ?? d['filiacaoMae'] ?? '').toString().trim();
        final legado = (d['FILIACAO'] ?? d['filiacao'] ?? '').toString().trim();
        _filiacaoPaiCtrl.text = pai.isNotEmpty ? pai : legado;
        _filiacaoMaeCtrl.text = mae;
        final sexo = (d['SEXO'] ?? '').toString();
        if (sexo.isNotEmpty) _sexo = sexo;
        final ts = d['DATA_NASCIMENTO'];
        if (ts is Timestamp) _birthDate = ts.toDate();
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

  String _formatDate(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  static String _buildFiliacaoLegado(String pai, String mae) {
    if (pai.isEmpty && mae.isEmpty) return '';
    if (pai.isEmpty) return mae;
    if (mae.isEmpty) return pai;
    return '$pai e $mae';
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a data de nascimento.')),
      );
      return;
    }
    if (_changePassword) {
      final cur = _senhaAtualCtrl.text;
      final nova = _senhaNovaCtrl.text;
      final conf = _senhaConfirmCtrl.text;
      if (nova.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nova senha deve ter pelo menos 6 caracteres.')),
        );
        return;
      }
      if (nova != conf) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmação da senha não confere.')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final age = _calcAge(_birthDate);
      final ageRange = _ageRange(age);

      final memberRef = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('membros')
          .doc(widget.cpf);
      final isNewMember = !(await memberRef.get()).exists;
      if (isNewMember) {
        final limitService = MembersLimitService();
        final limitResult = await limitService.checkLimit(widget.tenantId);
        if (limitResult.isBlocked) {
          if (mounted) {
            setState(() => _saving = false);
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
          }
          return;
        }
      }
      final tenantSnap = await FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).get();
      final tenantData = tenantSnap.data();
      final tid = tenantSnap.id;
      final alias = (tenantData?['alias'] ?? tenantData?['slug'] ?? tid).toString().trim();
      final slug = (tenantData?['slug'] ?? tenantData?['alias'] ?? tid).toString().trim();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await memberRef.set({
        'alias': alias.isEmpty ? tid : alias,
        'slug': slug.isEmpty ? tid : slug,
        'tenantId': widget.tenantId,
        'NOME_COMPLETO': _nameCtrl.text.trim(),
        'EMAIL': _emailCtrl.text.trim(),
        'TELEFONES': _phoneCtrl.text.trim(),
        'DATA_NASCIMENTO': Timestamp.fromDate(_birthDate!),
        'FAIXA_ETARIA': ageRange,
        'IDADE': age ?? 0,
        'SEXO': _sexo,
        'ENDERECO': _enderecoCtrl.text.trim(),
        'CEP': _cepCtrl.text.trim(),
        'CIDADE': _cityCtrl.text.trim(),
        'BAIRRO': _bairroCtrl.text.trim(),
        'ESTADO_CIVIL': _estadoCivilCtrl.text.trim(),
        'ESCOLARIDADE': _escolaridadeCtrl.text.trim(),
        'NOME_CONJUGE': _conjugeCtrl.text.trim(),
        'FILIACAO_PAI': _filiacaoPaiCtrl.text.trim(),
        'FILIACAO_MAE': _filiacaoMaeCtrl.text.trim(),
        'FILIACAO': _buildFiliacaoLegado(_filiacaoPaiCtrl.text.trim(), _filiacaoMaeCtrl.text.trim()),
        'ATUALIZADO_EM': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'mustCompleteRegistration': false,
          'name': _nameCtrl.text.trim(),
          'nome': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .collection('usersIndex')
            .doc(widget.cpf)
            .update({
          'mustCompleteRegistration': false,
          'name': _nameCtrl.text.trim(),
          'nome': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (_changePassword && user != null) {
        final email = user.email;
        if (email != null && email.isNotEmpty) {
          final cred = EmailAuthProvider.credential(
            email: email,
            password: _senhaAtualCtrl.text,
          );
          await user.reauthenticateWithCredential(cred);
          await user.updatePassword(_senhaNovaCtrl.text);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro atualizado com sucesso.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(widget.appBarTitle ?? 'Completar seu cadastro'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete ou altere seus dados. Depois você poderá acessar o painel.',
                            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome completo',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Telefones',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _pickBirthDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Data de nascimento',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_birthDate != null ? _formatDate(_birthDate!) : 'Toque para escolher'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _sexo,
                            decoration: const InputDecoration(
                              labelText: 'Sexo',
                              border: OutlineInputBorder(),
                            ),
                            items: ['Masculino', 'Feminino', 'Outro']
                                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (v) => setState(() => _sexo = v ?? _sexo),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _enderecoCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Endereço',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cepCtrl,
                            decoration: const InputDecoration(
                              labelText: 'CEP',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _bairroCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Bairro',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _estadoCivilCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Estado civil',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _escolaridadeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Escolaridade',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _conjugeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nome do cônjuge',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _filiacaoPaiCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Filiação (pai)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _filiacaoMaeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Filiação (mãe)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _changePassword,
                                onChanged: (v) => setState(() => _changePassword = v ?? false),
                              ),
                              const Expanded(
                                child: Text(
                                  'Trocar senha (recomendado sair da senha provisória)',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                          if (_changePassword) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _senhaAtualCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Senha atual',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _senhaNovaCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Nova senha',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _senhaConfirmCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Confirmar nova senha',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Salvar e continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
