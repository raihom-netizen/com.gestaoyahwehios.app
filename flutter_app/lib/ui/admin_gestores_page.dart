import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';
import 'pages/usuarios_permissoes_page.dart';

/// Confirma e executa a remoção da igreja e limpeza de todos os dados vinculados.
Future<void> _confirmarRemoverIgreja(BuildContext context, String tenantId, String nomeIgreja) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 12),
          Expanded(child: Text('Remover igreja e limpar dados')),
        ],
      ),
      content: Text(
        'Remover "$nomeIgreja" e apagar TODOS os dados vinculados (membros, eventos, notícias, departamentos, visitantes, financeiro, etc.) do banco? '
        'Esta ação é irreversível e libera espaço no banco. Confirma?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sim, remover e limpar tudo'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Removendo igreja e limpando dados...'),
    );
    await BillingLicenseService().removerIgrejaELimparDados(tenantId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Igreja e todos os dados vinculados foram removidos.'),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

/// Ativar mais gestores — lista igrejas e permite adicionar/gerenciar gestores por igreja (Super Premium, responsivo).
class AdminGestoresPage extends StatelessWidget {
  const AdminGestoresPage({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + 24),
          children: [
            Text(
              'Ativar mais gestores',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: isMobile ? 22 : 24,
                    color: ThemeCleanPremium.onSurface,
                  ) ??
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: ThemeCleanPremium.onSurface),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            Text(
              'Selecione uma igreja para gerenciar usuários e ativar mais gestores (ADM, GESTOR) que podem ajudar na administração.',
              style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            _IgrejasGestoresList(),
          ],
        ),
      ),
    );
  }
}

class _IgrejasGestoresList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tenantsCol = FirebaseFirestore.instance.collection('igrejas');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tenantsCol.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Center(child: Text('Erro ao carregar igrejas: ${snap.error}', style: TextStyle(color: ThemeCleanPremium.error)));
        }
        var docs = snap.data?.docs ?? [];
        docs = docs.toList()
          ..sort((a, b) {
            final na = (a.data()['name'] ?? a.data()['nome'] ?? a.id).toString();
            final nb = (b.data()['name'] ?? b.data()['nome'] ?? b.id).toString();
            return na.toLowerCase().compareTo(nb.toLowerCase());
          });
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.cardBackground,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.church_rounded, size: 56, color: Colors.grey.shade400),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                Text(
                  'Nenhuma igreja cadastrada.',
                  style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: docs.map((d) {
            final data = d.data();
            final tenantId = d.id;
            final name = (data['name'] ?? data['nome'] ?? tenantId).toString();
            return _IgrejaGestoresTile(
              tenantId: tenantId,
              name: name,
            );
          }).toList(),
        );
      },
    );
  }
}

class _IgrejaGestoresTile extends StatelessWidget {
  final String tenantId;
  final String name;

  const _IgrejaGestoresTile({required this.tenantId, required this.name});

