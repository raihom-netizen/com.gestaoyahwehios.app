import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Painel Master — Central de Alertas. Super Premium, responsivo.
class AdminAlertasPage extends StatefulWidget {
  const AdminAlertasPage({super.key});

  @override
  State<AdminAlertasPage> createState() => _AdminAlertasPageState();
}

class _AdminAlertasPageState extends State<AdminAlertasPage> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _alertas = [];
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('alertas')
          .orderBy('data', descending: true)
          .limit(200)
          .get();
      if (mounted) {
        _alertas = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        setState(() { _loading = false; _error = null; });
      }
    } catch (e) {
      if (mounted) {
        _alertas = [];
        setState(() {
          _loading = false;
          _error = e.toString().contains('permission-denied') || e.toString().contains('PERMISSION_DENIED')
              ? 'Sem permissão para acessar alertas. Confirme as regras do Firestore.'
              : 'Erro ao carregar: $e';
        });
      }
    }
  }

  Future<void> _marcarComoLido(Map<String, dynamic> alerta) async {
    final id = alerta['id'] as String?;
    if (id == null || id.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('alertas').doc(id).update({'lido': true});
      if (mounted) _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    final isMobile = ThemeCleanPremium.isMobile(context);
    final filtrados = _alertas.where((a) {
      final texto = (a['mensagem'] ?? '').toString().toLowerCase();
      return texto.contains(_busca.trim().toLowerCase());
    }).toList();

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, ThemeCleanPremium.spaceSm),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Buscar alerta',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                        filled: true,
                        fillColor: ThemeCleanPremium.cardBackground,
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: MasterPremiumCard(
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
                    child: filtrados.isEmpty
                        ? Center(
                            child: MasterPremiumCard(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none_rounded, size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _alertas.isEmpty ? 'Nenhum alerta registrado.' : 'Nenhum resultado para a busca.',
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
                              final a = filtrados[i];
                              final lido = a['lido'] == true;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceSm),
                                child: MasterPremiumCard(
                                  child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          lido ? Icons.notifications_none_rounded : Icons.notification_important_rounded,
                                          color: lido ? Colors.grey : Colors.orange.shade700,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                a['mensagem'] ?? 'Sem mensagem',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: ThemeCleanPremium.onSurface,
                                                ),
                                                maxLines: 4,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (a['data'] != null && a['data'].toString().isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    a['data'].toString(),
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (!lido)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8),
                                            child: IconButton(
                                            icon: const Icon(Icons.check_circle_outline_rounded),
                                            tooltip: 'Marcar como lido',
                                            onPressed: () => _marcarComoLido(a),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(ThemeCleanPremium.minTouchTarget, ThemeCleanPremium.minTouchTarget),
                                            ),
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
