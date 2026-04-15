import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Página que explica os níveis de acesso: Master (gestor geral), Gestor Local, ADM, Líder, Usuário. Super Premium, responsivo.
class AdminNiveisAcessoPage extends StatelessWidget {
  const AdminNiveisAcessoPage({super.key});

  static const Color menuBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Section(
              title: 'Gestor Master Geral',
              icon: Icons.admin_panel_settings_rounded,
              color: Colors.deepPurple,
              children: const [
                Text('• Controle total do sistema: todas as igrejas.'),
                SizedBox(height: 6),
                Text('• Pode remover, editar e criar qualquer dado (tenants, membros, usuários, assinaturas, vendas, licenças).'),
                SizedBox(height: 6),
                Text('• Acesso a todos os logs de auditoria (banco de dados, ações de usuários).'),
                SizedBox(height: 6),
                Text('• Único perfil que pode atribuir outro MASTER e operar em qualquer igreja.'),
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Gestor Local (GESTOR / ADM)',
              icon: Icons.business_center_rounded,
              color: menuBlue,
              children: const [
                Text('• Controla tudo dentro da sua igreja: membros, usuários, departamentos, escalas, financeiro.'),
                SizedBox(height: 6),
                Text('• Não vê e não pode alterar dados de outras igrejas.'),
                SizedBox(height: 6),
                Text('• Vê logs de auditoria apenas da própria igreja.'),
                SizedBox(height: 6),
                Text('• Pode ativar/inativar usuários e definir perfis (Líder, User) na sua igreja.'),
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Líder',
              icon: Icons.leaderboard_rounded,
              color: Colors.orange,
              children: const [
                Text('• Pode criar e editar escalas, eventos e publicações (mural/notícias).'),
                SizedBox(height: 6),
                Text('• Acesso somente aos dados da sua igreja, dentro do que o gestor local permitir.'),
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              title: 'Usuário (USER)',
              icon: Icons.person_rounded,
              color: Colors.grey,
              children: const [
                Text('• Acesso básico: ver escalas, eventos, perfil e o que for liberado pela igreja.'),
                SizedBox(height: 6),
                Text('• Acesso conforme permissões da igreja.'),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: menuBlue.withOpacity(0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: menuBlue, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'Gestor Master + Gestor Local',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Color(0xFF0D47A1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Você pode ser ao mesmo tempo o Gestor Master Geral e o Gestor Local de uma igreja (ex.: O Brasil Para Cristo). '
                      'Basta que, no Firebase Auth (custom claims), seu usuário tenha role = MASTER e igrejaId = ID da igreja em que você também é o gestor local. '
                      'Assim você controla tudo globalmente e, ao acessar essa igreja, age como gestor local dela.',
                      style: TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
