import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gestao_yahweh/services/utilitarios_daily_quota_service.dart';
import 'package:gestao_yahweh/services/utilitarios_local_service.dart';
import 'package:gestao_yahweh/services/utilitarios_photo_text_extract_service.dart';
import 'package:gestao_yahweh/utils/utilitarios_file_io.dart';
import 'package:gestao_yahweh/ui/pages/utilitarios_module_ui_compat.dart';

/// Abre o fluxo «Extração de texto em foto» (estilo Google Lens).
Future<void> openUtilitariosPhotoTextExtractFlow(
  BuildContext context, {
  required String quotaUid,
  required bool isAdmin,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoTextExtractPage(
        quotaUid: quotaUid,
        isAdmin: isAdmin,
      ),
    ),
  );
}

class _PhotoTextExtractPage extends StatefulWidget {
  const _PhotoTextExtractPage({
    required this.quotaUid,
    required this.isAdmin,
  });

  final String quotaUid;
  final bool isAdmin;

  @override
  State<_PhotoTextExtractPage> createState() => _PhotoTextExtractPageState();
}

class _PhotoTextExtractPageState extends State<_PhotoTextExtractPage> {
  static const _gradient = [
    Color(0xFF0EA5E9),
    Color(0xFF6366F1),
    Color(0xFF7C3AED),
  ];

  final _picker = ImagePicker();
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();

  bool _busy = false;
  String? _busyLabel;
  Uint8List? _previewImage;
  List<UtilPhotoTextParagraph> _paragraphs = const [];
  String? _sourceName;

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _hasText => _textCtrl.text.trim().isNotEmpty;

  Future<void> _withBusy(String label, Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('StateError: ', '').replaceFirst('Bad state: ', ''),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _pickAndExtract(ImageSource source) async {
    await _withBusy('Abrindo…', () async {
      Uint8List bytes;
      String name;
      if (source == ImageSource.camera) {
        final x = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
          maxWidth: 4096,
        );
        if (x == null) return;
        bytes = await x.readAsBytes();
        name = x.name;
      } else {
        final files = await utilitariosPickPlatformFiles(
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          preferBytes: true,
        );
        if (files.isEmpty) return;
        final f = files.first;
        bytes = await utilitariosReadPlatformFileBytes(f);
        name = f.name;
      }
      if (bytes.isEmpty) throw StateError('Imagem vazia.');
      await _runExtraction(bytes, sourceName: name);
    });
  }

