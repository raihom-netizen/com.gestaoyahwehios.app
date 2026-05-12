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

  const ChurchPostRichTextViewer({
    super.key,
    required this.data,
    this.maxHeight,
    this.padding = const EdgeInsets.only(bottom: 4),
    this.embedInParentScroll = true,
  });

  @override
  State<ChurchPostRichTextViewer> createState() =>
      _ChurchPostRichTextViewerState();
}

class _ChurchPostRichTextViewerState extends State<ChurchPostRichTextViewer> {
  late QuillController _controller;
  late ScrollController _scroll;

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
}
