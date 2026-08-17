import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;

/// Um membro dentro de uma fatia do gráfico (Homens, Crianças, Idosos…).
class MemberSegmentMember {
  const MemberSegmentMember({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  String get displayName {
    for (final k in const ['NOME_COMPLETO', 'nome', 'name', 'displayName']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return 'Membro';
  }

  String get phone {
    for (final k in const ['TELEFONES', 'telefone', 'telefones', 'phone']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get role {
    for (final k in const ['CARGO', 'cargo', 'FUNCAO', 'funcao']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get cpfDigits =>
      (data['CPF'] ?? data['cpf'] ?? '').toString().replaceAll(
        RegExp(r'\D'),
        '',
      );

  String? get authUid {
    final v = (data['authUid'] ?? data['firebaseUid'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }
}

/// Fatia clicável de um gráfico — o que o preview em tela cheia mostra.
class MemberSegment {
  const MemberSegment({
    required this.label,
    required this.members,
    required this.color,
  });

  final String label;
  final List<MemberSegmentMember> members;
  final Color color;

  int get count => members.length;
}

/// Abre o preview em tela cheia da fatia tocada (grid de membros + Voltar).
Future<void> openMemberSegmentPreview(
  BuildContext context, {
  required MemberSegment segment,
  required String chartTitle,
  String? tenantId,
  int? totalForPercent,
}) {
  return Navigator.of(context).push(
    ThemeCleanPremium.fadeSlideRoute(
      MemberSegmentPreviewPage(
        segment: segment,
        chartTitle: chartTitle,
        tenantId: tenantId,
        totalForPercent: totalForPercent,
      ),
    ),
  );
}

/// Grid moderno em tela cheia com os membros de uma fatia do gráfico.
class MemberSegmentPreviewPage extends StatefulWidget {
  const MemberSegmentPreviewPage({
    super.key,
    required this.segment,
    required this.chartTitle,
    this.tenantId,
    this.totalForPercent,
  });

  final MemberSegment segment;
  final String chartTitle;
  final String? tenantId;
  final int? totalForPercent;

  @override
  State<MemberSegmentPreviewPage> createState() =>
      _MemberSegmentPreviewPageState();
}

class _MemberSegmentPreviewPageState extends State<MemberSegmentPreviewPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MemberSegmentMember> get _filtered {
    final q = _query.trim().toLowerCase();
    final all = widget.segment.members;
    if (q.isEmpty) return all;
    return all
        .where(
          (m) =>
              m.displayName.toLowerCase().contains(q) ||
              m.phone.toLowerCase().contains(q) ||
              m.role.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;
    final base = seg.color;
    final dark = Color.lerp(base, const Color(0xFF0F172A), 0.30)!;
    final rows = _filtered;
    final total = widget.totalForPercent ?? 0;
    final pct = total > 0 ? seg.count / total * 100 : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(base, dark, pct),
            Expanded(
              child: rows.isEmpty
                  ? _empty(base)
                  : LayoutBuilder(
                      builder: (context, c) {
                        final crossAxisCount = c.maxWidth >= 1280
                            ? 4
                            : c.maxWidth >= 900
                            ? 3
                            : c.maxWidth >= 560
                            ? 2
                            : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 104,
                              ),
                          itemCount: rows.length,
                          itemBuilder: (context, i) =>
                              _memberCard(rows[i], base),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Color base, Color dark, double? pct) {
    final seg = widget.segment;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [dark, base],
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Material(
                color: Colors.white.withValues(alpha: 0.18),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.maybePop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seg.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    Text(
                      widget.chartTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${seg.count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      pct == null ? 'membros' : '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar nesta lista...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(Color base) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 56,
            color: base.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Text(
            _query.isEmpty
                ? 'Nenhum membro neste grupo.'
                : 'Nenhum resultado para «$_query».',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _memberCard(MemberSegmentMember m, Color base) {
    final idade = ageFromMemberData(m.data);
    final subtitleParts = <String>[
      if (m.role.isNotEmpty) m.role,
      if (idade != null) '$idade anos',
      if (m.phone.isNotEmpty) m.phone,
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: base.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: base.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: FotoMembroWidget(
              imageUrl: imageUrlFromMap(m.data),
              memberData: m.data,
              tenantId: widget.tenantId,
              memberId: m.id,
              cpfDigits: m.cpfDigits.isEmpty ? null : m.cpfDigits,
              authUid: m.authUid,
              size: 52,
              preferListThumbnail: true,
              backgroundColor: base.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitleParts.join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
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
