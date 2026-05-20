import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/master_church_detail_sheet.dart';

/// Pesquisa global de igrejas (⌘K / Ctrl+K) — padrão SaaS.
class MasterGlobalSearchDialog extends StatefulWidget {
  const MasterGlobalSearchDialog({super.key, this.onOpenChurch});

  final void Function(String tenantId, Map<String, dynamic> data)? onOpenChurch;

  static Future<void> show(
    BuildContext context, {
    void Function(String tenantId, Map<String, dynamic> data)? onOpenChurch,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => MasterGlobalSearchDialog(onOpenChurch: onOpenChurch),
    );
  }

  @override
  State<MasterGlobalSearchDialog> createState() => _MasterGlobalSearchDialogState();
}

class _MasterGlobalSearchDialogState extends State<MasterGlobalSearchDialog> {
  final _ctrl = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _hits = [];
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('igrejas').limit(400).get();
      final out = snap.docs.where((d) {
        final data = d.data();
        final nome = '${data['nome'] ?? data['name'] ?? ''}'.toLowerCase();
        final slug = '${data['slug'] ?? ''}'.toLowerCase();
        final email =
            '${data['gestorEmail'] ?? data['email'] ?? ''}'.toLowerCase();
        return nome.contains(query) ||
            slug.contains(query) ||
            email.contains(query) ||
            d.id.toLowerCase().contains(query);
      }).take(24).toList();
      if (mounted) setState(() => _hits = out);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    Navigator.pop(context);
    widget.onOpenChurch?.call(doc.id, doc.data());
    MasterChurchDetailSheet.show(
      context,
      tenantId: doc.id,
      churchData: doc.data(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pesquisar igreja'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nome, slug, e-mail gestor ou ID…',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _search(v),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_hits.isEmpty && _ctrl.text.trim().isNotEmpty)
              Text(
                'Nenhum resultado.',
                style: TextStyle(color: Colors.grey.shade600),
              )
            else
              SizedBox(
                height: 280,
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (_, i) {
                    final doc = _hits[i];
                    final data = doc.data();
                    final nome =
                        (data['nome'] ?? data['name'] ?? doc.id).toString();
                    return ListTile(
                      leading: const Icon(Icons.church_rounded),
                      title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(doc.id, style: const TextStyle(fontSize: 11)),
                      onTap: () => _open(doc),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
