import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

class GaleriaEventosPage extends StatefulWidget {
  const GaleriaEventosPage({super.key});

  @override
  State<GaleriaEventosPage> createState() => _GaleriaEventosPageState();
}

class _GaleriaEventosPageState extends State<GaleriaEventosPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _eventos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final snap = await FirebaseFirestore.instance.collection('eventos').orderBy('data', descending: true).get();
    _eventos = snap.docs.map((d) => d.data()).toList();
    setState(() => _loading = false);
  }

  void _abrirComentarios(Map<String, dynamic> evento) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ComentariosEvento(eventoId: evento['id']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galeria de Eventos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemCount: _eventos.length,
              itemBuilder: (_, i) {
                final e = _eventos[i];
                final imgUrl = imageUrlFromMap(e);
                return GestureDetector(
                  onTap: () => _abrirComentarios(e),
                  child: Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                            child: imgUrl.isNotEmpty
                                ? SafeNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover, errorWidget: Container(color: Colors.grey[300]))
                                : Container(color: Colors.grey[300]),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e['titulo'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(e['data'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.comment, size: 16, color: Colors.blueGrey),
                                  const SizedBox(width: 4),
                                  Text('${e['comentariosCount'] ?? 0} comentários', style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ComentariosEvento extends StatefulWidget {
  final String eventoId;
  const _ComentariosEvento({required this.eventoId});
  @override
  State<_ComentariosEvento> createState() => _ComentariosEventoState();
}

class _ComentariosEventoState extends State<_ComentariosEvento> {
  final _ctrl = TextEditingController();
  bool _enviando = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Comentários', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('eventos')
                    .doc(widget.eventoId)
                    .collection('comentarios')
                    .orderBy('data', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs;
                  return ListView.builder(
                    reverse: true,
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final c = docs[i].data() as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(c['autor'] ?? 'Anônimo'),
                        subtitle: Text(c['texto'] ?? ''),
                        trailing: Text(c['data'] ?? ''),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(hintText: 'Escreva um comentário...'),
                    ),
                  ),
                  IconButton(
                    icon: _enviando ? const CircularProgressIndicator() : const Icon(Icons.send),
                    onPressed: _enviando
                        ? null
                        : () async {
                            final texto = _ctrl.text.trim();
                            if (texto.isEmpty) return;
                            setState(() => _enviando = true);
                            await FirebaseFirestore.instance
                                .collection('eventos')
                                .doc(widget.eventoId)
                                .collection('comentarios')
                                .add({
                              'autor': 'Membro', // TODO: usar nome do usuário logado
                              'texto': texto,
                              'data': DateTime.now().toIso8601String(),
                            });
                            _ctrl.clear();
                            setState(() => _enviando = false);
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
