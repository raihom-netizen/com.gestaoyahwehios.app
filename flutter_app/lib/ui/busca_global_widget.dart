import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/search_input_debounce.dart';

class BuscaGlobalWidget extends StatefulWidget {
  const BuscaGlobalWidget({super.key});

  @override
  State<BuscaGlobalWidget> createState() => _BuscaGlobalWidgetState();
}

class _BuscaGlobalWidgetState extends State<BuscaGlobalWidget> {
  final _ctrl = TextEditingController();
  late final SearchInputDebounce _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _resultados = [];

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
      final fs = firebaseDefaultFirestore;
      final end = '$t\uf8ff';
      final membros = await fs
          .collection('membros')
          .where('nome', isGreaterThanOrEqualTo: t)
          .where('nome', isLessThanOrEqualTo: end)
          .limit(20)
          .get();
      final eventos = await fs
          .collection('eventos')
          .where('titulo', isGreaterThanOrEqualTo: t)
          .where('titulo', isLessThanOrEqualTo: end)
          .limit(20)
          .get();
      final avisos = await fs
          .collection('avisos')
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
                          r['tipo'] == 'Membro'
                              ? r['nome'] ?? ''
                              : r['tipo'] == 'Evento'
                                  ? r['titulo'] ?? ''
                                  : r['mensagem'] ?? '',
                        ),
                        subtitle: Text(r['tipo'] ?? ''),
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
