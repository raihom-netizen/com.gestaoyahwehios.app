import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Logs de uso de banco, Google Drive etc. Master vê todos; Gestor local vê só da sua igreja. Super Premium, responsivo.
class AdminAuditoriaPage extends StatefulWidget {
  const AdminAuditoriaPage({super.key});

  @override
  State<AdminAuditoriaPage> createState() => _AdminAuditoriaPageState();
}

class _AdminAuditoriaPageState extends State<AdminAuditoriaPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _logs = [];
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdTokenResult(true);
      final role = (token?.claims?['role'] ?? '').toString().toUpperCase();
      final igrejaId = (token?.claims?['igrejaId'] ?? '').toString().trim();
      final isMaster = role == 'MASTER' || role == 'ADMIN' || role == 'ADM';

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('auditoria')
          .orderBy('data', descending: true)
          .limit(500);
      if (!isMaster && igrejaId.isNotEmpty) {
        q = q.where('igrejaId', isEqualTo: igrejaId);
      }
      final snap = await q.get();
      if (mounted) {
        _logs = snap.docs.map((d) => d.data()).toList();
        setState(() { _loading = false; _error = null; });
      }
    } catch (e) {
      if (mounted) {
        _logs = [];
        setState(() {
          _loading = false;
          _error = e.toString().contains('permission-denied') || e.toString().contains('PERMISSION_DENIED')
              ? 'Sem permissão para acessar auditoria.'
              : 'Erro ao carregar: $e';
        });
      }
    }
  }

  String _formatData(dynamic data) {
    if (data == null) return '—';
    if (data is Timestamp) return _formatTimestamp(data);
    return data.toString();
  }

  String _formatTimestamp(Timestamp t) {
    final d = t.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final filtrados = _logs.where((l) {
      if (_busca.trim().isEmpty) return true;
      final b = _busca.toLowerCase();
      final acao = (l['acao'] ?? '').toString().toLowerCase();
      final usuario = (l['usuario'] ?? '').toString().toLowerCase();
      final resource = (l['resource'] ?? '').toString().toLowerCase();
      final details = (l['details'] ?? '').toString().toLowerCase();
      return acao.contains(b) || usuario.contains(b) || resource.contains(b) || details.contains(b);
    }).toList();

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, ThemeCleanPremium.spaceSm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Buscar por ação, usuário, recurso',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.cardBackground,
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _loading ? null : _load,
                    tooltip: 'Recarregar',
                    style: IconButton.styleFrom(minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget)),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _PremiumCard(
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: ThemeCleanPremium.error, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error!, style: const TextStyle(color: ThemeCleanPremium.error, fontSize: 13))),
                      TextButton(onPressed: _load, child: const Text('Tentar novamente')),
                    ],
                  ),
                ),
              ),
            if (_error != null) const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtrados.isEmpty
                      ? Center(
                          child: _PremiumCard(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  _logs.isEmpty ? 'Nenhum registro de auditoria.' : 'Nenhum resultado para a busca.',
                                  style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, padding.bottom + 24),
                          itemCount: filtrados.length,
                          itemBuilder: (_, i) {
                            final l = filtrados[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                              child: _PremiumCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.history_rounded, color: ThemeCleanPremium.primary, size: 22),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            l['acao'] ?? '—',
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: ThemeCleanPremium.onSurface),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Usuário: ${l['usuario'] ?? 'sistema'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                    if (l['resource'] != null && (l['resource'] as String).isNotEmpty)
                                      Text('Recurso: ${l['resource']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                    if (l['details'] != null && (l['details'] as String).isNotEmpty)
                                      Text('Detalhes: ${l['details']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text('Data: ${_formatData(l['data'])}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}
