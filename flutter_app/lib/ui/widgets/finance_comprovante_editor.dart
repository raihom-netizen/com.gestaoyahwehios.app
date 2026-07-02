import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/finance_comprovante_attach_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_update_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

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

/// Editor de comprovante — adicionar, trocar, remover (permissões explícitas).
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
      return FinanceComprovanteUpdateService.financeStoragePathHint(
        churchIdHint: cid,
        lancamentoId: lid.isEmpty ? 'novo' : lid,
        referenceDate: widget.referenceDate,
      );
    }
    return FinanceComprovanteUpdateService.fornecedorStoragePathHint(
      churchIdHint: cid,
      fornecedorId: widget.fornecedorId ?? '',
      compromissoId: widget.compromissoId ?? 'novo',
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

  Future<void> _pick() async {
    final canPick = widget.canAdd || widget.canChange;
    if (!canPick) {
      _showSemPermissao();
      return;
    }
    final picked = await FinanceComprovanteUpdateService.pickAttachment(
      context,
      canAdd: widget.canAdd,
      canChange: widget.canChange,
      hasExisting: _hasExistingReady || _pending != null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pending = picked;
      _removeExisting = false;
    });
    _notify();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${picked.fileName} selecionado — toque «Salvar» para enviar.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final hasPending = _pending != null;
    final hasExisting = _hasExistingReady;
    final canPick = widget.canAdd || widget.canChange;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Storage: $_storagePathHint',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        if (canPick)
          OutlinedButton.icon(
            onPressed: _pick,
            icon: Icon(
              hasPending || hasExisting
                  ? Icons.check_circle_rounded
                  : Icons.add_photo_alternate_rounded,
              size: 20,
            ),
            label: Text(
              hasPending
                  ? 'Pronto para enviar ao salvar'
                  : (hasExisting
                      ? 'Comprovante gravado — trocar'
                      : 'Anexar comprovante'),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: hasPending || hasExisting
                  ? ThemeCleanPremium.success
                  : null,
            ),
          )
        else
          Text(
            'Sem permissão para anexar ou alterar comprovantes.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        if (hasPending) ...[
          const SizedBox(height: 6),
          Text(
            _pending!.fileName,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          TextButton.icon(
            onPressed: _clearPending,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancelar novo anexo'),
            style: TextButton.styleFrom(
              foregroundColor: ThemeCleanPremium.error,
            ),
          ),
        ],
        if (_removeExisting)
          Padding(
            padding: const EdgeInsets.only(top: 6),
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              FinanceComprovanteAttachService.displayNameFromDoc(
                widget.existingData ?? {},
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
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
                  onPressed: _pick,
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
