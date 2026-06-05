import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/search_input_debounce.dart';

/// Busca global no painel — só em `igrejas/{tenantId}/…` (nunca coleções na raiz).
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
  String? _resolvedTenantId;

  @override
  void initState() {
    super.initState();
    _debounce = SearchInputDebounce(onDebounced: _buscar);
    _ctrl.addListener(() => _debounce.schedule(_ctrl.text));
    unawaited(_resolveTenant());
  }

  Future<void> _resolveTenant() async {
    final hint = widget.tenantId.trim();
    if (hint.isEmpty) return;
    try {
      final tid = await TenantResolverService.resolveOperationalChurchDocId(hint);
      if (!mounted) return;
      setState(() => _resolvedTenantId = tid.isNotEmpty ? tid : hint);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvedTenantId = hint);
    }
  }

  CollectionReference<Map<String, dynamic>> _churchCol(String segment) {
    final tid = (_resolvedTenantId ?? widget.tenantId).trim();
    return firebaseDefaultFirestore
        .collection('igrejas')
        .doc(tid)
        .collection(segment);
  }

  @override
  void dispose() {
    _debounce.dispose();
    _ctrl.dispose();
    super.dispose();
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
      if (_resolvedTenantId == null) {
        await _resolveTenant();
      }
      final tid = (_resolvedTenantId ?? widget.tenantId).trim();
      if (tid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final fs = firebaseDefaultFirestore;
      final end = '$t\uf8ff';
      final membros = await fs
          .collection('igrejas')
          .doc(tid)
          .collection('membros')
          .where('nome', isGreaterThanOrEqualTo: t)
          .where('nome', isLessThanOrEqualTo: end)
          .limit(20)
          .get();
      final eventos = await _churchCol(ChurchTenantPostsCollections.eventos)
          .where('titulo', isGreaterThanOrEqualTo: t)
          .where('titulo', isLessThanOrEqualTo: end)
          .limit(20)
          .get();
      final avisos = await _churchCol(ChurchTenantPostsCollections.avisos)
          .where('mensagem', isGreaterThanOrEqualTo: t)
          .where('mensagem', isLessThanOrEqualTo: end)
          .limit(20)
          .get();
      if (!mounted) return;
      setState(() {
        _resultados = [
          ...membros.docs.map((d) => {'tipo': 'Membro', ...d.data()}),
          ...eventos.docs.map((d) => {'tipo': 'Evento', ...d.data()}),
          ...avisos.docs.map((d) => {'tipo': 'Aviso', ...d.data()}),
        ];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar membros, eventos, avisos... (Ctrl+K)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _buscar,
              ),
              const SizedBox(height: 16),
              if (_loading) const CircularProgressIndicator(),
              if (!_loading && _resultados.isEmpty && _ctrl.text.isNotEmpty)
                const Text('Nenhum resultado encontrado.'),
              if (_resultados.isNotEmpty)
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: _resultados.length,
                    itemBuilder: (_, i) {
                      final r = _resultados[i];
                      return ListTile(
                        leading: Icon(
                          r['tipo'] == 'Membro'
                              ? Icons.person
                              : r['tipo'] == 'Evento'
                                  ? Icons.event
                                  : Icons.announcement,
                        ),
                        title: Text(
                          (r['nome'] ??
                                  r['titulo'] ??
                                  r['mensagem'] ??
                                  r['title'] ??
                                  '')
                              .toString(),
                        ),
                        subtitle: Text(r['tipo'].toString()),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
