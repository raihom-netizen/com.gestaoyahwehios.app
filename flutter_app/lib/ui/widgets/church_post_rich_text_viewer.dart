import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'church_post_rich_text_utils.dart';

/// Mostra corpo de post (evento/aviso) com formatação Quill; fallback para texto sem Delta.
class ChurchPostRichTextViewer extends StatefulWidget {
  final Map<String, dynamic> data;
  final double? maxHeight;
  final EdgeInsets padding;

  const ChurchPostRichTextViewer({
    super.key,
    required this.data,
    this.maxHeight = 360,
    this.padding = const EdgeInsets.only(bottom: 4),
  });

  @override
  State<ChurchPostRichTextViewer> createState() =>
      _ChurchPostRichTextViewerState();
}

class _ChurchPostRichTextViewerState extends State<ChurchPostRichTextViewer> {
  late QuillController _controller;
  late ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _controller = QuillController(
      document: churchPostDocumentFromData(widget.data),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
  }

  @override
  void didUpdateWidget(covariant ChurchPostRichTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (churchPostRichContentSig(widget.data) !=
        churchPostRichContentSig(oldWidget.data)) {
      _controller.dispose();
      _controller = QuillController(
        document: churchPostDocumentFromData(widget.data),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
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

    final editor = Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.transparent,
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
            scrollable: true,
            expands: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            autoFocus: false,
            showCursor: false,
            enableInteractiveSelection: true,
            enableSelectionToolbar: true,
            maxHeight: widget.maxHeight,
          ),
        ),
      ),
    );

    return Padding(
      padding: widget.padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: widget.maxHeight != null
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight!),
                  child: editor,
                )
              : editor,
        ),
      ),
    );
  }
}
