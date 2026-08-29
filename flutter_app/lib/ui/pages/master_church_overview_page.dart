import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/services/church_storage_footprint_service.dart';
import 'package:gestao_yahweh/ui/widgets/master_church_delete_dialog.dart';
import 'package:gestao_yahweh/services/master_church_overview_service.dart';
import 'package:gestao_yahweh/ui/pages/igreja_cadastro_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/url_launcher_helper.dart'
    show openUrlPreferChrome;

/// Slug público a partir do doc da igreja (campo `slug`) ou do id.
String _publicSlugFor(String tenantId, Map<String, dynamic> data) {
  for (final k in ['slug', 'slugId', 'alias']) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  // Nenhuma igreja em produção tem o campo `slug` — o índice público é sempre
  // derivado do id, e é essa a chave que o site resolve.
  return tenantId.trim().replaceAll('_', '-');
}

String _humanBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$s ${units[i]}';
}

/// Tela cheia de uma igreja no painel master.
///
/// Junta num só lugar o que antes estava espalhado (ou não existia): quantos
/// membros, quem lidera, quem administra, os dados cadastrais, quanto ocupa no
/// Storage, os links públicos — e as ações de cadastro completo e exclusão.
class MasterChurchOverviewPage extends StatefulWidget {
  const MasterChurchOverviewPage({
    super.key,
    required this.tenantId,
    this.initialData,
    this.onDeleted,
  });

  final String tenantId;
  final Map<String, dynamic>? initialData;

  /// Chamado depois de a igreja ser apagada — a lista precisa recarregar.
  final VoidCallback? onDeleted;

  @override
  State<MasterChurchOverviewPage> createState() =>
      _MasterChurchOverviewPageState();
}

