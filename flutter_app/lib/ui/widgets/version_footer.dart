import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/pages/legal_pages.dart';
import 'package:url_launcher/url_launcher.dart';

/// Versículo padrão no rodapé (igual ao Controle Total). Padronizado em site, app, web, igreja e cadastro.
const String kVersiculoRodape =
    'Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos.';
const String kVersiculoRef = 'Provérbios 16:3';

/// Rodapé padronizado: versículo + versão (v5.0). Usado em site divulgação, ADM, igrejas, cadastro e página pública.
class VersionFooter extends StatelessWidget {
  final bool showVersion;
  final String? versionLabel;
  final bool showLegalLinks;
  final String cnpjLabel;

  /// Quando o rodapé fica **acima** de um [NavigationBar]/barra do sistema, use `false`
  /// para não duplicar o padding inferior (evita faixa branca / rodapé “flutuando” no PWA).
  final bool safeAreaBottom;

  /// Na web, abre `/termodeuso` e `/privacidade` num **novo separador**
  /// (mantém a landing aberta). No app nativo, mantém navegação na mesma pilha.
  /// Só vale quando [useLegalPreviewModal] é `false`.
  final bool openLegalLinksInNewTab;

  /// Na **web**, com `true`, abre Termos/Privacidade num **modal premium** (fade + scale), como no site público.
  /// No **app Android/iOS**, o mesmo `true` abre a **tela completa** com o documento inteiro (equivalente a `/termodeuso` e `/privacidade` no site), não o diálogo compacto.
  final bool useLegalPreviewModal;

  /// Mini-links YouTube / Instagram (ícones Material — fiáveis na web). `false` no painel ADM se quiser rodapé só legal.
  final bool showOfficialSocialLinks;

  const VersionFooter({
    super.key,
    this.showVersion = true,
    this.versionLabel,
    this.showLegalLinks = true,
    this.cnpjLabel = 'CNPJ: não informado',
    this.safeAreaBottom = true,
    this.openLegalLinksInNewTab = false,
    this.useLegalPreviewModal = true,
    this.showOfficialSocialLinks = true,
  });

  static const Color _accentBlue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final paddingH = isNarrow ? 10.0 : 16.0;
    final paddingV = isNarrow ? 4.0 : 5.0;
    final verseSize = isNarrow ? 9.5 : 10.0;
    final metaSize = isNarrow ? 8.5 : 9.0;
    final versionStr = versionLabel ??
        (appVersionLabel.isNotEmpty ? appVersionLabel : 'v$appVersion');

    final metaStyle = TextStyle(fontSize: metaSize, color: Colors.grey[600]);
    final linkStyle = TextStyle(
      fontSize: metaSize,
      fontWeight: FontWeight.w600,
      color: _accentBlue,
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: paddingV, horizontal: paddingH),
      decoration: BoxDecoration(
        color: _accentBlue.withValues(alpha: 0.035),
        border: Border(
          top: BorderSide(color: _accentBlue.withValues(alpha: 0.12)),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: safeAreaBottom,
        left: true,
        right: true,
        minimum: EdgeInsets.zero,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: verseSize,
                      height: 1.22,
                      color: Colors.grey[700],
                    ),
                    children: [
                      TextSpan(
                        text: '"$kVersiculoRodape" ',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      TextSpan(
                        text: '— $kVersiculoRef',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _accentBlue,
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showVersion || showLegalLinks) SizedBox(height: isNarrow ? 3 : 4),
                if (showVersion || showLegalLinks)
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 0,
                    runSpacing: 2,
                    children: [
                      if (showVersion)
                        Text(versionStr, style: metaStyle),
                      if (showVersion && showLegalLinks)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('·', style: metaStyle),
                        ),
                      if (showLegalLinks) ...[
                        InkWell(
                          onTap: () => _openLegalPage(
                            context,
                            '/termodeuso',
                            openLegalLinksInNewTab,
                            useLegalPreviewModal,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: isNarrow ? 8 : 3,
                            ),
                            child: Text('Termos de uso', style: linkStyle),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('·', style: metaStyle),
                        ),
                        InkWell(
                          onTap: () => _openLegalPage(
                            context,
                            '/privacidade',
                            openLegalLinksInNewTab,
                            useLegalPreviewModal,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: isNarrow ? 8 : 3,
                            ),
                            child: Text('Privacidade', style: linkStyle),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('·', style: metaStyle),
                        ),
                        Text(cnpjLabel, style: metaStyle),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('·', style: metaStyle),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              size: metaSize + 2.5,
                              color: const Color(0xFF16A34A),
                            ),
                            const SizedBox(width: 3),
                            Text('SSL', style: metaStyle),
                          ],
                        ),
                        if (showOfficialSocialLinks) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Text('·', style: metaStyle),
                          ),
                          _OfficialSocialFooterIcons(metaSize: metaSize),
                        ],
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _openLegalPage(
    BuildContext context,
    String route,
    bool newTab,
    bool usePreviewModal,
  ) async {
    final r = route.startsWith('/') ? route : '/$route';
    final isPriv =
        r.contains('privacidade') || r.contains('politica-de-privacidade');

    // App nativo: mesma experiência das rotas web (página com AppBar, hero, seções e barra inferior).
    if (!kIsWeb && usePreviewModal && context.mounted) {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => isPriv
              ? const PoliticaPrivacidadePage()
              : const TermosDeUsoPage(),
        ),
      );
      return;
    }

    if (usePreviewModal && context.mounted) {
      await showGestaoYahwehLegalPreview(
        context,
        isPoliticaPrivacidade: isPriv,
      );
      return;
    }

    if (newTab && kIsWeb) {
      final origin = Uri.base.origin;
      final uri = Uri.parse('$origin/#$r');
      await launchUrl(uri, webOnlyWindowName: '_blank');
      return;
    }
    if (context.mounted) {
      await Navigator.of(context).pushNamed(r);
    }
  }
}

/// YouTube / Instagram com [Icon] Material (evita glifos em falta de Font Awesome na web).
class _OfficialSocialFooterIcons extends StatelessWidget {
  final double metaSize;

  const _OfficialSocialFooterIcons({required this.metaSize});

  Future<void> _open(String raw) async {
    final u = Uri.tryParse(raw.trim());
    if (u == null) return;
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok) await launchUrl(u, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    final sz = (metaSize + 6).clamp(14.0, 22.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Canal oficial no YouTube',
          child: InkWell(
            onTap: () => _open(AppConstants.marketingOfficialYoutubeUrl),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Icon(
                Icons.play_circle_filled_rounded,
                size: sz,
                color: const Color(0xFFFF0000),
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: 'Instagram Gestão YAHWEH',
          child: InkWell(
            onTap: () => _open(AppConstants.marketingOfficialInstagramUrl),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Icon(
                Icons.photo_camera_rounded,
                size: sz,
                color: const Color(0xFFE4405F),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Apenas o texto do versículo (para usar inline em outras telas).
class VersiculoRodapeText extends StatelessWidget {
  const VersiculoRodapeText({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            color: Colors.grey[700],
          ),
          children: [
            TextSpan(
              text: '"$kVersiculoRodape" ',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const TextSpan(
              text: '— $kVersiculoRef',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
