import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/data/app_global_firestore_access.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_info_footer_shortcuts.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_shell_nav_icon.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_module_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tela de informações do sistema, resumo geral e sugestões/críticas.
class SistemaInformacoesPage extends StatefulWidget {
  final String tenantId;
  final bool embeddedInShell;
  final ValueChanged<int>? onNavigateToShellModule;

  const SistemaInformacoesPage({
    super.key,
    required this.tenantId,
    this.embeddedInShell = false,
    this.onNavigateToShellModule,
  });

  @override
  State<SistemaInformacoesPage> createState() => _SistemaInformacoesPageState();
}

class _SistemaModuloResumo {
  const _SistemaModuloResumo({
    required this.shellIndex,
    required this.description,
    this.titleOverride,
  });

  final int shellIndex;
  final String description;
  final String? titleOverride;

  ChurchShellNavEntry get entry => kChurchShellNavEntries[shellIndex];
  String get title => titleOverride ?? entry.label;
}

const _kSistemaModulosResumo = <_SistemaModuloResumo>[
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.membros,
    description: 'Cadastro completo, carteirinha digital com QR Code',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.departamentos,
    description: 'Organização por áreas e lideranças',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.escalaGeral,
    description: 'Minha escala e escala geral de ministérios',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.financeiro,
    description: 'Receitas, despesas, contas e gráficos',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.patrimonio,
    description: 'Controle de bens e equipamentos da igreja',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.muralAvisos,
    description: 'Mural e comunicados oficiais',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.muralEventos,
    description: 'Cultos, programação e feed público',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.chatIgreja,
    description: 'Conversas internas, grupos e mídia em tempo real',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.configuracoes,
    titleOverride: 'Notificações',
    description: 'Comunicados, lembretes e alertas do painel',
  ),
  _SistemaModuloResumo(
    shellIndex: ChurchShellIndices.doacao,
    titleOverride: 'Assinaturas',
    description: 'Planos, PIX e cartão via Mercado Pago',
  ),
];

class _SistemaInformacoesPageState extends State<SistemaInformacoesPage> {
  final _textoController = TextEditingController();
  bool _loading = false;
  bool _enviado = false;

  @override
  void dispose() {
    _textoController.dispose();
    super.dispose();
  }

