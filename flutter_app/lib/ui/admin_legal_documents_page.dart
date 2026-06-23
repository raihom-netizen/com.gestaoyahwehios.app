import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/legal_document_models.dart';
import 'package:gestao_yahweh/services/legal_documents_defaults.dart';
import 'package:gestao_yahweh/services/legal_documents_service.dart';
import 'package:gestao_yahweh/ui/pages/legal_pages.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Painel Master — editar Termos de Uso e Política de Privacidade.
/// Publica em `config/legal_documents` — sincroniza Web, Android e iOS.
class AdminLegalDocumentsPage extends StatefulWidget {
  /// Quando [true], abre com AppBar própria (tela cheia — ideal no mobile).
  final bool fullScreen;

  const AdminLegalDocumentsPage({super.key, this.fullScreen = false});

  /// Editor em tela cheia (mobile) — ocupa 100% da área útil, sem footer do shell.
  static Future<void> openFullScreen(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const AdminLegalDocumentsPage(fullScreen: true),
      ),
    );
  }

  @override
  State<AdminLegalDocumentsPage> createState() =>
      _AdminLegalDocumentsPageState();
}

class _SectionFields {
  final TextEditingController title;
  final TextEditingController body;

  _SectionFields({required this.title, required this.body});

  void dispose() {
    title.dispose();
    body.dispose();
  }

  static _SectionFields fromEntry(LegalSectionEntry e) => _SectionFields(
        title: TextEditingController(text: e.title),
        body: TextEditingController(text: e.body),
      );

  LegalSectionEntry toEntry() => LegalSectionEntry(
        title: title.text.trim(),
        body: body.text.trim(),
      );
}

