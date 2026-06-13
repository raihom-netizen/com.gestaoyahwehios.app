import 'package:flutter/material.dart';

/// Permite selecionar e copiar textos do sistema e digitados pelo usuário
/// (Web, Android, iOS, site público, cadastro membro, painel master).
///
/// Envolve o subtree em [SelectionArea] — [Text], [RichText] e campos
/// de formulário continuam editáveis com seleção própria.
class GestaoYahwehSelectableScope extends StatelessWidget {
  const GestaoYahwehSelectableScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(child: child);
  }
}
