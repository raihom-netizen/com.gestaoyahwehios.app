import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_update_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';

/// Alvo do comprovante — financeiro ou compromisso de fornecedor.
enum FinanceComprovanteEditorTarget {
  financeLancamento,
  fornecedorCompromisso,
}

/// Estado local do editor (formulário — envio no Salvar).
class FinanceComprovanteEditorSnapshot {
  const FinanceComprovanteEditorSnapshot({
    this.pending,
    this.removeExisting = false,
  });

  final FinanceComprovanteAttachment? pending;
  final bool removeExisting;

  bool get hasPending => pending != null;
}

/// Editor de comprovante — Galeria / Câmera / Arquivo (padrão Controle Total).
class FinanceComprovanteEditor extends StatefulWidget {
  const FinanceComprovanteEditor({
    super.key,
    required this.churchIdHint,
    required this.target,
    required this.canAdd,
    required this.canChange,
    required this.canRemove,
    this.lancamentoId,
    this.referenceDate,
    this.fornecedorId,
    this.compromissoId,
    this.existingData,
    this.onChanged,
  });

  final String churchIdHint;
  final FinanceComprovanteEditorTarget target;
  final bool canAdd;
  final bool canChange;
  final bool canRemove;
  final String? lancamentoId;
  final DateTime? referenceDate;
  final String? fornecedorId;
  final String? compromissoId;
  final Map<String, dynamic>? existingData;
  final ValueChanged<FinanceComprovanteEditorSnapshot>? onChanged;

  @override
  State<FinanceComprovanteEditor> createState() =>
      FinanceComprovanteEditorState();
}

class FinanceComprovanteEditorState extends State<FinanceComprovanteEditor> {
  FinanceComprovanteAttachment? _pending;
  bool _removeExisting = false;
  bool _picking = false;

  FinanceComprovanteEditorSnapshot get snapshot =>
      FinanceComprovanteEditorSnapshot(
        pending: _pending,
        removeExisting: _removeExisting,
      );

  bool get _hasExistingReady {
    if (_removeExisting) return false;
    return FinanceComprovanteAttachService.hasComprovanteReady(
      widget.existingData ?? {},
    );
  }

  String get _storagePathHint {
    final cid = FinanceComprovanteUpdateService.resolveChurchId(
      widget.churchIdHint,
    );
    if (widget.target == FinanceComprovanteEditorTarget.financeLancamento) {
      final lid = (widget.lancamentoId ?? 'novo').trim();
      final ext = _pending != null
          ? FinanceComprovanteAttachService.extensionForMime(
              _pending!.mimeType,
            )
          : 'jpg';
      return FinanceComprovanteUpdateService.financeStoragePathHint(
        churchIdHint: cid,
        lancamentoId: lid.isEmpty ? 'novo' : lid,
        referenceDate: widget.referenceDate,
        ext: ext,
      );
    }
    final ext = _pending != null
        ? FinanceComprovanteAttachService.extensionForMime(_pending!.mimeType)
        : 'jpg';
    return FinanceComprovanteUpdateService.fornecedorStoragePathHint(
      churchIdHint: cid,
      fornecedorId: widget.fornecedorId ?? '',
      compromissoId: widget.compromissoId ?? 'novo',
      ext: ext,
    );
  }

  void _notify() => widget.onChanged?.call(snapshot);

