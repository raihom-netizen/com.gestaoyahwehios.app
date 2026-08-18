import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatFirebaseErrorForUser;
import 'package:gestao_yahweh/services/master_church_publication_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

class MasterChurchPublicationButton extends StatefulWidget {
  const MasterChurchPublicationButton({
    super.key,
    required this.churchId,
    required this.data,
    required this.canEdit,
  });

  final String churchId;
  final Map<String, dynamic> data;
  final bool canEdit;

  @override
  State<MasterChurchPublicationButton> createState() =>
      _MasterChurchPublicationButtonState();
}

class _MasterChurchPublicationButtonState
    extends State<MasterChurchPublicationButton> {
  bool? _published;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await MasterChurchPublicationService.isPublished(
        widget.churchId,
      );
      if (mounted) setState(() => _published = value);
    } catch (_) {
      if (mounted) setState(() => _published = false);
    }
  }

  Future<void> _toggle() async {
    if (!widget.canEdit || _busy) return;
    final next = !(_published ?? false);
    setState(() => _busy = true);
    try {
      await MasterChurchPublicationService.setPublished(
        churchId: widget.churchId,
        churchData: widget.data,
        published: next,
      );
      if (!mounted) return;
      setState(() {
        _published = next;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          next
              ? 'Igreja publicada na Galeria de Clientes.'
              : 'Igreja retirada da Galeria de Clientes.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Mensagem real: sem isto qualquer falha (permissão, rede, regra)
      // aparecia como o mesmo texto genérico e não dava para diagnosticar.
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.errorSnackBarWithRetry(
          'Não foi possível ${next ? 'publicar' : 'retirar'} na Galeria: '
          '${formatFirebaseErrorForUser(e)}',
          onRetry: _toggle,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _published == true;
    final label = active ? 'Publicado na Galeria' : 'Publicar na Galeria';
    final color = active ? const Color(0xFF0F8A63) : ThemeCleanPremium.primary;
    return Tooltip(
      message: active
          ? 'Retirar da Galeria de Clientes'
          : 'Publicar na Galeria de Clientes',
      child: OutlinedButton.icon(
        onPressed: widget.canEdit && !_busy ? _toggle : null,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                active ? Icons.visibility_rounded : Icons.visibility_outlined,
                size: 17,
              ),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