class _AdminLegalDocumentsPageState extends State<AdminLegalDocumentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  bool _publishedOnServer = false;
  int _revision = 0;
  String? _error;

  late TextEditingController _lastUpdated;
  late TextEditingController _supportEmail;
  late TextEditingController _supportWhatsApp;
  late TextEditingController _termsIntro;
  late TextEditingController _privacyIntro;
  final List<_SectionFields> _termsSections = [];
  final List<_SectionFields> _privacySections = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _lastUpdated = TextEditingController();
    _supportEmail = TextEditingController();
    _supportWhatsApp = TextEditingController();
    _termsIntro = TextEditingController();
    _privacyIntro = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _lastUpdated.dispose();
    _supportEmail.dispose();
    _supportWhatsApp.dispose();
    _termsIntro.dispose();
    _privacyIntro.dispose();
    for (final s in _termsSections) {
      s.dispose();
    }
    for (final s in _privacySections) {
      s.dispose();
    }
    super.dispose();
  }

  void _clearSectionLists() {
    for (final s in _termsSections) {
      s.dispose();
    }
    for (final s in _privacySections) {
      s.dispose();
    }
    _termsSections.clear();
    _privacySections.clear();
  }

  void _applyBundle(LegalDocumentsBundle bundle) {
    _clearSectionLists();
    _lastUpdated.text = bundle.lastUpdatedLabel;
    _supportEmail.text = bundle.supportEmail;
    _supportWhatsApp.text = bundle.supportWhatsAppDisplay;
    _termsIntro.text = bundle.terms.intro;
    _privacyIntro.text = bundle.privacy.intro;
    _revision = bundle.revision;
    for (final s in bundle.terms.sections) {
      _termsSections.add(_SectionFields.fromEntry(s));
    }
    for (final s in bundle.privacy.sections) {
      _privacySections.add(_SectionFields.fromEntry(s));
    }
  }

  LegalDocumentsBundle _buildBundle() {
    return LegalDocumentsBundle(
      lastUpdatedLabel: _lastUpdated.text.trim(),
      supportEmail: _supportEmail.text.trim(),
      supportWhatsAppDisplay: _supportWhatsApp.text.trim(),
      terms: LegalDocumentContent(
        title: LegalDocumentsDefaults.bundle.terms.title,
        intro: _termsIntro.text.trim(),
        sections: _termsSections.map((s) => s.toEntry()).toList(),
      ),
      privacy: LegalDocumentContent(
        title: LegalDocumentsDefaults.bundle.privacy.title,
        intro: _privacyIntro.text.trim(),
        sections: _privacySections.map((s) => s.toEntry()).toList(),
      ),
      revision: _revision,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _publishedOnServer = await LegalDocumentsService.existsOnServer();
      final bundle = _publishedOnServer
          ? await LegalDocumentsService.loadOnce(source: Source.server)
          : LegalDocumentsDefaults.bundle;
      if (!mounted) return;
      _applyBundle(bundle);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final bundle = _buildBundle();
    if (!bundle.isPublishable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preencha data de atualização, introdução e todas as seções (título + texto).',
          ),
        ),
      );
      return;
    }
    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Faça login como administrador.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final rev = await LegalDocumentsService.saveMaster(
        bundle: bundle,
        uid: uid,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _revision = rev;
        _publishedOnServer = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Publicado — revisão $rev. Web, Android e iOS sincronizam automaticamente.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  void _addSection(bool terms) {
    setState(() {
      final fields = _SectionFields(
        title: TextEditingController(),
        body: TextEditingController(),
      );
      if (terms) {
        _termsSections.add(fields);
      } else {
        _privacySections.add(fields);
      }
    });
  }

  void _removeSection(bool terms, int index) {
    setState(() {
      if (terms) {
        _termsSections.removeAt(index).dispose();
      } else {
        _privacySections.removeAt(index).dispose();
      }
    });
  }

  void _preview(bool privacy) {
    showGestaoYahwehLegalPreview(
      context,
      isPoliticaPrivacidade: privacy,
    );
  }

  Future<void> _showMetaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Dados de publicação',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lastUpdated,
                    decoration: _fieldDecoration(
                      label: 'Última atualização',
                      hint: 'Junho de 2026',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supportEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _fieldDecoration(label: 'E-mail suporte'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supportWhatsApp,
                    decoration: _fieldDecoration(label: 'WhatsApp exibição'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Concluído'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ThemeCleanPremium.primary, width: 1.5),
      ),
    );
  }

  Widget _buildEditorBody(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.fullScreen && isMobile) ...[
                FilledButton.tonalIcon(
                  onPressed: () => AdminLegalDocumentsPage.openFullScreen(context),
                  icon: const Icon(Icons.open_in_full_rounded, size: 20),
                  label: const Text('Abrir editor em tela cheia'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (!isMobile || widget.fullScreen) ...[
                Text(
                  'Termos e Privacidade',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Firestore: config/legal_documents — Web, Android e iOS leem o mesmo documento em tempo real.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              _SyncStatusChip(
                published: _publishedOnServer,
                revision: _revision,
                error: _error,
                onRetry: _load,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding.left),
          child: Material(
            color: Colors.white,
            elevation: 0,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8ECF4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabs,
                labelColor: ThemeCleanPremium.primary,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                tabs: const [
                  Tab(text: 'Termos de Uso'),
                  Tab(text: 'Política de Privacidade'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildDocEditor(
                intro: _termsIntro,
                sections: _termsSections,
                termsTab: true,
                padding: padding,
              ),
              _buildDocEditor(
                intro: _privacyIntro,
                sections: _privacySections,
                termsTab: false,
                padding: padding,
              ),
            ],
          ),
        ),
        _BottomActionBar(
          saving: _saving,
          onMeta: _showMetaSheet,
          onPreview: () => _preview(_tabs.index == 1),
          onPublish: _save,
          padding: padding,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = _buildEditorBody(context);

    if (widget.fullScreen) {
      return Scaffold(
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: ThemeCleanPremium.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          title: const Text(
            'Termos e Privacidade',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Voltar',
          ),
          actions: [
            IconButton(
              tooltip: 'Recarregar do Firestore',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Dados de publicação',
              onPressed: _showMetaSheet,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        body: SafeArea(child: editor),
      );
    }

    // Embutido no shell master — sem Scaffold/SafeArea extra (evita perder altura).
    return ColoredBox(
      color: ThemeCleanPremium.surfaceVariant,
      child: editor,
    );
  }

  Widget _buildDocEditor({
    required TextEditingController intro,
    required List<_SectionFields> sections,
    required bool termsTab,
    required EdgeInsets padding,
  }) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        4,
        padding.right,
        padding.bottom + 16,
      ),
      children: [
        MasterPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.subject_rounded,
                      size: 20, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Introdução',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: intro,
                minLines: 5,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: _fieldDecoration(
                  label: 'Parágrafo inicial',
                  hint: 'Texto exibido no topo do documento…',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < sections.length; i++) ...[
          MasterPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Seção ${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: ThemeCleanPremium.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Remover seção',
                      onPressed: sections.length <= 1
                          ? null
                          : () => _removeSection(termsTab, i),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: Colors.red.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sections[i].title,
                  decoration: _fieldDecoration(label: 'Título da seção'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sections[i].body,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: _fieldDecoration(
                    label: 'Texto completo',
                    hint: 'Conteúdo visível para o usuário…',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: () => _addSection(termsTab),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar seção'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncStatusChip extends StatelessWidget {
  final bool published;
  final int revision;
  final String? error;
  final VoidCallback onRetry;

  const _SyncStatusChip({
    required this.published,
    required this.revision,
    this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return MasterPremiumCard(
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: ThemeCleanPremium.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(
                  color: ThemeCleanPremium.error,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Recarregar')),
          ],
        ),
      );
    }

    final color = published ? Colors.green.shade700 : Colors.orange.shade800;
    final icon =
        published ? Icons.cloud_done_rounded : Icons.cloud_off_rounded;
    final text = published
        ? 'Sincronizado — revisão $revision · Web · Android · iOS'
        : 'Rascunho local — publique para sincronizar todas as plataformas';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onMeta;
  final VoidCallback onPreview;
  final VoidCallback onPublish;
  final EdgeInsets padding;

  const _BottomActionBar({
    required this.saving,
    required this.onMeta,
    required this.onPreview,
    required this.onPublish,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding.left, 10, padding.right, 10),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Data, e-mail e WhatsApp',
                onPressed: onMeta,
                icon: const Icon(Icons.tune_rounded),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: saving ? null : onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                  label: const Text('Pré-visualizar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: saving ? null : onPublish,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 20),
                  label: Text(saving ? 'Publicando…' : 'Publicar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
