import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Resultado — assinante da igreja + selo digital opcional.
typedef FornecedorReciboEmitConfig = ({
  ChurchSignatoryEntry? signer,
  bool useDigital,
});

/// Tela premium — emitir recibo PDF (somente liderança assina).
Future<FornecedorReciboEmitConfig?> showFornecedorReciboEmitSheet(
  BuildContext context, {
  required String tenantId,
  required String fornecedorNome,
  required double valor,
  required String referente,
  required List<ChurchSignatoryEntry> signers,
}) {
  return Navigator.of(context).push<FornecedorReciboEmitConfig>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => _FornecedorReciboEmitPage(
        tenantId: tenantId,
        fornecedorNome: fornecedorNome,
        valor: valor,
        referente: referente,
        signers: signers,
      ),
    ),
  );
}

class _FornecedorReciboEmitPage extends StatefulWidget {
  const _FornecedorReciboEmitPage({
    required this.tenantId,
    required this.fornecedorNome,
    required this.valor,
    required this.referente,
    required this.signers,
  });

  final String tenantId;
  final String fornecedorNome;
  final double valor;
  final String referente;
  final List<ChurchSignatoryEntry> signers;

  @override
  State<_FornecedorReciboEmitPage> createState() =>
      _FornecedorReciboEmitPageState();
}

class _FornecedorReciboEmitPageState extends State<_FornecedorReciboEmitPage> {
  final _search = TextEditingController();
  String _q = '';
  String? _selectedId;
  var _useDigital = true;

  static const _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D9488), Color(0xFF2563EB)],
  );

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

  ChurchSignatoryEntry? get _selected {
    if (_selectedId == null) return null;
    for (final e in widget.signers) {
      if (e.memberId == _selectedId) return e;
    }
    return null;
  }

  ({Color bg, Color fg}) _badgeForCargo(String cargo) {
    final c = cargo.toLowerCase();
    if (c.contains('pastor')) {
      return (bg: const Color(0xFFEEF2FF), fg: const Color(0xFF4338CA));
    }
    if (c.contains('tesour')) {
      return (bg: const Color(0xFFECFDF5), fg: const Color(0xFF047857));
    }
    if (c.contains('secret')) {
      return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309));
    }
    if (c.contains('admin') || c.contains('adm')) {
      return (bg: const Color(0xFFFCE7F3), fg: const Color(0xFFBE185D));
    }
    if (c.contains('gestor')) {
      return (bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0369A1));
    }
    if (c.contains('lider') || c.contains('líder')) {
      return (bg: const Color(0xFFF3E8FF), fg: const Color(0xFF7C3AED));
    }
    return (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF475569));
  }

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final safe = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(8, safe.top + 4, 16, 20),
            decoration: const BoxDecoration(
              gradient: _headerGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x220D9488),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Voltar',
                    ),
                    Expanded(
                      child: Text(
                        'Emitir recibo',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nf.format(widget.valor),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.fornecedorNome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (widget.referente.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.referente.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Quem assina pelo lado da igreja',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Somente liderança: pastor, gestor, secretário, tesoureiro, '
              'administrador ou líder de departamento.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou cargo…',
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              '${_filtered.length} assinante(s) elegível(is)',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: ThemeCleanPremium.primary,
              ),
            ),
          ),
          Expanded(
            child: widget.signers.isEmpty
                ? _emptyState(
                    'Nenhum assinante elegível.\nCadastre pastor, gestor, secretário, '
                    'tesoureiro ou administrador em Membros.',
                  )
                : _filtered.isEmpty
                    ? _emptyState('Nenhum assinante com este filtro.')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: _filtered.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == _filtered.length) {
                            return _digitalSwitchCard();
                          }
                          final e = _filtered[i];
                          final sel = e.memberId == _selectedId;
                          final badge = _badgeForCargo(e.cargo);
                          return Material(
                            color: Colors.white,
                            elevation: sel ? 0 : 0,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => setState(
                                () => _selectedId =
                                    sel ? null : e.memberId,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: sel
                                        ? ThemeCleanPremium.primary
                                        : const Color(0xFFE2E8F0),
                                    width: sel ? 1.6 : 1,
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                            color: ThemeCleanPremium.primary
                                                .withValues(alpha: 0.12),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : ThemeCleanPremium.softUiCardShadow,
                                ),
                                child: Row(
                                  children: [
                                    FotoMembroWidget(
                                      tenantId: widget.tenantId,
                                      memberId: e.memberId,
                                      size: 46,
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
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badge.bg,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              e.cargo,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: badge.fg,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      sel
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: sel
                                          ? ThemeCleanPremium.primary
                                          : Colors.grey.shade400,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    (signer: _selected, useDigital: _useDigital),
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Gerar recibo PDF'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeCleanPremium.minTouchTarget,
                  ),
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.grey.shade600,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _digitalSwitchCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: SwitchListTile.adaptive(
        value: _useDigital,
        onChanged: (v) => setState(() => _useDigital = v),
        activeThumbColor: const Color(0xFF0D9488),
        title: Text(
          'Assinatura digital da igreja',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          'Desative para assinar manualmente no papel.',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
