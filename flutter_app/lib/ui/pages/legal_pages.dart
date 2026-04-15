import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Data exibida no topo dos documentos (atualizar quando o texto mudar).
const String kLegalDocumentsLastUpdated = 'Abril de 2026';

/// Contato para dúvidas (termos, privacidade e suporte).
const String kLegalSupportEmail = 'raihom@gmail.com';
const String kLegalSupportWhatsAppDisplay = '(62) 9 9170-5247';

/// Mesmo número que [kLegalSupportWhatsAppDisplay], para `wa.me/…` (E.164 BR).
const String kLegalSupportWhatsAppWaMe = '5562991705247';

/// Nome exibido no rodapé de divulgação / site público.
const String kDeveloperPublicName = 'Raihom Barbosa';

// --- Termos de Uso (estrutura inspirada no Controle Total, texto Gestão YAHWEH) ---

class TermosDeUsoPage extends StatelessWidget {
  /// Quando [true], oculta AppBar/barra inferior para uso dentro de modal premium.
  final bool embeddedInDialog;

  const TermosDeUsoPage({super.key, this.embeddedInDialog = false});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScaffold(
      embeddedInDialog: embeddedInDialog,
      heroIcon: Icons.gavel_rounded,
      heroSubtitle: 'Gestão YAHWEH — Última atualização: $kLegalDocumentsLastUpdated',
      title: 'Termos de Uso',
      intro:
          'Leia atentamente estes Termos de Uso antes de utilizar o Gestão YAHWEH. '
          'Documento elaborado em observância à legislação brasileira aplicável, '
          'incluindo a Lei Geral de Proteção de Dados (Lei nº 13.709/2018), quando pertinente.',
      sections: [
        _LegalSection(
          title: '1. Aceitação',
          body:
              'Ao utilizar o Gestão YAHWEH (aplicativo, painel web e funcionalidades disponíveis), '
              'você concorda com estes Termos de Uso e com a Política de Privacidade. '
              'Se não concordar, não utilize o serviço.',
        ),
        _LegalSection(
          title: '2. Serviço',
          body:
              'O Gestão YAHWEH oferece ferramentas para gestão eclesiástica e administrativa: '
              'cadastro de membros e visitantes, departamentos, escalas e agendas, comunicação '
              '(avisos, notificações, mural), documentos (certificados, carteirinhas), finanças, '
              'patrimônio e demais módulos conforme o plano contratado. O acesso pode ser feito '
              'por celular, tablet ou computador (incluindo versão web/PWA). '
              'O ambiente é pensado para ser limpo e seguro, sem propagandas indesejadas no produto. '
              'Funcionalidades e limites seguem o plano Premium ou equivalente contratado pela igreja.',
        ),
        _LegalSection(
          title: '3. Conta e licença',
          body:
              'Você é responsável por manter a confidencialidade do login e pela atividade realizada '
              'na sua conta. O acesso depende de licença ativa (período de teste, assinatura ou '
              'condições comerciais vigentes). Licença vencida ou suspensa pode restringir o uso '
              'conforme a política do serviço e o contrato com a igreja.',
        ),
        _LegalSection(
          title: '4. Uso adequado',
          body:
              'Você se compromete a usar o app de forma lícita, sem prejudicar terceiros ou o serviço. '
              'É proibido o uso para atividades ilegais, envio de conteúdo ofensivo, violação de '
              'direitos de terceiros ou tentativas de acesso não autorizado.',
        ),
        _LegalSection(
          title: '5. Propriedade intelectual',
          body:
              'Todo o conteúdo e a tecnologia do Gestão YAHWEH são de propriedade do desenvolvedor '
              'ou licenciados para uso no produto. Você tem direito de usar o serviço conforme '
              'previsto nestes termos, sem copiar ou distribuir o software de forma indevida.',
        ),
        _LegalSection(
          title: '6. Pagamentos',
          body:
              'Os planos pagos podem ser processados via Mercado Pago (PIX ou cartão, conforme '
              'disponibilizado). As condições de reembolso seguem a política do Mercado Pago e '
              'podem ser solicitadas diretamente à plataforma, quando aplicável.',
        ),
        _LegalSection(
          title: '7. Limitação de responsabilidade',
          body:
              'O app é fornecido “como está”, no limite da lei aplicável. Não nos responsabilizamos '
              'por decisões pastorais, financeiras ou administrativas tomadas com base nos dados '
              'ou relatórios gerados — recomenda-se validação por responsáveis competentes quando necessário.',
        ),
        _LegalSection(
          title: '8. Alterações',
          body:
              'Podemos alterar estes termos. Alterações significativas serão comunicadas por meios '
              'razoáveis (aplicativo, painel ou e-mail). O uso continuado após as alterações pode '
              'indicar aceitação, sem prejuízo dos seus direitos legais.',
        ),
        _LegalSection(
          title: '9. Contato',
          body:
              'Dúvidas sobre estes Termos de Uso: $kLegalSupportEmail ou WhatsApp $kLegalSupportWhatsAppDisplay.',
        ),
      ],
    );
  }
}

