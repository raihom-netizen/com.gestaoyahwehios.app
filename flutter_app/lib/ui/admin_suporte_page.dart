import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Painel Master — Suporte e chamados (Super Premium: cards 16px, sombras suaves, espaçamento generoso).
class AdminSuportePage extends StatefulWidget {
  const AdminSuportePage({super.key});

  @override
  State<AdminSuportePage> createState() => _AdminSuportePageState();
}

class _AdminSuportePageState extends State<AdminSuportePage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _chamados = [];
  String _busca = '';

  static final _df = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  static DateTime _dataChamado(dynamic raw) {
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      } catch (_) {}
    }
    final s = raw.toString();
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Sem orderBy no servidor: evita índice composto + reduz bugs do listener/cache no Firestore Web (SDK 11.x).
      final snap = await FirebaseFirestore.instance
          .collection('suporte')
          .limit(200)
          .get(const GetOptions(source: Source.server));

      final list = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      list.sort((a, b) => _dataChamado(b['data'] ?? b['createdAt']).compareTo(_dataChamado(a['data'] ?? a['createdAt'])));

      if (mounted) {
        _chamados = list;
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _chamados = [];
        final msg = e.toString();
        final isDenied = msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED') ||
            msg.contains('Missing or insufficient permissions');
        setState(() {
          _loading = false;
          _error = isDenied
              ? 'Sem permissão na coleção suporte. Publique as regras do Firestore (match /suporte/{id}) e faça deploy: firebase deploy --only firestore:rules'
              : 'Não foi possível carregar. Publique as regras, recarregue com Ctrl+F5.\n\n$msg';
        });
      }
    }
  }

  Future<void> _responderChamado(Map<String, dynamic> chamado) async {
    final id = chamado['id'] as String?;
    if (id == null || id.isEmpty) return;
    final resposta = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => _ResponderChamadoDialog(
        usuario: (chamado['usuario'] ?? 'Usuário').toString(),
      ),
    );
    if (resposta != null && resposta.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('suporte').doc(id).update({
          'resposta': resposta,
          'respondido': true,
          'respondidoEm': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Resposta registrada.'),
          );
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: ThemeCleanPremium.error),
          );
        }
      }
    }
  }

  String _formatData(dynamic raw) {
    final d = _dataChamado(raw);
    if (d.millisecondsSinceEpoch == 0) return '';
    try {
      return _df.format(d);
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final filtrados = _chamados.where((c) {
      final b = _busca.trim().toLowerCase();
      if (b.isEmpty) return true;
      final texto = (c['mensagem'] ?? '').toString().toLowerCase();
      final usuario = (c['usuario'] ?? '').toString().toLowerCase();
      final email = (c['email'] ?? '').toString().toLowerCase();
      return texto.contains(b) || usuario.contains(b) || email.contains(b);
    }).toList();

    final abertos = _chamados.where((c) => c['respondido'] != true).length;
    final respondidos = _chamados.length - abertos;

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, ThemeCleanPremium.spaceSm),
              child: _SuporteHeaderCard(
                total: _chamados.length,
                abertos: abertos,
                respondidos: respondidos,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, ThemeCleanPremium.spaceSm),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                  hintText: 'Buscar chamado ou usuário',
                  hintStyle: TextStyle(color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.8)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, ThemeCleanPremium.spaceSm),
                child: _PremiumCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: ThemeCleanPremium.error, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13, height: 1.35),
                        ),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtrados.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(padding.left, 24, padding.right, padding.bottom + 24),
                            child: _PremiumCard(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.support_agent_rounded, size: 48, color: ThemeCleanPremium.primary.withValues(alpha: 0.9)),
                                  ),
                                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                                  Text(
                                    _chamados.isEmpty ? 'Nenhum chamado de suporte' : 'Nenhum resultado para a busca',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                      color: ThemeCleanPremium.onSurface,
                                      letterSpacing: 0.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _chamados.isEmpty
                                        ? 'Quando usuários abrirem chamados, eles aparecerão aqui em tempo real após o próximo carregamento.'
                                        : 'Ajuste os termos da busca ou limpe o campo.',
                                    style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14, height: 1.4),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                          itemCount: filtrados.length,
                          itemBuilder: (_, i) {
                            final c = filtrados[i];
                            final respondido = c['respondido'] == true;
                            final dataStr = _formatData(c['data'] ?? c['createdAt']);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                                  onTap: respondido ? null : () => _responderChamado(c),
                                  child: _PremiumCard(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: respondido
                                                    ? const Color(0xFFE8F5E9)
                                                    : const Color(0xFFFFF8E1),
                                                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                                              ),
                                              child: Icon(
                                                respondido ? Icons.check_circle_rounded : Icons.mark_chat_unread_rounded,
                                                color: respondido ? const Color(0xFF2E7D32) : const Color(0xFFF57C00),
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (c['usuario'] ?? 'Sem nome').toString(),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 15,
                                                      color: ThemeCleanPremium.onSurface,
                                                    ),
                                                  ),
                                                  if ((c['email'] ?? '').toString().isNotEmpty)
                                                    Text(
                                                      c['email'].toString(),
                                                      style: TextStyle(fontSize: 12, color: ThemeCleanPremium.onSurfaceVariant),
                                                    ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    (c['mensagem'] ?? '—').toString(),
                                                    style: TextStyle(fontSize: 14, height: 1.45, color: Colors.grey.shade800),
                                                  ),
                                                  if (dataStr.isNotEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 10),
                                                      child: Text(
                                                        dataStr,
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                                      ),
                                                    ),
                                                  if (respondido && (c['resposta'] ?? '').toString().isNotEmpty) ...[
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      width: double.infinity,
                                                      padding: const EdgeInsets.all(12),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFF0F7FF),
                                                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                                                        border: Border.all(color: const Color(0xFFBBDEFB).withValues(alpha: 0.6)),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            'Resposta',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w800,
                                                              color: ThemeCleanPremium.primary.withValues(alpha: 0.9),
                                                              letterSpacing: 0.6,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 6),
                                                          Text(
                                                            c['resposta'].toString(),
                                                            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade900),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (!respondido)
                                              IconButton(
                                                icon: Icon(Icons.reply_rounded, color: ThemeCleanPremium.primary),
                                                tooltip: 'Responder',
                                                onPressed: () => _responderChamado(c),
                                                style: IconButton.styleFrom(
                                                  minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
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
    );
  }
}

