import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/legal_document_models.dart';
import 'package:gestao_yahweh/services/legal_documents_defaults.dart';
import 'package:gestao_yahweh/services/legal_documents_service.dart';
import 'package:gestao_yahweh/ui/pages/legal_pages.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Painel Master — editar Termos de Uso e Política de Privacidade.
/// Publica em `config/legal_documents` — sincroniza Web, Android e iOS.
class AdminLegalDocumentsPage extends StatefulWidget {
  const AdminLegalDocumentsPage({super.key});

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
    final uid = FirebaseAuth.instance.currentUser?.uid;
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

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);

    if (_loading) {
      return const Scaffold(
        primary: false,
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Termos e Privacidade',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edite e publique em config/legal_documents — todas as plataformas leem o mesmo documento.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    MasterPremiumCard(
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: ThemeCleanPremium.error, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: ThemeCleanPremium.error,
                                    fontSize: 13)),
                          ),
                          TextButton(
                              onPressed: _load, child: const Text('Recarregar')),
                        ],
                      ),
                    ),
                  ],
                  if (!_publishedOnServer) ...[
                    const SizedBox(height: 10),
                    MasterPremiumCard(
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: Colors.orange.shade700, size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ainda não publicado no Firestore. O app usa o texto padrão até você salvar.',
                              style: TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    MasterPremiumCard(
                      child: Row(
                        children: [
                          Icon(Icons.cloud_done_rounded,
                              color: Colors.green.shade700, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Publicado — revisão $_revision. Alterações refletem em Web, Android e iOS.',
                              style: const TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: ThemeCleanPremium.primary,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: ThemeCleanPremium.primary,
              tabs: const [
                Tab(text: 'Termos de Uso'),
                Tab(text: 'Política de Privacidade'),
              ],
            ),
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
            Material(
              elevation: 8,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding.left,
                    10,
                    padding.right,
                    10,
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMetaFields(),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _saving
                                        ? null
                                        : () => _preview(_tabs.index == 1),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('Pré-visualizar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _saving ? null : _save,
                                    icon: _saving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.cloud_upload_rounded),
                                    label: Text(_saving ? 'Salvando…' : 'Publicar'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(flex: 3, child: _buildMetaFields()),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _preview(_tabs.index == 1),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Pré-visualizar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_upload_rounded),
                              label: Text(_saving ? 'Salvando…' : 'Publicar'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaFields() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 180,
          child: TextField(
            controller: _lastUpdated,
            decoration: const InputDecoration(
              labelText: 'Última atualização',
              hintText: 'Junho de 2026',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _supportEmail,
            decoration: const InputDecoration(
              labelText: 'E-mail suporte',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _supportWhatsApp,
            decoration: const InputDecoration(
              labelText: 'WhatsApp exibição',
              isDense: true,
            ),
          ),
        ),
      ],
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
        12,
        padding.right,
        padding.bottom + 120,
      ),
      children: [
        MasterPremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Introdução',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.primary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: intro,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Parágrafo inicial do documento…',
                  border: OutlineInputBorder(),
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
                    Text(
                      'Seção ${i + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
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
                TextField(
                  controller: sections[i].title,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sections[i].body,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Texto',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
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
        ),
      ],
    );
  }
}
