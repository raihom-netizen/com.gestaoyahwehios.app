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

class _AdminTelegramTdlibPageState extends State<AdminTelegramTdlibPage>
    with AutomaticKeepAliveClientMixin {
  final _apiIdCtrl = TextEditingController();
  final _apiHashCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController(text: 'Gestao YAHWEH');
  final _langCtrl = TextEditingController(text: 'pt-br');

  bool _loading = true;
  bool _saving = false;
  /// Master precisa ver o hash na edição — oculto só sob pedido.
  bool _obscureHash = false;
  bool _configured = false;
  String _updatedBy = '';
  String? _loadError;

  @override
  bool get wantKeepAlive => true;

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

  void _applyConfigToFields(TelegramTdlibConfig cfg) {
    if (cfg.apiId > 0) {
      _apiIdCtrl.text = '${cfg.apiId}';
    }
    if (cfg.apiHash.isNotEmpty) {
      _apiHashCtrl.text = cfg.apiHash;
    }
    if (cfg.deviceModel.isNotEmpty) {
      _deviceCtrl.text = cfg.deviceModel;
    }
    if (cfg.systemLanguageCode.isNotEmpty) {
      _langCtrl.text = cfg.systemLanguageCode;
    }
    _configured = cfg.isConfigured;
    _updatedBy = cfg.updatedByEmail;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cfg = await TelegramTdlibConfigService.load(preferServer: true);
      if (!mounted) return;
      _applyConfigToFields(cfg);
      if (cfg.isConfigured) {
        applyTelegramCredentialsCache(
          apiId: cfg.apiId,
          apiHash: cfg.apiHash,
          deviceModel: cfg.deviceModel,
          systemLanguageCode: cfg.systemLanguageCode,
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = formatFirebaseErrorForUser(e, logToCrashlytics: false);
      });
    }
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
      final saved = await TelegramTdlibConfigService.save(
        apiId: id,
        apiHash: hash,
        deviceModel: _deviceCtrl.text.trim(),
        systemLanguageCode: _langCtrl.text.trim(),
      );
      applyTelegramCredentialsCache(
        apiId: saved.apiId,
        apiHash: saved.apiHash,
        deviceModel: saved.deviceModel,
        systemLanguageCode: saved.systemLanguageCode,
      );
      if (!mounted) return;
      _applyConfigToFields(saved);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Integração Telegram gravada e confirmada em '
          '${TelegramTdlibConfigService.firestorePath}.',
        ),
      );
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
    super.build(context);
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
                'Guarde o api_id e api_hash da app Telegram. O Android lê do Firestore e liga o motor TDLib nativo. '
                'iOS e Web usam o Telegram Web embutido (mesma conta) — iOS só liga o motor nativo se o build for compilado com '
                'YAHWEH_TDLIB_IOS_ENABLED=1 e o dispositivo suportar.',
          ),
          const SizedBox(height: 12),
          if (_loadError != null) ...[
            Material(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFCF1322)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Falha ao carregar: $_loadError',
                        style: const TextStyle(
                          color: Color(0xFFCF1322),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _load,
                      child: const Text('Recarregar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          MasterPremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _configured
                            ? const Color(0xFFE6F7F1)
                            : const Color(0xFFFFF7E6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _configured ? 'Configurado' : 'Não configurado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _configured
                              ? const Color(0xFF0F766E)
                              : const Color(0xFFD48806),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _loading || _saving ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Recarregar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                    helperText: 'Visível na edição — valor gravado no Firestore',
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
                    helperText: 'Visível por defeito no painel Master',
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
                  'Após salvar com sucesso, estes campos voltam preenchidos ao reabrir o menu. '
                  'No telemóvel, o motor Telegram (TDLib) usa estes valores sem novo AAB. '
                  'Na web o TDLib nativo não corre (limitação do browser).',
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