class _MasterChurchOverviewPageState extends State<MasterChurchOverviewPage> {
  late Future<MasterChurchOverview> _future;
  Future<ChurchStorageFootprint>? _storageFuture;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _future = MasterChurchOverviewService.load(widget.tenantId);
    _storageFuture = ChurchStorageFootprintService.load(widget.tenantId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = MasterChurchOverviewService.load(widget.tenantId);
      _storageFuture = ChurchStorageFootprintService.load(widget.tenantId);
    });
  }

  Future<void> _openCadastroCompleto(MasterChurchOverview o) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IgrejaCadastroPage(
          tenantId: widget.tenantId,
          role: 'adm',
          // Endereça esta igreja mesmo que o painel esteja aberto noutra.
          exactTenant: true,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _confirmDelete(MasterChurchOverview o) async {
    setState(() => _deleting = true);
    final apagou = await confirmAndDeleteChurch(
      context: context,
      tenantId: widget.tenantId,
      churchName: o.name,
    );
    if (!mounted) return;
    if (!apagou) {
      setState(() => _deleting = false);
      return;
    }
    widget.onDeleted?.call();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Igreja'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _deleting ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<MasterChurchOverview>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorBox(error: '${snap.error}', onRetry: _reload);
          }
          final o = snap.data!;
          final pad = ThemeCleanPremium.pagePadding(context);
          return AbsorbPointer(
            absorbing: _deleting,
            child: Opacity(
              opacity: _deleting ? 0.5 : 1,
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 40),
                children: [
                  _HeaderCard(overview: o),
                  const SizedBox(height: 14),
                  _KpiGrid(overview: o),
                  const SizedBox(height: 14),
                  _StorageCard(future: _storageFuture),
                  const SizedBox(height: 14),
                  _PeopleCard(
                    title: 'Gestores',
                    subtitle: 'Quem administra o painel desta igreja',
                    icon: Icons.admin_panel_settings_rounded,
                    accent: const Color(0xFF7C3AED),
                    people: o.managers,
                    emptyLabel: 'Nenhum gestor registado.',
                  ),
                  const SizedBox(height: 14),
                  _PeopleCard(
                    title: 'Líderes',
                    subtitle: 'Pastores, líderes, diáconos e demais cargos',
                    icon: Icons.workspace_premium_rounded,
                    accent: const Color(0xFF0D9488),
                    people: o.leaders,
                    emptyLabel: 'Nenhum cargo de liderança atribuído.',
                  ),
                  const SizedBox(height: 14),
                  _DataCard(overview: o),
                  const SizedBox(height: 14),
                  _PublicLinksCard(overview: o),
                  const SizedBox(height: 18),
                  _ActionsCard(
                    busy: _deleting,
                    onCadastro: () => _openCadastroCompleto(o),
                    onDelete: () => _confirmDelete(o),
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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: ThemeCleanPremium.error,
            ),
            const SizedBox(height: 10),
            Text(
              'Não foi possível carregar a igreja.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: ThemeCleanPremium.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.overview});
  final MasterChurchOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final logo = o.logoUrl;
    return MasterPremiumCard(
      expandWidth: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            clipBehavior: Clip.antiAlias,
            child: logo.isNotEmpty
                ? Image.network(
                    logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.church_rounded,
                      color: ThemeCleanPremium.primary,
                    ),
                  )
                : const Icon(
                    Icons.church_rounded,
                    color: ThemeCleanPremium.primary,
                    size: 28,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        o.tenantId,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar ID',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: o.tenantId),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            ThemeCleanPremium.successSnackBar('ID copiado.'),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (o.plan.isNotEmpty)
                      _Pill(
                        label: 'Plano: ${o.plan}',
                        color: const Color(0xFF2563EB),
                      ),
                    if (o.expiresAt != null)
                      _Pill(
                        label:
                            'Vence ${o.expiresAt!.day.toString().padLeft(2, '0')}/'
                            '${o.expiresAt!.month.toString().padLeft(2, '0')}/'
                            '${o.expiresAt!.year}',
                        color: const Color(0xFFD97706),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.overview});
  final MasterChurchOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final tiles = <Widget>[
      MasterKpiCard(
        label: 'Membros',
        value: '${o.membersTotal}',
        icon: Icons.people_rounded,
        accent: const Color(0xFF2563EB),
        subtitle: o.membersPending > 0
            ? '${o.membersPending} pendente(s)'
            : (o.membersActive > 0 ? '${o.membersActive} ativos' : null),
      ),
      MasterKpiCard(
        label: 'Líderes',
        value: '${o.leaders.length}',
        icon: Icons.workspace_premium_rounded,
        accent: const Color(0xFF0D9488),
      ),
      MasterKpiCard(
        label: 'Gestores',
        value: '${o.managers.length}',
        icon: Icons.admin_panel_settings_rounded,
        accent: const Color(0xFF7C3AED),
      ),
      MasterKpiCard(
        label: 'Departamentos',
        value: '${o.departmentsCount}',
        icon: Icons.groups_rounded,
        accent: const Color(0xFFF59E0B),
      ),
      MasterKpiCard(
        label: 'Eventos',
        value: '${o.eventsCount}',
        icon: Icons.celebration_rounded,
        accent: const Color(0xFFEC4899),
      ),
      MasterKpiCard(
        label: 'Avisos',
        value: '${o.avisosCount}',
        icon: Icons.campaign_rounded,
        accent: const Color(0xFF16A34A),
      ),
    ];
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final cols = w > 1100 ? 3 : (w > 700 ? 2 : 1);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: tiles
              .map(
                (t) => SizedBox(
                  width: (c.maxWidth - 12 * (cols - 1)) / cols,
                  child: t,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.future});
  final Future<ChurchStorageFootprint>? future;

  @override
  Widget build(BuildContext context) {
    return MasterPremiumCard(
      expandWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.cloud_rounded,
            accent: Color(0xFF0EA5E9),
            title: 'Armazenamento',
            subtitle: 'Espaço ocupado por esta igreja no Storage',
          ),
          const SizedBox(height: 12),
          FutureBuilder<ChurchStorageFootprint>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 3),
                );
              }
              if (snap.hasError || snap.data == null) {
                return Text(
                  'Não foi possível medir o espaço agora.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                );
              }
              final r = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _humanBytes(r.totalBytes),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.totalFiles} ficheiro(s) no Storage'
                    '${r.firestoreDocs > 0 ? ' · ${r.firestoreDocs} documento(s) no Firestore' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  if (r.groups.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...r.groups.map(
                      (g) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(
                                g.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ThemeCleanPremium.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: r.totalBytes <= 0
                                      ? 0
                                      : g.bytes / r.totalBytes,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_humanBytes(g.bytes)} · ${g.files}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.people,
    required this.emptyLabel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<MasterChurchPerson> people;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return MasterPremiumCard(
      expandWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: icon,
            accent: accent,
            title: '$title (${people.length})',
            subtitle: subtitle,
          ),
          const SizedBox(height: 10),
          if (people.isEmpty)
            Text(
              emptyLabel,
              style: TextStyle(
                fontSize: 12,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            )
          else
            ...people.take(30).map((p) => _PersonRow(person: p, accent: accent)),
          if (people.length > 30) ...[
            const SizedBox(height: 6),
            Text(
              '+ ${people.length - 30} não listados',
              style: TextStyle(
                fontSize: 11,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.accent});
  final MasterChurchPerson person;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initials = person.name.trim().isEmpty
        ? '?'
        : person.name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w.characters.first.toUpperCase())
              .join();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: accent.withValues(alpha: 0.14),
            backgroundImage: person.photoUrl.isNotEmpty
                ? NetworkImage(person.photoUrl)
                : null,
            child: person.photoUrl.isEmpty
                ? Text(
                    initials,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                if (person.email.isNotEmpty || person.phone.isNotEmpty)
                  Text(
                    [
                      if (person.email.isNotEmpty) person.email,
                      if (person.phone.isNotEmpty) person.phone,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Pill(label: person.role, color: accent),
        ],
      ),
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.overview});
  final MasterChurchOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final linhas = <(String, String)>[
      ('Nome', o.name),
      if (o.document.isNotEmpty) ('CNPJ / CPF', o.document),
      if (o.address.isNotEmpty) ('Endereço', o.address),
      if (o.phone.isNotEmpty) ('Telefone', o.phone),
      if (o.managerName.isNotEmpty) ('Gestor', o.managerName),
      if (o.managerEmail.isNotEmpty) ('E-mail do gestor', o.managerEmail),
      if (o.managerPhone.isNotEmpty) ('Telefone do gestor', o.managerPhone),
    ];
    return MasterPremiumCard(
      expandWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.badge_rounded,
            accent: Color(0xFF2563EB),
            title: 'Dados da igreja',
            subtitle: 'Identidade, endereço e contacto do responsável',
          ),
          const SizedBox(height: 10),
          ...linhas.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      l.$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      l.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (linhas.length <= 1) ...[
            const SizedBox(height: 6),
            Text(
              'Cadastro incompleto — use «Cadastro completo» abaixo para '
              'preencher logo, endereço e responsável.',
              style: TextStyle(
                fontSize: 12,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublicLinksCard extends StatelessWidget {
  const _PublicLinksCard({required this.overview});
  final MasterChurchOverview overview;

  @override
  Widget build(BuildContext context) {
    final slug = _publicSlugFor(overview.tenantId, overview.data);
    final site = AppConstants.publicChurchHomeUrl(slug);
    final signup = AppConstants.publicChurchMemberSignupUrl(
      slug,
      church: overview.data,
    );
    return MasterPremiumCard(
      expandWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.public_rounded,
            accent: Color(0xFF16A34A),
            title: 'Links públicos',
            subtitle: 'Site da igreja e cadastro de novos membros',
          ),
          const SizedBox(height: 12),
          _LinkRow(
            icon: Icons.language_rounded,
            title: 'Site público',
            url: site,
          ),
          const SizedBox(height: 8),
          _LinkRow(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Cadastro de membros',
            url: signup,
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, required this.url});
  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: ThemeCleanPremium.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  url,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  ThemeCleanPremium.successSnackBar('Link copiado.'),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'Abrir',
            onPressed: () => unawaited(openUrlPreferChrome(url)),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.busy,
    required this.onCadastro,
    required this.onDelete,
  });
  final bool busy;
  final VoidCallback onCadastro;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return MasterPremiumCard(
      expandWidth: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.tune_rounded,
            accent: Color(0xFF64748B),
            title: 'Ações',
            subtitle: 'Editar o cadastro completo ou remover a igreja',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : onCadastro,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_document, size: 18),
            label: const Text(
              'Cadastro completo (logo, endereço, responsável)',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onDelete,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: ThemeCleanPremium.error,
              side: BorderSide(
                color: ThemeCleanPremium.error.withValues(alpha: 0.5),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(
              busy ? 'A excluir…' : 'Excluir igreja (Firestore + Storage)',
            ),
          ),
        ],
      ),
    );
  }
}
