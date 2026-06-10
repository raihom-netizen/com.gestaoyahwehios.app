import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_media_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Tela de teste — compara leitura Web/Android do mesmo doc `igrejas/{churchId}`.
class ChurchSyncTestPage extends StatefulWidget {
  final String tenantId;

  const ChurchSyncTestPage({super.key, required this.tenantId});

  @override
  State<ChurchSyncTestPage> createState() => _ChurchSyncTestPageState();
}

class _ChurchSyncTestPageState extends State<ChurchSyncTestPage> {
  ChurchSyncDiagnosticReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ChurchTenantMediaService.runFullDiagnostic(
        seedTenantId: widget.tenantId,
        userUid: FirebaseAuth.instance.currentUser?.uid,
      );
      await ChurchRepository.reportClientEmptyProfile(report);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _row(String label, String? value) {
    final v = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '(vazio)' : v,
              style: TextStyle(
                fontSize: 13,
                color: v.isEmpty ? ThemeCleanPremium.error : Colors.black87,
                fontWeight: v.isEmpty ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teste Sincronização Igreja'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _loading ? null : () => unawaited(_run()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => unawaited(_run()),
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_report?.tenantMismatch == true)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Text(
                          'WEB_FIRESTORE_MISMATCH — seed e tenant resolvido diferem.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    _row('churchId (resolvido)', _report?.resolvedChurchId),
                    _row('seed (entrada)', _report?.seedTenantId),
                    _row('Firestore Path', _report?.firestorePath),
                    _row('Storage Path', _report?.storageRootPath),
                    _row('Bucket', _report?.storageBucket),
                    _row(
                      'Firestore ativo',
                      _report?.firestoreActive == true ? 'sim' : 'não',
                    ),
                    _row(
                      'Storage ativo',
                      _report?.storageActive == true ? 'sim' : 'não',
                    ),
                    _row(
                      'Alinhado',
                      _report?.storageAligned == true ? 'sim' : 'NÃO',
                    ),
                    _row('Campos', '${_report?.fieldCount ?? 0}'),
                    _row(
                      'Última leitura',
                      _report?.lastReadAt?.toIso8601String(),
                    ),
                    const Divider(height: 28),
                    _row('nome', _report?.nome),
                    _row('cep', _report?.cep),
                    _row('rua', _report?.rua),
                    _row('bairro', _report?.bairro),
                    _row('cidade', _report?.cidade),
                    _row('instagram', _report?.instagram),
                    _row('facebook', _report?.facebook),
                    _row('whatsapp', _report?.whatsapp),
                    _row('logo path', _report?.logoStoragePath),
                    _row(
                      'logo no Storage',
                      _report?.logoExists == true ? 'sim' : 'não',
                    ),
                    if (_report?.lastError != null) ...[
                      const Divider(height: 28),
                      Text(
                        'Erro: ${_report!.lastError}',
                        style: TextStyle(color: ThemeCleanPremium.error),
                      ),
                    ],
                  ],
                ),
    );
  }
}
