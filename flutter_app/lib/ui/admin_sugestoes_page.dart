import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:intl/intl.dart';

/// Painel Master — Sugestões e Críticas. Padrão super premium, filtros modernos.
class AdminSugestoesPage extends StatefulWidget {
  const AdminSugestoesPage({super.key});

  @override
  State<AdminSugestoesPage> createState() => _AdminSugestoesPageState();
}

class _AdminSugestoesPageState extends State<AdminSugestoesPage> {
  String _filtroStatus = 'todos'; // todos | pendente | respondido
  String _filtroPeriodo = 'todos'; // todos | mes | ano
  String _busca = '';
  bool _carregando = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('suggestions')
          .limit(200)
          .get();
      final list = snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>().toList();
      list.sort((a, b) {
        final ta = a.data()['createdAt'];
        final tb = b.data()['createdAt'];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
        final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
        return mb.compareTo(ma);
      });
      if (mounted) {
        setState(() {
          _docs = list;
          _carregando = false;
        });
      }
    } catch (e) {
      final msg = e.toString();
      final isPermission = msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED');
      if (mounted) {
        setState(() {
          _docs = [];
          _carregando = false;
          _erro = isPermission
              ? 'Sem permissão. Faça login como administrador (Painel Master) e confirme que sua conta tem perfil ADM.'
              : msg;
        });
      }
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filtrar() {
    var list = _docs;
    if (_filtroStatus == 'pendente') {
      list = list.where((d) => (d.data()['status'] ?? 'pendente').toString() != 'respondido').toList();
    } else if (_filtroStatus == 'respondido') {
      list = list.where((d) => (d.data()['status'] ?? '').toString() == 'respondido').toList();
    }
    if (_filtroPeriodo == 'mes') {
      final now = DateTime.now();
      final inicio = DateTime(now.year, now.month, 1);
      list = list.where((d) {
        final t = d.data()['createdAt'];
        if (t == null) return false;
        final dt = t is Timestamp ? t.toDate() : null;
        return dt != null && !dt.isBefore(inicio);
      }).toList();
    } else if (_filtroPeriodo == 'ano') {
      final now = DateTime.now();
      final inicio = DateTime(now.year, 1, 1);
      list = list.where((d) {
        final t = d.data()['createdAt'];
        if (t == null) return false;
        final dt = t is Timestamp ? t.toDate() : null;
        return dt != null && !dt.isBefore(inicio);
      }).toList();
    }
    if (_busca.trim().isNotEmpty) {
      final q = _busca.trim().toLowerCase();
      list = list.where((d) {
        final data = d.data();
        final text = (data['text'] ?? '').toString().toLowerCase();
        final email = (data['userEmail'] ?? data['userName'] ?? '').toString().toLowerCase();
        final tenant = (data['tenantId'] ?? '').toString().toLowerCase();
        return text.contains(q) || email.contains(q) || tenant.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _responder(String docId, String textoAtual) async {
    final resposta = await showDialog<String>(
      context: context,
      builder: (_) {
        final ctrl = TextEditingController(text: textoAtual);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
          title: const Text('Responder sugestão'),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Digite sua resposta ao usuário...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Enviar resposta'),
            ),
          ],
        );
      },
    );
    if (resposta == null || resposta.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('suggestions').doc(docId).update({
        'response': resposta,
        'respondedAt': FieldValue.serverTimestamp(),
        'status': 'respondido',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Resposta enviada.'),
        );
        _carregar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _fmt(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate();
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrar();

    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _carregar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
            children: [
            Row(
              children: [
                Icon(Icons.feedback_rounded, size: 32, color: ThemeCleanPremium.primary),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sugestões e Críticas',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: ThemeCleanPremium.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mensagens enviadas pelas igrejas. Leia e responda para dar retorno.',
                        style: TextStyle(
                          color: ThemeCleanPremium.onSurfaceVariant,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ThemeCleanPremium.spaceXl),
            // Filtros super premium
            Container(
              padding: EdgeInsets.all(ThemeCleanPremium.spaceMd),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Filtros',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: ThemeCleanPremium.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  TextField(
                    onChanged: (v) => setState(() => _busca = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar por texto, e-mail ou igreja...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                      isDense: true,
                      filled: true,
                      fillColor: ThemeCleanPremium.surfaceVariant,
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filtroStatus,
                          decoration: InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'pendente', child: Text('Pendentes')),
                            DropdownMenuItem(value: 'respondido', child: Text('Respondidos')),
                          ],
                          onChanged: (v) => setState(() => _filtroStatus = v ?? 'todos'),
                        ),
                      ),
                      const SizedBox(width: ThemeCleanPremium.spaceSm),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _filtroPeriodo,
                          decoration: InputDecoration(
                            labelText: 'Período',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'mes', child: Text('Este mês')),
                            DropdownMenuItem(value: 'ano', child: Text('Este ano')),
                          ],
                          onChanged: (v) => setState(() => _filtroPeriodo = v ?? 'todos'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filtrados.length} resultado(s)',
                        style: TextStyle(
                          fontSize: 13,
                          color: ThemeCleanPremium.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _carregando ? null : _carregar,
                        icon: _carregando
                            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ThemeCleanPremium.primary))
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_carregando ? 'Carregando...' : 'Atualizar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            if (_erro != null) ...[
              Container(
                padding: EdgeInsets.all(ThemeCleanPremium.spaceMd),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                    const SizedBox(width: ThemeCleanPremium.spaceSm),
                    Expanded(
                      child: Text(
                        _erro!,
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
            ] else if (_carregando && _docs.isEmpty) ...[
              Center(
                child: Padding(
                  padding: EdgeInsets.all(ThemeCleanPremium.spaceXxl),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: ThemeCleanPremium.primary),
                      const SizedBox(height: ThemeCleanPremium.spaceMd),
                      Text('Carregando sugestões...', style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ] else if (filtrados.isEmpty) ...[
              Container(
                padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.cardBackground,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.feedback_outlined, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      _docs.isEmpty ? 'Nenhuma sugestão ou crítica ainda.' : 'Nenhum resultado para os filtros.',
                      style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else ...[
              ...filtrados.map((d) => _buildCard(d)),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final status = (data['status'] ?? 'pendente').toString();
    final response = (data['response'] ?? '').toString();
    final respondedAt = data['respondedAt'] as Timestamp?;
    final isRespondido = status == 'respondido';

    return Container(
      margin: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(ThemeCleanPremium.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isRespondido
                        ? ThemeCleanPremium.success.withOpacity(0.12)
                        : ThemeCleanPremium.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRespondido ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    color: isRespondido ? ThemeCleanPremium.success : ThemeCleanPremium.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: ThemeCleanPremium.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['userEmail'] ?? data['userName'] ?? 'Anônimo',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Igreja: ${data['tenantId'] ?? '—'} • ${_fmt(data['createdAt'] as Timestamp?)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeCleanPremium.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isRespondido)
                  FilledButton.icon(
                    onPressed: () => _responder(d.id, response),
                    icon: const Icon(Icons.reply_rounded, size: 18),
                    label: const Text('Responder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ThemeCleanPremium.spaceSm),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.surfaceVariant,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
              ),
              child: Text(
                data['text'] ?? '',
                style: const TextStyle(fontSize: 14, height: 1.5, color: ThemeCleanPremium.onSurface),
              ),
            ),
            if (response.isNotEmpty) ...[
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(ThemeCleanPremium.spaceSm),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  border: Border.all(color: ThemeCleanPremium.success.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.reply_rounded, size: 18, color: ThemeCleanPremium.success),
                        const SizedBox(width: 6),
                        Text(
                          'Sua resposta (${_fmt(respondedAt)})',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: ThemeCleanPremium.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      response,
                      style: TextStyle(fontSize: 14, height: 1.5, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
