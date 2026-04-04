import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show SafeMemberProfilePhoto, memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
import 'package:gestao_yahweh/utils/church_department_list.dart' show churchDepartmentNameFromData;

class PerfilMembroPage extends StatefulWidget {
  final String tenantId;
  final String memberId;
  const PerfilMembroPage({super.key, required this.tenantId, required this.memberId});

  @override
  State<PerfilMembroPage> createState() => _PerfilMembroPageState();
}

class _ProfileLoad {
  final Map<String, dynamic> data;
  final List<DocumentSnapshot<Map<String, dynamic>>> departmentDocs;
  final List<String> legacyDepartmentNames;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> upcomingSchedules;
  final String cpfDigits;

  const _ProfileLoad({
    required this.data,
    required this.departmentDocs,
    required this.legacyDepartmentNames,
    required this.upcomingSchedules,
    required this.cpfDigits,
  });
}

class _PerfilMembroPageState extends State<PerfilMembroPage> {
  late Future<_ProfileLoad?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProfile();
  }

  Future<void> _reload() async {
    setState(() => _future = _loadProfile());
  }

  static String _cpfDigits(Map<String, dynamic> data, String memberId) {
    final fromField =
        (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (fromField.length == 11) return fromField;
    final fromId = memberId.replaceAll(RegExp(r'[^0-9]'), '');
    if (fromId.length == 11) return fromId;
    return '';
  }

  Future<_ProfileLoad?> _loadProfile() async {
    final docRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('membros')
        .doc(widget.memberId);
    final snap = await docRef.get();
    if (!snap.exists || snap.data() == null) return null;
    final data = snap.data()!;
    final deptCol = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('departamentos');

    final ids = ((data['departamentosIds'] as List?) ?? [])
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final deptSnaps = await Future.wait(ids.map((id) => deptCol.doc(id).get()));
    final departments = deptSnaps.where((d) => d.exists).toList();

    final cpf = _cpfDigits(data, widget.memberId);
    var schedules = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (cpf.length == 11) {
      final escCol = FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection('escalas');
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      try {
        final q = await escCol
            .where('memberCpfs', arrayContains: cpf)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .orderBy('date')
            .limit(24)
            .get();
        schedules = q.docs;
      } catch (_) {
        final q2 = await escCol
            .where('memberCpfs', arrayContains: cpf)
            .orderBy('date', descending: true)
            .limit(48)
            .get();
        schedules = q2.docs.where((d) {
          final t = d.data()['date'];
          if (t is! Timestamp) return false;
          return !t.toDate().isBefore(start);
        }).toList()
          ..sort((a, b) {
            final da = (a.data()['date'] as Timestamp?)?.toDate() ?? DateTime(1970);
            final db = (b.data()['date'] as Timestamp?)?.toDate() ?? DateTime(1970);
            return da.compareTo(db);
          });
      }
    }

    final legacyNames = (data['DEPARTAMENTOS'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        <String>[];

    return _ProfileLoad(
      data: data,
      departmentDocs: departments,
      legacyDepartmentNames: legacyNames,
      upcomingSchedules: schedules,
      cpfDigits: cpf,
    );
  }

  Future<void> _confirmPresence(String scheduleDocId, String cpfDigits) async {
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('escalas')
        .doc(scheduleDocId);
    await ref.update({
      'confirmations.$cpfDigits': 'confirmado',
      'unavailabilityReasons.$cpfDigits': FieldValue.delete(),
    });
  }

  Future<void> _requestSubstitution(
    String scheduleDocId,
    String cpfDigits,
    String reason,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('escalas')
        .doc(scheduleDocId);
    final payload = <String, dynamic>{
      'confirmations.$cpfDigits': 'indisponivel',
    };
    if (reason.trim().isNotEmpty) {
      payload['unavailabilityReasons.$cpfDigits'] = reason.trim();
    }
    await ref.update(payload);
  }

  static String _photoUrlFromData(Map<String, dynamic> data) => imageUrlFromMap(data);

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(title: const Text('Perfil do Membro')),
      body: SafeArea(
        child: FutureBuilder<_ProfileLoad?>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
                    const SizedBox(height: 12),
                    Text('Erro ao carregar perfil.', style: TextStyle(color: Colors.grey.shade600)),
                    TextButton(onPressed: _reload, child: const Text('Tentar novamente')),
                  ],
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final load = snap.data;
            if (load == null) {
              return const Center(child: Text('Membro não encontrado.'));
            }

            final data = load.data;
            final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? '').toString();
            final email = (data['EMAIL'] ?? data['email'] ?? '').toString();
            final telefone = (data['TELEFONES'] ?? data['telefone'] ?? '').toString();
            final foto = _photoUrlFromData(data);
            final sexo = (data['SEXO'] ?? data['sexo'] ?? '').toString().toLowerCase();
            final avatarColor = sexo.startsWith('m')
                ? Colors.blue.shade600
                : sexo.startsWith('f')
                    ? Colors.pink.shade400
                    : Colors.grey.shade600;
            final nascimento = (data['DATA_NASCIMENTO'] ?? '').toString();
            final status = (data['STATUS'] ?? data['status'] ?? 'ativo').toString();
            final endereco = (data['ENDERECO'] ?? '').toString();
            final filiacaoPai = (data['FILIACAO_PAI'] ?? data['filiacaoPai'] ?? '').toString().trim();
            final filiacaoMae = (data['FILIACAO_MAE'] ?? data['filiacaoMae'] ?? '').toString().trim();
            final filiacaoLegado = (data['FILIACAO'] ?? '').toString().trim();
            final dataCadastro = (data['createdAt'] ?? '').toString();

            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: ThemeCleanPremium.pagePadding(context),
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: SafeMemberProfilePhoto(
                      imageUrl: foto.isNotEmpty ? foto : null,
                      tenantId: widget.tenantId,
                      memberId: widget.memberId,
                      imageCacheRevision: memberPhotoDisplayCacheRevision(data),
                      width: 96,
                      height: 96,
                      circular: true,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: avatarColor,
                        alignment: Alignment.center,
                        child: Text(
                          (nome.isNotEmpty ? nome[0] : '?').toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                          ),
                        ),
                      ),
                      errorChild: Container(
                        color: avatarColor,
                        alignment: Alignment.center,
                        child: Text(
                          (nome.isNotEmpty ? nome[0] : '?').toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      nome,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (email.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(email, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ),
                    ),
                  if (telefone.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(telefone, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ),
                    ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.success,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(context, Icons.groups_rounded, 'Meus departamentos'),
                  const SizedBox(height: 12),
                  if (load.departmentDocs.isNotEmpty)
                    ...load.departmentDocs.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DepartmentCard(
                            name: churchDepartmentNameFromData(d.data() ?? {}, docId: d.id),
                          ),
                        ))
                  else if (load.legacyDepartmentNames.isNotEmpty)
                    _LegacyDeptWrap(names: load.legacyDepartmentNames)
                  else
                    Text(
                      'Nenhum departamento vinculado ainda.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    ),
                  const SizedBox(height: 8),
                  _sectionTitle(context, Icons.event_available_rounded, 'Minhas próximas escalas'),
                  const SizedBox(height: 12),
                  if (load.cpfDigits.length != 11)
                    Text(
                      'CPF não informado — não é possível listar escalas.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    )
                  else if (load.upcomingSchedules.isEmpty)
                    Text(
                      'Sem escalas futuras com você neste momento.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    )
                  else
                    ...load.upcomingSchedules.map((doc) {
                      final m = doc.data();
                      final confirmations =
                          (m['confirmations'] as Map<String, dynamic>?) ?? {};
                      final st = (confirmations[load.cpfDigits] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ScheduleCard(
                          title: (m['title'] ?? '').toString(),
                          deptName: (m['departmentName'] ?? '').toString(),
                          time: (m['time'] ?? '').toString(),
                          date: m['date'],
                          status: st,
                          onConfirm: st == 'confirmado'
                              ? null
                              : () async {
                                  try {
                                    await _confirmPresence(doc.id, load.cpfDigits);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        ThemeCleanPremium.successSnackBar('Presença confirmada.'),
                                      );
                                      await _reload();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Não foi possível confirmar: $e'),
                                          backgroundColor: ThemeCleanPremium.error,
                                        ),
                                      );
                                    }
                                  }
                                },
                          onSubstitute: () async {
                            final reasonCtrl = TextEditingController();
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Solicitar substituição'),
                                content: TextField(
                                  controller: reasonCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Motivo (opcional)',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 2,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Enviar'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              try {
                                await _requestSubstitution(
                                  doc.id,
                                  load.cpfDigits,
                                  reasonCtrl.text,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                      'Indisponibilidade registrada. O líder será notificado.',
                                    ),
                                  );
                                  await _reload();
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Falha ao registrar: $e'),
                                      backgroundColor: ThemeCleanPremium.error,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  _InfoCard(children: [
                    _InfoRow(icon: Icons.cake_rounded, label: 'Nascimento', value: nascimento),
                    _InfoRow(icon: Icons.home_rounded, label: 'Endereço', value: endereco),
                    if (filiacaoPai.isNotEmpty)
                      _InfoRow(icon: Icons.family_restroom_rounded, label: 'Filiação (pai)', value: filiacaoPai),
                    if (filiacaoMae.isNotEmpty)
                      _InfoRow(icon: Icons.family_restroom_rounded, label: 'Filiação (mãe)', value: filiacaoMae),
                    if (filiacaoPai.isEmpty && filiacaoMae.isEmpty && filiacaoLegado.isNotEmpty)
                      _InfoRow(icon: Icons.family_restroom_rounded, label: 'Filiação', value: filiacaoLegado),
                    _InfoRow(icon: Icons.calendar_today_rounded, label: 'Data de cadastro', value: dataCadastro),
                  ]),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 22, color: ThemeCleanPremium.primary.withOpacity(0.85)),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final String name;
  const _DepartmentCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: ThemeCleanPremium.primary.withOpacity(0.12),
            child: Icon(Icons.groups_2_rounded, color: ThemeCleanPremium.primary.withOpacity(0.9)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyDeptWrap extends StatelessWidget {
  final List<String> names;
  const _LegacyDeptWrap({required this.names});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: names
          .map(
            (n) => Chip(
              label: Text(n),
              backgroundColor: ThemeCleanPremium.success.withOpacity(0.08),
              side: BorderSide(color: ThemeCleanPremium.success.withOpacity(0.25)),
            ),
          )
          .toList(),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final String title;
  final String deptName;
  final String time;
  final dynamic date;
  final String status;
  final VoidCallback? onConfirm;
  final VoidCallback? onSubstitute;

  const _ScheduleCard({
    required this.title,
    required this.deptName,
    required this.time,
    required this.date,
    required this.status,
    this.onConfirm,
    this.onSubstitute,
  });

  @override
  Widget build(BuildContext context) {
    DateTime? dt;
    if (date is Timestamp) {
      try {
        dt = date.toDate();
      } catch (_) {}
    }
    final dateLabel = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
        : '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'confirmado':
        statusColor = ThemeCleanPremium.success;
        statusLabel = 'Confirmado';
        break;
      case 'indisponivel':
        statusColor = ThemeCleanPremium.error;
        statusLabel = 'Indisponível';
        break;
      default:
        statusColor = Colors.amber.shade800;
        statusLabel = 'Pendente';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: statusColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isNotEmpty ? title : 'Escala',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if (deptName.isNotEmpty)
                      Text(
                        deptName,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [dateLabel, time].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
            ],
          ),
          if (onConfirm != null || (onSubstitute != null && status != 'indisponivel')) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (onConfirm != null)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: const Text('Confirmar presença'),
                    ),
                  ),
                if (onConfirm != null && onSubstitute != null && status != 'indisponivel')
                  const SizedBox(width: 10),
                if (onSubstitute != null && status != 'indisponivel')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSubstitute,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      label: const Text('Substituição'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ThemeCleanPremium.primary.withOpacity(0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
