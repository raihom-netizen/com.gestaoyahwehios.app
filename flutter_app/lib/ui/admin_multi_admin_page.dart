import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Painel Master — Multi-Admin e delegação (Super Premium).
/// Carrega `usuarios` sem `where` no servidor + filtro local + `GetOptions(server)` para evitar INTERNAL ASSERTION no Firestore Web 11.x.
class AdminMultiAdminPage extends StatefulWidget {
  const AdminMultiAdminPage({super.key});

  @override
  State<AdminMultiAdminPage> createState() => _AdminMultiAdminPageState();
}

class _AdminMultiAdminPageState extends State<AdminMultiAdminPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _admins = [];
  String _busca = '';

  static const _getServer = GetOptions(source: Source.server);

  @override
  void initState() {
    super.initState();
    _load();
  }

  static bool _isAdminPapel(Map<String, dynamic> data) {
    final p = (data['papel'] ?? data['role'] ?? '').toString().toLowerCase().trim();
    if (p == 'admin' || p == 'adm' || p == 'master') return true;
    if (p == 'gestor' && data['adminDelegado'] == true) return true;
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final merged = <String, Map<String, dynamic>>{};

      final usuSnap = await FirebaseFirestore.instance.collection('usuarios').limit(500).get(_getServer);
      for (final d in usuSnap.docs) {
        final data = d.data();
        if (_isAdminPapel(data)) {
          merged[d.id] = {...data, 'id': d.id, 'viaAdminsDoc': false};
        }
      }

      try {
        final admSnap = await FirebaseFirestore.instance.collection('admins').limit(200).get(_getServer);
        for (final doc in admSnap.docs) {
          final uid = doc.id;
          if (merged.containsKey(uid)) continue;
          var nome = 'Administrador';
          var email = '';
          try {
            final u = await FirebaseFirestore.instance.collection('users').doc(uid).get(_getServer);
            if (u.exists) {
              final ud = u.data() ?? {};
              nome = (ud['displayName'] ?? ud['nome'] ?? ud['name'] ?? nome).toString();
              email = (ud['email'] ?? '').toString();
            }
          } catch (_) {}
          merged[uid] = {
            'id': uid,
            'nome': nome,
            'email': email.isEmpty ? '(ver users/$uid)' : email,
            'papel': 'admin',
            'viaAdminsDoc': true,
          };
        }
      } catch (_) {}

      final list = merged.values.toList()
        ..sort((a, b) {
          final na = (a['nome'] ?? a['email'] ?? '').toString().toLowerCase();
          final nb = (b['nome'] ?? b['email'] ?? '').toString().toLowerCase();
          return na.compareTo(nb);
        });

      if (mounted) {
        _admins = list;
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        _admins = [];
        final msg = e.toString();
        final isDenied = msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED') ||
            msg.contains('Missing or insufficient permissions');
        setState(() {
          _loading = false;
          _error = isDenied
              ? 'Sem permissão em usuarios/ ou admins/. Publique as regras (admins: read isAdminPanel) e faça deploy: firebase deploy --only firestore:rules'
              : 'Não foi possível carregar. Recarregue com Ctrl+F5 e publique as regras.\n\n$msg';
        });
      }
    }
  }

  Future<void> _delegarAdmin() async {
    final email = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => const _DelegarAdminDialog(),
    );
    if (email == null || email.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('usuarios').where('email', isEqualTo: email).get(_getServer);
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'papel': 'admin'});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Usuário $email agora tem papel admin em usuarios/.'),
          );
          _load();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nenhum documento em usuarios/ com e-mail "$email". O usuário precisa existir em usuarios/{uid}.'),
              backgroundColor: ThemeCleanPremium.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  Future<void> _removerAdmin(Map<String, dynamic> admin) async {
    if (admin['viaAdminsDoc'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este acesso vem do documento admins/{uid} no Firebase. Remova manualmente no Console ou via Cloud Function.'),
          ),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
        title: const Text('Remover poderes administrativos'),
        content: Text('Remover papel admin de ${admin['nome'] ?? admin['email']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final email = (admin['email'] ?? '').toString();
      if (email.isEmpty) return;
      final snap = await FirebaseFirestore.instance.collection('usuarios').where('email', isEqualTo: email).get(_getServer);
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({'papel': 'usuario'});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Poderes removidos de $email'),
          );
          _load();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    final filtrados = _admins.where((a) {
      final b = _busca.trim().toLowerCase();
      if (b.isEmpty) return true;
      final nome = (a['nome'] ?? '').toString().toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();
      final id = (a['id'] ?? '').toString().toLowerCase();
      return nome.contains(b) || email.contains(b) || id.contains(b);
    }).toList();

    final viaDoc = _admins.where((a) => a['viaAdminsDoc'] == true).length;

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, ThemeCleanPremium.spaceSm),
              child: _MultiAdminHeaderCard(total: _admins.length, viaAdminsDoc: viaDoc),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, ThemeCleanPremium.spaceSm),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                  hintText: 'Buscar admin por nome ou e-mail',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, ThemeCleanPremium.spaceSm, padding.right, ThemeCleanPremium.spaceSm),
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('Delegar poderes a outro usuário'),
                onPressed: _delegarAdmin,
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  minimumSize: isMobile ? const Size(0, ThemeCleanPremium.minTouchTarget) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, ThemeCleanPremium.spaceSm),
                child: MasterPremiumCard(
                  expandWidth: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ThemeCleanPremium.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: ThemeCleanPremium.error, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(_error!, style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13, height: 1.35)),
                      ),
                      TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtrados.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(padding.left, 24, padding.right, padding.bottom + 24),
                            child: MasterPremiumCard(
                              expandWidth: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.verified_user_rounded, size: 48, color: ThemeCleanPremium.primary.withValues(alpha: 0.9)),
                                  ),
                                  const SizedBox(height: ThemeCleanPremium.spaceMd),
                                  Text(
                                    _admins.isEmpty ? 'Nenhum administrador listado' : 'Nenhum resultado para a busca',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: ThemeCleanPremium.onSurface),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _admins.isEmpty
                                        ? 'Delegue pelo e-mail ou cadastre papel admin em usuarios/{uid}.'
                                        : 'Limpe a busca ou use outros termos.',
                                    style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14, height: 1.4),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(padding.left, 4, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
                          itemCount: filtrados.length,
                          itemBuilder: (_, i) {
                            final a = filtrados[i];
                            final via = a['viaAdminsDoc'] == true;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
                              child: MasterPremiumCard(
                                expandWidth: true,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8EAF6),
                                        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                                      ),
                                      child: Icon(Icons.admin_panel_settings_rounded, color: ThemeCleanPremium.primary, size: 24),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (a['nome'] ?? 'Sem nome').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: ThemeCleanPremium.onSurface),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (a['email'] ?? '').toString(),
                                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                          ),
                                          if (via)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFF8E1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Acesso via admins/${a['id']}',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        via ? Icons.info_outline_rounded : Icons.remove_circle_outline_rounded,
                                        color: via ? ThemeCleanPremium.onSurfaceVariant : ThemeCleanPremium.error,
                                      ),
                                      tooltip: via ? 'Como remover acesso admins/' : 'Remover poderes',
                                      onPressed: () {
                                        if (via) {
                                          showDialog<void>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                                              ),
                                              title: const Text('Acesso via admins/'),
                                              content: Text(
                                                'Este usuário está em admins/${a['id']}. Para revogar, use o Firebase Console ou uma Cloud Function — o app não grava em admins/.',
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                              ],
                                            ),
                                          );
                                        } else {
                                          _removerAdmin(a);
                                        }
                                      },
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
                                      ),
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

