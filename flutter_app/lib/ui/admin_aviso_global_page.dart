import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Painel Master — Aviso global para todas as igrejas (melhorias, manutenção preventiva).
/// O usuário vê o aviso uma vez e ao clicar OK não volta a ver (registro por usuário).
class AdminAvisoGlobalPage extends StatefulWidget {
  const AdminAvisoGlobalPage({super.key});

  @override
  State<AdminAvisoGlobalPage> createState() => _AdminAvisoGlobalPageState();
}

class _AdminAvisoGlobalPageState extends State<AdminAvisoGlobalPage> {
  final _ref = FirebaseFirestore.instance.doc('config/global_announcement');
  final _audit =
      FirebaseFirestore.instance.collection('global_announcement_audit');
  final _messageCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  DateTime? _validUntil;
  bool _active = false;
  bool _saving = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await _ref.get();
      if (snap.exists && snap.data() != null) {
        final d = snap.data()!;
        Timestamp? v = d['validUntil'] as Timestamp?;
        _messageCtrl.text = (d['message'] ?? '').toString();
        setState(() {
          _validUntil = v?.toDate();
          _active = d['active'] == true;
          _loading = false;
        });
      } else {
        setState(() { _loading = false; });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite a mensagem do aviso.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _ref.set({
        'message': msg,
        'validUntil': _validUntil != null ? Timestamp.fromDate(_validUntil!) : null,
        'active': _active,
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
      }, SetOptions(merge: true));
      final snap = await _ref.get();
      final rev = (snap.data()?['revision'] as num?)?.toInt() ?? 0;
      final email =
          (FirebaseAuth.instance.currentUser?.email ?? '').trim();
      await _audit.add({
        'message': msg,
        'validUntil': _validUntil != null ? Timestamp.fromDate(_validUntil!) : null,
        'active': _active,
        'revision': rev,
        'savedAt': FieldValue.serverTimestamp(),
        'savedByEmail': email.isEmpty ? null : email,
        'action': 'save',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Aviso salvo (revisão $rev). Todos os painéis da igreja verão ao entrar; quem já deu OK verá de novo nesta revisão.'),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remover() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Remover aviso global?'),
        content: const Text(
          'O aviso será desativado e não será mais exibido a nenhum usuário. Você pode criar um novo aviso quando quiser.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Remover aviso'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _ref.set({
        'active': false,
        'message': FieldValue.delete(),
        'validUntil': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
      }, SetOptions(merge: true));
      final snap = await _ref.get();
      final rev = (snap.data()?['revision'] as num?)?.toInt() ?? 0;
      final email =
          (FirebaseAuth.instance.currentUser?.email ?? '').trim();
      await _audit.add({
        'message': '',
        'validUntil': null,
        'active': false,
        'revision': rev,
        'savedAt': FieldValue.serverTimestamp(),
        'savedByEmail': email.isEmpty ? null : email,
        'action': 'removed',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Aviso removido.'),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _carregarHistoricoNoFormulario(Map<String, dynamic> d) {
    final msg = (d['message'] ?? '').toString();
    _messageCtrl.text = msg;
    final vu = d['validUntil'];
    setState(() {
      _validUntil = vu is Timestamp ? vu.toDate() : null;
      _active = d['active'] == true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Carregado no formulário. Ajuste e toque em Salvar aviso para publicar.'),
      );
    }
  }

  Future<void> _prorrogarValidadePublicada() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _ref.set({
        'validUntil': Timestamp.fromDate(date),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': FieldValue.increment(1),
      }, SetOptions(merge: true));
      final snap = await _ref.get();
      final rev = (snap.data()?['revision'] as num?)?.toInt() ?? 0;
      final email =
          (FirebaseAuth.instance.currentUser?.email ?? '').trim();
      await _audit.add({
        'message': (snap.data()?['message'] ?? '').toString(),
        'validUntil': Timestamp.fromDate(date),
        'active': snap.data()?['active'] == true,
        'revision': rev,
        'savedAt': FieldValue.serverTimestamp(),
        'savedByEmail': email.isEmpty ? null : email,
        'action': 'extend',
      });
      if (mounted) {
        setState(() => _validUntil = date);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Validade prorrogada até ${DateFormat('dd/MM/yyyy').format(date)} (revisão $rev).'),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao prorrogar: $e'),
              backgroundColor: ThemeCleanPremium.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _excluirLinhaHistorico(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir linha do histórico?'),
        content: const Text(
            'Só remove este registro da lista; o aviso atual no painel não muda.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _audit.doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Registro removido do histórico.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    final minTouch = ThemeCleanPremium.minTouchTarget;
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  ),
                  child: Icon(Icons.campaign_rounded, size: 28, color: ThemeCleanPremium.primary),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aviso global / Manutenção',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: isMobile ? 20 : 22,
                              color: ThemeCleanPremium.onSurface,
                            ) ??
                            const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: ThemeCleanPremium.onSurface),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Exiba uma mensagem única para todos os usuários ao entrarem no painel (ex.: melhorias, manutenção preventiva). Quem clicar em OK não verá de novo.',
                        style: TextStyle(
                          fontSize: 14,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            if (_loading)
              _PremiumCard(
                child: const Padding(
                  padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              _PremiumCard(
                child: Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: ThemeCleanPremium.error, size: 24),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Mensagem do aviso',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLines: 5,
                      controller: _messageCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ex.: O sistema passará por melhorias no dia 15/03. Entre 22h e 23h pode haver instabilidade. Obrigado!',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Validade do aviso',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null && mounted) setState(() => _validUntil = date);
                      },
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                          filled: true,
                          fillColor: ThemeCleanPremium.surfaceVariant,
                          suffixIcon: const Icon(Icons.calendar_today_rounded),
                        ),
                        child: Text(
                          _validUntil != null
                              ? DateFormat('dd/MM/yyyy').format(_validUntil!)
                              : 'Sem data (aviso ativo até remover)',
                          style: TextStyle(
                            color: _validUntil != null ? ThemeCleanPremium.onSurface : ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'O dia escolhido vale até o fim desse dia (23h59). Em branco = sem data limite, até remover ou desativar.',
                      style: TextStyle(fontSize: 12, color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _validUntil = null),
                        child: const Text('Remover data limite'),
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    // Toggle: label em Expanded para não cortar no celular
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Switch(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                          activeTrackColor: ThemeCleanPremium.primary.withOpacity(0.5),
                          activeThumbColor: ThemeCleanPremium.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Aviso ativo (cada revisão reexibe para quem já tinha dado OK)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: ThemeCleanPremium.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 20),
                          label: Text(_saving ? 'Salvando...' : 'Salvar aviso'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            minimumSize: isMobile ? Size(0, minTouch) : null,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _remover,
                          icon: const Icon(Icons.delete_outline_rounded, size: 20),
                          label: const Text('Remover aviso'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error,
                            side: BorderSide(color: ThemeCleanPremium.error.withOpacity(0.7)),
                            minimumSize: isMobile ? Size(0, minTouch) : null,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _prorrogarValidadePublicada,
                          icon: const Icon(Icons.date_range_rounded, size: 20),
                          label: const Text('Só prorrogar validade'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: isMobile ? Size(0, minTouch) : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            Text(
              'Histórico (edição, prorrogação, remoção)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: isMobile ? 17 : 18,
                color: ThemeCleanPremium.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Últimos registros salvos. Use “carregar” para trazer ao formulário, “prorrogar” no cartão para mudar só a data do aviso atual, ou excluir só a linha do log.',
              style: TextStyle(
                fontSize: 13,
                color: ThemeCleanPremium.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _audit
                  .orderBy('savedAt', descending: true)
                  .limit(25)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _PremiumCard(
                    child: Text(
                      'Não foi possível carregar o histórico. Se for índice, faça deploy do firestore.indexes ou aguarde propagação.\n${snap.error}',
                      style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const _PremiumCard(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _PremiumCard(
                    child: Text(
                      'Nenhum registro ainda. Ao salvar ou remover um aviso, aparece aqui.',
                      style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final d in docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _rotuloAcaoHistorico(d.data()),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '#${(d.data()['revision'] ?? '—')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if ((d.data()['savedAt'] as Timestamp?) != null)
                                Text(
                                  DateFormat('dd/MM/yyyy HH:mm').format(
                                      (d.data()['savedAt'] as Timestamp)
                                          .toDate()),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                (d.data()['message'] ?? '').toString().trim().isEmpty
                                    ? '(sem texto — remoção ou rascunho)'
                                    : (d.data()['message'] ?? '').toString(),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, height: 1.35),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _carregarHistoricoNoFormulario(d.data()),
                                    icon: const Icon(Icons.edit_note_rounded,
                                        size: 18),
                                    label: const Text('Carregar no formulário'),
                                  ),
                                  if ((d.data()['action'] ?? '') != 'removed')
                                    OutlinedButton.icon(
                                      onPressed: _saving
                                          ? null
                                          : _prorrogarValidadePublicada,
                                      icon: const Icon(
                                          Icons.more_time_rounded,
                                          size: 18),
                                      label: const Text('Prorrogar (data)'),
                                    ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _excluirLinhaHistorico(d.id),
                                    icon: Icon(Icons.delete_sweep_rounded,
                                        size: 18,
                                        color: ThemeCleanPremium.error),
                                    label: Text(
                                      'Excluir log',
                                      style: TextStyle(
                                          color: ThemeCleanPremium.error),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _rotuloAcaoHistorico(Map<String, dynamic> d) {
    final a = (d['action'] ?? 'save').toString();
    switch (a) {
      case 'removed':
        return 'Removido';
      case 'extend':
        return 'Validade prorrogada';
      default:
        return 'Salvo';
    }
  }
}

/// Card Super Premium: bordas 16px, sombra suave.
class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}
