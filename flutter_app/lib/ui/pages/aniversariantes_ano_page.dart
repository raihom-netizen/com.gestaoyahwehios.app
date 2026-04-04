import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Página "Aniversariantes do ano" — mês a mês, todos os membros.
/// Livre para todos os usuários do painel.
class AniversariantesAnoPage extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  /// ID da igreja (documento) para fallback `igrejas/{tenant}/membros/{id}.jpg`.
  final String tenantId;

  const AniversariantesAnoPage({super.key, required this.docs, this.tenantId = ''});

  static const List<String> _meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  static DateTime? _parseBirthDate(Map<String, dynamic> data) => birthDateFromMemberData(data);

  static String _nome(Map<String, dynamic> d) =>
      (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString();

  static String? _fotoUrl(Map<String, dynamic> d) {
    final u = imageUrlFromMap(d);
    return u.isNotEmpty ? u : null;
  }

  static Color _avatarColor(Map<String, dynamic> d) {
    final g = genderCategoryFromMemberData(d);
    if (g == 'M') return Colors.blue.shade600;
    if (g == 'F') return Colors.pink.shade400;
    return Colors.grey.shade600;
  }

  static int? _diaDoMes(Map<String, dynamic> data) => _parseBirthDate(data)?.day;

  /// Agrupa membros por mês de aniversário (1..12). Ordena por dia dentro do mês (1, 2, 3...).
  Map<int, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _porMes() {
    final porMes = <int, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (var m = 1; m <= 12; m++) porMes[m] = [];
    for (final d in docs) {
      final dt = _parseBirthDate(d.data());
      if (dt == null) continue;
      porMes[dt.month]!.add(d);
    }
    for (var m = 1; m <= 12; m++) {
      porMes[m]!.sort((a, b) {
        final da = _parseBirthDate(a.data());
        final db = _parseBirthDate(b.data());
        if (da == null || db == null) return 0;
        return da.day.compareTo(db.day);
      });
    }
    return porMes;
  }

  @override
  Widget build(BuildContext context) {
    final porMes = _porMes();
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Aniversariantes do ano'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Text(
              'Todos os aniversariantes por mês. Livre para todos os usuários.',
              style: TextStyle(
                fontSize: 14,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            for (var m = 1; m <= 12; m++) ...[
              _MesSection(
                mes: m,
                mesNome: _meses[m - 1],
                membros: porMes[m]!,
                nome: _nome,
                fotoUrl: _fotoUrl,
                avatarColor: _avatarColor,
                diaDoMes: _diaDoMes,
                tenantId: tenantId,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceMd),
            ],
          ],
        ),
      ),
    );
  }
}

/// Um item na lista do mês: dia, foto e nome completo (ordem crescente por data).
class _ItemAniversariante extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int dia;
  final String Function(Map<String, dynamic>) nome;
  final String? Function(Map<String, dynamic>) fotoUrl;
  final Color Function(Map<String, dynamic>) avatarColor;
  final String tenantId;

  const _ItemAniversariante({
    required this.doc,
    required this.dia,
    required this.nome,
    required this.fotoUrl,
    required this.avatarColor,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final url = fotoUrl(data);
    final hasNet = url != null && isValidImageUrl(url);
    final nomeCompleto = nome(data);
    final cpfDigits =
        (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$dia',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FotoMembroWidget(
            imageUrl: hasNet ? url : null,
            tenantId: tenantId.isNotEmpty ? tenantId : null,
            memberId: doc.id,
            cpfDigits: cpfDigits.length >= 9 ? cpfDigits : null,
            memberData: data,
            size: 44,
            backgroundColor: avatarColor(data),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              nomeCompleto.isEmpty ? 'Sem nome' : nomeCompleto,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ThemeCleanPremium.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MesSection extends StatelessWidget {
  final int mes;
  final String mesNome;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> membros;
  final String Function(Map<String, dynamic>) nome;
  final String? Function(Map<String, dynamic>) fotoUrl;
  final Color Function(Map<String, dynamic>) avatarColor;
  final int? Function(Map<String, dynamic>) diaDoMes;
  final String tenantId;

  const _MesSection({
    required this.mes,
    required this.mesNome,
    required this.membros,
    required this.nome,
    required this.fotoUrl,
    required this.avatarColor,
    required this.diaDoMes,
    required this.tenantId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeCleanPremium.spaceMd,
              vertical: ThemeCleanPremium.spaceSm,
            ),
            color: ThemeCleanPremium.primary.withOpacity(0.08),
            child: Row(
              children: [
                Icon(Icons.cake_rounded, color: ThemeCleanPremium.primary, size: 22),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Text(
                  mesNome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${membros.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (membros.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
              child: Text(
                'Nenhum aniversariante neste mês.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeCleanPremium.spaceMd,
                vertical: ThemeCleanPremium.spaceSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < membros.length; i++) ...[
                    _ItemAniversariante(
                      doc: membros[i],
                      dia: diaDoMes(membros[i].data()) ?? 0,
                      nome: nome,
                      fotoUrl: fotoUrl,
                      avatarColor: avatarColor,
                      tenantId: tenantId,
                    ),
                    if (i < membros.length - 1)
                      Divider(height: 1, color: Colors.grey.shade200, indent: 52, endIndent: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