  @override
  Widget build(BuildContext context) {
    final usersCol = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('users');
    final isMobile = ThemeCleanPremium.isMobile(context);
    final minTouch = ThemeCleanPremium.minTouchTarget;

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersCol.snapshots(),
        builder: (context, usersSnap) {
          final users = usersSnap.data?.docs ?? [];
          final gestores = users.where((u) {
            final raw = u.data()['roles'] as List?;
            final roles = raw != null ? raw.map((e) => e.toString().toLowerCase()).toList() : <String>[];
            return roles.any((r) => r == 'gestor' || r == 'adm' || r == 'admin' || r == 'master');
          }).length;

          // Layout responsivo: título sempre com largura total para evitar "uma letra por linha"
          return Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: ThemeCleanPremium.primary.withOpacity(0.12),
                      child: const Icon(Icons.church_rounded, color: ThemeCleanPremium.primary, size: 28),
                    ),
                    const SizedBox(width: ThemeCleanPremium.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: ThemeCleanPremium.onSurface,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$gestores gestor(es) / ${users.length} usuário(s) no total',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeCleanPremium.spaceMd),
                // Ações em linha (mobile: wrap; desktop: row) — área de toque mínima em mobile
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await showDialog(
                          context: context,
                          builder: (_) => _CadastrarGestorDialog(tenantId: tenantId, igrejaName: name),
                        );
                      },
                      icon: const Icon(Icons.person_rounded, size: 18),
                      label: const Text('Cadastrar gestor'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: isMobile ? Size(0, minTouch) : null,
                        padding: EdgeInsets.symmetric(
                          horizontal: ThemeCleanPremium.spaceMd,
                          vertical: isMobile ? 14 : ThemeCleanPremium.spaceSm,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => UsuariosPermissoesPage(
                              tenantId: tenantId,
                              gestorRole: 'master',
                              nomeIgreja: name,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Gerenciar gestores'),
                      style: FilledButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary,
                        minimumSize: isMobile ? Size(0, minTouch) : null,
                        padding: EdgeInsets.symmetric(
                          horizontal: ThemeCleanPremium.spaceMd,
                          vertical: isMobile ? 14 : ThemeCleanPremium.spaceSm,
                        ),
                      ),
                    ),
                    if (isMobile)
                      SizedBox(
                        height: minTouch,
                        width: minTouch,
                        child: IconButton(
                          icon: const Icon(Icons.delete_forever_rounded),
                          tooltip: 'Remover igreja e limpar todos os dados do banco',
                          onPressed: () => _confirmarRemoverIgreja(context, tenantId, name),
                          style: IconButton.styleFrom(foregroundColor: Colors.red.shade700),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.delete_forever_rounded),
                        tooltip: 'Remover igreja e limpar todos os dados do banco',
                        onPressed: () => _confirmarRemoverIgreja(context, tenantId, name),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          minimumSize: Size(minTouch, minTouch),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Diálogo para cadastrar/editar dados completos do gestor da igreja (painel master).
class _CadastrarGestorDialog extends StatefulWidget {
  final String tenantId;
  final String igrejaName;

  const _CadastrarGestorDialog({required this.tenantId, required this.igrejaName});

  @override
  State<_CadastrarGestorDialog> createState() => _CadastrarGestorDialogState();
}

class _CadastrarGestorDialogState extends State<_CadastrarGestorDialog> {
  final _nomeCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  DateTime? _dataNascimento;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _cpfCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId).get();
      final data = doc.data() ?? {};
      if (mounted) {
        _nomeCtrl.text = (data['gestorNome'] ?? data['gestor_nome'] ?? data['responsavel'] ?? '').toString();
        _cpfCtrl.text = (data['gestorCpf'] ?? data['gestor_cpf'] ?? data['cpf'] ?? '').toString();
        _emailCtrl.text = (data['gestorEmail'] ?? data['gestor_email'] ?? data['email'] ?? '').toString();
        _telefoneCtrl.text = (data['gestorTelefone'] ?? data['gestor_telefone'] ?? data['phone'] ?? data['telefone'] ?? '').toString();
        if (data['gestorDataNascimento'] is Timestamp) {
          _dataNascimento = (data['gestorDataNascimento'] as Timestamp).toDate();
        } else if (data['gestor_data_nascimento'] is Timestamp) {
          _dataNascimento = (data['gestor_data_nascimento'] as Timestamp).toDate();
        }
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _salvar() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome completo do gestor.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final ref = FirebaseFirestore.instance.collection('igrejas').doc(widget.tenantId);
      final update = <String, dynamic>{
        'gestorNome': nome,
        'gestor_nome': nome,
        'responsavel': nome,
        'gestorCpf': _cpfCtrl.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        'gestor_cpf': _cpfCtrl.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
        'gestorEmail': _emailCtrl.text.trim(),
        'gestor_email': _emailCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'gestorTelefone': _telefoneCtrl.text.trim(),
        'gestor_telefone': _telefoneCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_dataNascimento != null) {
        update['gestorDataNascimento'] = Timestamp.fromDate(_dataNascimento!);
        update['gestor_data_nascimento'] = Timestamp.fromDate(_dataNascimento!);
      }
      await ref.set(update, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Dados do gestor salvos.'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AlertDialog(
        content: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AlertDialog(
      title: Text('Cadastrar gestor — ${widget.igrejaName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeCtrl,
              decoration: InputDecoration(
                labelText: 'Nome completo',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                prefixIcon: const Icon(Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cpfCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'CPF',
                hintText: 'Somente números',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                prefixIcon: const Icon(Icons.badge_rounded),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dataNascimento ?? DateTime(1990, 1, 1),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dataNascimento = picked);
              },
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data de nascimento',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  prefixIcon: const Icon(Icons.cake_rounded),
                ),
                child: Text(
                  _dataNascimento != null ? DateFormat('dd/MM/yyyy').format(_dataNascimento!) : 'Selecionar',
                  style: TextStyle(color: _dataNascimento != null ? null : Colors.grey.shade600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'E-mail',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                prefixIcon: const Icon(Icons.email_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Telefone',
                hintText: '(11) 99999-9999',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                prefixIcon: const Icon(Icons.phone_rounded),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _salvar,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
