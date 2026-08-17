import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/member_segment_preview_page.dart';

/// Card de gráfico pizza com legenda — **tudo clicável**: tocar numa fatia ou
/// num percentual abre [MemberSegmentPreviewPage] em tela cheia.
///
/// Fonte única do painel inicial da igreja e da aba «Painel & números» do
/// módulo Membros, para os dois terem exactamente o mesmo comportamento.
class MemberSegmentPieCard extends StatelessWidget {
  const MemberSegmentPieCard({
    super.key,
    required this.title,
    required this.icon,
    required this.segments,
    required this.total,
    this.tenantId,
    this.emptyLabel = 'Sem dados de membros.',
  });

  final String title;
  final IconData icon;
  final List<MemberSegment> segments;
  final int total;
  final String? tenantId;
  final String emptyLabel;

  void _open(BuildContext context, MemberSegment seg) {
    if (seg.count == 0) return;
    openMemberSegmentPreview(
      context,
      segment: seg,
      chartTitle: title,
      tenantId: tenantId,
      totalForPercent: total,
    );
  }

  LinearGradient _sliceGradient(Color base) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(base, Colors.white, 0.38)!,
      base,
      Color.lerp(base, const Color(0xFF0F172A), 0.22)!,
    ],
    stops: const [0.0, 0.5, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: ThemeCleanPremium.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _content(context),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (total == 0 || segments.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            emptyLabel,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }

    final sections = segments.map((seg) {
      final share = total > 0 ? seg.count / total : 0.0;
      return PieChartSectionData(
        value: seg.count.toDouble(),
        title: share >= 0.06 ? '${(share * 100).round()}%' : '',
        color: seg.color,
        radius: 58,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          shadows: [
            Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black54),
          ],
        ),
        borderSide: const BorderSide(color: Color(0xFFF8FAFC), width: 2),
      );
    }).toList(growable: false);

    final legend = [for (final s in segments) _legendItem(context, s)];
    final narrow = MediaQuery.sizeOf(context).width < 520;

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chart(context, sections),
          const SizedBox(height: 16),
          ...legend,
        ],
      );
    }
    return SizedBox(
      height: 280,
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: legend,
              ),
            ),
          ),
          Expanded(flex: 10, child: _chart(context, sections)),
        ],
      ),
    );
  }

  Widget _legendItem(BuildContext context, MemberSegment seg) {
    final pct = total > 0 ? seg.count / total * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _open(context, seg),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    gradient: _sliceGradient(seg.color),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF475569),
                      ),
                      children: [
                        TextSpan(
                          text: '${seg.label}\n',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        TextSpan(
                          text:
                              '  •  ${seg.count} '
                              '${seg.count == 1 ? 'membro' : 'membros'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: seg.color.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chart(BuildContext context, List<PieChartSectionData> sections) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth.clamp(160.0, 220.0);
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2.5,
                      centerSpaceRadius: side * 0.22,
                      pieTouchData: PieTouchData(
                        enabled: true,
                        touchCallback: (event, resp) {
                          if (event is! FlTapUpEvent) return;
                          final i = resp?.touchedSection?.touchedSectionIndex;
                          if (i == null || i < 0 || i >= segments.length) {
                            return;
                          }
                          _open(context, segments[i]);
                        },
                      ),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 500),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'membros',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Monta as fatias padrão (demografia, gênero, faixa etária) a partir dos
/// documentos de membro — fonte única para painel inicial e módulo Membros.
abstract final class MemberSegmentBuilders {
  MemberSegmentBuilders._();

  static List<MemberSegmentMember> _pick(
    List<MemberSegmentMember> all,
    bool Function(Map<String, dynamic>) test,
  ) => all.where((m) => test(m.data)).toList(growable: false);

  static bool _sexoEmBranco(Map<String, dynamic> d) =>
      (d['SEXO'] ?? d['sexo'] ?? d['genero'] ?? d['gender'] ?? '')
          .toString()
          .trim()
          .isEmpty;

  static List<MemberSegment> demografia(List<MemberSegmentMember> all) => [
    MemberSegment(
      label: 'Crianças',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i < 13;
      }),
      color: const Color(0xFFF59E0B),
    ),
    MemberSegment(
      label: 'Jovens',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 13 && i < 18;
      }),
      color: const Color(0xFF14B8A6),
    ),
    MemberSegment(
      label: 'Homens (18+)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 18 && genderCategoryFromMemberData(d) == 'M';
      }),
      color: const Color(0xFF2563EB),
    ),
    MemberSegment(
      label: 'Mulheres (18+)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 18 && genderCategoryFromMemberData(d) == 'F';
      }),
      color: const Color(0xFFDB2777),
    ),
    MemberSegment(
      label: 'Outros / sem dados',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        if (i == null) return true;
        if (i < 18) return false;
        final g = genderCategoryFromMemberData(d);
        return g != 'M' && g != 'F';
      }),
      color: const Color(0xFF94A3B8),
    ),
  ].where((s) => s.count > 0).toList(growable: false);

  static List<MemberSegment> genero(List<MemberSegmentMember> all) => [
    MemberSegment(
      label: 'Masculino',
      members: _pick(all, (d) => genderCategoryFromMemberData(d) == 'M'),
      color: const Color(0xFF2563EB),
    ),
    MemberSegment(
      label: 'Feminino',
      members: _pick(all, (d) => genderCategoryFromMemberData(d) == 'F'),
      color: const Color(0xFFDB2777),
    ),
    MemberSegment(
      label: 'Outros',
      members: _pick(all, (d) {
        final g = genderCategoryFromMemberData(d);
        return g != 'M' && g != 'F' && !_sexoEmBranco(d);
      }),
      color: const Color(0xFF7C3AED),
    ),
    MemberSegment(
      label: 'Não informado',
      members: _pick(all, (d) {
        final g = genderCategoryFromMemberData(d);
        return g != 'M' && g != 'F' && _sexoEmBranco(d);
      }),
      color: const Color(0xFF94A3B8),
    ),
  ].where((s) => s.count > 0).toList(growable: false);

  static List<MemberSegment> faixaEtaria(List<MemberSegmentMember> all) => [
    MemberSegment(
      label: 'Crianças (<13)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i < 13;
      }),
      color: const Color(0xFFF59E0B),
    ),
    MemberSegment(
      label: 'Adolescentes (13–17)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 13 && i < 18;
      }),
      color: const Color(0xFF14B8A6),
    ),
    MemberSegment(
      label: 'Adultos (18–59)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 18 && i < 60;
      }),
      color: const Color(0xFF2563EB),
    ),
    MemberSegment(
      label: 'Idosos (60+)',
      members: _pick(all, (d) {
        final i = ageFromMemberData(d);
        return i != null && i >= 60;
      }),
      color: const Color(0xFF4F46E5),
    ),
    MemberSegment(
      label: 'Sem idade informada',
      members: _pick(all, (d) => ageFromMemberData(d) == null),
      color: const Color(0xFFCBD5E1),
    ),
  ].where((s) => s.count > 0).toList(growable: false);
}