  Future<void> _runExtraction(Uint8List bytes, {String? sourceName}) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Extraindo texto (IA local)…';
    });
    try {
      final r = await UtilitariosPhotoTextExtractService.extractFromImage(bytes);
      if (!mounted) return;
      setState(() {
        _previewImage = r.sourcePreview;
        _paragraphs = r.paragraphs;
        _sourceName = sourceName;
        _textCtrl.text = r.plainText;
      });
      await UtilitariosDailyQuotaService.consumeLight(
        widget.quotaUid,
        isAdmin: widget.isAdmin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('StateError: ', '').replaceFirst('Bad state: ', ''),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  List<UtilPhotoTextParagraph> _paragraphsFromEditedText() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return const [];
    final headingByText = {
      for (final p in _paragraphs) p.text.trim(): p.isHeading,
    };
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map(
          (p) => UtilPhotoTextParagraph(
            text: p,
            isHeading:
                headingByText[p] ?? UtilitariosLocalService.looksLikeDocumentHeading(p),
          ),
        )
        .toList();
  }

  String _exportStem() {
    final base = (_sourceName ?? 'texto_foto')
        .replaceAll(RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false), '');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${base.isEmpty ? 'texto_foto' : base}_$stamp';
  }

  Future<void> _exportWord() async {
    if (!_hasText) return;
    await _withBusy('Gerando Word…', () async {
      final paras = _paragraphsFromEditedText();
      final bytes = UtilitariosPhotoTextExtractService.buildDocx(paras);
      if (!mounted) return;
      await _showExportSheet(
        bytes: bytes,
        fileName: '${_exportStem()}.docx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        label: 'Word (.docx)',
      );
    });
  }

  Future<void> _exportPdf() async {
    if (!_hasText) return;
    await _withBusy('Gerando PDF…', () async {
      final bytes = await UtilitariosPhotoTextExtractService.buildPdf(_textCtrl.text);
      if (!mounted) return;
      await _showExportSheet(
        bytes: bytes,
        fileName: '${_exportStem()}.pdf',
        mimeType: 'application/pdf',
        label: 'PDF',
      );
    });
  }

  Future<void> _copyText() async {
    if (!_hasText) return;
    await Clipboard.setData(ClipboardData(text: _textCtrl.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Texto copiado.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showExportSheet({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String label,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: ModernModuleUI.previewSheetDecoration(ctx, radius: 22),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Arquivo pronto',
                style: ModernModuleUI.moduleTitleStyle(ctx, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                '$label gerado localmente no aparelho.',
                style: ModernModuleUI.moduleSubtitleStyle(ctx),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'share'),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Compartilhar'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'save'),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Salvar no aparelho'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    final ok = await utilitariosSaveOrShareBytes(
      context: context,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      preferShare: action == 'share',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (action == 'share'
                  ? 'Escolha WhatsApp, e-mail ou outro app.'
                  : 'Arquivo salvo em Utilitarios_GestaoYahweh.')
              : 'Não foi possível exportar.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _resetToPicker() {
    setState(() {
      _previewImage = null;
      _paragraphs = const [];
      _sourceName = null;
      _textCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _previewImage != null && _hasText;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Extração de texto em foto'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        actions: [
          if (hasPreview)
            TextButton.icon(
              onPressed: _busy ? null : _resetToPicker,
              icon: const Icon(Icons.photo_camera_rounded, size: 20),
              label: const Text('Nova foto'),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (!hasPreview) _buildPickerBody() else _buildPreviewBody(),
          if (_busy) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildPickerBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _gradient.map((c) => c.withValues(alpha: 0.12)).toList(),
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _gradient.first.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _gradient),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _gradient.first.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.document_scanner_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Estilo Google Lens',
                  style: ModernModuleUI.moduleTitleStyle(context, fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tire uma foto ou escolha da galeria. O app extrai o texto, '
                  'mostra um preview editável e gera Word ou PDF.',
                  textAlign: TextAlign.center,
                  style: ModernModuleUI.moduleSubtitleStyle(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ModernModuleUI.centeredPickButton(
            gradient: _gradient,
            icon: Icons.photo_camera_rounded,
            label: 'Câmera',
            onPressed: _busy ? null : () => _pickAndExtract(ImageSource.camera),
          ),
          const SizedBox(height: 10),
          ModernModuleUI.centeredPickButton(
            gradient: const [Color(0xFFDB2777), Color(0xFF7C3AED)],
            icon: Icons.photo_library_rounded,
            label: 'Galeria',
            onPressed: _busy ? null : () => _pickAndExtract(ImageSource.gallery),
            secondary: true,
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 14),
            Text(
              'Na web o OCR usa visão em nuvem (login) ou Textify local.',
              textAlign: TextAlign.center,
              style: ModernModuleUI.moduleSubtitleStyle(context, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewBody() {
    final chars = _textCtrl.text.length;
    final words = _textCtrl.text.trim().isEmpty
        ? 0
        : _textCtrl.text.trim().split(RegExp(r'\s+')).length;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              if (_previewImage != null)
                Image.memory(
                  _previewImage!,
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: _gradient.first.withValues(alpha: 0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: _gradient.last,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Texto extraído',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$chars caracteres · $words palavras'
                        '${_paragraphs.where((p) => p.isHeading).isNotEmpty ? ' · ${_paragraphs.where((p) => p.isHeading).length} títulos' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Edite abaixo antes de exportar.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _miniAction(
                icon: Icons.copy_rounded,
                label: 'Copiar',
                onTap: _busy || !_hasText ? null : _copyText,
              ),
              const SizedBox(width: 8),
              _miniAction(
                icon: Icons.description_rounded,
                label: 'Word',
                color: const Color(0xFF2563EB),
                onTap: _busy || !_hasText ? null : _exportWord,
              ),
              const SizedBox(width: 8),
              _miniAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF',
                color: const Color(0xFFDC2626),
                onTap: _busy || !_hasText ? null : _exportPdf,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _gradient.first.withValues(alpha: 0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _gradient.last.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Scrollbar(
              controller: _scrollCtrl,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: TextField(
                  controller: _textCtrl,
                  focusNode: _focusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Texto extraído aparecerá aqui…',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || !_hasText ? null : _exportWord,
                    icon: const Icon(Icons.description_rounded),
                    label: const Text('Gerar Word'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: const Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || !_hasText ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('Gerar PDF'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: const Color(0xFF7C3AED),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final c = color ?? _gradient.first;
    return Expanded(
      child: Material(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, color: c, size: 20),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: c,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBusyOverlay() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: _gradient),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _gradient.last.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _busyLabel ?? 'Processando…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
