import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/billing_license_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';

/// Página de acompanhamento de espaço: Firestore (banco) e Drive para a igreja.
/// Inclui fallback local de uso Firestore quando a Cloud Function falha e ações para gerir/limpar espaço.
class StorageUsagePage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Chamado quando a igreja foi removida/limpa (para o painel master atualizar a lista).
  final VoidCallback? onCleaned;

  const StorageUsagePage({
    super.key,
    required this.tenantId,
    required this.role,
    this.onCleaned,
  });

  @override
  State<StorageUsagePage> createState() => _StorageUsagePageState();
}

class _StorageUsagePageState extends State<StorageUsagePage> {
  Map<String, dynamic>? _usage;
  String? _error;
  bool _loading = true;
  bool _testingDrive = false;
  String? _testResult;
  /// True quando os dados vêm do fallback local (Cloud Function falhou).
  bool _driveUnavailable = false;

  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Estima uso do Firestore contando documentos nas subcoleções do tenant (fallback quando a Cloud Function falha).
  Future<Map<String, dynamic>> _loadLocalFirestoreEstimate() async {
    final ref = _db.collection('igrejas').doc(widget.tenantId);
    final counts = <String, int>{};
    final collections = [
      'members',
      'membros',
      'noticias',
      'usersIndex',
      'event_templates',
      'departamentos',
      'patrimonio',
      'cultos',
      'visitantes',
      'eventos',
      'pedidosOracao',
    ];
    int totalDocs = 0;
    for (final name in collections) {
      try {
        final snap = await ref.collection(name).limit(9999).get();
        final c = snap.docs.length;
        counts[name] = c;
        totalDocs += c;
      } catch (_) {
        counts[name] = 0;
      }
    }
    final estimateBytes = totalDocs * 500; // ~500 bytes/doc médio
    return {
      'firestore': {
        'docCounts': counts,
        'totalDocs': totalDocs,
        'estimateBytes': estimateBytes,
      },
      'drive': null,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _usage = null;
      _testResult = null;
      _driveUnavailable = false;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = _functions.httpsCallable('getChurchStorageUsage');
      final result = await callable.call<Map<dynamic, dynamic>>({'tenantId': widget.tenantId});
      final data = result.data;
      if (data == null) throw Exception('Resposta vazia');
      final map = Map<String, dynamic>.from(data as Map);
      if (mounted) {
        setState(() {
          _usage = map;
          _loading = false;
          _driveUnavailable = false;
        });
      }
    } catch (e, st) {
      if (!mounted) return;
      try {
        final local = await _loadLocalFirestoreEstimate();
        if (mounted) {
          setState(() {
            _usage = local;
            _loading = false;
            _error = null;
            _driveUnavailable = true;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e is FirebaseFunctionsException
                ? (e.message ?? e.code)
                : e.toString();
            if (_error != null && _error!.toLowerCase().contains('internal')) {
              _error = 'A Cloud Function getChurchStorageUsage não está disponível ou retornou erro. Verifique se está implantada e se você está logado como admin.';
            }
          });
        }
      }
    }
  }

  Future<void> _confirmarLimparDados() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Limpar todos os dados da igreja?'),
        content: const Text(
          'Todos os dados vinculados a esta igreja (membros, notícias, eventos, visitantes, financeiro, etc.) serão apagados permanentemente do banco. A igreja deixará de existir no sistema. Esta ação não pode ser desfeita.\n\nDeseja realmente continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Sim, limpar tudo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await BillingLicenseService().removerIgrejaELimparDados(widget.tenantId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados da igreja removidos. Atualize a lista de igrejas.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
      widget.onCleaned?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao limpar: $e'), backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
  }

