import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/global_announcement_overlay.dart';
import 'package:intl/intl.dart';

/// Painel Master — Aviso global / manutenção / promoção temporária para todas as igrejas.
/// Tipo ([kind]), título opcional, texto com URLs clicáveis e até dois botões de link.
/// O usuário vê o aviso uma vez e ao tocar em «Entendi» não volta a ver na mesma revisão.
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
  final _titleCtrl = TextEditingController();
  final _primaryUrlCtrl = TextEditingController();
  final _primaryLabelCtrl = TextEditingController();
  final _secondaryUrlCtrl = TextEditingController();
  final _secondaryLabelCtrl = TextEditingController();
  final _androidUrlCtrl = TextEditingController();
  final _iosUrlCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  DateTime? _validUntil;
  bool _active = false;
  bool _saving = false;
  /// `info` | `maintenance` | `promotion` — define cores e título padrão no painel.
  String _kind = 'info';

  @override
  void dispose() {
    _messageCtrl.dispose();
    _titleCtrl.dispose();
    _primaryUrlCtrl.dispose();
    _primaryLabelCtrl.dispose();
    _secondaryUrlCtrl.dispose();
    _secondaryLabelCtrl.dispose();
    _androidUrlCtrl.dispose();
    _iosUrlCtrl.dispose();
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
        _titleCtrl.text = (d['title'] ?? '').toString();
        _primaryUrlCtrl.text = (d['primaryButtonUrl'] ?? '').toString();
        _primaryLabelCtrl.text = (d['primaryButtonLabel'] ?? '').toString();
        _secondaryUrlCtrl.text = (d['secondaryButtonUrl'] ?? '').toString();
        _secondaryLabelCtrl.text = (d['secondaryButtonLabel'] ?? '').toString();
        _androidUrlCtrl.text = (d['androidButtonUrl'] ?? '').toString();
        _iosUrlCtrl.text = (d['iosButtonUrl'] ?? '').toString();
        final k = (d['kind'] ?? 'info').toString().trim().toLowerCase();
        setState(() {
          _validUntil = v?.toDate();
          _active = d['active'] == true;
          _kind = (k == 'maintenance' ||
                  k == 'manutencao' ||
                  k == 'manutenção')
              ? 'maintenance'
              : (k == 'promotion' ||
                      k == 'promocao' ||
                      k == 'promoção')
                  ? 'promotion'
                  : 'info';
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
        'title': _titleCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _titleCtrl.text.trim(),
        'kind': _kind,
        'primaryButtonUrl': _primaryUrlCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _primaryUrlCtrl.text.trim(),
        'primaryButtonLabel': _primaryLabelCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _primaryLabelCtrl.text.trim(),
        'secondaryButtonUrl': _secondaryUrlCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _secondaryUrlCtrl.text.trim(),
        'secondaryButtonLabel': _secondaryLabelCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _secondaryLabelCtrl.text.trim(),
        'androidButtonUrl': _androidUrlCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _androidUrlCtrl.text.trim(),
        'iosButtonUrl': _iosUrlCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _iosUrlCtrl.text.trim(),
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
        'title': _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        'kind': _kind,
        'primaryButtonUrl':
            _primaryUrlCtrl.text.trim().isEmpty ? null : _primaryUrlCtrl.text.trim(),
        'primaryButtonLabel':
            _primaryLabelCtrl.text.trim().isEmpty ? null : _primaryLabelCtrl.text.trim(),
        'secondaryButtonUrl':
            _secondaryUrlCtrl.text.trim().isEmpty ? null : _secondaryUrlCtrl.text.trim(),
        'secondaryButtonLabel':
            _secondaryLabelCtrl.text.trim().isEmpty ? null : _secondaryLabelCtrl.text.trim(),
        'androidButtonUrl':
            _androidUrlCtrl.text.trim().isEmpty ? null : _androidUrlCtrl.text.trim(),
        'iosButtonUrl':
            _iosUrlCtrl.text.trim().isEmpty ? null : _iosUrlCtrl.text.trim(),
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
              'Aviso salvo (revisão $rev). Todos verão ao entrar no painel; quem já tinha fechado verá de novo nesta revisão.'),
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
        'title': FieldValue.delete(),
        'kind': FieldValue.delete(),
        'primaryButtonUrl': FieldValue.delete(),
        'primaryButtonLabel': FieldValue.delete(),
        'secondaryButtonUrl': FieldValue.delete(),
        'secondaryButtonLabel': FieldValue.delete(),
        'androidButtonUrl': FieldValue.delete(),
        'iosButtonUrl': FieldValue.delete(),
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
    _titleCtrl.text = (d['title'] ?? '').toString();
    _primaryUrlCtrl.text = (d['primaryButtonUrl'] ?? '').toString();
    _primaryLabelCtrl.text = (d['primaryButtonLabel'] ?? '').toString();
    _secondaryUrlCtrl.text = (d['secondaryButtonUrl'] ?? '').toString();
    _secondaryLabelCtrl.text = (d['secondaryButtonLabel'] ?? '').toString();
    _androidUrlCtrl.text = (d['androidButtonUrl'] ?? '').toString();
    _iosUrlCtrl.text = (d['iosButtonUrl'] ?? '').toString();
    final k = (d['kind'] ?? 'info').toString().trim().toLowerCase();
    final vu = d['validUntil'];
    setState(() {
      _validUntil = vu is Timestamp ? vu.toDate() : null;
      _active = d['active'] == true;
      _kind = (k == 'maintenance' ||
              k == 'manutencao' ||
              k == 'manutenção')
          ? 'maintenance'
          : (k == 'promotion' || k == 'promocao' || k == 'promoção')
              ? 'promotion'
              : 'info';
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
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary,
                    Color.lerp(ThemeCleanPremium.primary, ThemeCleanPremium.primaryLight, 0.45)!,
                    ThemeCleanPremium.primaryLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.campaign_rounded, size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: ThemeCleanPremium.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Avisos, manutenção e promoções',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: isMobile ? 20 : 22,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Uma mensagem por vez ao entrar no painel. O tipo define cores no cartão; links http(s) ou com domínio no texto abrem no navegador; use os botões para checkout ou site. Nova revisão reexibe para quem já tinha fechado.',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: Colors.white.withValues(alpha: 0.94),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            if (_loading)
              MasterPremiumCard(
                child: const Padding(
                  padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              MasterPremiumCard(
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
              MasterPremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tipo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'info',
                          label: Text('Geral'),
                          icon: Icon(Icons.notifications_active_outlined, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: 'maintenance',
                          label: Text('Manutenção'),
                          icon: Icon(Icons.build_circle_outlined, size: 18),
                        ),
                        ButtonSegment<String>(
                          value: 'promotion',
                          label: Text('Promoção'),
                          icon: Icon(Icons.local_offer_outlined, size: 18),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        setState(() => _kind = s.first);
                      },
                      style: SegmentedButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.onSurface,
                        selectedForegroundColor: Colors.white,
                        selectedBackgroundColor: ThemeCleanPremium.primary,
                        side: BorderSide(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Título no cartão (opcional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ex.: Atualização programada — deixe em branco para usar o título padrão do tipo',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Mensagem',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Inclua links completos (https://…) ou domínios com ponto (ex.: mercadopago.com.br/…); no painel ficam clicáveis no celular e na web.',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLines: 5,
                      controller: _messageCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ex.: O sistema passará por melhorias no dia 15/03. Entre 22h e 23h pode haver instabilidade. Saiba mais em https://…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageCtrl,
                      builder: (context, value, _) {
                        final t = value.text.trim();
                        if (t.isEmpty) return const SizedBox.shrink();
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.surfaceVariant.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            border: Border.all(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pré-visualização (como no painel)',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Linkify(
                                text: t,
                                linkifiers: kGlobalAnnouncementLinkifiers,
                                onOpen: (link) =>
                                    openHttpsUrlInBrowser(context, link.url),
                                options: kGlobalAnnouncementLinkifyOptions,
                                useMouseRegion: true,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: ThemeCleanPremium.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                                linkStyle: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: ThemeCleanPremium.primary,
                                  fontWeight: FontWeight.w800,
                                  decoration: TextDecoration.underline,
                                  decorationColor: ThemeCleanPremium.primary.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Botões de ação (opcional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Até dois botões grandes abaixo do texto (ex.: «Aproveitar oferta» + URL do checkout). Rótulo vazio usa «Abrir link».',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _primaryLabelCtrl,
                      decoration: InputDecoration(
                        labelText: '1º botão — rótulo',
                        hintText: 'Ex.: Ver oferta',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _primaryUrlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: '1º botão — URL',
                        hintText: 'https://…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    TextField(
                      controller: _secondaryLabelCtrl,
                      decoration: InputDecoration(
                        labelText: '2º botão — rótulo',
                        hintText: 'Ex.: Site oficial',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secondaryUrlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: '2º botão — URL',
                        hintText: 'https://…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    Text(
                      'Links por plataforma (Android/iPhone)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Quando preenchidos, aparecem como botões dedicados no aviso (clicáveis no Android, iPhone e Web).',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeCleanPremium.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _androidUrlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Link Android (Play Store/APK)',
                        hintText: 'https://play.google.com/store/apps/details?id=...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.surfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _iosUrlCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Link iPhone (App Store)',
                        hintText: 'https://apps.apple.com/app/id...',
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
                            'Aviso ativo (cada revisão reexibe para quem já tinha fechado)',
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
                  return MasterPremiumCard(
                    child: Text(
                      'Não foi possível carregar o histórico. Se for índice, faça deploy do firestore.indexes ou aguarde propagação.\n${snap.error}',
                      style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const MasterPremiumCard(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return MasterPremiumCard(
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
                        child: MasterPremiumCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        Text(
                                          _rotuloAcaoHistorico(d.data()),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if ((d.data()['kind'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty)
                                          Chip(
                                            label: Text(
                                              _rotuloTipoHistorico(d.data()['kind']),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize.shrinkWrap,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                          ),
                                      ],
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

  String _rotuloTipoHistorico(dynamic kind) {
    final k = (kind ?? 'info').toString().trim().toLowerCase();
    if (k == 'maintenance' || k == 'manutencao' || k == 'manutenção') {
      return 'Manutenção';
    }
    if (k == 'promotion' || k == 'promocao' || k == 'promoção') {
      return 'Promoção';
    }
    return 'Geral';
  }
}
