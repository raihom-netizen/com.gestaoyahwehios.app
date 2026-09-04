import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'church_post_rich_text_utils.dart';

/// Mostra corpo de post (evento/aviso) com formatação Quill; fallback para texto sem Delta.
///
/// **Tela cinza (Web / iOS):** costuma ser scroll **aninhado** (Quill com `scrollable: true`
/// + `maxHeight` dentro de ListView / Column com scroll). Por defeito [embedInParentScroll]
/// é `true`: um único eixo de scroll no **pai** — sem viewport Quill aninhada.
///
/// Só use [embedInParentScroll] `false` com [maxHeight] quando o widget **não** está
/// dentro de um scroll vertical (ex.: caixa isolada num diálogo).
class ChurchPostRichTextViewer extends StatefulWidget {
  final Map<String, dynamic> data;
  final double? maxHeight;
  final EdgeInsets padding;
  /// `true` = Quill sem scroll interno (recomendado em feed, mural, galeria).
  final bool embedInParentScroll;

  /// Legenda longa fica recolhida com o botao «Veja mais» (padrao do feed).
  /// Sem isto um texto grande empurrava os botoes do card para fora da tela.
  final bool collapsible;

  /// Linhas visiveis enquanto esta recolhido.
  final int collapsedMaxLines;

  /// Cartao cinza a volta do texto. No feed a legenda fica solta (Instagram).
  final bool boxed;

  const ChurchPostRichTextViewer({
    super.key,
    required this.data,
    this.maxHeight,
    this.padding = const EdgeInsets.only(bottom: 4),
    this.embedInParentScroll = true,
    this.collapsible = false,
    this.collapsedMaxLines = 4,
    this.boxed = true,
  });

  @override
  State<ChurchPostRichTextViewer> createState() =>
      _ChurchPostRichTextViewerState();
}

class _ChurchPostRichTextViewerState extends State<ChurchPostRichTextViewer> {
  late QuillController _controller;
  late ScrollController _scroll;
  bool _expanded = false;

  void _rebuildController() {
    _controller = QuillController(
      document: churchPostDocumentFromData(widget.data),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    try {
      _rebuildController();
    } catch (e, st) {
      assert(() {
        debugPrint('ChurchPostRichTextViewer init: $e\n$st');
        return true;
      }());
      _controller = QuillController.basic()..readOnly = true;
    }
  }

  @override
  void didUpdateWidget(covariant ChurchPostRichTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (churchPostRichContentSig(widget.data) !=
        churchPostRichContentSig(oldWidget.data)) {
      try {
        _controller.dispose();
        _rebuildController();
      } catch (e, st) {
        assert(() {
          debugPrint('ChurchPostRichTextViewer didUpdate: $e\n$st');
          return true;
        }());
        _controller.dispose();
        _controller = QuillController.basic()..readOnly = true;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plain = churchPostPlainText(widget.data);
    if (plain.isEmpty) return const SizedBox.shrink();

    final useInnerScroll = !widget.embedInParentScroll &&
        widget.maxHeight != null &&
        widget.maxHeight!.isFinite;

    final editor = Theme(
      data: Theme.of(context).copyWith(
        canvasColor: const Color(0xFFF8FAFC),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w500,
        ),
        child: QuillEditor.basic(
          controller: _controller,
          scrollController: _scroll,
          config: QuillEditorConfig(
            scrollable: useInnerScroll,
            expands: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            autoFocus: false,
            showCursor: false,
            enableInteractiveSelection: true,
            enableSelectionToolbar: true,
          ),
        ),
      ),
    );

    Widget body = editor;
    if (useInnerScroll) {
      body = SizedBox(
        height: widget.maxHeight!.clamp(120, 2000),
        child: ClipRect(child: editor),
      );
    } else if (widget.collapsible) {
      body = _collapsible(context, editor, plain);
    }

    if (!widget.boxed) {
      return Padding(padding: widget.padding, child: body);
    }

    return Padding(
      padding: widget.padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: const Color(0xFFF8FAFC),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  /// Recolhe a legenda em [ChurchPostRichTextViewer.collapsedMaxLines] linhas e
  /// mostra «Veja mais». A medicao usa o texto simples: o Quill nao expoe
  /// `maxLines`, entao o corte e por ALTURA (com `ClipRect`), o que preserva a
  /// formatacao (negrito, listas, links) do que fica visivel.
  Widget _collapsible(BuildContext context, Widget editor, String plain) {
    const style = TextStyle(fontSize: 14, height: 1.45);
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite && c.maxWidth > 0
            ? c.maxWidth - 16
            : 320.0;
        final tp = TextPainter(
          text: TextSpan(text: plain, style: style),
          maxLines: widget.collapsedMaxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: maxW > 0 ? maxW : 320.0);
        final overflows = tp.didExceedMaxLines;
        if (!overflows) return editor;
        // 14 * 1.45 por linha + o padding vertical do editor (8 + 8).
        final collapsedH = (14 * 1.45 * widget.collapsedMaxLines) + 16;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded)
              editor
            else
              SizedBox(
                height: collapsedH,
                child: ClipRect(
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black, Colors.black, Colors.transparent],
                      stops: [0.0, 0.72, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: editor,
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  _expanded ? 'Ver menos' : 'Veja mais',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
