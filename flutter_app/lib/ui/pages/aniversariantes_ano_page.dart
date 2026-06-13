import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_birthday_year_load_service.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, isValidImageUrl;
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';

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
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: const Text('Aniversariantes do ano'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: SafeArea(
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
                : ListView(
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
                        _EmptyYearCard()
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
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                        ],
                    ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary,
            ThemeCleanPremium.primaryLight,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.cake_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total aniversariantes no ano',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$monthName: $monthCount ${monthCount == 1 ? 'pessoa' : 'pessoas'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 14,
                    height: 1.3,
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

class _EmptyYearCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: 48,
            color: ThemeCleanPremium.primary.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum membro com data de nascimento cadastrada.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeCleanPremium.onSurfaceVariant,
              fontSize: 15,
              height: 1.35,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isCurrentMonth
            ? Border.all(
                color: gradient.first.withValues(alpha: 0.45),
                width: 2,
              )
            : null,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
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
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Nenhum aniversariante em $monthName.',
                style: TextStyle(
                  color: ThemeCleanPremium.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
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
    final narrow = MediaQuery.sizeOf(context).width <
        ThemeCleanPremium.breakpointMobile;
    final crossCount = narrow ? 1 : 2;

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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: narrow ? 2.35 : 1.05,
          ),
          itemCount: entries.length,
          itemBuilder: (context, i) => _BirthdayPersonTile(
            entry: entries[i],
            accent: monthGradient.first,
            tenantId: tenantId,
            memberRole: memberRole,
            viewerCpfDigits: viewerCpfDigits,
            compact: narrow,
          ),
        ),
      ],
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
    required this.compact,
  });

  final ChurchBirthdayYearEntry entry;
  final Color accent;
  final String tenantId;
  final String memberRole;
  final String viewerCpfDigits;
  final bool compact;

  String _phoneDigits(Map<String, dynamic> data) {
    for (final k in ['TELEFONES', 'telefone', 'phone', 'celular', 'whatsapp']) {
      final v = (data[k] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (v.length >= 10) return v;
    }
    return '';
  }

  String? _authUid(Map<String, dynamic> data) {
    for (final k in ['authUid', 'uid', 'userId', 'firebaseUid']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.length >= 8) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = entry.memberData;
    final nome = entry.displayName.isEmpty ? 'Membro' : entry.displayName;
    final primeiro = entry.firstName;
    final foto = MemberProfilePhotoResolver.displayRef(data, preferThumb: true);
    final hasFoto = MemberProfilePhotoResolver.hasPhotoRef(data, preferThumb: true);
    final avatarColor =
        avatarColorForMember(data, hasPhoto: hasFoto) ?? accent;
    final cpf = (data['CPF'] ?? data['cpf'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final fone = _phoneDigits(data);
    final age = ageFromMemberData(data);
    final avatarSize = compact ? 48.0 : 56.0;
    final memPx = (avatarSize * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(96, 240);

    final avatar = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.55)]),
      ),
      child: FotoMembroWidget(
        imageUrl: foto,
        memberData: data,
        tenantId: tenantId,
        memberId: entry.memberDocId,
        cpfDigits: cpf.length == 11 ? cpf : null,
        authUid: MemberProfilePhotoResolver.authUidFromData(
          data,
          memberDocId: entry.memberDocId,
        ),
        size: avatarSize,
        memCacheWidth: memPx,
        memCacheHeight: memPx,
        preferListThumbnail: true,
        backgroundColor: avatarColor.withValues(alpha: 0.15),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: accent.withValues(alpha: 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: compact
          ? Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      if (age != null)
                        Text(
                          '$age anos',
                          style: TextStyle(
                            fontSize: 12,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: YahwehSuperPremiumActionButton.chat(
                              compact: true,
                              label: 'Chat',
                              onPressed: () =>
                                  ChurchMemberContactChat.openChatIgrejaUnawaited(
                                context: context,
                                tenantId: tenantId,
                                memberRole: memberRole,
                                viewerCpfDigits: viewerCpfDigits,
                                memberData: data,
                                displayName: nome,
                                memberDocId: entry.memberDocId,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: YahwehSuperPremiumActionButton.whatsapp(
                              compact: true,
                              label: 'WhatsApp',
                              onPressed: () {
                                if (fone.length >= 10) {
                                  unawaited(
                                    YahwehWhatsAppService.openBirthdayWish(
                                      context,
                                      firstName: primeiro,
                                      phoneDigits: fone,
                                    ),
                                  );
                                } else {
                                  unawaited(
                                    YahwehWhatsAppService.openForMember(
                                      context,
                                      data,
                                      tenantId: tenantId,
                                      memberDocId: entry.memberDocId,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                avatar,
                const SizedBox(height: 10),
                Text(
                  nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                if (age != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$age anos',
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: YahwehSuperPremiumActionButton.chat(
                        compact: true,
                        label: 'Chat',
                        onPressed: () =>
                            ChurchMemberContactChat.openChatIgrejaUnawaited(
                          context: context,
                          tenantId: tenantId,
                          memberRole: memberRole,
                          viewerCpfDigits: viewerCpfDigits,
                          memberData: data,
                          displayName: nome,
                          memberDocId: entry.memberDocId,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: YahwehSuperPremiumActionButton.whatsapp(
                        compact: true,
                        label: 'WhatsApp',
                        onPressed: () {
                          if (fone.length >= 10) {
                            unawaited(
                              YahwehWhatsAppService.openBirthdayWish(
                                context,
                                firstName: primeiro,
                                phoneDigits: fone,
                              ),
                            );
                          } else {
                            unawaited(
                              YahwehWhatsAppService.openForMember(
                                context,
                                data,
                                tenantId: tenantId,
                                memberDocId: entry.memberDocId,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
