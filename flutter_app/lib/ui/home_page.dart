import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openChurchDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final slug = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Acessar minha igreja'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Nome da igreja (slug)',
              hintText: 'ex: iobpc-jardim-goiano',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Acessar'),
            ),
          ],
        );
      },
    );

    if (slug == null || slug.isEmpty) return;
    // /igreja/<slug>
    if (!context.mounted) return;
    Navigator.pushNamed(context, '/igreja/$slug');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth >= 980;
            return SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Image.asset('assets/logo.png', height: 38),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Gestão YAHWEH',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (isWide) ...[
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/'),
                            child: const Text('Início'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/planos'),
                            child: const Text('Planos'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/signup'),
                            child: const Text('Cadastrar igreja'),
                          ),
                          TextButton(
                            onPressed: () => _openChurchDialog(context),
                            child: const Text('Igrejas'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        OutlinedButton(
                          onPressed: () => Navigator.pushNamed(context, '/admin'),
                          child: const Text('Entrar (ADM)'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _openChurchDialog(context),
                          child: const Text('Acessar minha igreja'),
                        ),
                      ],
                    ),
                  ),

                  // Hero
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _HeroLeft(theme: theme, onOpenChurch: () => _openChurchDialog(context))),
                                const SizedBox(width: 18),
                                const Expanded(child: _HeroRight()),
                              ],
                            )
                          : Column(
                              children: [
                                _HeroLeft(theme: theme, onOpenChurch: () => _openChurchDialog(context)),
                                const SizedBox(height: 18),
                                const _HeroRight(),
                              ],
                            ),
                    ),
                  ),

                  // Highlights
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Acessos rápidos',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              _QuickCard(
                                title: 'Administrador',
                                subtitle: 'Gerencie igrejas, planos e usuários.',
                                button: 'Entrar no painel',
                                onTap: () => Navigator.pushNamed(context, '/admin'),
                                icon: Icons.admin_panel_settings,
                              ),
                              _QuickCard(
                                title: 'Minha Igreja',
                                subtitle: 'Acesse o site público e o sistema.',
                                button: 'Acessar agora',
                                onTap: () => _openChurchDialog(context),
                                icon: Icons.church,
                              ),
                              _QuickCard(
                                title: 'Planos',
                                subtitle: 'Veja preços e comece o teste grátis.',
                                button: 'Ver planos',
                                onTap: () => Navigator.pushNamed(context, '/planos'),
                                icon: Icons.payments,
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                        ],
                      ),
                    ),
                  ),

                  // Footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: const Center(
                      child: Text(
                        '© Gestão YAHWEH • Simples, completo e do seu jeito.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroLeft extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onOpenChurch;
  const _HeroLeft({required this.theme, required this.onOpenChurch});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gestão YAHWEH',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          'Plataforma moderna para gestão de igrejas, membros, escalas, finanças e comunicação.',
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.black87, height: 1.35),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ElevatedButton(
              onPressed: onOpenChurch,
              child: const Text('Acessar minha igreja'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/admin'),
              child: const Text('Login Administrador'),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/planos'),
              child: const Text('Ver planos'),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              child: const Text('Cadastrar igreja'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _Pill(text: '✅ Login por CPF'),
            _Pill(text: '✅ Teste grátis'),
            _Pill(text: '✅ Web + App'),
            _Pill(text: '✅ Firebase + Segurança'),
          ],
        )
      ],
    );
  }
}

class _HeroRight extends StatelessWidget {
  const _HeroRight();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('O que você gerencia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const _CheckRow(text: 'Membros e cadastro completo'),
            const _CheckRow(text: 'Escalas e notificações'),
            const _CheckRow(text: 'Eventos e mural de avisos'),
            const _CheckRow(text: 'Financeiro e relatórios'),
            const _CheckRow(text: 'Carteirinhas e documentos'),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFF7F8FA),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'Pronto para começar? Clique em “Acessar minha igreja” e entre pelo CPF.',
                style: TextStyle(height: 1.25),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String button;
  final VoidCallback onTap;
  final IconData icon;

  const _QuickCard({
    required this.title,
    required this.subtitle,
    required this.button,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFFF0F4FF),
                    ),
                    child: Icon(icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(subtitle, style: const TextStyle(color: Colors.black87, height: 1.25)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  child: Text(button),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String text;
  const _CheckRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
