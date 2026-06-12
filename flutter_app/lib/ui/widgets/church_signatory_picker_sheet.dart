import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';

/// Folha premium — escolher signatário (liderança apenas).
Future<ChurchSignatoryEntry?> showChurchSignatoryPickerSheet(
  BuildContext context, {
  required String title,
  required String tenantId,
  required List<ChurchSignatoryEntry> signers,
  String? selectedMemberId,
}) async {
  if (signers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Nenhum assinante elegível. Cadastre pastor, gestor, secretário, '
          'tesoureiro, administrador ou líder de departamento em Membros.',
        ),
        backgroundColor: ThemeCleanPremium.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }

  return showModalBottomSheet<ChurchSignatoryEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchSignatoryPickerSheet(
      title: title,
      tenantId: tenantId,
      signers: signers,
      selectedMemberId: selectedMemberId,
    ),
  );
}

class _ChurchSignatoryPickerSheet extends StatefulWidget {
  const _ChurchSignatoryPickerSheet({
    required this.title,
    required this.tenantId,
    required this.signers,
    this.selectedMemberId,
  });

  final String title;
  final String tenantId;
  final List<ChurchSignatoryEntry> signers;
  final String? selectedMemberId;

  @override
  State<_ChurchSignatoryPickerSheet> createState() =>
      _ChurchSignatoryPickerSheetState();
}

class _ChurchSignatoryPickerSheetState extends State<_ChurchSignatoryPickerSheet> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _q = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChurchSignatoryEntry> get _filtered {
    if (_q.isEmpty) return widget.signers;
    return widget.signers.where((e) {
      if (e.nome.toLowerCase().contains(_q)) return true;
      if (e.cargo.toLowerCase().contains(_q)) return true;
      final cpf = e.cpfDigits ?? '';
      final qDigits = _q.replaceAll(RegExp(r'\D'), '');
      return qDigits.length >= 3 && cpf.contains(qDigits);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height * 0.78;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: h.clamp(320.0, 880.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Pastor, gestor, secretário, tesoureiro, administrador ou '
                    'líder de departamento.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nome ou cargo…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${_filtered.length} assinante(s) elegível(is)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
                ),
                const Divider(height: 16),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum assinante com este filtro.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final e = _filtered[i];
                            final sel = e.memberId == widget.selectedMemberId;
                            return Material(
                              color: sel
                                  ? ThemeCleanPremium.primary
                                      .withValues(alpha: 0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(context, e),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: sel
                                          ? ThemeCleanPremium.primary
                                              .withValues(alpha: 0.35)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                    boxShadow: sel
                                        ? null
                                        : ThemeCleanPremium.softUiCardShadow,
                                  ),
                                  child: Row(
                                    children: [
                                      FotoMembroWidget(
                                        tenantId: widget.tenantId,
                                        memberId: e.memberId,
                                        size: 44,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.nome,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              e.cargo,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (sel)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: ThemeCleanPremium.primary,
                                          size: 22,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo premium — duas assinaturas (financeiro).
Future<({ChurchSignatoryEntry? left, ChurchSignatoryEntry? right, bool digital})?>
    showChurchDualSignatoryDialog(
  BuildContext context, {
  required String title,
  required List<ChurchSignatoryEntry> signers,
}) async {
  if (signers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Nenhum assinante elegível para o PDF.',
        ),
        backgroundColor: ThemeCleanPremium.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return null;
  }

  String? leftId;
  String? rightId;
  var digital = true;

  ChurchSignatoryEntry? find(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final e in signers) {
      if (e.memberId == id) return e;
    }
    return null;
  }

  return showDialog<
      ({ChurchSignatoryEntry? left, ChurchSignatoryEntry? right, bool digital})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        Widget signerDropdown({
          required String label,
          required String? value,
          required ValueChanged<String?> onChanged,
        }) {
          return DropdownButtonFormField<String?>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— Não definido —'),
              ),
              ...signers.map(
                (e) => DropdownMenuItem<String?>(
                  value: e.memberId,
                  child: Text(
                    '${e.nome} — ${e.cargo}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Somente liderança: pastor, gestor, secretário, tesoureiro, '
                  'administrador ou líder de departamento.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 14),
                signerDropdown(
                  label: 'Assinatura esquerda',
                  value: leftId,
                  onChanged: (v) => setDlg(() => leftId = v),
                ),
                const SizedBox(height: 12),
                signerDropdown(
                  label: 'Assinatura direita',
                  value: rightId,
                  onChanged: (v) => setDlg(() => rightId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: digital,
                  onChanged: (v) => setDlg(() => digital = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Carregar assinatura digital'),
                  subtitle: const Text(
                    'Desative para linhas de assinatura manual no PDF.',
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
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                (
                  left: find(leftId),
                  right: find(rightId),
                  digital: digital,
                ),
              ),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    ),
  );
}
