import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Feature flags globais (`config/featureFlags`) — master SaaS.
class MasterFeatureFlagsPage extends StatefulWidget {
  const MasterFeatureFlagsPage({super.key});

  @override
  State<MasterFeatureFlagsPage> createState() => _MasterFeatureFlagsPageState();
}

class _MasterFeatureFlagsPageState extends State<MasterFeatureFlagsPage> {
  static const _docPath = 'config/featureFlags';

  final Map<String, bool> _flags = {
    'chatIgrejaEnabled': true,
    'muralHdVideo': true,
    'offlineWarmup': true,
    'iosReaderMode': true,
    'panelFinanceSummaryCache': true,
  };

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => firebaseDefaultFirestore.doc(_docPath).get(),
      );
      final data = snap.data();
      if (data != null) {
        for (final k in _flags.keys.toList()) {
          if (data.containsKey(k)) {
            _flags[k] = data[k] == true;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirestoreWebGuard.recoverFirestoreWebSession(
        allowHardReconnect: true,
      );
      await FirestoreWebGuard.runWithWebRecovery(
        () => firebaseDefaultFirestore.doc(_docPath).set({
          ..._flags,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': firebaseDefaultAuth.currentUser?.email,
        }, SetOptions(merge: true)),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Feature flags atualizados.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            formatFirebaseErrorForUser(e, logToCrashlytics: false),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MasterModuleSectionTitle(
            title: 'Feature flags',
            subtitle:
                'Liga/desliga capacidades da plataforma sem novo deploy (consumo no app conforme implementação).',
          ),
          const SizedBox(height: 16),
          MasterPremiumCard(
            child: Column(
              children: [
                _row('Chat Igreja', 'chatIgrejaEnabled',
                    'Módulo de chat entre membros.'),
                _row('Vídeo HD no mural', 'muralHdVideo', 'Player e upload HD.'),
                _row('Warmup offline', 'offlineWarmup',
                    'Pré-cache ao abrir o painel da igreja.'),
                _row('Modo Reader iOS', 'iosReaderMode',
                    'Checkout externo / App Store 3.1.1.'),
                _row('Cache financeiro painel', 'panelFinanceSummaryCache',
                    'Gráfico via finance_summary.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Salvando…' : 'Salvar flags'),
          ),
        ],
      ),
    );
  }

  Widget _row(String title, String key, String help) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(help, style: const TextStyle(fontSize: 12)),
      value: _flags[key] ?? false,
      onChanged: (v) => setState(() => _flags[key] = v),
    );
  }
}
