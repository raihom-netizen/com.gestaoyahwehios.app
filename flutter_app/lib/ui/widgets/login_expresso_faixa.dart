import 'package:flutter/material.dart';

/// Faixa flutuante «Login expresso» — réplica visual da faixa do app
/// «Controle Total» (gradiente escuro → teal, ícone flash, copy curto e
/// botão «Entrar» à direita).
///
/// Usada no rodapé da tela de login mobile do Gestão YAHWEH para oferecer
/// um caminho de 1 toque (Google silencioso → Apple no iOS → Google com UI).
class LoginExpressoFaixa extends StatelessWidget {
  /// Disparado tanto ao tocar na faixa inteira quanto no botão «Entrar».
  final VoidCallback onTap;

  /// Quando `true`, troca o ícone «Entrar» por um spinner branco e desabilita o toque.
  final bool loading;

  /// Texto principal (default: «Login expresso»).
  final String title;

  /// Texto auxiliar (default: «Clique aqui e use e-mail salvo do navegador/celular»).
  final String subtitle;

  /// Texto do botão à direita (default: «Entrar»).
  final String buttonLabel;

  /// Padding externo da faixa (default 14/0/14/10 — alinha com o footer da landing).
  final EdgeInsetsGeometry padding;

  const LoginExpressoFaixa({
    super.key,
    required this.onTap,
    this.loading = false,
    this.title = 'Login expresso',
    this.subtitle = 'Clique aqui e use e-mail salvo do navegador/celular',
    this.buttonLabel = 'Entrar',
    this.padding = const EdgeInsets.fromLTRB(14, 0, 14, 10),
  });

  static const Color _violet = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = loading ? null : onTap;
    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF111827), Color(0xFF1F2937), Color(0xFF0F766E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: _violet.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: effectiveOnTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.flash_on_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFFD1FAE5),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: effectiveOnTap,
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login_rounded, size: 18),
                      label: Text(buttonLabel),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