  Future<void> _enviarSugestao() async {
    final texto = _textoController.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite sua sugestão ou crítica.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await AppGlobalFirestoreAccess.addSuggestion({
        'tenantId': widget.tenantId,
        'userId': user?.uid ?? '',
        'userEmail': user?.email ?? '',
        'userName': user?.displayName ?? '',
        'text': texto,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pendente',
      });
      _textoController.clear();
      setState(() => _enviado = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sua sugestão foi enviada. Obrigado!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor:
          widget.embeddedInShell ? Colors.transparent : ThemeCleanPremium.surfaceVariant,
      appBar: widget.embeddedInShell || isMobile
          ? null
          : AppBar(
        title: const Text('Informações'),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: !widget.embeddedInShell,
        child: SingleChildScrollView(
          padding: padding,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YahwehWisdomSectionCard(
                  borderTint: YahwehWisdomVisualKit.tealAccent,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ChurchShellNavIcon3D(
                            icon: kChurchShellNavEntries[ChurchShellIndices.informacoes].icon,
                            accent: kChurchShellNavEntries[ChurchShellIndices.informacoes].accent,
                            size: 52,
                            iconSize: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gestão YAHWEH',
                                  style: GoogleFonts.poppins(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: YahwehWisdomVisualKit.navyDeep,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Informações · ajuda, versão e módulos do app',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const YahwehWisdomGoldTitle(
                        text: 'Resumo do sistema',
                        fontSize: 20,
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Principais áreas do painel — ícones 3D iguais ao menu lateral.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildModulosResumoGrid(context),
                      const SizedBox(height: 24),
                      const YahwehWisdomGoldTitle(
                        text: 'Utilitários e segurança',
                        fontSize: 20,
                        textAlign: TextAlign.start,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tecnologia trabalhando nos bastidores para proteger seus dados e deixar tudo rápido.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _UtilitariosSegurancaGrid(),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              YahwehWisdomVisualKit.navyMid.withValues(alpha: 0.08),
                              YahwehWisdomVisualKit.tealAccent.withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: YahwehWisdomVisualKit.tealAccent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          'Agradecemos a confiança em nossa plataforma. '
                          'O Gestão YAHWEH foi desenvolvido para auxiliar igrejas na organização '
                          'de membros, eventos, finanças e comunicação. Seu feedback é muito importante para melhorarmos continuamente.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: YahwehWisdomVisualKit.navyDeep,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (widget.onNavigateToShellModule != null)
                        ChurchInfoFooterShortcuts(
                          onNavigate: widget.onNavigateToShellModule!,
                        ),
                      const SizedBox(height: 20),
                      Center(
                        child: Column(
                          children: [
                            Text(
                              'Desenvolvido por Raihom Barbosa',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Versão $appVersionFull',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                YahwehWisdomSectionCard(
                  borderTint: const Color(0xFF38BDF8),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.feedback_rounded, size: 28, color: Colors.orange.shade700),
                            const SizedBox(width: 12),
                            const Text(
                              'Sugestões ou críticas',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Envie sua opinião. Leitura e resposta são feitas pelo painel administrativo.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _textoController,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: 'Digite sua sugestão, crítica ou elogio...',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          enabled: !_loading,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _enviarSugestao,
                            icon: _loading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, size: 20),
                            label: Text(_loading ? 'Enviando...' : 'Enviar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E40AF),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_enviado)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Obrigado! Você receberá um retorno em breve.', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text('Suas mensagens e respostas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 8),
                        _MinhasSugestoes(tenantId: widget.tenantId),
                      ],
                    ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildModulosResumoGrid(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    if (wide) {
      return LayoutBuilder(
        builder: (context, c) {
          final cross = c.maxWidth >= 960 ? 2 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _kSistemaModulosResumo.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 3.35,
            ),
            itemBuilder: (_, i) => _buildModuloCard(_kSistemaModulosResumo[i]),
          );
        },
      );
    }
    return Column(
      children: [
        for (final m in _kSistemaModulosResumo) _buildModuloCard(m),
      ],
    );
  }

  Widget _buildModuloCard(_SistemaModuloResumo m) {
    final entry = m.entry;
    return ChurchWisdomModuleListCard(
      title: m.title,
      subtitle: m.description,
      accent: entry.accent,
      dense: true,
      onTap: widget.onNavigateToShellModule != null
          ? () => widget.onNavigateToShellModule!(m.shellIndex)
          : null,
      leading: ChurchShellNavIcon3D(
        icon: entry.icon,
        accent: entry.accent,
        size: 46,
        iconSize: 24,
      ),
    );
  }
}

/// Grid moderno de utilitários — segurança, backups, conversões e performance.
class _UtilitariosSegurancaGrid extends StatelessWidget {
  const _UtilitariosSegurancaGrid();

  static const List<({IconData icon, Color accent, String title, String body})>
      _items = [
    (
      icon: Icons.shield_rounded,
      accent: Color(0xFF10B981),
      title: 'Segurança de dados',
      body:
          'Criptografia em trânsito e acesso por perfil — cada membro vê só o que pode.',
    ),
    (
      icon: Icons.cloud_done_rounded,
      accent: Color(0xFF3B82F6),
      title: 'Backups automáticos',
      body:
          'Cadastros, finanças e mídias protegidos na nuvem Google / Firebase.',
    ),
    (
      icon: Icons.autorenew_rounded,
      accent: Color(0xFF8B5CF6),
      title: 'Conversões modernas',
      body:
          'Fotos e vídeos otimizados automaticamente (WebP HD) — envio rápido até no 4G.',
    ),
    (
      icon: Icons.picture_as_pdf_rounded,
      accent: Color(0xFFF59E0B),
      title: 'Exportações e PDF',
      body:
          'Relatórios premium e resumos mensais prontos para imprimir ou compartilhar.',
    ),
    (
      icon: Icons.bolt_rounded,
      accent: Color(0xFFEC4899),
      title: 'Cache inteligente',
      body:
          'Módulos abrem na hora: carregam da memória e sincronizam em segundo plano.',
    ),
    (
      icon: Icons.system_update_rounded,
      accent: Color(0xFF06B6D4),
      title: 'Atualizações contínuas',
      body:
          'Melhorias constantes com a mesma experiência em web, Android e iOS.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 2 : 1;
        const gap = 10.0;
        final tileW =
            cols <= 1 ? c.maxWidth : (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _items.map((it) {
            return Container(
              width: tileW,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: it.accent.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: it.accent.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          it.accent,
                          Color.lerp(it.accent, Colors.black, 0.25)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: it.accent.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(it.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it.title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: YahwehWisdomVisualKit.navyDeep,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          it.body,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MinhasSugestoes extends StatefulWidget {
  final String tenantId;

  const _MinhasSugestoes({required this.tenantId});

  @override
  State<_MinhasSugestoes> createState() => _MinhasSugestoesState();
}

class _MinhasSugestoesState extends State<_MinhasSugestoes> {
  int _streamKey = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(_streamKey),
      stream: AppGlobalFirestoreAccess.watchUserSuggestions(uid),
      builder: (context, snap) {
        if (snap.hasError && (snap.data?.docs.isEmpty ?? true)) {
          return ChurchPanelResilientLoadBanner(
            hasLocalData: false,
            isSyncing: false,
            errorTitle: 'Não foi possível carregar suas mensagens',
            error: snap.error,
            onRetry: () => setState(() => _streamKey++),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text('Nenhuma mensagem enviada ainda.', style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        final docs = snap.data!.docs.toList()
          ..sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: docs.map((d) {
            final data = d.data();
            final response = (data['response'] ?? '').toString();
            final respondedAt = data['respondedAt'] as Timestamp?;
            String fmt(Timestamp? ts) {
              if (ts == null) return '—';
              final dt = ts.toDate();
              return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
            }
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(response.isEmpty ? Icons.schedule : Icons.check_circle, size: 18, color: response.isEmpty ? Colors.orange : Colors.green),
                        const SizedBox(width: 8),
                        Text('${fmt(data['createdAt'] as Timestamp?)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(data['text'] ?? '', style: const TextStyle(fontSize: 14)),
                    if (response.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Resposta: ${fmt(respondedAt)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                            const SizedBox(height: 4),
                            Text(response, style: TextStyle(fontSize: 13, color: Colors.green.shade900)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