// --- Política de Privacidade ---

class PoliticaPrivacidadePage extends StatelessWidget {
  final bool embeddedInDialog;

  const PoliticaPrivacidadePage({super.key, this.embeddedInDialog = false});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScaffold(
      embeddedInDialog: embeddedInDialog,
      heroIcon: Icons.verified_user_rounded,
      heroSubtitle: 'Gestão YAHWEH — Última atualização: $kLegalDocumentsLastUpdated',
      title: 'Política de Privacidade',
      intro:
          'O Gestão YAHWEH respeita a sua privacidade. Este documento descreve como tratamos '
          'dados pessoais no contexto do aplicativo e do painel web, em linha com a LGPD '
          '(Lei nº 13.709/2018) e demais normas aplicáveis.',
      sections: [
        _LegalSection(
          title: '1. Informações que coletamos',
          body:
              'Podem ser tratados, conforme os módulos utilizados: nome, e-mail, telefone, CPF '
              '(quando informado), dados de cadastro pastoral e administrativo, departamentos, '
              'escalas, finanças da igreja, ocorrências, preferências e configurações da conta. '
              'O login pode ocorrer por CPF/e-mail, Google ou Apple, conforme disponível na versão. '
              'Também podem ser tratados dados técnicos necessários ao funcionamento (tokens de '
              'notificação, logs de segurança, identificadores de sessão).',
        ),
        _LegalSection(
          title: '2. Uso dos dados',
          body:
              'Utilizamos os dados para prestar o serviço, personalizar a experiência no painel, '
              'enviar comunicações relacionadas à conta e aos planos quando necessário, e '
              'reforçar a segurança. O produto é voltado à gestão da igreja, sem exibir anúncios '
              'de terceiros no aplicativo.',
        ),
        _LegalSection(
          title: '3. Armazenamento e segurança',
          body:
              'Os dados são armazenados em infraestrutura segura (Firebase / Google Cloud). '
              'Aplicamos medidas técnicas e administrativas para proteger suas informações contra '
              'acesso não autorizado, em conformidade com o risco e com a LGPD.',
        ),
        _LegalSection(
          title: '4. Compartilhamento',
          body:
              'Não vendemos seus dados. Podemos compartilhar informações apenas quando exigido '
              'por lei ou para processar pagamentos via Mercado Pago (ou outro meio contratado), '
              'conforme políticas desses provedores. Dados entre usuários da mesma igreja seguem '
              'as permissões definidas pela liderança.',
        ),
        _LegalSection(
          title: '5. Seus direitos',
          body:
              'Nos termos da LGPD, você pode solicitar acesso, correção ou exclusão dos seus dados, '
              'entre outros direitos previstos em lei. Para isso, entre em contato pelo e-mail ou '
              'WhatsApp indicados abaixo ou pelos canais de suporte no aplicativo.',
        ),
        _LegalSection(
          title: '6. Atualizações',
          body:
              'Esta política pode ser atualizada. Alterações significativas serão comunicadas no app '
              'ou por e-mail, quando razoável. O uso continuado após alterações pode indicar ciência, '
              'sem prejuízo dos direitos do titular.',
        ),
        _LegalSection(
          title: '7. Biometria e reconhecimento facial (Face ID)',
          body:
              'O app não coleta, não armazena e não envia ao servidor imagens do rosto, mapas '
              'faciais ou templates biométricos.\n\n'
              'O uso de Face ID ou impressão digital é opcional e serve apenas para desbloquear '
              'uma sessão já autenticada neste aparelho, por meio da API de autenticação local do '
              'sistema operacional. O processamento biométrico ocorre no dispositivo; não recebemos '
              'esses dados biométricos.\n\n'
              'Não compartilhamos dados faciais com terceiros porque não temos acesso a eles. '
              'Podemos guardar apenas uma preferência (por exemplo, se o desbloqueio por biometria '
              'está ativado), sem dados biométricos.\n\n'
              'Não há retenção de dados faciais pelo Gestão YAHWEH, pois esses dados não são '
              'transmitidos aos nossos sistemas.',
        ),
        _LegalSection(
          title: '8. Contato',
          body:
              'Dúvidas sobre privacidade: $kLegalSupportEmail ou WhatsApp $kLegalSupportWhatsAppDisplay.',
        ),
      ],
    );
  }
}

