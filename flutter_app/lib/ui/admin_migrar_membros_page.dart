import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Painel Master — Migração: sincroniza usuários (users) para a tabela de membros
/// da igreja (igrejas/{id}/membros) para corrigir exibição
/// de membros e fotos no painel da igreja.
class AdminMigrarMembrosPage extends StatefulWidget {
  const AdminMigrarMembrosPage({super.key});

  @override
  State<AdminMigrarMembrosPage> createState() => _AdminMigrarMembrosPageState();
}

class _AdminMigrarMembrosPageState extends State<AdminMigrarMembrosPage> {
  bool _loading = false;
  String? _resultMessage;
  String? _errorMessage;

  static const _timeout = Duration(seconds: 520);
  static const _retries = 1;

  Future<HttpsCallableResult<Map<String, dynamic>>> _callWithTimeoutAndRetry(Future<HttpsCallableResult<Map<String, dynamic>>> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn().timeout(_timeout);
      } catch (e) {
        attempt++;
        if (attempt > _retries) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Migração completa: consolida membros→members em todos os tenants e sincroniza users→members.
  /// Se [targetSlug] for passado, a consolidação e o sync são feitos só para essa igreja.
  Future<void> _executarMigracaoCompleta({String? targetSlug}) async {
    ThemeCleanPremium.hapticAction();
    setState(() {
      _loading = true;
      _resultMessage = null;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('migrateMembersFull');
      final params = <String, dynamic>{};
      if (targetSlug != null && targetSlug.trim().isNotEmpty) {
        params['targetSlug'] = targetSlug.trim();
      }
      final res = await _callWithTimeoutAndRetry(() => callable.call<Map<String, dynamic>>(params));
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      final ok = data['ok'] == true;
      final msg = (data['message'] ?? 'Concluído.').toString();
      final consolidated = data['consolidatedCount'] ?? 0;
      final usersProcessed = data['usersProcessed'] ?? 0;
      final membersWritten = data['membersWritten'] ?? 0;
      if (mounted) {
        setState(() {
          _loading = false;
          if (ok) {
            _resultMessage = msg != 'Concluído.' && msg.isNotEmpty
                ? msg
                : 'Migração: $consolidated doc(s) members→membros, $usersProcessed usuários, $membersWritten em membros.';
            _errorMessage = null;
          } else {
            _resultMessage = null;
            _errorMessage = msg;
          }
        });
        if (ok) ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Migração completa executada.'));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final code = e.code;
        final msg = (e.message ?? '').trim().isNotEmpty ? e.message! : code;
        final details = e.details?.toString() ?? '';
        final isInternal = code == 'internal' || code == 'unknown';
        String fullMsg = msg;
        if (details.isNotEmpty) fullMsg = '$fullMsg\n$details';
        if (isInternal) {
          fullMsg = '$fullMsg\n\n'
              'A função "migrateMembersFull" pode não estar publicada. Na pasta "functions": npm run build e firebase deploy --only functions.';
        }
        setState(() {
          _loading = false;
          _errorMessage = fullMsg;
          _resultMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $msg'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
        setState(() {
          _loading = false;
          _errorMessage = raw.contains('internal') || raw.contains('INTERNAL')
              ? '$raw\n\nNa pasta "functions": npm run build e firebase deploy --only functions.'
              : raw;
          _resultMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $raw'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// Executa migração. Se [targetSlug] for passado (ex.: brasil-para-cristo), todos os usuários
  /// são migrados para essa igreja (escritos em igrejas/{id}/membros e users atualizados com tenantId/igrejaId).
  Future<void> _executarMigracao({String? targetSlug}) async {
    ThemeCleanPremium.hapticAction();
    setState(() {
      _loading = true;
      _resultMessage = null;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('syncMembersFromUsers');
      final params = <String, dynamic>{};
      if (targetSlug != null && targetSlug.trim().isNotEmpty) {
        params['targetSlug'] = targetSlug.trim();
      }
      final res = await _callWithTimeoutAndRetry(() => callable.call<Map<String, dynamic>>(params));
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      final ok = data['ok'] == true;
      final msg = (data['message'] ?? 'Concluído.').toString();
      final usersProcessed = data['usersProcessed'] ?? 0;
      final membersWritten = data['membersWritten'] ?? 0;
      final usersUpdated = data['usersUpdated'];
      if (mounted) {
        setState(() {
          _loading = false;
          _resultMessage = ok
              ? (usersUpdated != null
                  ? 'Migração para a igreja concluída. $usersProcessed usuários processados, $membersWritten documentos de membros escritos, $usersUpdated usuários atualizados com a igreja.'
                  : 'Migração concluída. $usersProcessed usuários processados, $membersWritten documentos de membros escritos em igrejas. As igrejas passam a buscar membros e fotos na tabela correta.')
              : msg;
          _errorMessage = ok ? null : msg;
        });
        if (ok) ScaffoldMessenger.of(context).showSnackBar(ThemeCleanPremium.successSnackBar('Migração executada com sucesso.'));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final code = e.code;
        final msg = (e.message ?? '').trim().isNotEmpty ? e.message! : code;
        final details = e.details?.toString() ?? '';
        final isInternal = code == 'internal' || code == 'unknown';
        String fullMsg = msg;
        if (details.isNotEmpty) fullMsg = '$fullMsg\n$details';
        if (isInternal) {
          fullMsg = '$fullMsg\n\n'
              'Causa comum: a função "syncMembersFromUsers" ainda não foi publicada no Firebase. '
              'Na pasta do projeto, abra o terminal na pasta "functions", execute:\n'
              '  npm run build\n'
              '  firebase deploy --only functions\n'
              'Depois tente executar a migração novamente.';
        }
        setState(() {
          _loading = false;
          _errorMessage = fullMsg;
          _resultMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $msg'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        final raw = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
        setState(() {
          _loading = false;
          _errorMessage = raw.contains('internal') || raw.contains('INTERNAL')
              ? '$raw\n\nA função pode não estar publicada. Na pasta "functions": npm run build e firebase deploy --only functions.'
              : raw;
          _resultMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $raw'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            pad.left,
            pad.top,
            pad.right,
            pad.bottom + ThemeCleanPremium.spaceXl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Migrar membros',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800) ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Sincroniza todos os usuários (coleção users) para a tabela de membros de cada igreja (igrejas), com nome, e-mail e foto. Assim o painel da igreja passa a exibir corretamente os membros e as fotos.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 24),
              MasterPremiumCard(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.sync_rounded, size: 48, color: Colors.deepPurple.shade600),
                    const SizedBox(height: 16),
                    const Text(
                      'Migração completa (recomendado)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Copia a subcoleção legada "members" para "membros" em cada igreja e sincroniza a coleção users para igrejas/.../membros. Pode levar alguns minutos; não feche a página.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _executarMigracaoCompleta(),
                      icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.all_inclusive_rounded),
                      label: Text(_loading ? 'Executando...' : 'Executar migração completa'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.deepPurple.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              MasterPremiumCard(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.people_alt_rounded, size: 48, color: ThemeCleanPremium.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'Executar migração (MASTER / ADMIN)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cada usuário com tenantId ou igrejaId será escrito em igrejas/{id}/membros, com foto (FOTO_URL_OU_ID) quando existir.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Se aparecer erro "internal": publique a função antes. Na pasta "functions" do projeto: npm run build e firebase deploy --only functions.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _executarMigracao(),
                      icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.sync_rounded),
                      label: Text(_loading ? 'Executando...' : 'Executar migração'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: ThemeCleanPremium.primary,
                      ),
                    ),
                    if (_resultMessage != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_resultMessage!, style: TextStyle(fontSize: 13, color: Colors.green.shade900))),
                          ],
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_errorMessage!, style: TextStyle(fontSize: 13, color: Colors.red.shade900))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              MasterPremiumCard(
                padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.church_rounded, size: 48, color: Colors.green.shade700),
                    const SizedBox(height: 16),
                    const Text(
                      'Migrar todos para Brasil para Cristo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Todos os usuários (users) serão escritos como membros da igreja Brasil para Cristo e seus tenantId/igrejaId serão atualizados para essa igreja. Use após configurar a igreja no cadastro.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loading ? null : () => _executarMigracao(targetSlug: 'brasil-para-cristo'),
                      icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.people_rounded),
                      label: Text(_loading ? 'Executando...' : 'Migrar todos para Brasil para Cristo'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
