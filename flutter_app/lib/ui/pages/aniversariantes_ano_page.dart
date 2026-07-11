import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_birthday_parabenizar.dart';
import 'package:gestao_yahweh/services/church_birthday_year_load_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_member_pastoral_contact_card.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_birthday_ui.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_back_button.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// «Aniversariantes do ano» — grelha colorida mês a mês, dia a dia, com Chat e WhatsApp.
class AniversariantesAnoPage extends StatefulWidget {
  const AniversariantesAnoPage({
    super.key,
    this.tenantId = '',
    this.memberRole = 'membro',
    this.viewerCpfDigits = '',
    this.membersDirectory,
  });

  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;
  final MembersDirectorySnapshot? membersDirectory;

  @override
  State<AniversariantesAnoPage> createState() => _AniversariantesAnoPageState();
}

class _AniversariantesAnoPageState extends State<AniversariantesAnoPage> {
  bool _loading = true;
  String? _error;
  List<ChurchBirthdayYearEntry> _entries = [];

  static const List<String> _meses = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro',
  ];

  static const List<List<Color>> _monthGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFFEC4899), Color(0xFFF97316)],
    [Color(0xFF14B8A6), Color(0xFF06B6D4)],
    [Color(0xFF22C55E), Color(0xFF84CC16)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF3B82F6), Color(0xFF6366F1)],
    [Color(0xFF0EA5E9), Color(0xFF2563EB)],
    [Color(0xFF8B5CF6), Color(0xFFD946EF)],
    [Color(0xFF10B981), Color(0xFF059669)],
    [Color(0xFFF97316), Color(0xFFEA580C)],
    [Color(0xFF64748B), Color(0xFF475569)],
    [Color(0xFFDC2626), Color(0xFF991B1B)],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _effectiveTenantId => ChurchPanelTenant.resolve(widget.tenantId);

  Future<void> _load() async {
    final tid = _effectiveTenantId;
    if (tid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Igreja não identificada.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await ChurchBirthdayYearLoadService.load(
        seedTenantId: tid,
        directoryHint: widget.membersDirectory,
      );
      if (!mounted) return;
      setState(() {
        _entries = loaded;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('TimeoutException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final now = DateTime.now();
    final grouped = ChurchBirthdayYearLoadService.groupByMonthAndDay(_entries);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leadingWidth: 64,
        leading: YahwehSuperPremiumBackButton.appBarLeading(context),
        automaticallyImplyLeading: false,
        title: Text(
          'Aniversariantes do ano',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kChurchBirthdayAccent,
                Color.lerp(kChurchBirthdayAccent, Colors.white, 0.22)!,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kChurchBirthdayAccent.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: churchModuleBodyGradient(kChurchBirthdayAccent),
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : _error != null
                  ? _ErrorBody(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: ThemeCleanPremium.isMobile(context)
                            ? double.infinity
                            : 1040,
                      ),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: padding,
                        children: [
                          _YearSummaryHeader(
                            total: _entries.length,
                            monthName: _meses[now.month - 1],
                            monthCount: grouped[now.month]?.values
                                    .fold<int>(0, (a, b) => a + b.length) ??
                                0,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                          if (_entries.isEmpty)
                            const ChurchWisdomModuleEmptyState(
                              icon: Icons.calendar_month_outlined,
                              title: 'Nenhum aniversariante cadastrado',
                              message:
                                  'Cadastre a data de nascimento dos membros em Membros > Editar.',
                              accent: kChurchBirthdayAccent,
                            )
                          else
                            for (var m = 1; m <= 12; m++) ...[
                              _MonthBirthdaySection(
                                month: m,
                                monthName: _meses[m - 1],
                                gradient: _monthGradients[m - 1],
                                daysMap: grouped[m] ?? const {},
                                isCurrentMonth: m == now.month,
                                tenantId: _effectiveTenantId,
                                memberRole: widget.memberRole,
                                viewerCpfDigits: widget.viewerCpfDigits,
                              ),
                              const SizedBox(
                                  height: ThemeCleanPremium.spaceMd),
                            ],
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

class _YearSummaryHeader extends StatelessWidget {
  const _YearSummaryHeader({
    required this.total,
    required this.monthName,
    required this.monthCount,
  });

  final int total;
  final String monthName;
  final int monthCount;

  @override
  Widget build(BuildContext context) {
    return YahwehWisdomSectionCard(
      borderTint: kChurchBirthdayAccent,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          churchWisdomModuleIconLeading(
            icon: Icons.cake_rounded,
            accent: kChurchBirthdayAccent,
            size: 52,
            moduleAssetKey: 'aniversario',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total aniversariantes no ano',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$monthName: $monthCount ${monthCount == 1 ? 'pessoa' : 'pessoas'}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: ThemeCleanPremium.pagePadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: ThemeCleanPremium.primary.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthBirthdaySection extends StatelessWidget {
  const _MonthBirthdaySection({
    required this.month,
    required this.monthName,
    required this.gradient,
    required this.daysMap,
    required this.isCurrentMonth,
    required this.tenantId,
    required this.memberRole,
    required this.viewerCpfDigits,
  });

  final int month;
  final String monthName;
  final List<Color> gradient;
  final Map<int, List<ChurchBirthdayYearEntry>> daysMap;
  final bool isCurrentMonth;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;

  int get _total =>
      daysMap.values.fold<int>(0, (sum, list) => sum + list.length);

  @override
  Widget build(BuildContext context) {
    final sortedDays = daysMap.keys.toList()..sort();

    return ClipRRect(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
      child: YahwehWisdomSectionCard(
        borderTint: gradient.first,
        padding: EdgeInsets.zero,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: gradient,
              ),
            ),
            child: Row(
              children: [
                Text(
                  monthName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$_total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isCurrentMonth) ...[
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Mês atual',
                      style: TextStyle(
                        color: gradient.first,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_total == 0)
            ChurchWisdomBirthdayEmptyRow(
              message: 'Nenhum aniversariante em $monthName.',
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final day in sortedDays) ...[
                    _DayBirthdayBlock(
                      day: day,
                      entries: daysMap[day]!,
                      monthGradient: gradient,
                      tenantId: tenantId,
                      memberRole: memberRole,
                      viewerCpfDigits: viewerCpfDigits,
                    ),
                    if (day != sortedDays.last)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _DayBirthdayBlock extends StatelessWidget {
  const _DayBirthdayBlock({
    required this.day,
    required this.entries,
    required this.monthGradient,
    required this.tenantId,
    required this.memberRole,
    required this.viewerCpfDigits,
  });

  final int day;
  final List<ChurchBirthdayYearEntry> entries;
  final List<Color> monthGradient;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: monthGradient),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: monthGradient.first.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                day.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              entries.length == 1 ? '1 aniversariante' : '${entries.length} aniversariantes',
              style: TextStyle(
                color: ThemeCleanPremium.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BirthdayYearPersonGrid(
          entries: entries,
          accent: monthGradient.first,
          tenantId: tenantId,
          memberRole: memberRole,
          viewerCpfDigits: viewerCpfDigits,
        ),
      ],
    );
  }
}

class _BirthdayYearPersonGrid extends StatelessWidget {
  const _BirthdayYearPersonGrid({
    required this.entries,
    required this.accent,
    required this.tenantId,
    required this.memberRole,
    required this.viewerCpfDigits,
  });

  final List<ChurchBirthdayYearEntry> entries;
  final Color accent;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 900 ? 3 : (w >= 520 ? 2 : 1);
        const gap = 10.0;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: cols == 1 ? 2.65 : (cols == 2 ? 1.28 : 1.05),
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            return _BirthdayPersonTile(
              entry: entries[index],
              accent: accent,
              tenantId: tenantId,
              memberRole: memberRole,
              viewerCpfDigits: viewerCpfDigits,
              compact: true,
            );
          },
        );
      },
    );
  }
}

class _BirthdayPersonTile extends StatelessWidget {
  const _BirthdayPersonTile({
    required this.entry,
    required this.accent,
    required this.tenantId,
    required this.memberRole,
    required this.viewerCpfDigits,
    this.compact = false,
  });

  final ChurchBirthdayYearEntry entry;
  final Color accent;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = entry.memberData;
    final nome = entry.displayName.isEmpty ? 'Membro' : entry.displayName;
    final primeiro = entry.firstName;
    final age = ageFromMemberData(data);
    final subtitle = age != null ? '$age anos · Parabenize!' : 'Aniversariante';

    return ChurchMemberPastoralContactCard(
      displayName: nome,
      subtitle: subtitle,
      memberData: data,
      tenantId: tenantId,
      memberDocId: entry.memberDocId,
      memberRole: memberRole,
      viewerCpfDigits: viewerCpfDigits,
      accent: accent,
      compact: compact,
      whatsappMessage: ChurchBirthdayParabenizar.messageFor(primeiro),
    );
  }
}
