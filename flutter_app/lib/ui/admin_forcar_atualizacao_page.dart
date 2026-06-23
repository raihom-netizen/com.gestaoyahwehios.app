import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/services/installed_app_build.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Versão mínima em `config/appVersion`: força ou avisa utilizadores Android/iOS/Web.
class AdminForcarAtualizacaoPage extends StatefulWidget {
  const AdminForcarAtualizacaoPage({super.key});

  @override
  State<AdminForcarAtualizacaoPage> createState() =>
      _AdminForcarAtualizacaoPageState();
}

class _AdminForcarAtualizacaoPageState extends State<AdminForcarAtualizacaoPage> {
  static const _path = 'config/appVersion';

  final _minVersionCtrl = TextEditingController();
  final _minBuildCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _storeAndroidCtrl = TextEditingController();
  final _storeIosCtrl = TextEditingController();
  final _latestVersionCtrl = TextEditingController();
  final _panelMessageCtrl = TextEditingController();
  final _minBuildIosAscCtrl = TextEditingController();

  bool _webRefresh = true;
  bool _forceUpdate = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _publishedBuild;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minVersionCtrl.dispose();
    _minBuildCtrl.dispose();
    _messageCtrl.dispose();
    _storeAndroidCtrl.dispose();
    _storeIosCtrl.dispose();
    _latestVersionCtrl.dispose();
    _panelMessageCtrl.dispose();
    _minBuildIosAscCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirestoreReadResilience.getDocument(
        firebaseDefaultFirestore.doc(_path),
        cacheKey: 'config_appVersion',
      );
      final data = doc.data();
      if (mounted) {
        _minVersionCtrl.text = (data?['minVersion'] ?? '').toString().trim();
        final buildRaw = data?['minBuildNumber'];
        _minBuildCtrl.text = buildRaw == null
            ? ''
            : (buildRaw is num ? buildRaw.toInt() : int.tryParse('$buildRaw') ?? '')
                .toString();
        _messageCtrl.text = (data?['message'] ?? '').toString().trim();
        _storeAndroidCtrl.text = (data?['storeUrlAndroid'] ?? '').toString().trim();
        _storeIosCtrl.text = (data?['storeUrlIos'] ?? '').toString().trim();
        _latestVersionCtrl.text = (data?['latestVersion'] ?? '').toString().trim();
        _panelMessageCtrl.text =
            (data?['panelUpdateMessage'] ?? '').toString().trim();
        _webRefresh = data?['webRefresh'] != false;
        _forceUpdate = data?['forceUpdate'] == true;
        _publishedBuild = (data?['publishedBuild'] ?? '').toString().trim();
        final iosAscRaw = data?['minBuildNumberIosAsc'];
        _minBuildIosAscCtrl.text = iosAscRaw == null
            ? ''
            : (iosAscRaw is num
                    ? iosAscRaw.toInt()
                    : int.tryParse('$iosAscRaw') ?? '')
                .toString();
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = formatFirebaseErrorForUser(e, logToCrashlytics: false);
        });
      }
    }
  }

  void _fillCurrentBuildFields() {
    _minVersionCtrl.text = appVersion;
    _minBuildCtrl.text = appBuildNumber;
    _minBuildIosAscCtrl.clear();
    _latestVersionCtrl.text = appVersionFull;
    if (_storeAndroidCtrl.text.trim().isEmpty) {
      _storeAndroidCtrl.text = AppConstants.gestaoYahwehPlayStoreUrl;
    }
    if (_storeIosCtrl.text.trim().isEmpty) {
      _storeIosCtrl.text = AppConstants.gestaoYahwehTestFlightUrl;
    }
    if (_messageCtrl.text.trim().isEmpty) {
      _messageCtrl.text =
          'Atualização obrigatória ($appVersionFull). Instale o build mais recente '
          'para continuar — correções de desempenho, painel, membros, eventos e avisos.';
    }
    if (_panelMessageCtrl.text.trim().isEmpty) {
      _panelMessageCtrl.text =
          'Nova versão $appVersionFull disponível. Atualize na loja (Android ou iPhone).';
    }
    _forceUpdate = true;
    _webRefresh = true;
    setState(() {});
  }

  Future<void> _save({bool fromPublishButton = false}) async {
    final minVersion = _minVersionCtrl.text.trim();
    final minBuild = int.tryParse(_minBuildCtrl.text.trim());
    final minIosAsc = int.tryParse(_minBuildIosAscCtrl.text.trim());
    if (minBuild != null &&
        isIosAscStyleBuildNumber(minBuild) &&
        minIosAsc == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'O build +$minBuild parece número da App Store (TestFlight), não o +N do '
              'app_version.dart ($appBuildNumber). Use «Publicar build atual» ou deixe o '
              'campo Build mínimo com +$appBuildNumber — iPhone e Android usam o mesmo +N.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }
    if (minVersion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a versão mínima (ex: 11.2.295)')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'minVersion': minVersion,
        'minBuildNumber': minBuild ?? int.tryParse(appBuildNumber) ?? 0,
        'latestVersion': _latestVersionCtrl.text.trim().isEmpty
            ? appVersionFull
            : _latestVersionCtrl.text.trim(),
        'forceUpdate': _forceUpdate,
        'message': _messageCtrl.text.trim(),
        'webRefresh': _webRefresh,
        'storeUrlAndroid': _storeAndroidCtrl.text.trim().isEmpty
            ? AppConstants.gestaoYahwehPlayStoreUrl
            : _storeAndroidCtrl.text.trim(),
        'storeUrlIos': _storeIosCtrl.text.trim().isEmpty
            ? AppConstants.gestaoYahwehTestFlightUrl
            : _storeIosCtrl.text.trim(),
        'panelUpdateMessage': _panelMessageCtrl.text.trim(),
        'publishedBuild': appVersionFull,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (minIosAsc != null && minIosAsc > 0) {
        payload['minBuildNumberIosAsc'] = minIosAsc;
      } else {
        payload['minBuildNumberIosAsc'] = FieldValue.delete();
      }
      await FirestoreWebGuard.prepareForCriticalWrite();
      await FirestoreWebGuard.runWithWebRecovery(
        () => firebaseDefaultFirestore
            .doc(_path)
            .set(payload, SetOptions(merge: true)),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _publishedBuild = appVersionFull;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            fromPublishButton
                ? 'Build $appVersionFull publicado. Quem estiver abaixo de +${payload['minBuildNumber']} '
                    'será obrigado a atualizar (Android → Play Store, iOS → link configurado).'
                : 'Configuração salva.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = formatFirebaseErrorForUser(e, logToCrashlytics: false);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              formatFirebaseErrorForUser(e, logToCrashlytics: false),
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _publishCurrentBuild() async {
    _fillCurrentBuildFields();
    await _save(fromPublishButton: true);
  }

  @override
  Widget build(BuildContext context) {
    final padding = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      primary: false,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  padding.left,
                  padding.top,
                  padding.right,
                  padding.bottom + ThemeCleanPremium.spaceXl,
                ),
                children: [
                  MasterPremiumCard(
                    padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.system_update_rounded,
                                color: ThemeCleanPremium.primary, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Forçar atualização — build completo',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Publica em `config/appVersion` a versão mínima e o build +N '
                          '(app_version.dart — igual Android e iPhone). Utilizadores abaixo '
                          'disso veem o diálogo com Play Store ou TestFlight.\n\n'
                          'No TestFlight o número longo (ex.: 1779982861) é só da Apple — '
                          'não use esse valor em «Build mínimo». Use sempre o +$appBuildNumber '
                          'deste painel ao clicar «Publicar build atual».',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Build deste painel admin: $appVersionFull',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: ThemeCleanPremium.primary,
                              ),
                        ),
                        if (_publishedBuild != null &&
                            _publishedBuild!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Último publicado no Firestore: $_publishedBuild',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _publishCurrentBuild,
                      icon: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.publish_rounded),
                      label: Text(
                        _saving
                            ? 'Publicando…'
                            : 'Publicar build atual ($appVersionFull)',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    title: const Text('Atualização obrigatória (bloqueia o app)'),
                    subtitle: const Text(
                      'Se ativo, o utilizador não pode usar o app sem ir à loja. '
                      'Recomendado após publicar AAB + build iOS.',
                    ),
                    value: _forceUpdate,
                    onChanged: (v) => setState(() => _forceUpdate = v),
                    activeColor: ThemeCleanPremium.primary,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _minVersionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Versão mínima (marketing)',
                      hintText: 'ex: 11.2.295',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minBuildCtrl,
                    decoration: InputDecoration(
                      labelText: 'Build mínimo (+N) — Android e iOS',
                      hintText: 'ex: $appBuildNumber',
                      helperText:
                          'Mesmo número do pubspec/app_version.dart. Não coloque o número longo do TestFlight.',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.numbers_rounded),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minBuildIosAscCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Build mínimo iOS ASC (opcional)',
                      hintText: 'Deixe vazio — quase sempre',
                      helperText:
                          'Só se precisar exigir um CFBundleVersion específico da App Store. '
                          '«Publicar build atual» limpa este campo.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.apple_rounded),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mensagem no diálogo (app)',
                      hintText: kDefaultVersionUpdateMessage(appVersionFull),
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Web: recarregar ao atualizar'),
                    subtitle: const Text(
                      'No painel web, o botão Atualizar recarrega a página (Ctrl+F5).',
                    ),
                    value: _webRefresh,
                    onChanged: (v) => setState(() => _webRefresh = v),
                    activeColor: ThemeCleanPremium.primary,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _latestVersionCtrl,
                    decoration: InputDecoration(
                      labelText: 'Versão exibida (painel / aviso)',
                      hintText: appVersionFull,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.new_releases_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _panelMessageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mensagem no painel da igreja (faixa laranja)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _storeAndroidCtrl,
                    decoration: InputDecoration(
                      labelText: 'Link Android (Google Play)',
                      hintText: AppConstants.gestaoYahwehPlayStoreUrl,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.android_rounded),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _storeIosCtrl,
                    decoration: InputDecoration(
                      labelText: 'Link iOS (App Store / TestFlight)',
                      hintText: AppConstants.gestaoYahwehTestFlightUrl,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.apple_rounded),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              _minVersionCtrl.text = appVersion;
                              _minBuildCtrl.text = appBuildNumber;
                              _minBuildIosAscCtrl.clear();
                              _forceUpdate = false;
                              setState(() {});
                              await _save();
                            },
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: const Text(
                        'Parar aviso no iPhone (build atual, sem bloquear)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Salvando…' : 'Salvar sem alterar build'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
