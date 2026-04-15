import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/services/schedule_swap_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/pages/member_schedule_availability_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Agrupa documentos de escala por dia civil (ordenados por horário dentro do dia).
Map<DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupSchedulesByDay(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final map = <DateTime, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  for (final d in docs) {
    DateTime? dt;
    try {
      dt = (d.data()['date'] as Timestamp).toDate();
    } catch (_) {}
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    map.putIfAbsent(day, () => []).add(d);
  }
  for (final list in map.values) {
    list.sort((a, b) {
      final ta = (a.data()['time'] ?? '').toString();
      final tb = (b.data()['time'] ?? '').toString();
      return ta.compareTo(tb);
    });
  }
  return map;
}

String _capitalizeFirstLetter(String s) {
  final t = s.trim();
  if (t.isEmpty) return s;
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

String _statusLabelPt(String raw) {
  switch (raw) {
    case 'confirmado':
      return 'Confirmado';
    case 'indisponivel':
      return 'Indisponível';
    case 'falta_nao_justificada':
      return 'Falta';
    default:
      return raw.isEmpty ? 'Pendente' : raw;
  }
}

Color _statusColor(String raw) {
  switch (raw) {
    case 'confirmado':
      return ThemeCleanPremium.success;
    case 'indisponivel':
      return ThemeCleanPremium.error;
    case 'falta_nao_justificada':
      return const Color(0xFFB91C1C);
    default:
      return Colors.grey.shade600;
  }
}

/// Pré-visualização premium: uma ou várias frentes (mesmo dia).
Future<void> showEscalaPremiumPreviewSheet(
  BuildContext context, {
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required DateTime now,
  required String cpfDigits,
  required List<Color> deptColors,
  required Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm,
  Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? onRequestSwap,
  DateTime? dayContext,
}) async {
  if (docs.isEmpty) return;
  final primary = ThemeCleanPremium.primary;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottomInset = MediaQuery.paddingOf(ctx).bottom;
      final maxH = MediaQuery.sizeOf(ctx).height * 0.92;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primary,
                          primary.withValues(alpha: 0.85),
                          const Color(0xFF0F172A).withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded, color: Colors.white),
                              tooltip: 'Fechar',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    docs.length > 1
                                        ? 'Escalas do dia'
                                        : 'Detalhe da escala',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.88),
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dayContext != null
                                        ? _capitalizeFirstLetter(
                                            DateFormat("EEEE, d 'de' MMMM yyyy", 'pt_BR').format(dayContext),
                                          )
                                        : (() {
                                            DateTime? dt;
                                            try {
                                              dt = (docs.first.data()['date'] as Timestamp).toDate();
                                            } catch (_) {}
                                            return dt != null
                                                ? _capitalizeFirstLetter(
                                                    DateFormat("EEEE, d 'de' MMMM yyyy", 'pt_BR').format(dt),
                                                  )
                                                : 'Data';
                                          })(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var di = 0; di < docs.length; di++) ...[
                            if (di > 0) const SizedBox(height: 18),
                            _EscalaPreviewSection(
                              doc: docs[di],
                              now: now,
                              cpfDigits: cpfDigits,
                              deptColors: deptColors,
                              onConfirm: onConfirm,
                              onRequestSwap: onRequestSwap,
                              showDividerHeader: docs.length > 1,
                              indexLabel: docs.length > 1 ? '${di + 1}/${docs.length}' : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _EscalaPreviewSection extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final DateTime now;
  final String cpfDigits;
  final List<Color> deptColors;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? onRequestSwap;
  final bool showDividerHeader;
  final String? indexLabel;

  const _EscalaPreviewSection({
    required this.doc,
    required this.now,
    required this.cpfDigits,
    required this.deptColors,
    required this.onConfirm,
    this.onRequestSwap,
    this.showDividerHeader = false,
    this.indexLabel,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();
    final title = (m['title'] ?? 'Escala').toString();
    final dept = (m['departmentName'] ?? '').toString();
    final time = (m['time'] ?? '').toString();
    final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};
    final deptId = (m['departmentId'] ?? '').toString();
    final color = deptColors[deptId.hashCode.abs() % deptColors.length];
    DateTime? dt;
    try {
      dt = (m['date'] as Timestamp).toDate();
    } catch (_) {}
    final isFuture = dt != null && dt.isAfter(now.subtract(const Duration(hours: 12)));

    String confForCpf(String c) {
      var s = (confirmations[c] ?? '').toString();
      if (s.isEmpty) {
        for (final k in confirmations.keys) {
          if (k.toString().replaceAll(RegExp(r'[^0-9]'), '') ==
              c.replaceAll(RegExp(r'[^0-9]'), '')) {
            s = (confirmations[k] ?? '').toString();
            break;
          }
        }
      }
      return s;
    }

    String myStatus = confForCpf(cpfDigits);
    final unavailabilityReasons = (m['unavailabilityReasons'] as Map<String, dynamic>?) ?? {};
    String? myReason;
    for (final k in unavailabilityReasons.keys) {
      if (k.toString().replaceAll(RegExp(r'[^0-9]'), '') ==
          cpfDigits.replaceAll(RegExp(r'[^0-9]'), '')) {
        final v = unavailabilityReasons[k];
        if (v is Map && v['reason'] != null) myReason = v['reason'].toString();
        break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0C0F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showDividerHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
                  if (indexLabel != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        indexLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300, height: 1)),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                    if (time.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.65)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              time,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (dt != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.event_rounded, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat("dd/MM/yyyy · EEEE", 'pt_BR').format(dt),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
                if (dept.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.church_rounded, size: 18, color: color),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dept,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Equipe (${cpfs.isEmpty ? 0 : cpfs.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                if (cpfs.isEmpty)
                  Text(
                    'Nenhum membro listado nesta frente.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  )
                else
                  ...List.generate(cpfs.length, (i) {
                    final c = cpfs[i];
                    final n = i < names.length && names[i].trim().isNotEmpty
                        ? names[i].trim()
                        : 'Membro ${i + 1}';
                    final conf = confForCpf(c);
                    final stColor = _statusColor(conf.isEmpty ? '' : conf);
                    final initials = n.isNotEmpty
                        ? n.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0]).join()
                        : '?';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: stColor.withValues(alpha: 0.15),
                              child: Text(
                                initials.isNotEmpty ? initials.toUpperCase() : '?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: stColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (c.length == 11)
                                    Text(
                                      '***.${c.substring(6, 9)}-**',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: stColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabelPt(conf),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: stColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                if (isFuture && cpfDigits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Confirmar',
                          icon: Icons.check_circle_rounded,
                          color: ThemeCleanPremium.success,
                          active: myStatus == 'confirmado',
                          onTap: () async {
                            await onConfirm(doc, myStatus == 'confirmado' ? '' : 'confirmado');
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Indisponível',
                          icon: Icons.cancel_rounded,
                          color: ThemeCleanPremium.error,
                          active: myStatus == 'indisponivel',
                          onTap: () async {
                            if (myStatus == 'indisponivel') {
                              await onConfirm(doc, '');
                              if (context.mounted) Navigator.pop(context);
                              return;
                            }
                            final reason = await showDialog<String>(
                              context: context,
                              builder: (ctx) {
                                final ctrl = TextEditingController();
                                return AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                                  ),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.cancel_rounded, color: ThemeCleanPremium.error),
                                      SizedBox(width: 10),
                                      Text('Indisponível', style: TextStyle(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Informe o motivo (o gestor verá esta justificativa):',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: ctrl,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: viagem, saúde, compromisso...',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                                          ),
                                          filled: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                                      style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
                                      child: const Text('Enviar'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (reason != null) {
                              await onConfirm(
                                doc,
                                'indisponivel',
                                reason.isNotEmpty ? reason : null,
                              );
                              if (context.mounted) Navigator.pop(context);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (onRequestSwap != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await onRequestSwap!(doc);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Solicitar troca'),
                      ),
                    ),
                  ],
                ] else if (myStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: (myStatus == 'confirmado' ? ThemeCleanPremium.success : ThemeCleanPremium.error)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          myStatus == 'confirmado'
                              ? 'Você confirmou presença'
                              : 'Você marcou indisponível',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: myStatus == 'confirmado'
                                ? ThemeCleanPremium.success
                                : ThemeCleanPremium.error,
                          ),
                        ),
                        if (myStatus == 'indisponivel' && (myReason ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Motivo: ${myReason!.trim()}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ],
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

class MySchedulesPage extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  /// Dentro de [IgrejaCleanShell]: evita [SafeArea] superior extra sob o cartão do módulo.
  final bool embeddedInShell;
  const MySchedulesPage({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<MySchedulesPage> createState() => _MySchedulesPageState();
}

/// Filtro de período — sem calendário em grelha: navegação por mês + atalhos.
const _periodFilterKeys = [
  ('month', 'Por mês'),
  ('year', 'Ano'),
  ('day', 'Hoje'),
  ('custom', 'Intervalo'),
];

class _MySchedulesPageState extends State<MySchedulesPage> {
  /// Pode ser preenchido a partir da ficha em `membros` se o perfil vier sem CPF.
  String _cpfDigits = '';
  late Future<String> _effectiveTidFuture;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = [];
  bool _loading = true;
  /// `month` = lista só no mês de [_monthCursor] (setas anterior/próximo).
  String _dateFilter = 'month';
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _periodStart;
  DateTime? _periodEnd;
  /// Vista em grade (cartões) vs lista por dia.
  bool _useGridView = false;

  static const _deptColors = [
    Color(0xFF3B82F6), Color(0xFF16A34A), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF8B5CF6), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF059669),
  ];

  @override
  void initState() {
    super.initState();
    _cpfDigits = widget.cpf.replaceAll(RegExp(r'[^0-9]'), '');
    _effectiveTidFuture = TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
    _bootstrap();
  }

  /// Extrai 11 dígitos do documento de membro (campos CPF/cpf ou ID = CPF).
  String? _cpfDigitsFromMemberDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    for (final k in ['CPF', 'cpf', 'documento']) {
      final raw = (data[k] ?? '').toString();
      final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 11) return d;
    }
    final idDigits = doc.id.replaceAll(RegExp(r'[^0-9]'), '');
    if (idDigits.length == 11) return idDigits;
    return null;
  }

  /// Quando o login não traz CPF no perfil, busca na ficha `membros` (authUid / e-mail).
  Future<void> _hydrateCpfFromMemberRecord() async {
    if (_cpfDigits.length == 11) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    late final String tid;
    try {
      tid = await _effectiveTidFuture;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('membros');

    Future<bool> applyFirst(QuerySnapshot<Map<String, dynamic>> snap) async {
      if (snap.docs.isEmpty) return false;
      final extracted = _cpfDigitsFromMemberDoc(snap.docs.first);
      if (extracted != null && mounted) {
        setState(() => _cpfDigits = extracted);
        return true;
      }
      return false;
    }

    try {
      if (await applyFirst(
          await col.where('authUid', isEqualTo: user.uid).limit(1).get())) {
        return;
      }
    } catch (_) {}
    try {
      if (await applyFirst(
          await col.where('firebaseUid', isEqualTo: user.uid).limit(1).get())) {
        return;
      }
    } catch (_) {}

    final email = user.email?.trim();
    if (email == null || email.isEmpty) return;
    final variants = <String>{email, email.toLowerCase()};
    for (final v in variants) {
      try {
        if (await applyFirst(
            await col.where('email', isEqualTo: v).limit(1).get())) {
          return;
        }
      } catch (_) {}
      try {
        if (await applyFirst(
            await col.where('EMAIL', isEqualTo: v).limit(1).get())) {
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _bootstrap() async {
    await _hydrateCpfFromMemberRecord();
    if (mounted) await _load();
  }

  bool get _isAdmin {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tid = await _effectiveTidFuture;
      final schedules = FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('escalas');
      final members = FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      if (_isAdmin) {
        final snap = await schedules.orderBy('date').limit(200).get();
        docs = snap.docs;
      } else {
        final deptIds = await _loadMemberDepartments(members);
        final byMember = _cpfDigits.isNotEmpty
            ? (await schedules.where('memberCpfs', arrayContains: _cpfDigits).get()).docs
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final byDept = deptIds.isNotEmpty && deptIds.length <= 10
            ? (await schedules.where('departmentId', whereIn: deptIds).get()).docs
            : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in byMember) {
          map[d.id] = d;
        }
        for (final d in byDept) {
          map.putIfAbsent(d.id, () => d);
        }
        docs = map.values.toList()..sort((a, b) {
          final da = (a.data()['date'] as Timestamp?)?.toDate();
          final db = (b.data()['date'] as Timestamp?)?.toDate();
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
      }
      _allDocs = docs;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Documentos filtrados pelo período selecionado (sem widget de calendário em grelha).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filteredDocs {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final yNav = _monthCursor.year;
    final mNav = _monthCursor.month;
    final startOfNavMonth = DateTime(yNav, mNav, 1);
    final endOfNavMonth = DateTime(yNav, mNav + 1, 0, 23, 59, 59);
    final startOfNavYear = DateTime(yNav, 1, 1);
    final endOfNavYear = DateTime(yNav, 12, 31, 23, 59, 59);

    return _allDocs.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) return false;
      switch (_dateFilter) {
        case 'month':
          return !dt.isBefore(startOfNavMonth) && !dt.isAfter(endOfNavMonth);
        case 'year':
          return !dt.isBefore(startOfNavYear) && !dt.isAfter(endOfNavYear);
        case 'day':
          return !dt.isBefore(startOfToday) && !dt.isAfter(endOfToday);
        case 'custom':
          if (_periodStart == null || _periodEnd == null) return true;
          final start = DateTime(_periodStart!.year, _periodStart!.month, _periodStart!.day);
          final end = DateTime(_periodEnd!.year, _periodEnd!.month, _periodEnd!.day, 23, 59, 59);
          return !dt.isBefore(start) && !dt.isAfter(end);
        default:
          return !dt.isBefore(startOfNavMonth) && !dt.isAfter(endOfNavMonth);
      }
    }).toList();
  }

  /// Escalas do filtro atual, ordenadas por data e horário.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _sortedFilteredDocs {
    final list =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_filteredDocs);
    list.sort((a, b) {
      DateTime? da;
      DateTime? db;
      try {
        da = (a.data()['date'] as Timestamp).toDate();
      } catch (_) {}
      try {
        db = (b.data()['date'] as Timestamp).toDate();
      } catch (_) {}
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final c = da.compareTo(db);
      if (c != 0) return c;
      return (a.data()['time'] ?? '')
          .toString()
          .compareTo((b.data()['time'] ?? '').toString());
    });
    return list;
  }

  Future<List<String>> _loadMemberDepartments(CollectionReference<Map<String, dynamic>> members) async {
    if (_cpfDigits.isEmpty) return [];
    final byId = await members.doc(_cpfDigits).get();
    if (byId.exists) return _deptList(byId.data());
    final q = await members.where('CPF', isEqualTo: _cpfDigits).limit(1).get();
    if (q.docs.isNotEmpty) return _deptList(q.docs.first.data());
    return [];
  }

  List<String> _deptList(Map<String, dynamic>? data) {
    final raw = data?['DEPARTAMENTOS'];
    return raw is List ? raw.map((e) => e.toString()).toList() : [];
  }

  /// Retorna a chave de CPF usada no documento (igual à de memberCpfs/confirmations).
  String _confirmationKey(Map<String, dynamic> data) {
    final raw = data['memberCpfs'];
    final normalized = _cpfDigits.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw is List) {
      for (final e in raw) {
        final c = e?.toString() ?? '';
        if (c.replaceAll(RegExp(r'[^0-9]'), '') == normalized) return c;
      }
    }
    return _cpfDigits;
  }

  Future<void> _abrirPedidoTroca(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> escalaDoc,
  ) async {
    if (_cpfDigits.length != 11) return;
    final m = escalaDoc.data();
    final deptId = (m['departmentId'] ?? '').toString();
    if (deptId.isEmpty) return;
    DateTime? escDt;
    try {
      escDt = (m['date'] as Timestamp?)?.toDate();
    } catch (_) {}
    if (escDt == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data da escala inválida.')),
      );
      return;
    }
    final escalaTime = (m['time'] ?? '19:00').toString();
    final escalaTitle = (m['title'] ?? 'Escala').toString().trim();
    final escalaDateLabel = DateFormat('dd/MM/yyyy', 'pt_BR').format(escDt);
    final memberCpfs =
        ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final currentNorm = <String>{
      for (final c in memberCpfs) c.replaceAll(RegExp(r'[^0-9]'), ''),
    };

    final tid = await _effectiveTidFuture;
    if (!context.mounted) return;

    String solicitanteNome = '';
    try {
      final col =
          FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');
      final byId = await col.doc(_cpfDigits).get();
      if (byId.exists) {
        final d = byId.data()!;
        solicitanteNome =
            (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
      } else {
        final q = await col.where('CPF', isEqualTo: _cpfDigits).limit(1).get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          solicitanteNome =
              (d['NOME_COMPLETO'] ?? d['nome'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    List<ScheduleSwapCandidate> candidates;
    try {
      candidates = await ScheduleSwapService.filterFreeCandidates(
        tenantId: tid,
        departmentId: deptId,
        solicitanteCpfDigits: _cpfDigits,
        escalaDay: escDt,
        escalaTime: escalaTime,
        currentEscalaMemberCpfsNorm: currentNorm,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar irmãos disponíveis: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não há irmãos livres neste horário (outra escala no mesmo dia ou indisponibilidade no calendário).',
          ),
        ),
      );
      return;
    }

    final chosen = await showDialog<ScheduleSwapCandidate?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Solicitar troca'),
        content: SizedBox(
          width: 320,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Só aparecem irmãos do mesmo departamento livres nesta data e horário.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final o = candidates[i];
                    return ListTile(
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: Text(o.nome),
                      subtitle: const Text(
                        'Livre neste horário',
                        style: TextStyle(fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(ctx, o),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tid)
          .collection('escala_trocas')
          .add({
        'escalaId': escalaDoc.id,
        'departmentId': deptId,
        'solicitanteCpf': _cpfDigits,
        'alvoCpf': chosen.cpf,
        'status': 'pendente_alvo',
        'solicitanteNome': solicitanteNome.isNotEmpty ? solicitanteNome : _cpfDigits,
        'escalaTitle': escalaTitle,
        'escalaDateLabel': escalaDateLabel,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Convite enviado para ${chosen.nome}. Quando aceitar, a escala será atualizada e o líder notificado.',
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registrar pedido: $e')),
        );
      }
    }
  }

  Future<void> _respondTrocaConvite(String tid, String trocaId, bool accept) async {
    try {
      await ScheduleSwapService.respondSwap(
        tenantId: tid,
        trocaId: trocaId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          accept
              ? 'Troca confirmada. A escala foi atualizada e o líder foi avisado.'
              : 'Você recusou o pedido. O irmão foi avisado.',
        ),
      );
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Não foi possível concluir.'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  Widget _buildIncomingSwapInvites() {
    if (_cpfDigits.length != 11) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: _effectiveTidFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final tid = snap.data!;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('igrejas')
              .doc(tid)
              .collection('escala_trocas')
              .where('alvoCpf', isEqualTo: _cpfDigits)
              .snapshots(),
          builder: (context, tSnap) {
            if (!tSnap.hasData) return const SizedBox.shrink();
            final items = tSnap.data!.docs
                .where(
                    (d) => (d.data()['status'] ?? '').toString() == 'pendente_alvo')
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mail_outline_rounded,
                          color: Colors.deepPurple.shade700, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Convites de troca',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.deepPurple.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final doc in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              (doc.data()['solicitanteNome'] ?? 'Um irmão')
                                  .toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'pediu para você assumir esta escala.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                (doc.data()['escalaDateLabel'] ?? '').toString(),
                                (doc.data()['escalaTitle'] ?? '').toString(),
                              ].where((s) => s.trim().isNotEmpty).join(' · '),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _respondTrocaConvite(
                                        tid, doc.id, true),
                                    icon: const Icon(Icons.check_rounded, size: 20),
                                    label: const Text('Aceitar'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _respondTrocaConvite(
                                        tid, doc.id, false),
                                    icon: const Icon(Icons.close_rounded, size: 20),
                                    label: const Text('Recusar'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

  Future<String?> _resolveMemberDocId(String tid) async {
    if (_cpfDigits.length != 11) return null;
    final col =
        FirebaseFirestore.instance.collection('igrejas').doc(tid).collection('membros');
    final byId = await col.doc(_cpfDigits).get();
    if (byId.exists) return _cpfDigits;
    for (final field in ['CPF', 'cpf']) {
      final q = await col.where(field, isEqualTo: _cpfDigits).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.id;
    }
    return null;
  }

  Future<void> _openAvailabilityCalendar() async {
    await _hydrateCpfFromMemberRecord();
    if (!mounted) return;
    if (_cpfDigits.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Não foi possível identificar seu CPF (cadastro de membro). '
                'Confira se a ficha tem CPF ou está vinculada ao seu login (e-mail).')),
      );
      return;
    }
    final tid = await _effectiveTidFuture;
    if (!mounted) return;
    final mid = await _resolveMemberDocId(tid);
    if (!mounted) return;
    if (mid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cadastro de membro não encontrado para este CPF.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MemberScheduleAvailabilityPage(
          tenantId: widget.tenantId,
          memberDocId: mid,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _confirmPresence(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) async {
    if (_cpfDigits.isEmpty) return;
    final key = _confirmationKey(doc.data() ?? {});
    // Não usar 'confirmations.$key': pontos no CPF formatado viram segmentos aninhados no update().
    final updates = <Object, Object?>{};
    if (status.isEmpty) {
      updates[FieldPath(['confirmations', key])] = FieldValue.delete();
      updates[FieldPath(['unavailabilityReasons', key])] = FieldValue.delete();
    } else {
      updates[FieldPath(['confirmations', key])] = status;
      if (status == 'indisponivel' && (motivo ?? '').trim().isNotEmpty) {
        updates[FieldPath(['unavailabilityReasons', key])] = {
          'reason': motivo!.trim(),
          'at': FieldValue.serverTimestamp(),
        };
      } else if (status != 'indisponivel') {
        updates[FieldPath(['unavailabilityReasons', key])] = FieldValue.delete();
      }
    }
    try {
      await doc.reference.update(updates);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isEmpty
                ? 'Confirmação atualizada.'
                : (status == 'confirmado'
                    ? 'Presença confirmada.'
                    : 'Indisponibilidade registrada.'),
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível salvar. ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  /// Um único eixo de rolagem (web + app): filtros, resumo e lista sobem/descem juntos.
  List<Widget> _mySchedulesScrollChildren(
    BuildContext context,
    DateTime now,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sorted,
  ) {
    final children = <Widget>[
      _buildIncomingSwapInvites(),
      _buildSummary(now),
      const SizedBox(height: ThemeCleanPremium.spaceSm),
      _buildPremiumPeriodSection(context),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(
          children: [
            Icon(Icons.view_list_rounded,
                size: 22, color: ThemeCleanPremium.primary),
            const SizedBox(width: 8),
            Text(
              'Suas escalas',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${sorted.length}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Lista por dia',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: !_useGridView
                      ? ThemeCleanPremium.primary.withValues(alpha: 0.14)
                      : null,
                ),
                onPressed: () => setState(() => _useGridView = false),
                icon: Icon(
                  Icons.view_list_rounded,
                  size: 20,
                  color: !_useGridView ? ThemeCleanPremium.primary : Colors.grey,
                ),
              ),
            ),
            Tooltip(
              message: 'Grade de cartões',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: _useGridView
                      ? ThemeCleanPremium.primary.withValues(alpha: 0.14)
                      : null,
                ),
                onPressed: () => setState(() => _useGridView = true),
                icon: Icon(
                  Icons.grid_view_rounded,
                  size: 20,
                  color: _useGridView ? ThemeCleanPremium.primary : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
    if (sorted.isEmpty) {
      children.add(
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded,
                  size: 52, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                'Nenhuma escala neste período.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Altere o filtro acima ou aguarde o líder publicar novas escalas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      if (_useGridView) {
        children.add(_buildScheduleGrid(sorted, now));
      } else {
        children.addAll(_buildScheduleListWithDateHeaders(sorted, now));
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final now = DateTime.now();
    final sorted = _sortedFilteredDocs;

    final pagePad = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(
        elevation: 0,
        title: const Text('Minhas Escalas', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Indisponibilidade para escalas',
            onPressed: _openAvailabilityCalendar,
            icon: const Icon(Icons.event_busy_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isMobile)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        pagePad.left,
                        widget.embeddedInShell ? 4 : ThemeCleanPremium.spaceSm,
                        pagePad.right,
                        ThemeCleanPremium.spaceSm,
                      ),
                      child: FilledButton.tonalIcon(
                        onPressed: _openAvailabilityCalendar,
                        icon: const Icon(Icons.event_busy_rounded, size: 20),
                        label: const Text('Dias em que não posso servir'),
                        style: FilledButton.styleFrom(
                          foregroundColor: ThemeCleanPremium.primary,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(
                              color: _premiumFilterBorderStrong,
                              width: 1.35,
                            ),
                          ),
                          elevation: 0,
                          shadowColor: const Color(0x220F172A),
                        ),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              pagePad.left,
                              4,
                              pagePad.right,
                              pagePad.bottom + 16,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate(
                                _mySchedulesScrollChildren(
                                    context, now, sorted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSummary(DateTime now) {
    final filtered = _filteredDocs;
    final refY = _dateFilter == 'month' ? _monthCursor.year : now.year;
    final refM = _dateFilter == 'month' ? _monthCursor.month : now.month;
    final thisMonth = filtered.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      return dt != null && dt.month == refM && dt.year == refY;
    }).toList();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final upcoming = filtered.where((d) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      return dt != null && !dt.isBefore(startOfToday);
    }).toList();
    final confirmed = filtered.where((d) {
      final conf = (d.data()['confirmations'] as Map<String, dynamic>?) ?? {};
      return conf[_cpfDigits] == 'confirmado';
    }).toList();

    return Row(children: [
      Expanded(
        child: _SummaryCard(
          value: '${thisMonth.length}',
          label: 'Este mês',
          icon: Icons.calendar_month_rounded,
          color: ThemeCleanPremium.primary,
          onTap: () => _openListaDetalhada(context, 'Este mês', thisMonth, now),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          value: '${upcoming.length}',
          label: 'Próximas',
          icon: Icons.upcoming_rounded,
          color: const Color(0xFF0891B2),
          onTap: () => _openListaDetalhada(context, 'Próximas', upcoming, now),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _SummaryCard(
          value: '${confirmed.length}',
          label: 'Confirmadas',
          icon: Icons.check_circle_rounded,
          color: ThemeCleanPremium.success,
          onTap: () => _openListaDetalhada(context, 'Confirmadas', confirmed, now),
        ),
      ),
    ]);
  }

  void _openListaDetalhada(
    BuildContext context,
    String titulo,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _MinhaEscalaListaPage(
          titulo: titulo,
          docs: docs,
          now: now,
          cpfDigits: _cpfDigits,
          onConfirm: _confirmPresence,
          onPop: () => setState(() {}),
          onRequestSwap: _cpfDigits.length == 11
              ? (d) => _abrirPedidoTroca(context, d)
              : null,
        ),
      ),
    );
  }

  static const Color _premiumFilterBorder = Color(0xFF94A3B8);
  static const Color _premiumFilterBorderStrong = Color(0xFF64748B);

  Widget _buildPremiumPeriodSection(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _premiumFilterBorderStrong, width: 1.25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 20, color: primary),
              const SizedBox(width: 8),
              Text(
                'Período',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          if (_dateFilter == 'month') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: 0.08),
                    const Color(0xFFF1F5F9),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withValues(alpha: 0.35), width: 1.25),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _monthCursor = DateTime(
                        _monthCursor.year,
                        _monthCursor.month - 1,
                        1,
                      );
                    }),
                    icon: const Icon(Icons.chevron_left_rounded, size: 26),
                    style: IconButton.styleFrom(
                      foregroundColor: primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: primary.withValues(alpha: 0.4), width: 1.2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          DateFormat('MMMM yyyy', 'pt_BR').format(_monthCursor),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: ThemeCleanPremium.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Lista por dia — sem calendário em grelha',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _monthCursor = DateTime(
                        _monthCursor.year,
                        _monthCursor.month + 1,
                        1,
                      );
                    }),
                    icon: const Icon(Icons.chevron_right_rounded, size: 26),
                    style: IconButton.styleFrom(
                      foregroundColor: primary,
                      backgroundColor: Colors.white,
                      side: BorderSide(color: primary.withValues(alpha: 0.4), width: 1.2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  final n = DateTime.now();
                  setState(() => _monthCursor = DateTime(n.year, n.month, 1));
                },
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Ir para mês atual'),
                style: FilledButton.styleFrom(
                  foregroundColor: primary,
                  backgroundColor: primary.withValues(alpha: 0.12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: primary.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            ),
          ],
          if (_dateFilter == 'year') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withValues(alpha: 0.08),
                    const Color(0xFFF1F5F9),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withValues(alpha: 0.35), width: 1.25),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _monthCursor =
                          DateTime(_monthCursor.year - 1, _monthCursor.month, 1);
                    }),
                    icon: const Icon(Icons.chevron_left_rounded, size: 26),
                    style: IconButton.styleFrom(
                      foregroundColor: primary,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Ano ${_monthCursor.year}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _monthCursor =
                          DateTime(_monthCursor.year + 1, _monthCursor.month, 1);
                    }),
                    icon: const Icon(Icons.chevron_right_rounded, size: 26),
                    style: IconButton.styleFrom(
                      foregroundColor: primary,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Tipo de filtro',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              ..._periodFilterKeys.map((e) {
                final selected = _dateFilter == e.$1;
                return FilterChip(
                  label: Text(
                    e.$2,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12.5,
                      color: selected ? primary : ThemeCleanPremium.onSurface,
                    ),
                  ),
                  selected: selected,
                  showCheckmark: true,
                  checkmarkColor: primary,
                  onSelected: (v) {
                    if (v) setState(() => _dateFilter = e.$1);
                  },
                  selectedColor: primary.withValues(alpha: 0.16),
                  backgroundColor: const Color(0xFFF8FAFC),
                  side: BorderSide(
                    color: selected ? primary : _premiumFilterBorder,
                    width: selected ? 2 : 1.25,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              }),
            ],
          ),
          if (_dateFilter == 'custom') ...[
            const SizedBox(height: 14),
            Text(
              'Datas do intervalo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _periodStart ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (d != null) setState(() => _periodStart = d);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _premiumFilterBorderStrong,
                            width: 1.35,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_rounded,
                                size: 20, color: primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Início',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    _periodStart == null
                                        ? 'Toque para escolher'
                                        : DateFormat('dd/MM/yyyy', 'pt_BR')
                                            .format(_periodStart!),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _periodEnd ??
                              _periodStart ??
                              DateTime.now(),
                          firstDate: _periodStart ?? DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (d != null) setState(() => _periodEnd = d);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _premiumFilterBorderStrong,
                            width: 1.35,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.flag_rounded, size: 20, color: primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Fim',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    _periodEnd == null
                                        ? 'Toque para escolher'
                                        : DateFormat('dd/MM/yyyy', 'pt_BR')
                                            .format(_periodEnd!),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: ThemeCleanPremium.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventCard(QueryDocumentSnapshot<Map<String, dynamic>> doc, DateTime now) {
    return _ScaleEventCard(
      doc: doc,
      now: now,
      cpfDigits: _cpfDigits,
      deptColors: _deptColors,
      onConfirm: (d, status, [motivo]) => _confirmPresence(d, status, motivo),
      onRequestSwap: _cpfDigits.length == 11
          ? () => _abrirPedidoTroca(context, doc)
          : null,
      onOpenPreview: () => showEscalaPremiumPreviewSheet(
        context,
        docs: [doc],
        now: now,
        cpfDigits: _cpfDigits,
        deptColors: _deptColors,
        onConfirm: _confirmPresence,
        onRequestSwap: _cpfDigits.length == 11
            ? (d) => _abrirPedidoTroca(context, d)
            : null,
      ),
    );
  }

  /// Grade compacta: toque abre o mesmo preview premium da lista.
  Widget _buildScheduleGrid(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) {
    final w = MediaQuery.sizeOf(context).width;
    final crossAxis = w >= 900 ? 3 : (w >= 560 ? 2 : 1);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: crossAxis >= 3 ? 1.42 : (crossAxis == 2 ? 1.28 : 1.12),
      ),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final m = doc.data();
        final title = (m['title'] ?? 'Escala').toString();
        final dept = (m['departmentName'] ?? '').toString();
        final time = (m['time'] ?? '').toString();
        final deptId = (m['departmentId'] ?? '').toString();
        final color = _deptColors[deptId.hashCode.abs() % _deptColors.length];
        DateTime? dt;
        try {
          dt = (m['date'] as Timestamp).toDate();
        } catch (_) {}
        final dateLine = dt != null
            ? DateFormat("dd/MM/yyyy · EEE", 'pt_BR').format(dt)
            : '';
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          child: InkWell(
            onTap: () => showEscalaPremiumPreviewSheet(
              context,
              docs: [doc],
              now: now,
              cpfDigits: _cpfDigits,
              deptColors: _deptColors,
              onConfirm: _confirmPresence,
              onRequestSwap: _cpfDigits.length == 11
                  ? (d) => _abrirPedidoTroca(context, d)
                  : null,
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(ThemeCleanPremium.radiusMd),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          if (dateLine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              dateLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          if (dept.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              dept,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              if (time.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule_rounded, size: 14, color: color),
                                      const SizedBox(width: 4),
                                      Text(
                                        time,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const Spacer(),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 16,
                                color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Agrupa a lista por dia com título legível (pt_BR); toque no dia abre preview com todas as frentes.
  List<Widget> _buildScheduleListWithDateHeaders(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
  ) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final out = <Widget>[];
    final withDate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final withoutDate = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      DateTime? dt;
      try {
        dt = (doc.data()['date'] as Timestamp).toDate();
      } catch (_) {}
      if (dt != null) {
        withDate.add(doc);
      } else {
        withoutDate.add(doc);
      }
    }
    final grouped = _groupSchedulesByDay(withDate);
    final dayKeys = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    for (final dayOnly in dayKeys) {
      final dayDocs = grouped[dayOnly]!;
      final raw = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(dayOnly);
      final cap = _capitalizeFirstLetter(raw);
      final sameCalendarDay = dayOnly.year == now.year &&
          dayOnly.month == now.month &&
          dayOnly.day == now.day;
      out.add(
        Padding(
          padding: EdgeInsets.only(
            top: out.isEmpty ? 0 : 20,
            bottom: 10,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => showEscalaPremiumPreviewSheet(
                context,
                docs: dayDocs,
                now: now,
                cpfDigits: _cpfDigits,
                deptColors: _deptColors,
                onConfirm: _confirmPresence,
                onRequestSwap: _cpfDigits.length == 11
                    ? (d) => _abrirPedidoTroca(context, d)
                    : null,
                dayContext: dayOnly,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.groups_2_rounded,
                      size: 22,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cap,
                        style: GoogleFonts.poppins(
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w800,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                    if (sameCalendarDay)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Hoje',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.primary,
                          ),
                        ),
                      ),
                    Text(
                      'Pré-visualizar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final doc in dayDocs) {
        out.add(_buildEventCard(doc, now));
      }
    }
    for (final doc in withoutDate) {
      out.add(_buildEventCard(doc, now));
    }
    return out;
  }
}

/// Card de uma frente de escala (reutilizado na lista detalhada).
class _ScaleEventCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final DateTime now;
  final String cpfDigits;
  final List<Color> deptColors;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm;
  final VoidCallback? onRequestSwap;
  final VoidCallback onOpenPreview;

  const _ScaleEventCard({
    required this.doc,
    required this.now,
    required this.cpfDigits,
    required this.deptColors,
    required this.onConfirm,
    required this.onOpenPreview,
    this.onRequestSwap,
  });

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final cpfs = ((m['memberCpfs'] as List?) ?? []).map((e) => e.toString()).toList();
    final title = (m['title'] ?? '').toString();
    final dept = (m['departmentName'] ?? '').toString();
    final time = (m['time'] ?? '').toString();
    final confirmations = (m['confirmations'] as Map<String, dynamic>?) ?? {};
    String myStatus = (confirmations[cpfDigits] ?? '').toString();
    if (myStatus.isEmpty && cpfs.contains(cpfDigits)) {
      for (final k in confirmations.keys) {
        if (k.toString().replaceAll(RegExp(r'[^0-9]'), '') ==
            cpfDigits.replaceAll(RegExp(r'[^0-9]'), '')) {
          myStatus = (confirmations[k] ?? '').toString();
          break;
        }
      }
    }
    final unavailabilityReasons = (m['unavailabilityReasons'] as Map<String, dynamic>?) ?? {};
    String? myReason;
    for (final k in unavailabilityReasons.keys) {
      if (k.toString().replaceAll(RegExp(r'[^0-9]'), '') ==
          cpfDigits.replaceAll(RegExp(r'[^0-9]'), '')) {
        final v = unavailabilityReasons[k];
        if (v is Map && v['reason'] != null) myReason = v['reason'].toString();
        break;
      }
    }
    final deptId = (m['departmentId'] ?? '').toString();
    final color = deptColors[deptId.hashCode.abs() % deptColors.length];
    DateTime? dt;
    try { dt = (m['date'] as Timestamp).toDate(); } catch (_) {}
    final isFuture = dt != null && dt.isAfter(now.subtract(const Duration(hours: 12)));
    final names = ((m['memberNames'] as List?) ?? []).map((e) => e.toString()).toList();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: InkWell(
        onTap: onOpenPreview,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 5, height: 140, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                    if (time.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                      ),
                  ]),
                  if (dt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      DateFormat("dd/MM/yyyy · EEEE", 'pt_BR').format(dt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (dept.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(dept, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
                  ],
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List.generate(names.length.clamp(0, 6), (i) {
                        final n = i < names.length ? names[i] : '';
                        final c = i < cpfs.length ? cpfs[i] : '';
                        final conf = (confirmations[c] ?? '').toString();
                        Color bg;
                        if (conf == 'confirmado') { bg = ThemeCleanPremium.success; }
                        else if (conf == 'indisponivel') { bg = ThemeCleanPremium.error; }
                        else if (conf == 'falta_nao_justificada') { bg = const Color(0xFFB91C1C); }
                        else { bg = Colors.grey.shade400; }
                        return Tooltip(
                          message: '$n (${conf.isEmpty ? 'pendente' : conf})',
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: bg.withValues(alpha: 0.2),
                            child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: bg)),
                          ),
                        );
                      }),
                    ),
                  ],
                  if (isFuture && cpfDigits.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Confirmar',
                          icon: Icons.check_circle_rounded,
                          color: ThemeCleanPremium.success,
                          active: myStatus == 'confirmado',
                          onTap: () async {
                            await onConfirm(doc, myStatus == 'confirmado' ? '' : 'confirmado');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ConfirmButton(
                          label: 'Indisponível',
                          icon: Icons.cancel_rounded,
                          color: ThemeCleanPremium.error,
                          active: myStatus == 'indisponivel',
                          onTap: () async {
                            if (myStatus == 'indisponivel') {
                              await onConfirm(doc, '');
                              return;
                            }
                            final reason = await showDialog<String>(
                              context: context,
                              builder: (ctx) {
                                final ctrl = TextEditingController();
                                return AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.cancel_rounded, color: ThemeCleanPremium.error),
                                      SizedBox(width: 10),
                                      Text('Indisponível', style: TextStyle(fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('Informe o motivo (o gestor verá esta justificativa):', style: TextStyle(fontSize: 14)),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: ctrl,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: viagem, saúde, compromisso...',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                                          filled: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                                      style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
                                      child: const Text('Enviar'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (reason != null) await onConfirm(doc, 'indisponivel', reason.isNotEmpty ? reason : null);
                          },
                        ),
                      ),
                    ]),
                    if (onRequestSwap != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onRequestSwap,
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Solicitar troca'),
                        ),
                      ),
                    ],
                  ] else if (myStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (myStatus == 'confirmado' ? ThemeCleanPremium.success : ThemeCleanPremium.error).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            myStatus == 'confirmado' ? 'Você confirmou presença' : 'Você marcou indisponível',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: myStatus == 'confirmado' ? ThemeCleanPremium.success : ThemeCleanPremium.error),
                          ),
                          if (myStatus == 'indisponivel' && (myReason ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Motivo: ${myReason!.trim()}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// Página de lista detalhada: dias e frentes de escala ao clicar em Este mês / Próximas / Confirmadas.
class _MinhaEscalaListaPage extends StatefulWidget {
  final String titulo;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final DateTime now;
  final String cpfDigits;
  final Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) onConfirm;
  final VoidCallback onPop;
  final Future<void> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? onRequestSwap;

  const _MinhaEscalaListaPage({
    required this.titulo,
    required this.docs,
    required this.now,
    required this.cpfDigits,
    required this.onConfirm,
    required this.onPop,
    this.onRequestSwap,
  });

  @override
  State<_MinhaEscalaListaPage> createState() => _MinhaEscalaListaPageState();
}

class _MinhaEscalaListaPageState extends State<_MinhaEscalaListaPage> {
  static const _deptColors = [
    Color(0xFF3B82F6), Color(0xFF16A34A), Color(0xFFE11D48), Color(0xFFF59E0B),
    Color(0xFF8B5CF6), Color(0xFF0891B2), Color(0xFFDB2777), Color(0xFF059669),
  ];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _sortedDocs {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(widget.docs);
    list.sort((a, b) {
      DateTime? da;
      DateTime? db;
      try { da = (a.data()['date'] as Timestamp).toDate(); } catch (_) {}
      try { db = (b.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (da == null || db == null) return 0;
      int c = da.compareTo(db);
      if (c != 0) return c;
      final ta = (a.data()['time'] ?? '').toString();
      final tb = (b.data()['time'] ?? '').toString();
      return ta.compareTo(tb);
    });
    return list;
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> get _byDay {
    final map = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in _sortedDocs) {
      DateTime? dt;
      try { dt = (d.data()['date'] as Timestamp).toDate(); } catch (_) {}
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(d);
    }
    return map;
  }

  Future<void> _confirm(DocumentSnapshot<Map<String, dynamic>> doc, String status, [String? motivo]) async {
    await widget.onConfirm(doc, status, motivo);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _byDay;
    final days = byDay.keys.toList()..sort();

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            widget.onPop();
            Navigator.pop(context);
          },
          style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
        ),
        title: Text(widget.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: widget.docs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_available_rounded, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('Nenhuma escala nesta lista.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                ],
              ),
            )
          : ListView.builder(
              padding: ThemeCleanPremium.pagePadding(context),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final key = days[i];
                final parts = key.split('-');
                final year = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
                final month = parts.length >= 2 ? int.tryParse(parts[1]) ?? 0 : 0;
                final day = parts.length >= 3 ? int.tryParse(parts[2]) ?? 0 : 0;
                final date = DateTime(year, month, day);
                final labelRaw = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(date);
                final label = labelRaw.isNotEmpty ? '${labelRaw[0].toUpperCase()}${labelRaw.substring(1)}' : labelRaw;
                final events = byDay[key]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: i == 0 ? 8 : 20),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      child: InkWell(
                        onTap: () => showEscalaPremiumPreviewSheet(
                          context,
                          docs: events,
                          now: widget.now,
                          cpfDigits: widget.cpfDigits,
                          deptColors: _deptColors,
                          onConfirm: _confirm,
                          onRequestSwap: widget.onRequestSwap,
                          dayContext: date,
                        ),
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                            border: Border.all(color: ThemeCleanPremium.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 20, color: ThemeCleanPremium.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ThemeCleanPremium.onSurface),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${events.length} frente(s)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: ThemeCleanPremium.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.visibility_rounded,
                                size: 20,
                                color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...events.map((doc) => _ScaleEventCard(
                      doc: doc,
                      now: widget.now,
                      cpfDigits: widget.cpfDigits,
                      deptColors: _deptColors,
                      onConfirm: _confirm,
                      onOpenPreview: () => showEscalaPremiumPreviewSheet(
                        context,
                        docs: [doc],
                        now: widget.now,
                        cpfDigits: widget.cpfDigits,
                        deptColors: _deptColors,
                        onConfirm: _confirm,
                        onRequestSwap: widget.onRequestSwap,
                      ),
                      onRequestSwap: widget.onRequestSwap != null
                          ? () => widget.onRequestSwap!(doc)
                          : null,
                    )),
                  ],
                );
              },
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
      ]),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: child,
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ConfirmButton({required this.label, required this.icon, required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: active ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : color)),
          ]),
        ),
      ),
    );
  }
}
