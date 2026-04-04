import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BuscaGlobalWidget extends StatefulWidget {
  const BuscaGlobalWidget({super.key});

  @override
  State<BuscaGlobalWidget> createState() => _BuscaGlobalWidgetState();
}

class _BuscaGlobalWidgetState extends State<BuscaGlobalWidget> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _resultados = [];

  Future<void> _buscar(String termo) async {
    if (termo.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _resultados = [];
    });
    // Exemplo: busca em membros, eventos e avisos
    final membros = await FirebaseFirestore.instance.collection('membros').where('nome', isGreaterThanOrEqualTo: termo).where('nome', isLessThanOrEqualTo: termo + '\uf8ff').get();
    final eventos = await FirebaseFirestore.instance.collection('eventos').where('titulo', isGreaterThanOrEqualTo: termo).where('titulo', isLessThanOrEqualTo: termo + '\uf8ff').get();
    final avisos = await FirebaseFirestore.instance.collection('avisos').where('mensagem', isGreaterThanOrEqualTo: termo).where('mensagem', isLessThanOrEqualTo: termo + '\uf8ff').get();
    setState(() {
      _resultados = [
        ...membros.docs.map((d) => {'tipo': 'Membro', ...d.data()}),
        ...eventos.docs.map((d) => {'tipo': 'Evento', ...d.data()}),
        ...avisos.docs.map((d) => {'tipo': 'Aviso', ...d.data()}),
      ];
      _loading = false;
    });
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
                        leading: Icon(r['tipo'] == 'Membro' ? Icons.person : r['tipo'] == 'Evento' ? Icons.event : Icons.announcement),
                        title: Text(r['tipo'] == 'Membro' ? r['nome'] ?? '' : r['tipo'] == 'Evento' ? r['titulo'] ?? '' : r['mensagem'] ?? ''),
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
