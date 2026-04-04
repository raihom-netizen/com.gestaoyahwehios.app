import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/admin_igreja_usuarios_page.dart';
import 'package:intl/intl.dart';

/// Painel Master — Usuários: lista gestores com sua igreja e vencimento; remover ou excluir para limpar o banco.
class AdminUsuariosPage extends StatefulWidget {
  const AdminUsuariosPage({super.key});

  @override
  State<AdminUsuariosPage> createState() => _AdminUsuariosPageState();
}

class _AdminUsuariosPageState extends State<AdminUsuariosPage> {
  bool _loading = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tenants = [];
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('igrejas').get();
      final list = snap.docs.toList()
        ..sort((a, b) {
          final na = (a.data()['name'] ?? a.data()['nome'] ?? a.id).toString().toLowerCase();
          final nb = (b.data()['name'] ?? b.data()['nome'] ?? b.id).toString().toLowerCase();
          return na.compareTo(nb);
        });
      setState(() {
        _tenants = list;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _tenants = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _busca.trim().toLowerCase();
    final filtrados = _tenants.where((d) {
      final data = d.data();
      final nome = (data['name'] ?? data['nome'] ?? '').toString().toLowerCase();
      final gestor = (data['gestorNome'] ?? data['gestorEmail'] ?? '').toString().toLowerCase();
      final slug = (data['slug'] ?? data['alias'] ?? d.id).toString().toLowerCase();
      return nome.contains(q) || gestor.contains(q) || slug.contains(q);
    }).toList();

    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      primary: false,
      appBar: isMobile ? null : AppBar(title: const Text('Gestores e Igrejas')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: padding,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar por nome da igreja, gestor ou slug...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text('Total: ${filtrados.length}', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtrados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_rounded, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  _tenants.isEmpty ? 'Nenhuma igreja cadastrada.' : 'Nenhum resultado para a busca.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: filtrados.length,
                            itemBuilder: (_, i) {
                              final doc = filtrados[i];
                              final data = doc.data();
                              final tenantId = doc.id;
                              final nomeIgreja = (data['name'] ?? data['nome'] ?? tenantId).toString();
                              final gestorNome = (data['gestorNome'] ?? data['gestor_nome'] ?? data['responsavel'] ?? '').toString();
                              final gestorEmail = (data['gestorEmail'] ?? data['gestor_email'] ?? data['email'] ?? '').toString();
                              final removed = data['removedByAdminAt'] != null;
                              DateTime? vencimento;
                              if (data['licenseExpiresAt'] is Timestamp) {
                                vencimento = (data['licenseExpiresAt'] as Timestamp).toDate();
                              } else if (data['license'] is Map) {
                                final exp = (data['license'] as Map)['expiresAt'];
                                if (exp is Timestamp) vencimento = exp.toDate();
                              }
                              final plano = (data['plano'] ?? 'free').toString();
                              final status = (data['status'] ?? 'ativa').toString();

                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                color: removed ? Colors.grey.shade50 : null,
                                child: ListTile(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AdminIgrejaUsuariosPage(
                                          tenantId: tenantId,
                                          nomeIgreja: nomeIgreja,
                                        ),
                                      ),
                                    );
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: removed ? Colors.grey : ThemeCleanPremium.primary.withOpacity(0.15),
                                    child: Icon(
                                      removed ? Icons.block_rounded : Icons.person_rounded,
                                      color: removed ? Colors.grey.shade600 : ThemeCleanPremium.primary,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    nomeIgreja,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      decoration: removed ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 4),
                                      if (gestorNome.isNotEmpty || gestorEmail.isNotEmpty)
                                        Text(
                                          'Gestor: ${[gestorNome, gestorEmail].where((s) => s.isNotEmpty).join(' — ')}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Plano: $plano'
                                        '${vencimento != null ? ' | Venc.: ${DateFormat('dd/MM/yyyy').format(vencimento)}' : ' | Sem licença'}'
                                        ' | ${removed || status == 'inativa' ? 'Removida' : status}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (removed)
                                        TextButton.icon(
                                          icon: const Icon(Icons.person_add_rounded, size: 18),
                                          label: const Text('Reativar'),
                                          onPressed: () async {
                                            await BillingLicenseService().reativarTenant(tenantId);
                                            _load();
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                ThemeCleanPremium.successSnackBar('Igreja reativada.'),
                                              );
                                            }
                                          },
                                        )
                                      else
                                        IconButton(
                                          icon: const Icon(Icons.person_remove_rounded),
                                          tooltip: 'Remover (pode reativar depois)',
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Remover igreja'),
                                                content: Text(
                                                  'Remover "$nomeIgreja"? Ela perderá acesso ao sistema. Você pode reativar depois.',
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              await BillingLicenseService().removerTenant(tenantId);
                                              _load();
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  ThemeCleanPremium.successSnackBar('Igreja removida. Use Reativar para restaurar.'),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_forever_rounded),
                                        tooltip: 'Excluir (limpar banco — irreversível)',
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Excluir igreja do banco'),
                                              content: Text(
                                                'Excluir permanentemente "$nomeIgreja"? O documento do tenant será apagado. Use apenas quando a igreja não quiser mais o sistema. Esta ação não pode ser desfeita.',
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                                FilledButton(
                                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('Excluir permanentemente'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (ok == true) {
                                            try {
                                              await BillingLicenseService().excluirTenant(tenantId);
                                              _load();
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  ThemeCleanPremium.successSnackBar('Tenant excluído do banco.'),
                                                );
                                              }
                                            } catch (e) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Erro ao excluir: $e')),
                                                );
                                              }
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