class _SuporteHeaderCard extends StatelessWidget {
  const _SuporteHeaderCard({
    required this.total,
    required this.abertos,
    required this.respondidos,
  });

  final int total;
  final int abertos;
  final int respondidos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.92),
            ThemeCleanPremium.primary.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Central de suporte',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Chamados dos usuários — responda com clareza e empatia.',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(label: 'Total', value: '$total', light: true),
              _StatChip(label: 'Abertos', value: '$abertos', light: true),
              _StatChip(label: 'Respondidos', value: '$respondidos', light: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.light = false});

  final String label;
  final String value;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.22) : ThemeCleanPremium.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: light ? Colors.white24 : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: light ? Colors.white70 : ThemeCleanPremium.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: light ? Colors.white : ThemeCleanPremium.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 24, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x04000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: child,
    );
  }
}

class _ResponderChamadoDialog extends StatefulWidget {
  const _ResponderChamadoDialog({required this.usuario});

  final String usuario;

  @override
  State<_ResponderChamadoDialog> createState() => _ResponderChamadoDialogState();
}

class _ResponderChamadoDialogState extends State<_ResponderChamadoDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
      title: Row(
        children: [
          Icon(Icons.reply_rounded, color: ThemeCleanPremium.primary, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Responder',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.usuario,
              style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Sua resposta',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                filled: true,
                fillColor: ThemeCleanPremium.surfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          icon: const Icon(Icons.send_rounded, size: 20),
          label: const Text('Enviar resposta'),
          style: FilledButton.styleFrom(
            backgroundColor: ThemeCleanPremium.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}
