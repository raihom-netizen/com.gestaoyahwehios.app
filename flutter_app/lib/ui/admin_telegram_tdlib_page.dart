import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_credentials.dart';
import 'package:gestao_yahweh/services/telegram_tdlib_config_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:url_launcher/url_launcher.dart';

/// Painel Master — integra Telegram TDLib (`config/telegram_tdlib`).
class AdminTelegramTdlibPage extends StatefulWidget {
  const AdminTelegramTdlibPage({super.key});

  @override
  State<AdminTelegramTdlibPage> createState() => _AdminTelegramTdlibPageState();
}

class _AdminTelegramTdlibPageState extends State<AdminTelegramTdlibPage> {
  final _apiIdCtrl = TextEditingController();
  final _apiHashCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController(text: 'Gestao YAHWEH');
  final _langCtrl = TextEditingController(text: 'pt-br');

  bool _loading = true;
  bool _saving = false;
  bool _obscureHash = true;
  String _updatedBy = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _apiIdCtrl.dispose();
    _apiHashCtrl.dispose();
    _deviceCtrl.dispose();
    _langCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cfg = await TelegramTdlibConfigService.load();
    if (!mounted) return;
    if (cfg.apiId > 0) _apiIdCtrl.text = '${cfg.apiId}';
    if (cfg.apiHash.isNotEmpty) _apiHashCtrl.text = cfg.apiHash;
    if (cfg.deviceModel.isNotEmpty) _deviceCtrl.text = cfg.deviceModel;
    if (cfg.systemLanguageCode.isNotEmpty) {
      _langCtrl.text = cfg.systemLanguageCode;
    }
    setState(() {
      _updatedBy = cfg.updatedByEmail;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final id = int.tryParse(_apiIdCtrl.text.trim()) ?? 0;
    final hash = _apiHashCtrl.text.trim();
    if (id <= 0 || hash.length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Preencha api_id e api_hash válidos (de my.telegram.org/apps).',
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TelegramTdlibConfigService.save(
        apiId: id,
        apiHash: hash,
        deviceModel: _deviceCtrl.text.trim(),
        systemLanguageCode: _langCtrl.text.trim(),
      );
      applyTelegramCredentialsCache(
        apiId: id,
        apiHash: hash,
        deviceModel: _deviceCtrl.text.trim(),
        systemLanguageCode: _langCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Integração Telegram salva em ${TelegramTdlibConfigService.firestorePath}.',
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          formatFirebaseErrorForUser(e, logToCrashlytics: false),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openTelegramApps() async {
    final uri = Uri.parse('https://my.telegram.org/apps');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
            title: 'Telegram / TDLib',
            subtitle:
                'Guarde o api_id e api_hash da app Telegram. O app Android/iOS lê do Firestore e liga o motor TDLib (Yahweh Chat).',
          ),
          const SizedBox(height: 12),
          MasterPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Path: ${TelegramTdlibConfigService.firestorePath}',
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeCleanPremium.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_updatedBy.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Última gravação: $_updatedBy',
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openTelegramApps,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Abrir my.telegram.org/apps'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiIdCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'App api_id',
                    hintText: 'Ex.: 37029102',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiHashCtrl,
                  obscureText: _obscureHash,
                  decoration: InputDecoration(
                    labelText: 'App api_hash',
                    hintText: 'Cole o hash de 32 caracteres',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscureHash ? 'Mostrar' : 'Ocultar',
                      onPressed: () =>
                          setState(() => _obscureHash = !_obscureHash),
                      icon: Icon(
                        _obscureHash
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deviceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Device model (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _langCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Idioma do sistema (opcional)',
                    hintText: 'pt-br',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Na web o TDLib não corre (limitação do browser). No telemóvel, após salvar aqui, o motor Telegram usa estes valores sem novo AAB.',
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeCleanPremium.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
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
            label: Text(_saving ? 'Salvando…' : 'Salvar integração Telegram'),
          ),
        ],
      ),
    );
  }
}
