import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';

/// Avatar do gestor/usuário no header (shell): mesma pipeline que [FotoMembroWidget]
/// (Storage seguro na web + cache), com chave estável para menos “piscar” ao trocar de aba.
class AvatarGestorWidget extends StatelessWidget {
  final String? imageUrl;
  final String tenantId;
  /// Documento em `membros` ou CPF normalizado (fallback no Storage).
  final String memberDocIdOrCpf;
  final double size;

  const AvatarGestorWidget({
    super.key,
    this.imageUrl,
    required this.tenantId,
    required this.memberDocIdOrCpf,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final cpf = memberDocIdOrCpf.replaceAll(RegExp(r'\D'), '');
    return FotoMembroWidget(
      key: ValueKey<String>('avatar_gestor_${tenantId}_$memberDocIdOrCpf'),
      imageUrl: imageUrl,
      tenantId: tenantId,
      memberId: memberDocIdOrCpf.trim(),
      cpfDigits: cpf.length >= 9 ? cpf : null,
      size: size,
      memCacheWidth: 150,
      memCacheHeight: 150,
      backgroundColor: Colors.white.withValues(alpha: 0.25),
      fallbackIcon: Icons.person_rounded,
    );
  }
}
