import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/legal_document_models.dart';
import 'package:gestao_yahweh/services/legal_documents_defaults.dart';
import 'package:gestao_yahweh/services/legal_documents_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

export 'package:gestao_yahweh/services/legal_documents_defaults.dart'
    show
        kDeveloperPublicName,
        kLegalDocumentsLastUpdatedDefault,
        kLegalSupportEmail,
        kLegalSupportWhatsAppDisplay,
        kLegalSupportWhatsAppWaMe;

/// Alias legado — preferir [LegalDocumentsService] / `lastUpdatedLabel` remoto.
const String kLegalDocumentsLastUpdated = kLegalDocumentsLastUpdatedDefault;

// --- Termos de Uso ---

class TermosDeUsoPage extends StatelessWidget {
  /// Quando [true], oculta AppBar/barra inferior para uso dentro de modal premium.
  final bool embeddedInDialog;

  const TermosDeUsoPage({super.key, this.embeddedInDialog = false});

  @override
  Widget build(BuildContext context) {
    return _RemoteLegalDocumentView(
      embeddedInDialog: embeddedInDialog,
      heroIcon: Icons.gavel_rounded,
      pickContent: (b) => b.terms,
    );
  }
}

// --- Política de Privacidade ---

class PoliticaPrivacidadePage extends StatelessWidget {
  final bool embeddedInDialog;

  const PoliticaPrivacidadePage({super.key, this.embeddedInDialog = false});

  @override
  Widget build(BuildContext context) {
    return _RemoteLegalDocumentView(
      embeddedInDialog: embeddedInDialog,
      heroIcon: Icons.verified_user_rounded,
      pickContent: (b) => b.privacy,
    );
  }
}

class _RemoteLegalDocumentView extends StatelessWidget {
  final bool embeddedInDialog;
  final IconData heroIcon;
  final LegalDocumentContent Function(LegalDocumentsBundle bundle) pickContent;

  const _RemoteLegalDocumentView({
    required this.embeddedInDialog,
    required this.heroIcon,
    required this.pickContent,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LegalDocumentsBundle>(
      stream: LegalDocumentsService.watch(),
      initialData: LegalDocumentsService.peekCached(),
      builder: (context, snap) {
        final bundle = snap.data ?? LegalDocumentsDefaults.bundle;
        final doc = pickContent(bundle);
        return _LegalDocumentScaffold(
          embeddedInDialog: embeddedInDialog,
          heroIcon: heroIcon,
          heroSubtitle:
              'Gestão YAHWEH — Última atualização: ${bundle.lastUpdatedLabel}',
          title: doc.title,
          intro: doc.intro,
          sections: doc.sections,
        );
      },
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

class _LegalDocumentScaffold extends StatelessWidget {
  final IconData heroIcon;
  final String heroSubtitle;
  final String title;
  final String intro;
  final List<LegalSectionEntry> sections;
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
  final LegalSectionEntry section;

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