// --- Layout ultra premium ---

class _LegalAppBarBrand extends StatelessWidget {
  final String pageTitle;

  const _LegalAppBarBrand({required this.pageTitle});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return Row(
      children: [
        Image.asset(
          'assets/LOGO_GESTAO_YAHWEH.png',
          height: narrow ? 24 : 28,
          width: narrow ? 24 : 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.church_rounded,
            color: Colors.white,
            size: narrow ? 24 : 28,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gestão YAHWEH',
                style: TextStyle(
                  fontSize: narrow ? 9.5 : 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.88),
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                pageTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: narrow ? 13.5 : 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection({
    required this.title,
    required this.body,
  });
}

class _LegalDocumentScaffold extends StatelessWidget {
  final IconData heroIcon;
  final String heroSubtitle;
  final String title;
  final String intro;
  final List<_LegalSection> sections;
  final bool embeddedInDialog;

  const _LegalDocumentScaffold({
    required this.heroIcon,
    required this.heroSubtitle,
    required this.title,
    required this.intro,
    required this.sections,
    this.embeddedInDialog = false,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final bottomPad = embeddedInDialog ? 28.0 : 100.0;

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      extendBodyBehindAppBar: false,
      appBar: embeddedInDialog
          ? null
          : AppBar(
              toolbarHeight: 52,
              title: _LegalAppBarBrand(pageTitle: title),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                tooltip: 'Voltar',
                onPressed: () => Navigator.maybePop(context),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text(
                    'Fechar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 16 : 28,
                  embeddedInDialog ? 12 : 20,
                  isNarrow ? 16 : 28,
                  bottomPad,
                ),
                children: [
                  _PremiumHero(
                    icon: heroIcon,
                    subtitle: heroSubtitle,
                    title: title,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    intro,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final section in sections) ...[
                    _PremiumSectionCard(section: section),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Gestão YAHWEH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: embeddedInDialog
          ? null
          : Material(
              elevation: 12,
              shadowColor: Colors.black26,
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          label: const Text('Voltar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.primary,
                            side: BorderSide(
                              color: ThemeCleanPremium.primary.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Entendi'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PremiumHero extends StatelessWidget {
  final IconData icon;
  final String subtitle;
  final String title;

  const _PremiumHero({
    required this.icon,
    required this.subtitle,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary,
            Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.15)!,
          ],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.92),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumSectionCard extends StatelessWidget {
  final _LegalSection section;

  const _PremiumSectionCard({
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: ThemeCleanPremium.primary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            section.body,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre Termos ou Privacidade num painel premium (fade + scale), sem perder o contexto da página.
Future<void> showGestaoYahwehLegalPreview(
  BuildContext context, {
  required bool isPoliticaPrivacidade,
}) {
  final theme = Theme.of(context);
  final barrierLabel = MaterialLocalizations.of(context).modalBarrierDismissLabel;
  final title =
      isPoliticaPrivacidade ? 'Política de Privacidade' : 'Termos de Uso';
  final icon =
      isPoliticaPrivacidade ? Icons.verified_user_rounded : Icons.gavel_rounded;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: barrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final h = MediaQuery.sizeOf(ctx).height;
      final dialogH = (h * 0.9).clamp(420.0, h - 24);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: dialogH,
              ),
              child: Material(
                color: Colors.transparent,
                elevation: 0,
                shadowColor: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LegalPreviewHeader(
                        title: title,
                        icon: icon,
                        onClose: () => Navigator.of(ctx).pop(),
                      ),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                          ),
                          child: isPoliticaPrivacidade
                              ? const PoliticaPrivacidadePage(
                                  embeddedInDialog: true,
                                )
                              : const TermosDeUsoPage(embeddedInDialog: true),
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
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.93, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _LegalPreviewHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onClose;

  const _LegalPreviewHeader({
    required this.title,
    required this.icon,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary,
            Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.14)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'GESTÃO YAHWEH',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.88),
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.35,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Documento oficial — leitura integral',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
