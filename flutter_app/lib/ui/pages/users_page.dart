import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class UsersPage extends StatefulWidget {
  final String tenantId;
  final String role;
  const UsersPage({super.key, required this.tenantId, required this.role});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _q = '';

  bool get _canEditRole => widget.role.toLowerCase() == 'master';

  Future<void> _editRole({
    required BuildContext context,
    required String cpf,
    required String email,
    required String currentRole,
  }) async {
    if (!_canEditRole) return;

    final roles = ['MASTER', 'GESTOR', 'ADM', 'LIDER', 'USER'];
    String selected = currentRole.toUpperCase();
    if (!roles.contains(selected)) selected = 'USER';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterar perfil'),
        content: DropdownButtonFormField<String>(
          value: selected,
          items: roles
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => selected = v ?? selected,
          decoration: const InputDecoration(
            labelText: 'Perfil',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('setUserRole');
      await callable.call({
        'tenantId': widget.tenantId,
        'cpf': cpf,
        'role': selected,
        'email': email,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar perfil: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(widget.tenantId)
        .collection('usersIndex');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(title: const Text('Usuarios')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por email, CPF ou nome...',
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: col.snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  final email = (m['email'] ?? '').toString().toLowerCase();
                  final name = (m['name'] ?? m['nome'] ?? '').toString().toLowerCase();
                  final cpf = d.id.toLowerCase();
                  // Oculta o cadastro do master para outros usuários
                  final isMaster = (m['role'] ?? '').toString().toLowerCase() == 'master' || email == 'raihom@gmail.com';
                  if (isMaster && widget.role.toLowerCase() != 'master') return false;
                  if (_q.isEmpty) return true;
                  return email.contains(_q) || name.contains(_q) || cpf.contains(_q);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Nenhum usuario encontrado.'),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();
                    final email = (data['email'] ?? '').toString();
                    final name = (data['name'] ?? data['nome'] ?? '')
                        .toString();
                    final role = (data['role'] ?? 'user').toString();
                    final active = (data['active'] ?? true) == true;
                    final mustChangePass =
                        (data['mustChangePass'] ?? false) == true;

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: active
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          child: Icon(
                            active ? Icons.check : Icons.block,
                            color: active
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                        ),
                        title: Text(
                          name.isEmpty ? email : name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('CPF: ${d.id} • $email • role: $role'),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            if (mustChangePass)
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFB45309),
                              ),
                            if (_canEditRole)
                              OutlinedButton(
                                onPressed: () => _editRole(
                                  context: context,
                                  cpf: d.id,
                                  email: email,
                                  currentRole: role,
                                ),
                                child: const Text('Editar perfil'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
