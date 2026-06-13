import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/utils/br_input_formatters.dart';

/// Estilo unificado: cadastro público e cadastro interno de membro.
class MemberSignupPremiumUi {
  MemberSignupPremiumUi._();

  static const List<String> estadoCivilOptions = [
    'casado (a)',
    'solteiro (a)',
    'viúvo (a)',
  ];

  static const List<String> escolaridadeOptions = [
    'Ensino Fundamental',
    'Ensino Médio',
    'Bacharel',
    'Superior',
    'Mestrado',
    'Doutorado',
    'Não informar',
  ];
}

/// Formata data para exibição / digitação (DD/MM/AAAA).
String memberSignupFormatBirthDateBr(DateTime d) => formatBrDateDdMmYyyy(d);

/// Interpreta [raw] como DD/MM/AAAA (com ou sem separadores).
DateTime? memberSignupParseBirthDateBr(String raw) =>
    parseBrDateDdMmYyyy(raw, maxYear: DateTime.now().year + 1);

/// Máscara numérica → DD/MM/AAAA ao digitar.
typedef MemberSignupBirthDateInputFormatter = BrDateDdMmYyyyInputFormatter;

/// Máscaras CPF / telefone (mesmo comportamento do cadastro público).
String memberSignupOnlyDigits(String v) =>
    v.replaceAll(RegExp(r'[^0-9]'), '');

String memberSignupFormatCpfMask(String raw) {
  final d = memberSignupOnlyDigits(raw);
  final p1 = d.length > 3 ? d.substring(0, 3) : d;
  final p2 =
      d.length > 6 ? d.substring(3, 6) : (d.length > 3 ? d.substring(3) : '');
  final p3 =
      d.length > 9 ? d.substring(6, 9) : (d.length > 6 ? d.substring(6) : '');
  final p4 = d.length > 11
      ? d.substring(9, 11)
      : (d.length > 9 ? d.substring(9) : '');
  final b = StringBuffer()..write(p1);
  if (p2.isNotEmpty) {
    b
      ..write('.')
      ..write(p2);
  }
  if (p3.isNotEmpty) {
    b
      ..write('.')
      ..write(p3);
  }
  if (p4.isNotEmpty) {
    b
      ..write('-')
      ..write(p4);
  }
  return b.toString();
}

String memberSignupFormatPhoneMask(String raw) {
  final d = memberSignupOnlyDigits(raw);
  if (d.isEmpty) return '';
  final ddd = d.length >= 2 ? d.substring(0, 2) : d;
  final rest = d.length > 2 ? d.substring(2) : '';
  final b = StringBuffer()
    ..write('(')
    ..write(ddd);
  if (d.length >= 2) b.write(')');
  if (rest.isEmpty) return b.toString();
  if (rest.length <= 4) return '${b.toString()} $rest';
  if (rest.length <= 8) {
    return '${b.toString()} ${rest.substring(0, rest.length - 4)}-${rest.substring(rest.length - 4)}';
  }
  final prefix = rest.substring(0, 5);
  final suffix = rest.substring(5, rest.length > 9 ? 9 : rest.length);
  return '${b.toString()} $prefix-$suffix';
}

InputDecoration memberSignupInputDecoration({
  required String label,
  String? hint,
  IconData? icon,
  Widget? suffixIcon,
  String? counterText,
  Color? accentColor,
}) {
  final accent = accentColor ?? ThemeCleanPremium.primary;
  final fill = Color.lerp(accent, Colors.white, 0.92)!;
  final border = OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(14)),
    borderSide: BorderSide(color: accent.withValues(alpha: 0.18)),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null
        ? null
        : Icon(icon, size: 22, color: accent.withValues(alpha: 0.85)),
    suffixIcon: suffixIcon,
    counterText: counterText,
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: accent.withValues(alpha: 0.95),
        width: 1.8,
      ),
    ),
    labelStyle: TextStyle(
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade800,
      fontSize: 14,
    ),
  );
}

/// Título de bloco (Dados pessoais, Endereço, …).
class MemberSignupSectionTitle extends StatelessWidget {
  final String title;
  final Color? accentColor;

