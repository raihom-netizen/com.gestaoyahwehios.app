import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';

/// Logs de uso do Firebase — master vê tudo, gestor vê só a sua igreja.
///
/// Leitura por REST ([[project_web_rest_gateway_total_fix]]): o `.get()` do SDK
/// JS abre um alvo de listen por chamada e era o que devolvia «Sincronização
/// com o servidor em curso» nesta tela.
class AdminAuditoriaPage extends StatefulWidget {
  const AdminAuditoriaPage({super.key});

  @override
  State<AdminAuditoriaPage> createState() => _AdminAuditoriaPageState();
}

class _AdminAuditoriaPageState extends State<AdminAuditoriaPage> {
  static const Color _cIndigo = Color(0xFF4F46E5);
  static const Color _cBlue = Color(0xFF2563EB);
  static const Color _cGreen = Color(0xFF16A34A);
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cRed = Color(0xFFDC2626);
  static const Color _cSlate = Color(0xFF64748B);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = const [];
  String _busca = '';
  String _acaoFiltro = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = firebaseDefaultAuth.currentUser;
      await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
      final token = await user?.getIdTokenResult(false);
      final role = '${token?.claims?['role'] ?? ''}'.toUpperCase();
      final igrejaId = '${token?.claims?['igrejaId'] ?? ''}'.trim();
      final isMaster = role == 'MASTER' || role == 'ADMIN' || role == 'ADM';

      final docs = await firestoreListDocsSafe(
        firebaseDefaultFirestore.collection('auditoria'),
        equals: !isMaster && igrejaId.isNotEmpty
            ? {'igrejaId': igrejaId}
            : const {},
        orderByField: 'data',
        descending: true,
        limit: YahwehPerformanceV4.masterAuditLogLimit,
      );
      if (!mounted) return;
      setState(() {
        _logs = docs.map((d) => d.data()).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      setState(() {
        _logs = const [];
        _loading = false;
        _error =
            s.contains('permission-denied') || s.contains('PERMISSION_DENIED')
            ? 'Sem permissão para acessar a auditoria.'
            : 'Não foi possível carregar a auditoria agora. '
                  'Toque em Tentar novamente.';
      });
    }
  }

  /// Cor e ícone conforme a natureza da ação registada.
  ({Color cor, IconData icone}) _estilo(String acao) {
    final a = acao.toLowerCase();
    if (a.contains('exclu') || a.contains('delete') || a.contains('remov')) {
      return (cor: _cRed, icone: Icons.delete_forever_rounded);
    }
    if (a.contains('cri') || a.contains('add') || a.contains('cadastr')) {
      return (cor: _cGreen, icone: Icons.add_circle_rounded);
    }
    if (a.contains('edit') || a.contains('atualiz') || a.contains('update')) {
      return (cor: _cAmber, icone: Icons.edit_rounded);
    }
    if (a.contains('login') || a.contains('sess') || a.contains('acesso')) {
      return (cor: _cBlue, icone: Icons.login_rounded);
    }
    return (cor: _cIndigo, icone: Icons.history_rounded);
  }

  String _formatData(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  /// Categorias presentes nos logs — viram filtros rápidos no topo.
  List<String> get _categorias {
    final set = <String>{};
    for (final l in _logs) {
      final a = '${l['acao'] ?? ''}'.trim();
      if (a.isNotEmpty) set.add(a);
    }
    final lista = set.toList()..sort();
    return lista.take(8).toList();
  }

  List<Map<String, dynamic>> get _filtrados {
    final b = _busca.trim().toLowerCase();
    return _logs.where((l) {
      if (_acaoFiltro.isNotEmpty && '${l['acao'] ?? ''}' != _acaoFiltro) {
        return false;
      }
      if (b.isEmpty) return true;
      final texto =
          '${l['acao'] ?? ''} ${l['usuario'] ?? ''} '
                  '${l['resource'] ?? ''} ${l['details'] ?? ''}'
              .toLowerCase();
      return texto.contains(b);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final itens = _filtrados;
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                10,
              ),
              child: Column(
                children: [
                  _cabecalho(),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar por ação, usuário ou recurso',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusMd,
                        ),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: ThemeCleanPremium.cardBackground,
                    ),
                    onChanged: (v) => setState(() => _busca = v),
                  ),
                  if (_categorias.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip('Todas', ''),
                          for (final c in _categorias) _chip(c, c),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _banner(),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : itens.isEmpty
                  ? _vazio()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          padding.left,
                          4,
                          padding.right,
                          padding.bottom + 28,
                        ),
                        itemCount: itens.length,
                        itemBuilder: (_, i) => _cartao(itens[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF334155), _cIndigo],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: _cIndigo.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Auditoria',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_logs.length} registro(s) carregado(s).',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String valor) {
    final ativo = _acaoFiltro == valor;
    final cor = valor.isEmpty ? _cSlate : _estilo(valor).cor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _acaoFiltro = valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: ativo ? cor : cor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cor.withValues(alpha: ativo ? 1 : 0.30)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ativo ? Colors.white : cor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _cRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: _cRed.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _cRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: _cRed),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('Tentar novamente')),
        ],
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> l) {
    final acao = '${l['acao'] ?? '—'}';
    final e = _estilo(acao);
    final usuario = '${l['usuario'] ?? 'sistema'}';
    final resource = '${l['resource'] ?? ''}'.trim();
    final details = '${l['details'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          border: Border.all(color: e.cor.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: e.cor.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: e.cor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: e.cor.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(e.icone, color: e.cor, size: 20),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acao,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _tag(Icons.person_rounded, usuario, _cSlate),
                                if (resource.isNotEmpty)
                                  _tag(
                                    Icons.folder_rounded,
                                    resource,
                                    _cIndigo,
                                  ),
                                _tag(
                                  Icons.schedule_rounded,
                                  _formatData(l['data']),
                                  _cBlue,
                                ),
                              ],
                            ),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Text(
                                details,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: _cSlate,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar registro',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  '$acao | $usuario | $resource | '
                                  '${_formatData(l['data'])} | $details',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            ThemeCleanPremium.successSnackBar(
                              'Registro copiado.',
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 18,
                          color: _cSlate,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cor),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: MasterPremiumCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 52,
                color: _cSlate.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                _logs.isEmpty
                    ? 'Nenhum registro de auditoria.'
                    : 'Nenhum resultado com este filtro.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _cSlate, fontSize: 14),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Atualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
