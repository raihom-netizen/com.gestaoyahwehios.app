import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'departments_page.dart';
import 'events_manager_page.dart';
import 'finance_page.dart';
import 'patrimonio_page.dart';
import 'member_card_page.dart';
import 'members_page.dart';
import 'mural_page.dart';
import 'my_schedules_page.dart';
import 'notifications_page.dart';
import 'plans/renew_plan_page.dart';
import 'schedules_page.dart';
import 'users_page.dart';
import 'sistema_informacoes_page.dart';
import '../widgets/version_footer.dart';
import '../widgets/member_demographics_utils.dart';
import '../widgets/install_pwa_button.dart';
import '../widgets/yahweh_premium_feed_widgets.dart'
    show YahwehPremiumFeedShimmer;

class DashboardPage extends StatelessWidget {
  final String tenantId; // igrejaId
  final String cpf;
  final String role;
  final bool trialExpired;
  final Map<String, dynamic>? subscription;

  const DashboardPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.trialExpired,
    required this.subscription,
  });

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  String _formatDayMonth(DateTime d) {
    const months = [
      'Janeiro',
      'Fevereiro',
      'Marco',
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
    final m = months[d.month - 1];
    return '${d.day} $m';
  }

  String _normStatus(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return 'ativo';
    if (s.contains('inativ') || s.contains('bloq') || s.contains('off'))
      return 'inativo';
    return 'ativo';
  }

  String _normGender(dynamic raw) {
    final c = genderCategoryFromMemberData({'SEXO': raw, 'sexo': raw});
    if (c == 'M') return 'm';
    if (c == 'F') return 'f';
    return 'o';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final nowBuild = DateTime.now();
    final roleKey = role.toLowerCase();
    final isAdmin = roleKey == 'adm' || roleKey == 'admin' || roleKey == 'gestor' || roleKey == 'master';
    final isLeader = roleKey == 'lider';
    final isUser = !isAdmin && !isLeader;

    final membersCol = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('membros');

    final visitantesMesQuery = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('visitantes')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime(nowBuild.year, nowBuild.month, 1),
          ),
        );
    final proximoEventoQuery = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('noticias')
        .where('type', isEqualTo: 'evento')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(nowBuild))
        .orderBy('startAt')
        .limit(1);

    Widget banner() {
      final status = (subscription?['status'] ?? '').toString().toUpperCase();

      if (trialExpired) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFD1A6)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFB75A00)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Seu teste gratis expirou. Para continuar usando todos os recursos, ative um plano.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RenewPlanPage()),
                  );
                },
                child: const Text('Ativar plano'),
              ),
            ],
          ),
        );
      }

      if (status == 'TRIAL') {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Teste gratis ativo. Vincule o pagamento para nao perder acesso quando o periodo encerrar.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RenewPlanPage()),
                  );
                },
                child: const Text('Ver planos'),
              ),
            ],
          ),
        );
      }

      return const SizedBox.shrink();
    }

    Widget tile(IconData icon, String title, String subtitle) {
      final locked =
          trialExpired && title != 'Configurações' && title != 'Assinatura' && title != 'Informações do Sistema';
      void open() {
        if (title == 'Membros') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MembersPage(tenantId: tenantId, role: role),
            ),
          );
          return;
        }
        if (title == 'Carteirinha') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MemberCardPage(
                tenantId: tenantId,
                role: role,
                cpf: cpf,
              ),
            ),
          );
          return;
        }
        if (title == 'Usuarios') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsersPage(tenantId: tenantId, role: role),
            ),
          );
          return;
        }
        if (title == 'Mural') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MuralPage(tenantId: tenantId, role: role),
            ),
          );
          return;
        }
        if (title == 'Notificacoes') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsPage(
                tenantId: tenantId,
                cpf: cpf,
                role: role,
              ),
            ),
          );
          return;
        }
        if (title == 'Eventos') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventsManagerPage(tenantId: tenantId, role: role),
            ),
          );
          return;
        }
        if (title == 'Escalas') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SchedulesPage(
                tenantId: tenantId,
                role: role,
                cpf: cpf,
              ),
            ),
          );
          return;
        }
        if (title == 'Minhas Escalas') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MySchedulesPage(
                tenantId: tenantId,
                cpf: cpf,
                role: role,
              ),
            ),
          );
          return;
        }
        if (title == 'Departamentos') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DepartmentsPage(tenantId: tenantId, role: role),
            ),
          );
          return;
        }
        if (title == 'Receitas e Despesas') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FinancePage(tenantId: tenantId, role: role)),
          );
          return;
        }
        if (title == 'Patrimônio') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PatrimonioPage(tenantId: tenantId, role: role)),
          );
          return;
        }
        if (title == 'Assinatura') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RenewPlanPage()),
          );
          return;
        }
        if (title == 'Informações do Sistema') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SistemaInformacoesPage(tenantId: tenantId)),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abrir: $title (módulo na base V9)')),
        );
      }

      return Opacity(
        opacity: locked ? 0.55 : 1,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: locked
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Plano expirado. Ative um plano para usar este modulo.',
                        ),
                      ),
                    )
                : open,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFEAF0FF),
                    child: Icon(icon, color: const Color(0xFF1D4ED8)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openQuickCreate() async {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded),
                  title: const Text('Novo Membro'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MembersPage(tenantId: tenantId, role: role),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event_available_rounded),
                  title: const Text('Novo Evento'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EventsManagerPage(tenantId: tenantId, role: role),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.volunteer_activism_rounded),
                  title: const Text('Lançar Oferta / Dízimo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FinancePage(tenantId: tenantId, role: role),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4FA),
      bottomNavigationBar: const VersionFooter(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openQuickCreate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('+ Novo Registro'),
      ),
      body: SafeArea(
        child: Column(
        children: [
          _TopBar(
            title: 'Igreja',
            subtitle: 'Gestao YAHWEH',
            userName: user?.displayName ?? user?.email ?? 'Admin',
            photoUrl: user?.photoURL,
            tenantId: tenantId,
            subscription: subscription,
            onLogout: () => FirebaseAuth.instance.signOut().then((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: membersCol.get(const GetOptions(source: Source.cache)),
                    builder: (context, cachedSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: membersCol.snapshots(),
                        builder: (context, membersSnap) {
                          final fallbackDocs = cachedSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                          final docs = membersSnap.data?.docs ?? fallbackDocs;
                          if (docs.isEmpty && !membersSnap.hasData && cachedSnap.connectionState == ConnectionState.waiting) {
                            return YahwehPremiumFeedShimmer.dashboardOverviewLoading();
                          }

                      final now = DateTime.now();

                      int active = 0;
                      int inactive = 0;
                      int newMembers = 0;

                      int male = 0;
                      int female = 0;
                      int other = 0;
                      final monthStarts = List<DateTime>.generate(
                        6,
                        (i) => DateTime(now.year, now.month - 5 + i, 1),
                      );
                      final newMembersByMonth = List<int>.filled(6, 0);

                      final ageBuckets = <String, int>{
                        '0-12': 0,
                        '13-17': 0,
                        '18-25': 0,
                        '26-35': 0,
                        '36-50': 0,
                        '51+': 0,
                      };

                      final birthdays = <Map<String, dynamic>>[];

                      for (final d in docs) {
                        final data = d.data();
                        final status = _normStatus(
                          data['STATUS'] ?? data['status'],
                        );
                        if (status == 'ativo') {
                          active += 1;
                        } else {
                          inactive += 1;
                        }

                        final createdAt = _parseDate(
                          data['CRIADO_EM'] ?? data['createdAt'],
                        );
                        if (createdAt != null &&
                            now.difference(createdAt).inDays <= 30) {
                          newMembers += 1;
                        }
                        if (createdAt != null) {
                          for (var i = 0; i < monthStarts.length; i++) {
                            final m = monthStarts[i];
                            if (createdAt.year == m.year &&
                                createdAt.month == m.month) {
                              newMembersByMonth[i] += 1;
                              break;
                            }
                          }
                        }

                        final gender = _normGender(
                          data['SEXO'] ?? data['sexo'],
                        );
                        if (gender == 'm') {
                          male += 1;
                        } else if (gender == 'f') {
                          female += 1;
                        } else {
                          other += 1;
                        }

                        final age = ageFromMemberData(data);
                        if (age != null) {
                          if (age <= 12)
                            ageBuckets['0-12'] = (ageBuckets['0-12'] ?? 0) + 1;
                          else if (age <= 17)
                            ageBuckets['13-17'] =
                                (ageBuckets['13-17'] ?? 0) + 1;
                          else if (age <= 25)
                            ageBuckets['18-25'] =
                                (ageBuckets['18-25'] ?? 0) + 1;
                          else if (age <= 35)
                            ageBuckets['26-35'] =
                                (ageBuckets['26-35'] ?? 0) + 1;
                          else if (age <= 50)
                            ageBuckets['36-50'] =
                                (ageBuckets['36-50'] ?? 0) + 1;
                          else
                            ageBuckets['51+'] = (ageBuckets['51+'] ?? 0) + 1;
                        }

                        final birth = birthDateFromMemberData(data) ??
                            _parseDate(
                              data['DATA_NASCIMENTO'] ?? data['dataNascimento'],
                            );
                        if (birth != null && birth.month == now.month) {
                          final cpfRaw =
                              (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                          birthdays.add({
                            'name': (data['NOME_COMPLETO'] ??
                                    data['nome'] ??
                                    'Membro')
                                .toString(),
                            'birth': birth,
                            'photo': imageUrlFromMap(data),
                            'id': d.id,
                            'cpf': cpfRaw,
                            'memberData': Map<String, dynamic>.from(data),
                          });
                        }
                      }

                      birthdays.sort((a, b) {
                        final ad = a['birth'] as DateTime;
                        final bd = b['birth'] as DateTime;
                        return ad.day.compareTo(bd.day);
                      });

                      final total = active + inactive;
                      final totalNewIn6Months = newMembersByMonth.fold<int>(
                        0,
                        (acc, v) => acc + v,
                      );
                      var base = total - totalNewIn6Months;
                      if (base < 0) base = 0;
                      final growthSpots = <FlSpot>[];
                      final monthLabels = <String>[];
                      var cumul = base;
                      for (var i = 0; i < newMembersByMonth.length; i++) {
                        cumul += newMembersByMonth[i];
                        growthSpots.add(FlSpot(i.toDouble(), cumul.toDouble()));
                        final m = monthStarts[i];
                        monthLabels.add('${m.month.toString().padLeft(2, '0')}/${(m.year % 100).toString().padLeft(2, '0')}');
                      }
                      final dist = <_PieSlice>[
                        _PieSlice(
                          label: 'Ativos',
                          value: active,
                          color: const Color(0xFF2563EB),
                        ),
                        _PieSlice(
                          label: 'Novos',
                          value: newMembers,
                          color: const Color(0xFF22C55E),
                        ),
                        _PieSlice(
                          label: 'Inativos',
                          value: inactive,
                          color: const Color(0xFFEF4444),
                        ),
                      ];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          banner(),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Aniversariantes do Mes',
                            trailing: TextButton(
                              onPressed: birthdays.isEmpty
                                  ? null
                                  : () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => _BirthdaysDialog(
                                          tenantId: tenantId,
                                          birthdays: birthdays,
                                          formatDayMonth: _formatDayMonth,
                                        ),
                                      );
                                    },
                              child: const Text('Ver todos'),
                            ),
                            child: SizedBox(
                              height: 120,
                              child: birthdays.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Nenhum aniversariante neste mes.',
                                      ),
                                    )
                                  : ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: birthdays.length > 10
                                          ? 10
                                          : birthdays.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (context, i) {
                                        final b = birthdays[i];
                                        final dt = b['birth'] as DateTime;
                                        return _BirthdayChip(
                                          tenantId: tenantId,
                                          memberId: b['id'] as String,
                                          cpfDigits: (b['cpf'] as String?) ?? '',
                                          name: b['name'] as String,
                                          date: _formatDayMonth(dt),
                                          photoUrl: (b['photo'] as String?) ?? '',
                                          memberData: b['memberData'] as Map<String, dynamic>?,
                                        );
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: visitantesMesQuery.snapshots(),
                            builder: (context, visitSnap) {
                              final visitantesMes = visitSnap.data?.docs.length ?? 0;
                              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: proximoEventoQuery.snapshots(),
                                builder: (context, eventSnap) {
                                  final nextEvent = eventSnap.data?.docs.isNotEmpty == true
                                      ? eventSnap.data!.docs.first.data()
                                      : const <String, dynamic>{};
                                  final nextEventDate = nextEvent['startAt'] is Timestamp
                                      ? (nextEvent['startAt'] as Timestamp).toDate()
                                      : null;
                                  final nextEventLabel = nextEventDate == null
                                      ? 'Sem data'
                                      : '${nextEventDate.day.toString().padLeft(2, '0')}/${nextEventDate.month.toString().padLeft(2, '0')}';
                                  return _SectionCard(
                                    title: 'Resumo Rapido',
                                    child: GridView.count(
                                      crossAxisCount: MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointTablet ? 2 : 4,
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 2.1,
                                      children: [
                                        _KpiTile(
                                          title: 'Total de Membros',
                                          value: total.toString(),
                                          icon: Icons.group_rounded,
                                          color: const Color(0xFF2563EB),
                                        ),
                                        _KpiTile(
                                          title: 'Visitantes do Mes',
                                          value: visitantesMes.toString(),
                                          icon: Icons.person_add_alt_rounded,
                                          color: const Color(0xFF16A34A),
                                        ),
                                        _KpiTile(
                                          title: 'Proximo Evento',
                                          value: nextEventLabel,
                                          icon: Icons.event_available_rounded,
                                          color: const Color(0xFFF97316),
                                        ),
                                        _KpiTile(
                                          title: 'Aniversariantes',
                                          value: birthdays.length.toString(),
                                          icon: Icons.cake_rounded,
                                          color: const Color(0xFFE11D48),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Crescimento de Membros (6 meses)',
                            child: SizedBox(
                              height: 210,
                              child: _GrowthLineChart(
                                spots: growthSpots,
                                labels: monthLabels,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < ThemeCleanPremium.breakpointTablet;
                              final muralCard = _SectionCard(
                                title: 'Mural de Avisos',
                                trailing: TextButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EventsManagerPage(
                                          tenantId: tenantId,
                                          role: role,
                                          initialTabIndex: 1,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                                  label: const Text('Galeria de eventos'),
                                ),
                                child: _MuralPreview(tenantId: tenantId),
                              );
                              final statsCard = _SectionCard(
                                  title: 'Estatisticas de Membros',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 140,
                                            height: 140,
                                            child: _PieChart(
                                              slices: dist,
                                              total: total,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _LegendRow(
                                                  color: const Color(
                                                    0xFF2563EB,
                                                  ),
                                                  label: 'Ativos',
                                                  value: active,
                                                ),
                                                _LegendRow(
                                                  color: const Color(
                                                    0xFF22C55E,
                                                  ),
                                                  label: 'Novos',
                                                  value: newMembers,
                                                ),
                                                _LegendRow(
                                                  color: const Color(
                                                    0xFFEF4444,
                                                  ),
                                                  label: 'Inativos',
                                                  value: inactive,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Por Genero',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _LegendRow(
                                        color: const Color(0xFF2563EB),
                                        label: 'Homens',
                                        value: male,
                                      ),
                                      _LegendRow(
                                        color: const Color(0xFFE11D48),
                                        label: 'Mulheres',
                                        value: female,
                                      ),
                                      if (other > 0)
                                        _LegendRow(
                                          color: const Color(0xFF64748B),
                                          label: 'Outros',
                                          value: other,
                                        ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Por Faixa Etaria',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _AgeBarRow(values: ageBuckets),
                                    ],
                                  ),
                                );
                              if (isNarrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    muralCard,
                                    const SizedBox(height: 14),
                                    statsCard,
                                  ],
                                );
                              }
                              return Wrap(
                                spacing: 14,
                                runSpacing: 14,
                                children: [
                                  SizedBox(width: 620, child: muralCard),
                                  SizedBox(width: 420, child: statsCard),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < ThemeCleanPremium.breakpointTablet;
                              final tileWidth = isNarrow ? constraints.maxWidth : 340.0;
                              return _SectionCard(
                                title: 'Acessos rapidos',
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.person_add_alt_1_rounded,
                                          'Membros',
                                          'Novo Membro',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.event_available_rounded,
                                          'Eventos',
                                          'Novo Evento',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.volunteer_activism_rounded,
                                          'Receitas e Despesas',
                                          'Lançar Oferta / Dízimo',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.people_alt_rounded,
                                          'Membros',
                                          'Cadastrar/editar membros e gerar carteirinhas.',
                                        ),
                                      ),
                                    SizedBox(
                                      width: tileWidth,
                                      child: tile(
                                        Icons.badge_rounded,
                                        'Carteirinha',
                                        'Sua carteirinha digital com QR Code e PDF.',
                                      ),
                                    ),
                                    SizedBox(
                                      width: tileWidth,
                                      child: tile(
                                        Icons.notifications_active_rounded,
                                        'Notificacoes',
                                        'Avisos de escalas e comunicados do departamento.',
                                      ),
                                    ),
                                    SizedBox(
                                      width: tileWidth,
                                      child: tile(
                                        Icons.schedule_rounded,
                                        'Minhas Escalas',
                                        'Veja suas escalas detalhadas por dia e horario.',
                                      ),
                                    ),
                                    SizedBox(
                                      width: tileWidth,
                                      child: tile(
                                        Icons.view_quilt_rounded,
                                        'Mural',
                                        'Avisos e eventos estilo Instagram (WhatsApp incluso).',
                                      ),
                                    ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.event_rounded,
                                          'Eventos',
                                          'Eventos fixos (recorrentes) e casuais.',
                                        ),
                                      ),
                                    if (!isUser)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.event_available_rounded,
                                          'Escalas',
                                          'Gerar escalas: dia, semanal, mensal e anual.',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.apartment_rounded,
                                          'Departamentos',
                                          'Criar departamentos com imagens padrão (desenhos).',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.account_balance_wallet_rounded,
                                          'Receitas e Despesas',
                                          'Controle financeiro com categorias e gráficos.',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.inventory_2_rounded,
                                          'Patrimônio',
                                          'Cadastro de bens, equipamentos e imóveis da igreja.',
                                        ),
                                      ),
                                    if (isAdmin)
                                      SizedBox(
                                        width: tileWidth,
                                        child: tile(
                                          Icons.verified_user_rounded,
                                          'Assinatura',
                                          'Plano atual, pagamento e ativacao.',
                                        ),
                                      ),
                                    SizedBox(
                                      width: tileWidth,
                                      child: tile(
                                        Icons.info_outline_rounded,
                                        'Informações do Sistema',
                                        'Resumo, créditos e envie sugestões ou críticas.',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Downloads do app',
                            child: StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .doc('config/appDownloads')
                                  .snapshots(),
                              builder: (context, dlSnap) {
                                final data = dlSnap.data?.data() ?? {};
                                final folderUrl =
                                    (data['driveFolderUrl'] ?? '').toString();
                                final androidUrl =
                                    (data['androidUrl'] ?? '').toString();
                                final iosUrl =
                                    (data['iosUrl'] ?? '').toString();
                                final downloadUrl = androidUrl.isNotEmpty
                                    ? androidUrl
                                    : (iosUrl.isNotEmpty ? iosUrl : folderUrl);

                                void open(String url) {
                                  if (url.isEmpty) return;
                                  launchUrl(
                                    Uri.parse(url),
                                    mode: LaunchMode.externalApplication,
                                  );
                                }

                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: downloadUrl.isEmpty
                                          ? null
                                          : () => open(downloadUrl),
                                      icon: const Icon(Icons.android),
                                      label: const Text('Android'),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: downloadUrl.isEmpty
                                          ? null
                                          : () => open(downloadUrl),
                                      icon: const Icon(Icons.apple),
                                      label: const Text('iOS'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: folderUrl.isEmpty
                                          ? null
                                          : () => open(folderUrl),
                                      icon: const Icon(Icons.folder_open),
                                      label: const Text('Pasta de downloads'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'IgrejaId: $tenantId',
                            style: const TextStyle(color: Colors.black45),
                          ),
                        ],
                      );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Badge no topo direito: Licença Ativa • Vencimento até DD/MM • Plano para X membros
class _LicenseActiveBadge extends StatelessWidget {
  final String tenantId;
  final String planId;

  const _LicenseActiveBadge({required this.tenantId, required this.planId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('igrejas').doc(tenantId).snapshots(),
      builder: (context, tenantSnap) {
        DateTime? vencimento;
        if (tenantSnap.hasData) {
          final billing = tenantSnap.data!.data()?['billing'] as Map<String, dynamic>?;
          final raw = billing?['nextChargeAt'];
          if (raw is Timestamp) vencimento = raw.toDate();
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
          future: planId.isEmpty
              ? Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null)
              : FirebaseFirestore.instance
                  .collection('config')
                  .doc('plans')
                  .collection('items')
                  .doc(planId)
                  .get(),
          builder: (context, planSnap) {
            int membersMax = 0;
            if (planSnap.hasData && planSnap.data != null && planSnap.data!.exists) {
              final data = planSnap.data!.data() ?? {};
              final raw = data['membersMax'] ?? data['limits']?['members'] ?? data['members'];
              membersMax = raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
            }
            final venStr = vencimento != null
                ? '${vencimento.day.toString().padLeft(2, '0')}/${vencimento.month.toString().padLeft(2, '0')}/${vencimento.year}'
                : null;
            final parts = <String>['Licença Ativa'];
            if (venStr != null) parts.add('Vencimento até $venStr');
            if (membersMax > 0) parts.add('Plano para $membersMax membros');
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, color: const Color(0xFFFFE082), size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      parts.join(' • '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final String userName;
  final String? photoUrl;
  final String? tenantId;
  final Map<String, dynamic>? subscription;
  final VoidCallback onLogout;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.userName,
    required this.photoUrl,
    this.tenantId,
    this.subscription,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointTablet;
    final isVeryNarrow = MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointMobile;
    final shortName = userName.length > 12 ? '${userName.substring(0, 10)}…' : userName;
    final status = (subscription?['status'] ?? '').toString().toUpperCase();
    final isActive = status == 'ACTIVE';

    return Container(
      padding: EdgeInsets.fromLTRB(isNarrow ? 12 : 18, isNarrow ? 10 : 16, isNarrow ? 8 : 18, isNarrow ? 10 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2B6CB0), Color(0xFF3B82F6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: isNarrow ? 38 : 44,
            height: isNarrow ? 38 : 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/LOGO_GESTAO_YAHWEH.png',
                fit: BoxFit.contain,
                height: isNarrow ? 30 : 36,
                width: isNarrow ? 30 : 36,
              ),
            ),
          ),
          SizedBox(width: isNarrow ? 8 : 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: isNarrow ? 14 : 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isVeryNarrow)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFDDEBFF),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isActive && tenantId != null && !isVeryNarrow)
            _LicenseActiveBadge(tenantId: tenantId!, planId: (subscription?['planId'] ?? '').toString()),
          if (isActive && tenantId != null && !isVeryNarrow) const SizedBox(width: 12),
          if (!isVeryNarrow) const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
          if (!isVeryNarrow) const SizedBox(width: 6),
          if (!isVeryNarrow) const InstallPwaButton(),
          if (!isVeryNarrow) const SizedBox(width: 12),
          if (!isVeryNarrow)
            Text(
              'Ola, $shortName',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: isNarrow ? 12 : 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(width: 8),
          SafeCircleAvatarImage(
            imageUrl: isValidImageUrl(photoUrl) ? sanitizeImageUrl(photoUrl) : null,
            radius: isNarrow ? 18 : 22,
            fallbackIcon: Icons.person_rounded,
            fallbackColor: const Color(0xFF2B6CB0),
            backgroundColor: Colors.white,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 16, vertical: isNarrow ? 6 : 8),
              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
            ),
            onPressed: onLogout,
            child: Text(isVeryNarrow ? 'Sair' : 'Sair'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFEFF3FA)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _BirthdayChip extends StatelessWidget {
  final String tenantId;
  final String memberId;
  final String cpfDigits;
  final String name;
  final String date;
  final String photoUrl;
  final Map<String, dynamic>? memberData;

  const _BirthdayChip({
    required this.tenantId,
    required this.memberId,
    required this.cpfDigits,
    required this.name,
    required this.date,
    required this.photoUrl,
    this.memberData,
  });

  @override
  Widget build(BuildContext context) {
    final cpf = cpfDigits.replaceAll(RegExp(r'[^0-9]'), '');
    return Container(
      width: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF3)),
      ),
      child: Column(
        children: [
          FotoMembroWidget(
            imageUrl: isValidImageUrl(photoUrl) ? sanitizeImageUrl(photoUrl) : null,
            tenantId: tenantId,
            memberId: memberId,
            cpfDigits: cpf.length >= 9 ? cpf : null,
            memberData: memberData,
            size: 52,
            memCacheWidth: 150,
            memCacheHeight: 150,
            backgroundColor: Colors.grey.shade200,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            date,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              Text(title, style: const TextStyle(color: Colors.black54)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MuralPreview extends StatelessWidget {
  final String tenantId;
  const _MuralPreview({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('noticias')
        .orderBy('createdAt', descending: true)
        .limit(2);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Text('Nenhum aviso publicado ainda.');

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: docs.map((d) {
            final data = d.data();
            final title = (data['title'] ?? 'Aviso').toString();
            final date = data['startAt'] is Timestamp
                ? (data['startAt'] as Timestamp).toDate()
                : null;
            final photos = eventNoticiaPhotoUrls(data);
            final img = photos.isNotEmpty ? photos.first : '';
            return SizedBox(
              width: 260,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (img.isNotEmpty)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: SafeNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 120,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(14),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (date != null)
                            Text(
                              '${date.day}/${date.month}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PieSlice {
  final String label;
  final int value;
  final Color color;
  const _PieSlice({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _GrowthLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<String> labels;
  const _GrowthLineChart({required this.spots, required this.labels});

  @override
  Widget build(BuildContext context) {
    final chartSpots = spots.isEmpty
        ? const [FlSpot(0, 0), FlSpot(1, 0)]
        : spots;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (chartSpots.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (value) => FlLine(
            color: const Color(0xFFE2E8F0),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.round();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[idx],
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: chartSpots,
            isCurved: true,
            curveSmoothness: 0.22,
            color: const Color(0xFF2563EB),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF2563EB).withOpacity(0.18),
                  const Color(0xFF2563EB).withOpacity(0.03),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }
}

class _PieChart extends StatelessWidget {
  final List<_PieSlice> slices;
  final int total;
  const _PieChart({required this.slices, required this.total});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(slices: slices, total: total),
      child: const SizedBox.expand(),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<_PieSlice> slices;
  final int total;
  const _PiePainter({required this.slices, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    double start = -1.5708;
    final sum = total == 0 ? 1 : total;

    for (final s in slices) {
      final sweep = (s.value / sum) * 6.28318;
      paint.color = s.color;
      canvas.drawArc(rect.deflate(10), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AgeBarRow extends StatelessWidget {
  final Map<String, int> values;
  const _AgeBarRow({required this.values});

  @override
  Widget build(BuildContext context) {
    final maxValue = values.values.fold<int>(1, (p, v) => v > p ? v : p);
    return Column(
      children: values.entries.map((e) {
        final w = (e.value / maxValue).clamp(0.0, 1.0).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  e.key,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5EAF3),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: w,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 24,
                child: Text(
                  '${e.value}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _BirthdaysDialog extends StatelessWidget {
  final String tenantId;
  final List<Map<String, dynamic>> birthdays;
  final String Function(DateTime) formatDayMonth;
  const _BirthdaysDialog({
    required this.tenantId,
    required this.birthdays,
    required this.formatDayMonth,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aniversariantes do Mes'),
      content: SizedBox(
        width: 380,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: birthdays.length,
          separatorBuilder: (_, __) => const Divider(height: 12),
          itemBuilder: (context, i) {
            final b = birthdays[i];
            final dt = b['birth'] as DateTime;
            final photo = (b['photo'] as String?) ?? '';
            final mid = (b['id'] as String?) ?? '';
            final cpf = ((b['cpf'] as String?) ?? '').replaceAll(RegExp(r'[^0-9]'), '');
            return Row(
              children: [
                FotoMembroWidget(
                  imageUrl: isValidImageUrl(photo) ? sanitizeImageUrl(photo) : null,
                  tenantId: tenantId,
                  memberId: mid.isNotEmpty ? mid : null,
                  cpfDigits: mid.isNotEmpty && cpf.length >= 9 ? cpf : null,
                  memberData: b['memberData'] as Map<String, dynamic>?,
                  size: 40,
                  memCacheWidth: 150,
                  memCacheHeight: 150,
                  backgroundColor: Colors.grey.shade200,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatDayMonth(dt),
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