  Future<void> _testDrive() async {
    setState(() {
      _testingDrive = true;
      _testResult = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = _functions.httpsCallable('testDriveWriteForChurch');
      final result = await callable.call<Map<dynamic, dynamic>>({'tenantId': widget.tenantId});
      final data = result.data as Map?;
      final message = data?['message'] ?? data?['ok']?.toString() ?? 'OK';
      if (mounted) {
        setState(() {
          _testingDrive = false;
          _testResult = message as String? ?? 'Teste concluído.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testingDrive = false;
          _testResult = e is FirebaseFunctionsException
              ? (e.message ?? e.code)
              : e.toString();
        });
      }
    }
  }

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Armazenamento'),
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  'Uso de espaço — Banco de dados e Drive',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Acompanhe o espaço usado pela sua igreja no Firestore (banco) e no Google Drive (mídias arquivadas).',
                  style: TextStyle(
                    fontSize: 14,
                    color: ThemeCleanPremium.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: ThemeCleanPremium.error, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Erro ao carregar',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(fontSize: 14)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Tentar novamente'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_usage != null) ...[
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.storage_rounded,
                                color: ThemeCleanPremium.primary, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Banco de dados (Firestore)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildFirestoreContent(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_rounded,
                                color: Colors.amber.shade700, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Google Drive (mídias arquivadas)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildDriveContent(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Testar gravação no Drive',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cria e remove um arquivo de teste na pasta da igreja no Drive. Use para garantir que o arquivamento automático de mídias funcionará sem erros.',
                          style: TextStyle(
                            fontSize: 13,
                            color: ThemeCleanPremium.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_testResult != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _testResult!.toLowerCase().contains('ok') ||
                                      _testResult!.toLowerCase().contains('concluídas')
                                  ? ThemeCleanPremium.success.withOpacity(0.12)
                                  : ThemeCleanPremium.error.withOpacity(0.12),
                              borderRadius:
                                  BorderRadius.circular(ThemeCleanPremium.radiusSm),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _testResult!.toLowerCase().contains('ok') ||
                                          _testResult!.toLowerCase().contains('concluídas')
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_rounded,
                                  color: _testResult!.toLowerCase().contains('ok') ||
                                          _testResult!.toLowerCase().contains('concluídas')
                                      ? ThemeCleanPremium.success
                                      : ThemeCleanPremium.error,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _testResult!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        FilledButton.icon(
                          onPressed: _testingDrive ? null : _testDrive,
                          icon: _testingDrive
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 20),
                          label: Text(
                              _testingDrive ? 'Testando...' : 'Testar gravação no Drive'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cleaning_services_rounded, color: ThemeCleanPremium.primary, size: 26),
                            const SizedBox(width: 10),
                            const Text(
                              'Gerenciar espaço',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Limpar ou apagar todos os dados desta igreja libera espaço no banco. Use apenas se a igreja não for mais utilizar o sistema. Esta ação é irreversível.',
                          style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _confirmarLimparDados,
                          icon: const Icon(Icons.delete_forever_rounded, size: 20),
                          label: const Text('Limpar todos os dados desta igreja'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error,
                            side: BorderSide(color: ThemeCleanPremium.error.withOpacity(0.7)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFirestoreContent() {
    final firestore = _usage!['firestore'];
    if (firestore == null) {
      return const Text('Dados do Firestore não disponíveis.');
    }
    final map = Map<String, dynamic>.from(firestore as Map);
    final counts = map['docCounts'] as Map?;
    final totalDocs = (map['totalDocs'] as num?)?.toInt() ?? 0;
    final estimateBytes = (map['estimateBytes'] as num?)?.toInt() ?? 0;
    final membersCount = (counts != null ? ((counts['members'] ?? counts['membros']) as num?)?.toInt() : null) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_driveUnavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Estimativa local (Cloud Function getChurchStorageUsage indisponível)',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (counts != null) ...[
          _row('Membros', '${membersCount} documentos'),
          _row('Notícias / Avisos', '${counts['noticias'] ?? 0} documentos'),
          _row('Índice de usuários', '${counts['usersIndex'] ?? 0} documentos'),
        ],
        const SizedBox(height: 8),
        _row('Total (estimado)', '~$totalDocs docs · ${_fmtBytes(estimateBytes)}'),
      ],
    );
  }

  Widget _buildDriveContent() {
    final drive = _usage!['drive'];
    if (drive == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_driveUnavailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Dados do Google Drive indisponíveis. A Cloud Function getChurchStorageUsage não está implantada ou falhou. Use "Testar gravação no Drive" para verificar o acesso.',
                style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant, fontStyle: FontStyle.italic),
              ),
            ),
          const Text('Dados do Drive não disponíveis.'),
        ],
      );
    }
    final map = Map<String, dynamic>.from(drive as Map);
    final bytes = (map['bytes'] as num?)?.toInt() ?? 0;
    final folderId = (map['folderId'] as String?)?.trim() ?? '';
    final folderUrl = (map['folderUrl'] as String?)?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Espaço usado', _fmtBytes(bytes)),
        if (folderUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final uri = Uri.tryParse(folderUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.open_in_new_rounded,
                      size: 18, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Abrir pasta no Drive',
                    style: TextStyle(
                      fontSize: 14,
                      color: ThemeCleanPremium.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (folderId.isEmpty && bytes == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nenhuma mídia arquivada ainda. O Drive é preenchido quando as mídias do mural/eventos passam do prazo de retenção (ex.: 15 dias).',
              style: TextStyle(
                fontSize: 12,
                color: ThemeCleanPremium.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: child,
    );
  }
}

/// Página de Armazenamento no Painel Master: seleção de igreja e exibição do uso por igreja.
class StorageUsageMasterPage extends StatefulWidget {
  const StorageUsageMasterPage({super.key});

  @override
  State<StorageUsageMasterPage> createState() => _StorageUsageMasterPageState();
}

class _StorageUsageMasterPageState extends State<StorageUsageMasterPage> {
  String? _selectedTenantId;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tenants = [];
  bool _loadingTenants = true;

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  Future<void> _loadTenants() async {
    setState(() => _loadingTenants = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .orderBy('nome')
          .get();
      if (mounted) {
        setState(() {
          _tenants = snap.docs;
          _loadingTenants = false;
          if (_selectedTenantId == null && _tenants.isNotEmpty) {
            _selectedTenantId = _tenants.first.id;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTenants = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);

    if (_loadingTenants) {
      return Scaffold(
        primary: false,
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (_tenants.isEmpty) {
      return Scaffold(
        primary: false,
        backgroundColor: ThemeCleanPremium.surfaceVariant,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.church_rounded, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma igreja cadastrada',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0),
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storage_rounded, color: ThemeCleanPremium.primary, size: 26),
                  const SizedBox(width: 12),
                  const Text(
                    'Armazenamento por igreja',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Selecione a igreja para ver o uso de espaço (Firestore e Drive). Controle exclusivo do Painel Master.',
                style: TextStyle(fontSize: 13, color: ThemeCleanPremium.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTenantId,
                decoration: InputDecoration(
                  labelText: 'Igreja',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                items: _tenants.map((d) {
                  final data = d.data();
                  final nome = (data['nome'] ?? data['razaoSocial'] ?? d.id).toString();
                  return DropdownMenuItem(value: d.id, child: Text(nome, overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (v) => setState(() => _selectedTenantId = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _selectedTenantId == null
              ? const SizedBox.shrink()
              : StorageUsagePage(
                  tenantId: _selectedTenantId!,
                  role: 'admin',
                  onCleaned: () {
                    _loadTenants().then((_) {
                      if (!mounted) return;
                      setState(() {
                        _selectedTenantId = _tenants.isNotEmpty ? _tenants.first.id : null;
                      });
                    });
                  },
                ),
        ),
      ],
        ),
      ),
    );
  }
}
