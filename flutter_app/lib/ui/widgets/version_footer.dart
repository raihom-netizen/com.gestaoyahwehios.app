import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';

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

  const VersionFooter({
    super.key,
    this.showVersion = true,
    this.versionLabel,
    this.showLegalLinks = true,
    this.cnpjLabel = 'CNPJ: não informado',
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
                          onTap: () =>
                              Navigator.of(context).pushNamed('/termos-de-uso'),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: isNarrow ? 8 : 3,
                            ),
                            child: Text('Termos', style: linkStyle),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text('·', style: metaStyle),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(context)
                              .pushNamed('/politica-de-privacidade'),
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
