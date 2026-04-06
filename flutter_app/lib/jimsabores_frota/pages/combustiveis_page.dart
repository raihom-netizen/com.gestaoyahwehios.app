import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/jimsabores_frota/core/frota_firestore_paths.dart';

class CombustiveisPage extends StatefulWidget {
  const CombustiveisPage({super.key});

  @override
  State<CombustiveisPage> createState() => _CombustiveisPageState();
}

class _CombustiveisPageState extends State<CombustiveisPage> {
  static const String _masterEmail = 'raihom@gmail.com';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isMaster = false;
  bool _loadingPermissao = true;

  @override
  void initState() {
    super.initState();
    _carregarPermissao();
  }

  Future<void> _carregarPermissao() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isMaster = false;
        _loadingPermissao = false;
      });
      return;
    }

    try {
      final doc = await _db.collection('usuarios').doc(user.uid).get();
      final emailPerfil = (doc.data()?['email'] ?? user.email ?? '').toString().trim().toLowerCase();
      if (!mounted) return;
      setState(() {
        _isMaster = emailPerfil == _masterEmail;
        _loadingPermissao = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isMaster = (user.email ?? '').trim().toLowerCase() == _masterEmail;
        _loadingPermissao = false;
      });
    }
  }

  Future<bool> _combustivelEmUso(String nomeCombustivel) async {
    final usoEmCombustivel = await FrotaFirestorePaths.abastecimentos()
        .where('combustivel', isEqualTo: nomeCombustivel)
        .limit(1)
        .get();
    if (usoEmCombustivel.docs.isNotEmpty) return true;

    final usoEmTipoCombustivel = await FrotaFirestorePaths.abastecimentos()
        .where('tipo_combustivel', isEqualTo: nomeCombustivel)
        .limit(1)
        .get();
    return usoEmTipoCombustivel.docs.isNotEmpty;
  }

  Future<void> _atualizarVinculosCombustivel({
    required String nomeAntigo,
    required String nomeNovo,
  }) async {
    final oldValue = nomeAntigo.trim();
    final newValue = nomeNovo.trim();
    if (oldValue.isEmpty || newValue.isEmpty || oldValue == newValue) return;

    final updates = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};

    Future<void> coletar(String campo) async {
      final snap =
          await FrotaFirestorePaths.abastecimentos().where(campo, isEqualTo: oldValue).get();
      for (final doc in snap.docs) {
        final atual = updates[doc.reference] ?? <String, dynamic>{};
        atual[campo] = newValue;
        updates[doc.reference] = atual;
      }
    }

    await coletar('combustivel');
    await coletar('tipo_combustivel');

    if (updates.isEmpty) return;

    final entries = updates.entries.toList();
    for (int i = 0; i < entries.length; i += 400) {
      final batch = _db.batch();
      final fim = (i + 400 < entries.length) ? i + 400 : entries.length;
      for (final entry in entries.sublist(i, fim)) {
        batch.set(entry.key, {
          ...entry.value,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _abrirFormulario({DocumentSnapshot? doc}) async {
    final dados = doc?.data() as Map<String, dynamic>?;
    final nomeAntigo = (dados?['nome'] ?? '').toString().trim();
    final nomeController = TextEditingController(text: (dados?['nome'] ?? '').toString());
    bool ativo = (dados?['ativo'] as bool?) ?? true;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(doc == null ? 'Novo combustível' : 'Editar combustível'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do combustível',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    value: ativo,
                    onChanged: (v) => setDialogState(() => ativo = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (salvar != true) return;

    final nome = nomeController.text.trim();
    if (nome.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do combustível.')),
      );
      return;
    }

    final payload = {
      'nome': nome,
      'ativo': ativo,
      'nome_lower': nome.toLowerCase(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (doc == null) {
      await FrotaFirestorePaths.combustiveis().add({
        ...payload,
        'created_at': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.reference.set(payload, SetOptions(merge: true));
      await _atualizarVinculosCombustivel(nomeAntigo: nomeAntigo, nomeNovo: nome);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(doc == null ? 'Combustível criado!' : 'Combustível atualizado!')),
    );
  }

  Future<void> _excluir(DocumentSnapshot doc) async {
    // Usuário master pode excluir tudo

    final data = doc.data() as Map<String, dynamic>?;
    final nomeCombustivel = (data?['nome'] ?? '').toString().trim();

    bool emUso = false;
    if (nomeCombustivel.isNotEmpty) {
      emUso = await _combustivelEmUso(nomeCombustivel);
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir combustível'),
        content: Text(
          emUso
              ? 'ATENÇÃO: este combustível já foi usado em abastecimentos. Confirma excluir mesmo assim?'
              : 'Tem certeza que deseja excluir este combustível?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await doc.reference.delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Combustível excluído.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermissao) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro de Combustíveis'),
        backgroundColor: const Color(0xFF0056b3),
      ),
      body: Container(
        color: const Color(0xFFF5F2F8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 520,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0056b3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      onPressed: () => _abrirFormulario(),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Novo combustível',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FrotaFirestorePaths.combustiveis()
                          .orderBy('nome_lower')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return const Center(child: Text('Nenhum combustível cadastrado.'));
                        }

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final nome = (data['nome'] ?? '').toString();
                            final ativo = (data['ativo'] as bool?) ?? true;

                            return ListTile(
                              title: Text(nome.isEmpty ? '(Sem nome)' : nome),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    icon: const Icon(Icons.edit, color: Color(0xFF0056b3)),
                                    onPressed: () => _abrirFormulario(doc: doc),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir',
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: _isMaster ? () => _excluir(doc) : null,
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
