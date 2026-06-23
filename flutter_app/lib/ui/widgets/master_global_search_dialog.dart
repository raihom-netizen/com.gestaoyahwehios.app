import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
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

  bool _matches(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String query,
  ) {
    final data = d.data();
    final nome = '${data['nome'] ?? data['name'] ?? ''}'.toLowerCase();
    final slug = '${data['slug'] ?? ''}'.toLowerCase();
    final email =
        '${data['gestorEmail'] ?? data['email'] ?? ''}'.toLowerCase();
    return nome.contains(query) ||
        slug.contains(query) ||
        email.contains(query) ||
        d.id.toLowerCase().contains(query);
  }

  Future<void> _search(String q) async {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      var scanLimit = YahwehPerformanceV4.masterGlobalSearchScanLimit;
      while (out.length < 24) {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await firebaseDefaultFirestore
              .collection('igrejas')
              .orderBy('nome')
              .limit(scanLimit)
              .get();
        } catch (_) {
          snap = await firebaseDefaultFirestore
              .collection('igrejas')
              .limit(scanLimit)
              .get();
        }
        for (final d in snap.docs) {
          if (_matches(d, query)) {
            out.add(d);
            if (out.length >= 24) break;
          }
        }
        if (snap.docs.length < scanLimit || out.length >= 24) break;
        scanLimit += YahwehPerformanceV4.masterGlobalSearchScanLimit;
        if (scanLimit > YahwehPerformanceV4.masterChurchesListLimit * 3) break;
      }
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