  void _showSemPermissao() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Sem permissão para alterar comprovantes.',
      ),
    );
  }

  Future<void> _applyPicked(FinanceComprovanteAttachment? picked) async {
    if (picked == null || !mounted) return;
    setState(() {
      _pending = picked;
      _removeExisting = false;
    });
    _notify();
    ImmediateMediaAttachFeedback.showArquivoAnexado(context, picked.fileName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${picked.fileName} selecionado — toque «Salvar» para enviar.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _pickGallery() async {
    if (_picking) return;
    if (!(widget.canAdd || widget.canChange)) {
      _showSemPermissao();
      return;
    }
    setState(() => _picking = true);
    try {
      await _applyPicked(
        await FinanceComprovanteAttachService.pickFromGallery(context),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickCamera() async {
    if (_picking) return;
    if (!(widget.canAdd || widget.canChange)) {
      _showSemPermissao();
      return;
    }
    setState(() => _picking = true);
    try {
      await _applyPicked(
        await FinanceComprovanteAttachService.pickFromCamera(context),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickReplace() async {
    if (_picking) return;
    if (!(widget.canAdd || widget.canChange)) {
      _showSemPermissao();
      return;
    }
    setState(() => _picking = true);
    try {
      final picked = await FinanceComprovanteAttachService.showPickSheet(
        context,
        title: 'Trocar comprovante',
      );
      await _applyPicked(picked);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFile() async {
    if (_picking) return;
    if (!(widget.canAdd || widget.canChange)) {
      _showSemPermissao();
      return;
    }
    setState(() => _picking = true);
    try {
      await _applyPicked(
        await FinanceComprovanteAttachService.pickFromFiles(context),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirmRemoveExisting() async {
    if (!widget.canRemove || !_hasExistingReady) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Remover comprovante'),
        content: const Text(
          'O comprovante será removido deste registo e apagado do Storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _pending = null;
      _removeExisting = true;
    });
    _notify();
  }

  void _clearPending() {
    setState(() => _pending = null);
    _notify();
  }

  static String _formatBytes(int n) {
    if (n < 1000) return '$n bytes';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _pendingPreview(FinanceComprovanteAttachment pending) {
    if (pending.isPdf) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.picture_as_pdf_rounded,
          color: ThemeCleanPremium.primary,
          size: 28,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Image.memory(
          pending.bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _pending != null;
    final hasExisting = _hasExistingReady;
    final canPick = widget.canAdd || widget.canChange;
    final cor = ThemeCleanPremium.primary;

    Widget actionButtons() {
      if (!canPick) {
        return Text(
          'Sem permissão para anexar ou alterar comprovantes.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _picking ? null : () => unawaited(_pickGallery()),
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            label: const Text('Galeria'),
            style: FilledButton.styleFrom(
              backgroundColor: cor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _picking ? null : () => unawaited(_pickCamera()),
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            label: const Text('Câmera'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cor,
              side: BorderSide(color: cor.withValues(alpha: 0.55), width: 1.5),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _picking ? null : () => unawaited(_pickFile()),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: const Text('PDF / arquivo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cor,
              side: BorderSide(color: cor.withValues(alpha: 0.55), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.receipt_long_rounded, color: cor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPending
                              ? 'Pronto para enviar ao salvar'
                              : (hasExisting
                                  ? 'Comprovante gravado'
                                  : 'Sem comprovante'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'JPEG, PNG ou PDF — até 5 MB. Toque em Salvar para enviar.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Storage: $_storagePathHint',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              actionButtons(),
              if (_picking) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'A preparar ficheiro…',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (hasPending) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _pendingPreview(_pending!),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pending!.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${_formatBytes(_pending!.bytes.length)} · '
                      '${_pending!.mimeType} · será enviado ao salvar',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancelar novo anexo',
                onPressed: _clearPending,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                ),
              ),
            ],
          ),
        ] else if (!hasExisting && canPick) ...[
          const SizedBox(height: 8),
          Text(
            'Nenhum comprovante — use Galeria, Câmera ou PDF.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
        if (_removeExisting)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Comprovante marcado para remoção ao salvar.',
              style: TextStyle(
                fontSize: 12,
                color: ThemeCleanPremium.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (hasExisting && !hasPending && !_removeExisting) ...[
          const SizedBox(height: 10),
          Text(
            FinanceComprovanteAttachService.displayNameFromDoc(
              widget.existingData ?? {},
            ),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => FinanceComprovanteAttachService.viewFromDoc(
                  context,
                  widget.existingData ?? {},
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Ver'),
              ),
              if (widget.canChange)
                TextButton.icon(
                  onPressed: _picking ? null : () => unawaited(_pickReplace()),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Trocar'),
                ),
              if (widget.canRemove)
                TextButton.icon(
                  onPressed: _confirmRemoveExisting,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remover'),
                  style: TextButton.styleFrom(
                    foregroundColor: ThemeCleanPremium.error,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
