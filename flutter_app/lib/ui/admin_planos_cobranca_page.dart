import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

class AdminPlanosCobrancaPage extends StatefulWidget {
  const AdminPlanosCobrancaPage({super.key});

  @override
  State<AdminPlanosCobrancaPage> createState() => _AdminPlanosCobrancaPageState();
}

class _AdminPlanosCobrancaPageState extends State<AdminPlanosCobrancaPage> {
  bool _loading = false;
  List<Map<String, dynamic>> _planos = [];
  List<Map<String, dynamic>> _recebimentos = [];
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final planosSnap = await FirebaseFirestore.instance.collection('planos').get();
      QuerySnapshot<Map<String, dynamic>> recSnap;
      try {
        recSnap = await FirebaseFirestore.instance.collection('pagamentos').orderBy('data', descending: true).get();
      } catch (_) {
        recSnap = await FirebaseFirestore.instance.collection('pagamentos').get();
      }
      _planos = planosSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      _recebimentos = recSnap.docs.map((d) => d.data()).toList();
      _recebimentos.sort((a, b) {
        final da = a['data'];
        final db = b['data'];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.toString().compareTo(da.toString());
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _editarPlano(Map<String, dynamic> plano) async {
    await showDialog(
      context: context,
      builder: (_) => _EditarPlanoDialog(plano: plano),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final recFiltrados = _recebimentos.where((r) {
      final nome = (r['cliente'] ?? '').toString().toLowerCase();
      return nome.contains(_busca);
    }).toList();
    final totalRecebido = _recebimentos.fold(0.0, (a, b) => a + (double.tryParse(b['valor']?.toString() ?? '') ?? 0));
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: isMobile ? null : AppBar(title: const Text('Planos e Cobranças')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  padding.top,
                  padding.right,
                  padding.bottom + ThemeCleanPremium.spaceXl,
                ),
                children: [
                  const MasterModuleSectionTitle(
                    title: 'Planos',
                    subtitle: 'Valores exibidos no sistema e na divulgação.',
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  ..._planos.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                      child: MasterPremiumCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(
                            p['nome'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('R\$ ${p['preco'] ?? ''} / ${p['periodo'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_rounded),
                            tooltip: 'Editar plano',
                            onPressed: () => _editarPlano(p),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceLg),
                  const Divider(height: 1),
                  const SizedBox(height: ThemeCleanPremium.spaceLg),
                  MasterModuleSectionTitle(
                    title: 'Recebimentos',
                    subtitle: 'Pagamentos registrados na coleção «pagamentos».',
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceSm),
                  MasterPremiumCard(
                    child: Text(
                      'Total recebido: R\$ ${totalRecebido.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar por cliente',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      filled: true,
                      fillColor: ThemeCleanPremium.cardBackground,
                    ),
                    onChanged: (v) => setState(() => _busca = v.toLowerCase()),
                  ),
                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                  ...recFiltrados.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                      child: MasterPremiumCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(
                            Icons.attach_money_rounded,
                            color: ThemeCleanPremium.primary,
                          ),
                          title: Text(r['cliente'] ?? ''),
                          subtitle: Text('R\$ ${r['valor'] ?? ''} — ${r['data'] ?? ''}'),
                          trailing: Text(
                            r['status'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: r['status'] == 'pago' ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EditarPlanoDialog extends StatefulWidget {
  final Map<String, dynamic> plano;
  const _EditarPlanoDialog({required this.plano});
  @override
  State<_EditarPlanoDialog> createState() => _EditarPlanoDialogState();
}

class _EditarPlanoDialogState extends State<_EditarPlanoDialog> {
  late TextEditingController _nome;
  late TextEditingController _preco;
  late TextEditingController _periodo;

  @override
  void initState() {
    super.initState();
    _nome = TextEditingController(text: widget.plano['nome'] ?? '');
    _preco = TextEditingController(text: widget.plano['preco']?.toString() ?? '');
    _periodo = TextEditingController(text: widget.plano['periodo'] ?? '');
  }

  Future<void> _salvar() async {
    final ref = FirebaseFirestore.instance.collection('planos').doc(widget.plano['id']);
    await ref.update({
      'nome': _nome.text.trim(),
      'preco': double.tryParse(_preco.text.trim()) ?? 0,
      'periodo': _periodo.text.trim(),
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Plano'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nome,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          TextField(
            controller: _preco,
            decoration: const InputDecoration(labelText: 'Preço'),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _periodo,
            decoration: const InputDecoration(labelText: 'Período (ex: mês, ano)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
