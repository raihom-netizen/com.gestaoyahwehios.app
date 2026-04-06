import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/jimsabores_frota/core/frota_firestore_paths.dart';

class VeiculosPage extends StatefulWidget {
  const VeiculosPage({super.key});

  @override
  State<VeiculosPage> createState() => _VeiculosPageState();
}

class _VeiculosPageState extends State<VeiculosPage> {
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
      final isMaster = emailPerfil == _masterEmail;
      if (!mounted) return;
      setState(() {
        _isMaster = isMaster;
        _loadingPermissao = false;
      });
    } catch (_) {
      final emailAuth = (user.email ?? '').trim().toLowerCase();
      if (!mounted) return;
      setState(() {
        _isMaster = emailAuth == _masterEmail;
        _loadingPermissao = false;
      });
    }
  }

  String _normalizePlaca(String placa) {
    return placa.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  Future<void> _atualizarVinculosVeiculo({
    required String placaAntiga,
    required String placaNova,
    required String frotaNova,
  }) async {
    final updates = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};

    Future<void> coletar({required String campo, required String valor, required Map<String, dynamic> dados}) async {
      if (valor.isEmpty) return;
      final snap = await FrotaFirestorePaths.abastecimentos().where(campo, isEqualTo: valor).get();
      for (final doc in snap.docs) {
        final atual = updates[doc.reference] ?? <String, dynamic>{};
        atual.addAll(dados);
        updates[doc.reference] = atual;
      }
    }

    if (placaAntiga.isNotEmpty && placaAntiga != placaNova) {
      await coletar(campo: 'placa', valor: placaAntiga, dados: {'placa': placaNova, 'veiculo': placaNova});
      await coletar(campo: 'veiculo', valor: placaAntiga, dados: {'placa': placaNova, 'veiculo': placaNova});
    }

    final chaveAtual = placaNova.isNotEmpty ? placaNova : placaAntiga;
    if (frotaNova.isNotEmpty && chaveAtual.isNotEmpty) {
      await coletar(campo: 'placa', valor: chaveAtual, dados: {'frota': frotaNova});
      await coletar(campo: 'veiculo', valor: chaveAtual, dados: {'frota': frotaNova});
    }

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
    final placaAntiga = (dados?['placa'] ?? doc?.id ?? '').toString().trim().toUpperCase();
    final placaController = TextEditingController(text: (dados?['placa'] ?? '').toString());
    final modeloController = TextEditingController(text: (dados?['modelo'] ?? '').toString());
    final frotaController = TextEditingController(text: (dados?['frota'] ?? '').toString());
    bool ativo = (dados?['ativo'] as bool?) ?? true;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(doc == null ? 'Novo veículo' : 'Editar veículo'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: placaController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Placa',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: modeloController,
                      decoration: const InputDecoration(
                        labelText: 'Modelo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: frotaController,
                      decoration: const InputDecoration(
                        labelText: 'Frota',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativo'),
                      value: ativo,
                      onChanged: (v) => setDialogState(() => ativo = v),
                    ),
                  ],
                ),
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

    final placa = placaController.text.trim().toUpperCase();
    final modelo = modeloController.text.trim();
    final frota = frotaController.text.trim();

    if (placa.isEmpty || modelo.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Placa e modelo são obrigatórios.')),
      );
      return;
    }

    final placaId = _normalizePlaca(placa);
    final payload = {
      'placa': placa,
      'placa_normalizada': placaId,
      'modelo': modelo,
      'frota': frota,
      'ativo': ativo,
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (doc == null) {
      final jaExiste = await _db.collection('veiculos').doc(placaId).get();
      if (jaExiste.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um veículo com essa placa.')),
        );
        return;
      }
      await FrotaFirestorePaths.veiculos().doc(placaId).set({
        ...payload,
        'created_at': FieldValue.serverTimestamp(),
      });
      await _atualizarVinculosVeiculo(
        placaAntiga: '',
        placaNova: placa,
        frotaNova: frota,
      );
    } else {
      final antigoId = doc.id;
      if (antigoId != placaId) {
        final novoDoc = await FrotaFirestorePaths.veiculos().doc(placaId).get();
        if (novoDoc.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Já existe um veículo com essa placa.')),
          );
          return;
        }

        final batch = _db.batch();
        final novoRef = FrotaFirestorePaths.veiculos().doc(placaId);
        batch.set(novoRef, {
          ...payload,
          'created_at': dados?['created_at'] ?? FieldValue.serverTimestamp(),
        });
        batch.delete(doc.reference);
        await batch.commit();
      } else {
        await doc.reference.set(payload, SetOptions(merge: true));
      }

      await _atualizarVinculosVeiculo(
        placaAntiga: placaAntiga,
        placaNova: placa,
        frotaNova: frota,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(doc == null ? 'Veículo cadastrado!' : 'Veículo atualizado!')),
    );
  }

  Future<void> _excluir(DocumentSnapshot doc) async {
    if (!_isMaster) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrador não pode excluir veículos. Apenas inativar/editar.')),
      );
      return;
    }

    final dados = doc.data() as Map<String, dynamic>?;
    final placa = (dados?['placa'] ?? doc.id).toString();

    final uso = await FrotaFirestorePaths.abastecimentos()
        .where('placa', isEqualTo: placa)
        .limit(1)
        .get();

    final usoLegado = await FrotaFirestorePaths.abastecimentos()
        .where('veiculo', isEqualTo: placa)
        .limit(1)
        .get();

    final possuiVinculos = uso.docs.isNotEmpty || usoLegado.docs.isNotEmpty;

    if (!mounted) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir veículo'),
        content: Text(
          possuiVinculos
              ? 'ATENÇÃO: o veículo $placa possui abastecimentos vinculados. Confirma excluir mesmo assim?'
              : 'Confirma excluir o veículo $placa?',
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
      const SnackBar(content: Text('Veículo excluído.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermissao) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro de Veículos'),
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
                        'Novo veículo',
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
                      stream: FrotaFirestorePaths.veiculos().orderBy('placa').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return const Center(child: Text('Nenhum veículo cadastrado.'));
                        }

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final placa = (data['placa'] ?? '').toString();
                            final modelo = (data['modelo'] ?? '').toString();
                            final frota = (data['frota'] ?? '').toString();
                            final ativo = (data['ativo'] as bool?) ?? true;

                            return ListTile(
                              leading: const Icon(Icons.directions_car, color: Color(0xFF0056b3)),
                              title: Text(placa.isEmpty ? doc.id : placa),
                              subtitle: Text('Modelo: $modelo${frota.isNotEmpty ? ' | Frota: $frota' : ''}${ativo ? '' : ' | Inativo'}'),
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
