import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart'
    show kFornecedoresModuleIcon;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

String _memberNomeFromData(Map<String, dynamic> m) =>
    (m['NOME_COMPLETO'] ?? m['nome'] ?? m['name'] ?? '').toString().trim();

String? _memberTelefoneRaw(Map<String, dynamic> m) {
  final t = (m['TELEFONES'] ??
          m['telefone'] ??
          m['celular'] ??
          m['whatsapp'] ??
          '')
      .toString()
      .trim();
  return t.isEmpty ? null : t;
}

/// Nome exibido em listas de receita recorrente / despesa fixa (membro ou fornecedor).
String titularNomeFinanceFixo(Map<String, dynamic> d) {
  final t = (d['titularNome'] ?? '').toString().trim();
  if (t.isNotEmpty) return t;
  final vt = (d['vinculoTipo'] ?? 'membro').toString();
  if (vt == 'nenhum') return '';
  if (vt == 'fornecedor') {
    return (d['fornecedorNome'] ?? '').toString().trim();
  }
  return (d['membroNome'] ?? d['memberNome'] ?? '').toString().trim();
}

/// Despesas fixas: vínculo opcional (nenhum / membro / fornecedor).
class FinanceFixoVinculoSegmentDespesa extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const FinanceFixoVinculoSegmentDespesa({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vincular a (opcional)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'nenhum',
              label: Text('Nenhum'),
              icon: Icon(Icons.link_off_rounded, size: 16),
            ),
            ButtonSegment<String>(
              value: 'membro',
              label: Text('Membro'),
              icon: Icon(Icons.person_rounded, size: 18),
            ),
            ButtonSegment<String>(
              value: 'fornecedor',
              label: Text('Fornecedor'),
              icon: Icon(kFornecedoresModuleIcon, size: 18),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) onChanged(s.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: WidgetStateProperty.all(
              BorderSide(color: p.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Segmento Membro / Fornecedor — mesmo padrão em receitas e despesas fixas.
class FinanceFixoVinculoSegment extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const FinanceFixoVinculoSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vincular a',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'membro',
              label: Text('Membro'),
              icon: Icon(Icons.person_rounded, size: 18),
            ),
            ButtonSegment<String>(
              value: 'fornecedor',
              label: Text('Fornecedor'),
              icon: Icon(kFornecedoresModuleIcon, size: 18),
            ),
          ],
          selected: {value},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) onChanged(s.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: WidgetStateProperty.all(
              BorderSide(color: p.withValues(alpha: 0.35)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cartão de seleção (membro ou fornecedor) — toque abre o picker premium.
class FinanceFixoTitularCard extends StatelessWidget {
  final String vinculoTipo;
  final String tituloPlaceholder;
  final String nomeExibicao;
  final VoidCallback onTap;

  const FinanceFixoTitularCard({
    super.key,
    required this.vinculoTipo,
    required this.tituloPlaceholder,
    required this.nomeExibicao,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMembro = vinculoTipo == 'membro';
    final p = ThemeCleanPremium.primary;
    final empty = nomeExibicao.isEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                p.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            border: Border.all(
              color: p.withValues(alpha: empty ? 0.22 : 0.38),
              width: empty ? 1 : 1.2,
            ),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isMembro ? Icons.person_rounded : kFornecedoresModuleIcon,
                    color: p,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloPlaceholder,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        empty
                            ? (isMembro
                                ? 'Toque para escolher um membro'
                                : 'Toque para escolher um fornecedor')
                            : nomeExibicao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: empty ? Colors.grey.shade500 : ThemeCleanPremium.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<(String, String, String?)?> showFinancePremiumMemberPicker(
  BuildContext context, {
  required String tenantId,
}) async {
  final membros = (await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .collection('membros')
          .limit(3000)
          .get())
      .docs;
  membros.sort((a, b) => _memberNomeFromData(a.data()).toLowerCase().compareTo(
        _memberNomeFromData(b.data()).toLowerCase(),
      ));
  var q = '';
  if (!context.mounted) return null;
  return showDialog<(String, String, String?)>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final filtered = membros.where((d) {
          if (q.isEmpty) return true;
          final n = _memberNomeFromData(d.data()).toLowerCase();
          return n.contains(q);
        }).toList();
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 460,
            height: MediaQuery.sizeOf(ctx).height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary,
                        ThemeCleanPremium.primary.withValues(alpha: 0.88),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_search_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Escolher membro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar nome ou CPF…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        borderSide: BorderSide(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setS(() => q = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Nenhum resultado.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final d = filtered[i];
                            final nome = _memberNomeFromData(d.data());
                            final label = nome.isEmpty ? d.id : nome;
                            return Material(
                              color: const Color(0xFFF8FAFC),
                              borderRadius:
                                  BorderRadius.circular(ThemeCleanPremium.radiusSm),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm,
                                  ),
                                  side: const BorderSide(color: Color(0xFFE8EDF3)),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: ThemeCleanPremium.primary,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  label,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: Colors.grey.shade400,
                                ),
                                onTap: () => Navigator.pop(
                                  ctx,
                                  (
                                    d.id,
                                    label,
                                    _memberTelefoneRaw(d.data()),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<List<({String id, String nome})>> _fornecedoresAtivos(String tenantId) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
        .collection('fornecedores')
        .orderBy('nome')
        .limit(500)
        .get();
    final out = <({String id, String nome})>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (m['status'] == 'inativo') continue;
      final n = (m['nome'] ?? '').toString().trim();
      out.add((id: d.id, nome: n.isEmpty ? d.id : n));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<(String, String)?> showFinancePremiumFornecedorPicker(
  BuildContext context, {
  required String tenantId,
}) async {
  final fornecedores = await _fornecedoresAtivos(tenantId);
  var q = '';
  if (!context.mounted) return null;
  return showDialog<(String, String)>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final filtered = fornecedores.where((e) {
          if (q.isEmpty) return true;
          return e.nome.toLowerCase().contains(q);
        }).toList();
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 460,
            height: MediaQuery.sizeOf(ctx).height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary,
                        ThemeCleanPremium.primary.withValues(alpha: 0.88),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          kFornecedoresModuleIcon,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Escolher fornecedor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        tooltip: 'Fechar',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar nome…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        borderSide: BorderSide(
                          color: ThemeCleanPremium.primary.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (v) => setS(() => q = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              fornecedores.isEmpty
                                  ? 'Nenhum fornecedor cadastrado. Cadastre em Financeiro → Fornecedores.'
                                  : 'Nenhum resultado.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final e = filtered[i];
                            return Material(
                              color: const Color(0xFFF8FAFC),
                              borderRadius:
                                  BorderRadius.circular(ThemeCleanPremium.radiusSm),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusSm,
                                  ),
                                  side: const BorderSide(color: Color(0xFFE8EDF3)),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: ThemeCleanPremium.primary
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    kFornecedoresModuleIcon,
                                    color: ThemeCleanPremium.primary,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  e.nome,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                trailing: Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: Colors.grey.shade400,
                                ),
                                onTap: () => Navigator.pop(ctx, (e.id, e.nome)),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