class _MultiAdminHeaderCard extends StatelessWidget {
  const _MultiAdminHeaderCard({required this.total, required this.viaAdminsDoc});

  final int total;
  final int viaAdminsDoc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E3A5F),
            ThemeCleanPremium.primary.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: const Icon(Icons.groups_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Multi-Admin',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 0.2),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Quem pode ajudar a operar o painel master — usuarios/ + admins/.',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Chip(light: true, label: 'Total', value: '$total'),
              _Chip(light: true, label: 'Só admins/', value: '$viaAdminsDoc'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, this.light = false});

  final String label;
  final String value;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.22) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        border: Border.all(color: light ? Colors.white24 : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: light ? Colors.white70 : ThemeCleanPremium.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: light ? Colors.white : ThemeCleanPremium.onSurface)),
        ],
      ),
    );
  }
}

class _DelegarAdminDialog extends StatefulWidget {
  const _DelegarAdminDialog();

  @override
  State<_DelegarAdminDialog> createState() => _DelegarAdminDialogState();
}

class _DelegarAdminDialogState extends State<_DelegarAdminDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
      title: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: ThemeCleanPremium.primary),
          SizedBox(width: 10),
          Expanded(child: Text('Delegar poderes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        ],
      ),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'E-mail do usuário',
          hintText: 'exemplo@email.com',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
          filled: true,
          fillColor: ThemeCleanPremium.surfaceVariant,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim().toLowerCase()),
          style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.primary),
          child: const Text('Delegar'),
        ),
      ],
    );
  }
}
