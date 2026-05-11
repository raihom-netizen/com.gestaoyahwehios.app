import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Configuração partilhada da barra Quill (eventos / avisos).
QuillSimpleToolbarConfig churchPostQuillToolbarConfig() {
  return const QuillSimpleToolbarConfig(
    multiRowsDisplay: true,
    showDividers: true,
    showAlignmentButtons: true,
    showFontFamily: true,
    showFontSize: true,
    showBoldButton: true,
    showItalicButton: true,
    showUnderLineButton: true,
    showStrikeThrough: true,
    showInlineCode: false,
    showSubscript: false,
    showSuperscript: false,
    showSmallButton: false,
    showColorButton: true,
    showBackgroundColorButton: true,
    showClearFormat: true,
    showHeaderStyle: true,
    showListNumbers: true,
    showListBullets: true,
    showListCheck: true,
    showCodeBlock: false,
    showQuote: true,
    showIndent: true,
    showLink: true,
    showUndo: true,
    showRedo: true,
    showSearchButton: false,
    color: Color(0xFFF8FAFC),
    sectionDividerColor: Color(0xFFE2E8F0),
  );
}

void churchPostRichApplySelectionCase(
  BuildContext context,
  QuillController controller,
  String Function(String) map,
) {
  final sel = controller.selection;
  if (!sel.isValid) return;
  final plain = controller.document.toPlainText();
  final start = sel.start.clamp(0, plain.length);
  final end = sel.end.clamp(0, plain.length);
  if (start >= end) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Selecione o texto para alterar maiúsculas.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.grey.shade800,
      ),
    );
    return;
  }
  final chunk = plain.substring(start, end);
  final replaced = map(chunk);
  controller.replaceText(
    start,
    end - start,
    replaced,
    TextSelection.collapsed(offset: start + replaced.length),
  );
}

Future<void> churchPostRichCopyAll(
    BuildContext context, QuillController controller) async {
  final t = controller.document.toPlainText().trim();
  await Clipboard.setData(ClipboardData(text: t));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    ThemeCleanPremium.successSnackBar(
        'Texto copiado para a área de transferência.'),
  );
}

/// Editor estilo Word para corpo de eventos/avisos (Delta Quill).
class ChurchPostRichTextEditor extends StatefulWidget {
  final QuillController controller;
  final String label;
  final String? hint;

  const ChurchPostRichTextEditor({
    super.key,
    required this.controller,
    this.label = 'Descrição / texto',
    this.hint,
  });

  @override
  State<ChurchPostRichTextEditor> createState() =>
      _ChurchPostRichTextEditorState();
}

class _ChurchPostRichTextEditorState extends State<ChurchPostRichTextEditor> {
  late FocusNode _focus;
  late ScrollController _scroll;
  bool _fullscreenActive = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _scroll = ScrollController();
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openFullscreen() async {
    setState(() => _fullscreenActive = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => ChurchPostRichTextFullscreenPage(
            controller: widget.controller,
            title: widget.label,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _fullscreenActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hint ??
        'Negrito, cores, alinhamento, listas e tamanhos — use a barra acima.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_fix_high_rounded,
                size: 20,
                color: ThemeCleanPremium.primary.withValues(alpha: 0.9)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            Tooltip(
              message: _fullscreenActive
                  ? 'Já está em ecrã inteiro'
                  : 'Texto em ecrã inteiro',
              child: IconButton.filledTonal(
                onPressed: _fullscreenActive ? null : _openFullscreen,
                icon: const Icon(Icons.fullscreen_rounded),
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: ThemeCleanPremium.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style:
              TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: const Color(0xFFF8FAFC),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: QuillSimpleToolbar(
                    controller: widget.controller,
                    config: churchPostQuillToolbarConfig(),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Texto:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    ActionChip(
                      label: const Text('MAIÚSCULAS'),
                      labelStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => churchPostRichApplySelectionCase(
                          context, widget.controller, (s) => s.toUpperCase()),
                    ),
                    ActionChip(
                      label: const Text('minúsculas'),
                      labelStyle: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => churchPostRichApplySelectionCase(
                          context, widget.controller, (s) => s.toLowerCase()),
                    ),
                    ActionChip(
                      avatar: Icon(Icons.copy_rounded,
                          size: 16, color: ThemeCleanPremium.primary),
                      label: const Text('Copiar tudo'),
                      labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ThemeCleanPremium.primary),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          churchPostRichCopyAll(context, widget.controller),
                    ),
                  ],
                ),
              ),
              if (!_fullscreenActive)
                SizedBox(
                  height: 220,
                  child: QuillEditor.basic(
                    controller: widget.controller,
                    focusNode: _focus,
                    scrollController: _scroll,
                    config: QuillEditorConfig(
                      placeholder: 'Escreva aqui…',
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                      scrollable: true,
                      expands: false,
                      minHeight: 200,
                      autoFocus: false,
                    ),
                  ),
                )
              else
                _FullscreenPlaceholder(onOpenAgain: _openFullscreen),
            ],
          ),
        ),
      ],
    );
  }
}

/// Placeholder enquanto o único [QuillEditor] está na rota de ecrã inteiro (evita dois editores no mesmo controller).
class _FullscreenPlaceholder extends StatelessWidget {
  final VoidCallback onOpenAgain;

  const _FullscreenPlaceholder({required this.onOpenAgain});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note_rounded,
              size: 40, color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
          const SizedBox(height: 10),
          Text(
            'Edição em ecrã inteiro',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use «Voltar» no topo para regressar ao formulário (data, horário, fotos, etc.).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onOpenAgain,
            icon: const Icon(Icons.fullscreen_rounded, size: 20),
            label: const Text('Reabrir ecrã inteiro'),
          ),
        ],
      ),
    );
  }
}

/// Página modal: texto ocupa o espaço disponível; AppBar com voltar ao formulário.
class ChurchPostRichTextFullscreenPage extends StatefulWidget {
  final QuillController controller;
  final String title;

  const ChurchPostRichTextFullscreenPage({
    super.key,
    required this.controller,
    required this.title,
  });

  @override
  State<ChurchPostRichTextFullscreenPage> createState() =>
      _ChurchPostRichTextFullscreenPageState();
}

class _ChurchPostRichTextFullscreenPageState
    extends State<ChurchPostRichTextFullscreenPage> {
  late FocusNode _focus;
  late ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Voltar ao formulário',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Editar texto',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
            label: const Text(
              'Concluir',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                '«${widget.title}» · Voltar (←) ou Concluir regressa ao formulário (data, horário, fotos…).',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Material(
              color: Colors.white,
              elevation: 1,
              shadowColor: Colors.black12,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: QuillSimpleToolbar(
                  controller: widget.controller,
                  config: churchPostQuillToolbarConfig(),
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Texto:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  ActionChip(
                    label: const Text('MAIÚSCULAS'),
                    labelStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => churchPostRichApplySelectionCase(
                        context, widget.controller, (s) => s.toUpperCase()),
                  ),
                  ActionChip(
                    label: const Text('minúsculas'),
                    labelStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => churchPostRichApplySelectionCase(
                        context, widget.controller, (s) => s.toLowerCase()),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.copy_rounded,
                        size: 16, color: ThemeCleanPremium.primary),
                    label: const Text('Copiar tudo'),
                    labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ThemeCleanPremium.primary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        churchPostRichCopyAll(context, widget.controller),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: QuillEditor.basic(
                    controller: widget.controller,
                    focusNode: _focus,
                    scrollController: _scroll,
                    config: QuillEditorConfig(
                      placeholder: 'Escreva aqui…',
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                      scrollable: true,
                      expands: true,
                      autoFocus: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
