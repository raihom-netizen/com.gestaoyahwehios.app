import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/firestore_rest_read.dart';

/// Painel Master — Central de Alertas.
///
/// Leitura por REST: o `.get()` do SDK JS abre um alvo de listen a cada
/// chamada e era o que devolvia «Sincronização com o servidor em curso» nesta
/// tela ([[project_web_rest_gateway_total_fix]]).
class AdminAlertasPage extends StatefulWidget {
  const AdminAlertasPage({super.key});

  @override
  State<AdminAlertasPage> createState() => _AdminAlertasPageState();
}

enum _FiltroAlerta { todos, naoLidos, lidos }

class _AdminAlertasPageState extends State<AdminAlertasPage> {
  static const Color _cAmber = Color(0xFFD97706);
  static const Color _cRed = Color(0xFFDC2626);
  static const Color _cGreen = Color(0xFF16A34A);
  static const Color _cIndigo = Color(0xFF4F46E5);
  static const Color _cSlate = Color(0xFF64748B);

  bool _loading = true;
  bool _marcando = false;
  String? _error;
  List<Map<String, dynamic>> _alertas = const [];
  String _busca = '';
  _FiltroAlerta _filtro = _FiltroAlerta.todos;

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
      final docs = await firestoreListDocsSafe(
        firebaseDefaultFirestore.collection('alertas'),
        orderByField: 'data',
        descending: true,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _alertas = docs.map((d) => {...d.data(), 'id': d.id}).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      setState(() {
        _alertas = const [];
        _loading = false;
        _error =
            s.contains('permission-denied') || s.contains('PERMISSION_DENIED')
            ? 'Sem permissão para acessar alertas. Confirme as regras do Firestore.'
            : 'Não foi possível carregar os alertas agora. Toque em Tentar novamente.';
      });
    }
  }

  Future<void> _marcarComoLido(Map<String, dynamic> alerta) async {
    final id = '${alerta['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    try {
      await YahwehDocWrite.update(
        firebaseDefaultFirestore.collection('alertas').doc(id),
        {'lido': true},
      );
      if (!mounted) return;
      setState(() {
        _alertas = _alertas
            .map((a) => a['id'] == id ? {...a, 'lido': true} : a)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatFirebaseErrorForUser(e, logToCrashlytics: false)),
          backgroundColor: ThemeCleanPremium.error,
        ),
      );
    }
  }

  Future<void> _marcarTodos() async {
    final pendentes = _alertas.where((a) => a['lido'] != true).toList();
    if (pendentes.isEmpty || _marcando) return;
    setState(() => _marcando = true);
    var falhas = 0;
    for (final a in pendentes) {
      final id = '${a['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      try {
        await YahwehDocWrite.update(
          firebaseDefaultFirestore.collection('alertas').doc(id),
          {'lido': true},
        );
      } catch (_) {
        falhas++;
      }
    }
    if (!mounted) return;
    setState(() {
      _marcando = false;
      _alertas = _alertas.map((a) => {...a, 'lido': true}).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      falhas == 0
          ? ThemeCleanPremium.successSnackBar(
              '${pendentes.length} alerta(s) marcados como lidos.',
            )
          : SnackBar(
              content: Text('$falhas alerta(s) não puderam ser marcados.'),
              backgroundColor: ThemeCleanPremium.error,
            ),
    );
  }

  /// Cor/ícone por severidade — «critico», «erro», «aviso» ou informativo.
  ({Color cor, IconData icone}) _estilo(Map<String, dynamic> a) {
    final nivel = '${a['nivel'] ?? a['severidade'] ?? a['tipo'] ?? ''}'
        .toLowerCase();
    if (nivel.contains('crit') || nivel.contains('erro') ||
        nivel.contains('error')) {
      return (cor: _cRed, icone: Icons.error_rounded);
    }
    if (nivel.contains('aviso') || nivel.contains('warn')) {
      return (cor: _cAmber, icone: Icons.warning_amber_rounded);
    }
    if (nivel.contains('ok') || nivel.contains('sucesso')) {
      return (cor: _cGreen, icone: Icons.check_circle_rounded);
    }
    return (cor: _cIndigo, icone: Icons.notifications_active_rounded);
  }

  String _dataTexto(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return v.toString();
  }

  List<Map<String, dynamic>> get _filtrados {
    final b = _busca.trim().toLowerCase();
    return _alertas.where((a) {
      final lido = a['lido'] == true;
      if (_filtro == _FiltroAlerta.naoLidos && lido) return false;
      if (_filtro == _FiltroAlerta.lidos && !lido) return false;
      if (b.isEmpty) return true;
      final texto =
          '${a['mensagem'] ?? ''} ${a['titulo'] ?? ''} ${a['tipo'] ?? ''}'
              .toLowerCase();
      return texto.contains(b);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final naoLidos = _alertas.where((a) => a['lido'] != true).length;
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
                  _cabecalho(naoLidos),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar alerta',
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _chip('Todos', _FiltroAlerta.todos, _cIndigo,
                          _alertas.length),
                      const SizedBox(width: 8),
                      _chip('Não lidos', _FiltroAlerta.naoLidos, _cAmber,
                          naoLidos),
                      const SizedBox(width: 8),
                      _chip('Lidos', _FiltroAlerta.lidos, _cGreen,
                          _alertas.length - naoLidos),
                    ],
                  ),
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

  Widget _cabecalho(int naoLidos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: naoLidos > 0
              ? const [_cAmber, Color(0xFFF59E0B)]
              : const [_cIndigo, Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
            color: (naoLidos > 0 ? _cAmber : _cIndigo).withValues(alpha: 0.28),
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
              Icons.notifications_active_rounded,
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
                  'Central de Alertas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  naoLidos > 0
                      ? '$naoLidos alerta(s) por ler'
                      : 'Tudo em dia — nenhum alerta pendente.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (naoLidos > 0)
            TextButton.icon(
              onPressed: _marcando ? null : _marcarTodos,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: _marcando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Ler todos'),
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

  Widget _chip(String label, _FiltroAlerta f, Color cor, int total) {
    final ativo = _filtro == f;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _filtro = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: ativo ? cor : cor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cor.withValues(alpha: ativo ? 1 : 0.30)),
          ),
          child: Text(
            '$label ($total)',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
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

  Widget _cartao(Map<String, dynamic> a) {
    final lido = a['lido'] == true;
    final e = _estilo(a);
    final cor = lido ? _cSlate : e.cor;
    final data = _dataTexto(a['data']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          border: Border.all(color: cor.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: cor.withValues(alpha: lido ? 0.03 : 0.09),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: cor),
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
                          color: cor.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(e.icone, color: cor, size: 20),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${a['mensagem'] ?? a['titulo'] ?? 'Sem mensagem'}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: lido
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                fontSize: 14,
                                height: 1.35,
                                color: ThemeCleanPremium.onSurface,
                              ),
                            ),
                            if (data.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: _cSlate,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    data,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: _cSlate,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!lido)
                        IconButton(
                          tooltip: 'Marcar como lido',
                          onPressed: () => unawaited(_marcarComoLido(a)),
                          icon: Icon(
                            Icons.check_circle_outline_rounded,
                            color: cor,
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

  Widget _vazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: MasterPremiumCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_off_rounded,
                size: 52,
                color: _cSlate.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                _alertas.isEmpty
                    ? 'Nenhum alerta registrado.'
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
