import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_theme.dart' show SaaSContentViewport;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import '../widgets/instagram_mural.dart';

class MuralPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Evita AppBar duplicada quando aberto dentro de [IgrejaCleanShell].
  final bool embeddedInShell;
  const MuralPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.embeddedInShell = false,
  });

  @override
  State<MuralPage> createState() => _MuralPageState();
}

class _MuralPageState extends State<MuralPage> {
  int _slugRetryKey = 0;

  Future<String> _loadSlug() async {
    final snap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .get();
    final data = snap.data() ?? {};
    final slug = (data['slug'] ?? '').toString().trim();
    return slug.isEmpty ? widget.tenantId : slug;
  }

  Future<void> _onRefresh() async {
    setState(() => _slugRetryKey++);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final basePad = ThemeCleanPremium.pagePadding(context);
    final padding = widget.embeddedInShell
        ? EdgeInsets.fromLTRB(
            basePad.left,
            ThemeCleanPremium.spaceSm,
            basePad.right,
            basePad.bottom,
          )
        : basePad;
    final showAppBar =
        !widget.embeddedInShell && (!isMobile || Navigator.canPop(context));
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: !showAppBar
          ? null
          : AppBar(
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Mural de Avisos'),
            ),
      body: SafeArea(
        child: FutureBuilder<String>(
          key: ValueKey(_slugRetryKey),
          future: _loadSlug(),
          builder: (context, snap) {
            if (snap.hasError) {
              return ChurchPanelErrorBody(
                title: 'Não foi possível carregar o mural',
                error: snap.error,
                onRetry: () => setState(() => _slugRetryKey++),
              );
            }
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const ChurchPanelLoadingBody();
            }
            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: SaaSContentViewport(
                // Largura útil como nos demais módulos do painel (até 1200px), não coluna fixa de feed social.
                child: ListView(
                  padding: padding,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    InstagramMural(
                      tenantId: widget.tenantId,
                      role: widget.role,
                      churchSlug: snap.data!,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
