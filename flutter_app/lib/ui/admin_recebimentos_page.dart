import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Recebimentos de licenças — sales (Mercado Pago) + status por tenant. Super Premium, responsivo.
class AdminRecebimentosPage extends StatelessWidget {
  const AdminRecebimentosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + 24),
          children: [
            Text(
              'Recebimentos de Licenças',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: isMobile ? 22 : 24,
                    color: ThemeCleanPremium.onSurface,
                  ) ??
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: ThemeCleanPremium.onSurface),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            Text(
              'Cobranças do Mercado Pago e status das licenças por igreja.',
              style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text(
              'Resumo por período',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            _RecebimentosResumoWidget(),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text(
              'Cobranças recebidas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            _SalesList(),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Text(
              'Licenças por igreja',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceSm),
            _LicensesSummary(),
          ],
        ),
      ),
    );
  }
}

/// Resumo de recebimentos por período: Hoje, semana, mês, ano e personalizado (sales + mp_payments se existir).
class _RecebimentosResumoWidget extends StatefulWidget {
  @override
  State<_RecebimentosResumoWidget> createState() => _RecebimentosResumoWidgetState();
}

class _RecebimentosResumoWidgetState extends State<_RecebimentosResumoWidget> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  String? _loadError;
  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 365));
  DateTime _periodEnd = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final List<Map<String, dynamic>> list = [];
      final salesSnap = await FirebaseFirestore.instance.collection('sales').limit(1000).get();
      for (final d in salesSnap.docs) {
        final data = d.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status.isNotEmpty &&
            status != 'approved' &&
            status != 'paid' &&
            status != 'accredited') {
          continue;
        }
        list.add(data);
      }
      final mpSnap = await FirebaseFirestore.instance.collection('mp_payments').limit(1000).get();
      for (final d in mpSnap.docs) {
        final data = d.data();
        if ((data['status'] ?? '').toString() != 'approved') continue;
        final raw = data['raw'];
        if (raw is Map) list.add({'amount': (raw['transaction_amount'] is num) ? (raw['transaction_amount'] as num).toDouble() : 0, 'createdAt': raw['date_approved']});
      }
      if (mounted) setState(() {
        _payments = list;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      final err = e.toString();
      final isPermissionDenied = err.contains('permission-denied') || err.contains('PERMISSION_DENIED');
      if (mounted) setState(() {
        _payments = [];
        _loading = false;
        _loadError = isPermissionDenied
            ? 'Sem permissão. Faça login como administrador e publique as regras do Firestore (firebase deploy --only firestore:rules).'
            : null;
      });
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static double _amount(Map<String, dynamic> d) {
    if (d['amount'] != null) return (d['amount'] as num).toDouble();
    final raw = d['raw'];
    if (raw is! Map) return 0;
    final a = raw['transaction_amount'];
    if (a is num) return a.toDouble();
    return double.tryParse(a?.toString() ?? '0') ?? 0;
  }

  double _totalInRange(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
    double sum = 0;
    for (final d in _payments) {
      DateTime? dt = _parseDate(d['createdAt']);
      if (dt == null && d['raw'] is Map) dt = _parseDate((d['raw'] as Map)['date_approved']);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (!day.isBefore(startDay) && !day.isAfter(endDay)) sum += _amount(d);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final yearStart = DateTime(now.year, 1, 1);
    const brandBlue = Color(0xFF1E293B);
    const brandTeal = Color(0xFF0D9488);

    if (_loading) {
      return _PremiumCard(
        child: const Padding(
          padding: EdgeInsets.all(ThemeCleanPremium.spaceLg),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final daily = _totalInRange(todayStart, now);
    final weekly = _totalInRange(weekStartDay, now);
    final monthly = _totalInRange(monthStart, now);
    final annual = _totalInRange(yearStart, now);
    final custom = _totalInRange(
      DateTime(_periodStart.year, _periodStart.month, _periodStart.day),
      DateTime(_periodEnd.year, _periodEnd.month, _periodEnd.day, 23, 59, 59),
    );

    return _PremiumCard(
      child: Padding(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loadError != null) ...[
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_loadError!, style: TextStyle(fontSize: 13, color: Colors.grey.shade800))),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _recebCard('Hoje', daily, brandTeal),
                _recebCard('Esta semana', weekly, brandBlue),
                _recebCard('Este mês', monthly, brandTeal),
                _recebCard('Este ano', annual, brandBlue),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Período personalizado', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      DateFormat('dd/MM/yyyy').format(_periodStart),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _periodStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _periodStart = d);
                    },
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('até')),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                      DateFormat('dd/MM/yyyy').format(_periodEnd),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _periodEnd,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setState(() => _periodEnd = d);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                  tooltip: 'Recarregar pagamentos',
                  style: IconButton.styleFrom(
                    minimumSize: Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: brandBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payment_rounded, color: brandBlue, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Total no período: R\$ ${custom.toStringAsFixed(2).replaceFirst('.', ',')}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _recebCard(String label, double value, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(
          'R\$ ${value.toStringAsFixed(2).replaceFirst('.', ',')}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
        ),
      ],
    ),
  );
}

class _SalesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sales')
          .orderBy('createdAt', descending: true)
          .limit(80)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final err = snapshot.error.toString();
          final isPermissionDenied = err.contains('permission-denied') || err.contains('PERMISSION_DENIED');
          return _PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: ThemeCleanPremium.spaceSm),
                  Expanded(
                    child: Text(
                      isPermissionDenied
                          ? 'Sem permissão para acessar cobranças. Confirme que você está logado como administrador (Painel Master) e que as regras do Firestore foram publicadas (firebase deploy --only firestore:rules).'
                          : 'Erro ao carregar: $err',
                      style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              child: Text(
                'Nenhuma cobrança registrada. Pagamentos via Mercado Pago (PIX ou cartão) aparecem aqui.',
                style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14),
              ),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final tenantId = d['tenantId'] ?? '';
            final amount = (d['amount'] ?? 0).toDouble();
            final status = (d['status'] ?? '').toString();
            final type = (d['type'] ?? 'payment').toString();
            final createdAt = d['createdAt'] is Timestamp
                ? (d['createdAt'] as Timestamp).toDate()
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: _PremiumCard(
                child: Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.payment_rounded, color: Colors.green.shade700, size: 24),
                          const SizedBox(width: ThemeCleanPremium.spaceSm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Igreja: $tenantId',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${type == 'preapproval' ? 'Assinatura' : 'Pagamento'} • $status'
                                  '${createdAt != null ? ' • ${_fmt(createdAt)}' : ''}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'R\$ ${amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _LicensesSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final minTouch = ThemeCleanPremium.minTouchTarget;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('igrejas').limit(150).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final err = snapshot.error.toString();
          final isPermissionDenied = err.contains('permission-denied') || err.contains('PERMISSION_DENIED');
          return _PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                  const SizedBox(width: ThemeCleanPremium.spaceSm),
                  Expanded(
                    child: Text(
                      isPermissionDenied
                          ? 'Sem permissão para listar igrejas. Confirme o login como administrador e as regras do Firestore.'
                          : 'Erro: $err',
                      style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _PremiumCard(
            child: Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
              child: Center(
                child: Text(
                  'Nenhuma licença cadastrada.',
                  style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 15),
                ),
              ),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(docs.length, (i) {
            final d = docs[i].data();
            final tenantId = docs[i].id;
            final name = (d['name'] ?? d['nome'] ?? tenantId).toString();
            final license = d['license'] as Map<String, dynamic>?;
            final status = (license?['status'] ?? d['licenseStatus'] ?? '-').toString();
            final billing = d['billing'] as Map<String, dynamic>?;
            final billingStatus = (billing?['status'] ?? d['billingStatus'] ?? '-').toString();
            final gestorNome = (d['gestorNome'] ?? d['gestor_nome'] ?? d['gestorName'] ?? '').toString().trim();
            final gestorEmail = (d['gestorEmail'] ?? d['gestor_email'] ?? d['email'] ?? '').toString().trim();
            final gestorTelefone = (d['gestorTelefone'] ?? d['gestor_telefone'] ?? d['phone'] ?? d['telefone'] ?? '').toString().trim();
            final hasGestor = gestorNome.isNotEmpty || gestorEmail.isNotEmpty || gestorTelefone.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
              child: _PremiumCard(
                child: Padding(
                  padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: status == 'active' ? Colors.green : Colors.orange.shade200,
                            child: Icon(
                              status == 'active' ? Icons.check_rounded : Icons.schedule_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: ThemeCleanPremium.spaceMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: ThemeCleanPremium.onSurface,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (hasGestor) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      if (gestorNome.isNotEmpty) gestorNome,
                                      if (gestorEmail.isNotEmpty) gestorEmail,
                                      if (gestorTelefone.isNotEmpty) gestorTelefone,
                                    ].join(' • '),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Licença: $status • Cobrança: $billingStatus',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (hasGestor) ...[
                        const SizedBox(height: ThemeCleanPremium.spaceSm),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (gestorEmail.isNotEmpty)
                              _ActionChip(
                                icon: Icons.copy_rounded,
                                label: 'Copiar e-mail',
                                minTouch: minTouch,
                                isMobile: isMobile,
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: gestorEmail));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ThemeCleanPremium.successSnackBar('E-mail do gestor copiado.'),
                                  );
                                },
                              ),
                            if (gestorEmail.isNotEmpty)
                              _ActionChip(
                                icon: Icons.email_outlined,
                                label: 'E-mail',
                                minTouch: minTouch,
                                isMobile: isMobile,
                                onPressed: () => launchUrl(Uri.parse('mailto:$gestorEmail')),
                              ),
                            if (gestorTelefone.isNotEmpty)
                              _ActionChip(
                                icon: Icons.chat_rounded,
                                label: 'WhatsApp',
                                minTouch: minTouch,
                                isMobile: isMobile,
                                onPressed: () {
                                  final tel = gestorTelefone.replaceAll(RegExp(r'[^\d+]'), '');
                                  final link = tel.startsWith('+') ? 'https://wa.me/$tel' : 'https://wa.me/55$tel';
                                  launchUrl(Uri.parse(link));
                                },
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Card com borda 16px e sombra suave (Super Premium).
class _PremiumCard extends StatelessWidget {
  final Widget child;

  const _PremiumCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}

/// Botão de ação com área de toque mínima em mobile.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double minTouch;
  final bool isMobile;
  final VoidCallback onPressed;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.minTouch,
    required this.isMobile,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeCleanPremium.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ThemeCleanPremium.spaceSm,
            vertical: isMobile ? (minTouch - 24) / 2 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: ThemeCleanPremium.primary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ThemeCleanPremium.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
