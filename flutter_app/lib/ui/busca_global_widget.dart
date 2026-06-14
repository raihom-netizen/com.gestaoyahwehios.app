import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/church_panel_tenant_gateway.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/utils/search_input_debounce.dart';

/// Busca global no painel — `igrejas/{churchId}/…` via [ChurchRepository].
///
/// **Sem** `.where()` Firestore na Web: carrega cache plain-first e filtra no cliente.
class BuscaGlobalWidget extends StatefulWidget {
  final String tenantId;

  const BuscaGlobalWidget({super.key, required this.tenantId});

  @override
  State<BuscaGlobalWidget> createState() => _BuscaGlobalWidgetState();
}

class _BuscaGlobalWidgetState extends State<BuscaGlobalWidget> {
  final _ctrl = TextEditingController();
  late final SearchInputDebounce _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _resultados = [];

  String get _churchId => ChurchPanelTenantGateway.churchId(widget.tenantId);

  @override
  void initState() {
    super.initState();
    _debounce = SearchInputDebounce(onDebounced: _buscar);
    _ctrl.addListener(() => _debounce.schedule(_ctrl.text));
  }

  @override
  void dispose() {
    _debounce.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  static bool _matchesTerm(Map<String, dynamic> data, String termo) {
    final t = termo.toLowerCase();
    for (final key in [
      'nome',
      'NOME_COMPLETO',
      'name',
      'titulo',
      'title',
      'mensagem',
      'descricao',
      'texto',
    ]) {
      final v = (data[key] ?? '').toString().toLowerCase();
      if (v.contains(t)) return true;
    }
    return false;
  }

  Future<void> _buscar(String termo) async {
    final t = termo.trim();
    if (t.isEmpty) {
      if (mounted) setState(() => _resultados = []);
      return;
    }
    setState(() {
      _loading = true;
      _resultados = [];
    });
    try {
      final churchId = _churchId;
      if (churchId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final results = <Map<String, dynamic>>[];
      final tl = t.toLowerCase();

      final membros = await ChurchRepository.listCacheFirst(
        module: ChurchRepository.membros,
        churchIdHint: churchId,
        limit: 400,
      );
      for (final d in membros.items) {
        if (!_matchesTerm(d.data(), tl)) continue;
        results.add({'tipo': 'Membro', ...d.data(), 'id': d.id});
        if (results.length >= 20) break;
      }

      if (results.length < 20) {
        final eventos = await ChurchRepository.listCacheFirst(
          module: ChurchRepository.eventos,
          churchIdHint: churchId,
          limit: 120,
        );
        for (final d in eventos.items) {
          if (!_matchesTerm(d.data(), tl)) continue;
          results.add({'tipo': 'Evento', ...d.data(), 'id': d.id});
          if (results.length >= 20) break;
        }
      }

      if (results.length < 20) {
        final avisos = await ChurchRepository.listCacheFirst(
          module: ChurchRepository.avisos,
          churchIdHint: churchId,
          limit: 120,
        );
        for (final d in avisos.items) {
          if (!_matchesTerm(d.data(), tl)) continue;
          results.add({'tipo': 'Aviso', ...d.data(), 'id': d.id});
          if (results.length >= 20) break;
        }
      }

      if (!mounted) return;
      setState(() {
        _resultados = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            labelText: 'Buscar no painel',
            hintText: 'Membro, evento, aviso…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_resultados.isEmpty && _ctrl.text.trim().isNotEmpty)
          const Text('Nenhum resultado.')
        else
          ..._resultados.map(
            (r) => ListTile(
              title: Text(
                (r['nome'] ??
                        r['NOME_COMPLETO'] ??
                        r['titulo'] ??
                        r['title'] ??
                        r['mensagem'] ??
                        '—')
                    .toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text((r['tipo'] ?? '').toString()),
            ),
          ),
      ],
    );
  }
}