  const MemberSignupSectionTitle({
    super.key,
    required this.title,
    this.accentColor,
  });

  static const _stepColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF97316),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? ThemeCleanPremium.primary;
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent,
                Color.lerp(accent, _stepColors[2], 0.35)!,
              ],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Colors.grey.shade900,
          ),
        ),
      ],
    );
  }
}

/// Passos 1–3 (cadastro público e fluxo interno alinhado).
class MemberSignupWizardProgress extends StatelessWidget {
  final int step;

  const MemberSignupWizardProgress({super.key, required this.step});

  static const _labels = ['Seus dados', 'Endereço', 'Família e foto'];
  static const _stepColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF97316),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _stepColors[step].withValues(alpha: 0.12),
                _stepColors[(step + 1).clamp(0, 2)].withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _stepColors[step].withValues(alpha: 0.22),
            ),
          ),
          child: Text(
            'Passo ${step + 1} de 3',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.3,
              color: _stepColors[step].withValues(alpha: 0.95),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(3, (i) {
            final active = i == step;
            final done = i < step;
            final color = _stepColors[i];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: done || active
                            ? LinearGradient(
                                colors: [color, Color.lerp(color, Colors.white, 0.2)!],
                              )
                            : null,
                        color: done || active ? null : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active ? color : Colors.grey.shade600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Cabeçalho do cadastro público — faixa de acento fina + cartão claro (alinhado ao site premium).
class PublicMemberSignupCompactHeader extends StatelessWidget {
  final bool loading;
  final bool churchNotFound;
  final String tenantName;
  final String formSubtitle;
  final String endereco;
  final Widget logoSlot;
  final VoidCallback? onBack;

  const PublicMemberSignupCompactHeader({
    super.key,
    required this.loading,
    required this.churchNotFound,
    required this.tenantName,
    required this.formSubtitle,
    required this.endereco,
    required this.logoSlot,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    const logoBox = 44.0;
    final primary = ThemeCleanPremium.primary;
    final onSurface = const Color(0xFF0F172A);
    final bandBlue = Color.lerp(
      ThemeCleanPremium.navSidebar,
      primary,
      0.55,
    )!;
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ThemeCleanPremium.navSidebar,
                  bandBlue,
                  Color.lerp(primary, const Color(0xFF1D4ED8), 0.35)!,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.church_rounded,
                        color: Colors.white.withValues(alpha: 0.95), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Gestão YAHWEH',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.98),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 12, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!kIsWeb && Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: YahwehSuperPremiumBackButton(
                          onPressed:
                              onBack ?? () => Navigator.maybePop(context),
                          tooltip: 'Voltar ao painel',
                          variant:
                              YahwehSuperPremiumBackVariant.onLightSurface,
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.grey.shade800,
                        ),
                        tooltip: 'Voltar',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            onBack ?? () => Navigator.maybePop(context),
                      ),
                    SizedBox(
                      width: logoBox,
                      height: logoBox,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: ThemeCleanPremium.softUiCardShadow,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: logoSlot,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: loading
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 13,
                                  width: 160,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 10,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  churchNotFound
                                      ? 'Cadastro público'
                                      : tenantName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: onSurface,
                                    height: 1.2,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  churchNotFound
                                      ? 'Igreja não encontrada'
                                      : formSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (!churchNotFound &&
                                    endereco.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 12,
                                        color: primary.withValues(alpha: 0.85),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          endereco,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            height: 1.25,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de contexto para cadastro interno (sem faixa azul alta).
class InternalMemberSignupHeroCard extends StatelessWidget {
  final String churchName;
  final String subtitle;

  const InternalMemberSignupHeroCard({
    super.key,
    required this.churchName,
    this.subtitle =
        'Mesmos dados do cadastro público. O membro é salvo como ativo.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.1),
            ThemeCleanPremium.cardBackground,
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.person_add_alt_1_rounded,
              color: ThemeCleanPremium.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  churchName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.grey.shade700,
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
