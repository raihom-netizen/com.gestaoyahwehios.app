import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Versão mínima em `config/appVersion`: usuários desatualizados veem **aviso** com link da loja (app não bloqueia).
class AdminForcarAtualizacaoPage extends StatefulWidget {
  const AdminForcarAtualizacaoPage({super.key});

  @override
  State<AdminForcarAtualizacaoPage> createState() => _AdminForcarAtualizacaoPageState();
}

class _AdminForcarAtualizacaoPageState extends State<AdminForcarAtualizacaoPage> {
  static const _path = 'config/appVersion';

  final _minVersionCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _storeAndroidCtrl = TextEditingController();
  final _storeIosCtrl = TextEditingController();
  final _latestVersionCtrl = TextEditingController();
  final _panelMessageCtrl = TextEditingController();

  bool _webRefresh = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minVersionCtrl.dispose();
    _messageCtrl.dispose();
    _storeAndroidCtrl.dispose();
    _storeIosCtrl.dispose();
    _latestVersionCtrl.dispose();
    _panelMessageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final doc = await FirebaseFirestore.instance.doc(_path).get();
      final data = doc.data();
      if (mounted) {
        _minVersionCtrl.text = (data?['minVersion'] ?? '').toString().trim();
        _messageCtrl.text = (data?['message'] ?? '').toString().trim();
        _storeAndroidCtrl.text = (data?['storeUrlAndroid'] ?? '').toString().trim();
        _storeIosCtrl.text = (data?['storeUrlIos'] ?? '').toString().trim();
        _latestVersionCtrl.text = (data?['latestVersion'] ?? '').toString().trim();
        _panelMessageCtrl.text = (data?['panelUpdateMessage'] ?? '').toString().trim();
        _webRefresh = data?['webRefresh'] != false;
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _save() async {
    final minVersion = _minVersionCtrl.text.trim();
    if (minVersion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a versão mínima (ex: 11.0.7)')),
      );
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await FirebaseFirestore.instance.doc(_path).set({
        'minVersion': minVersion,
        'forceUpdate': false,
        'message': _messageCtrl.text.trim(),
        'webRefresh': _webRefresh,
        'storeUrlAndroid': _storeAndroidCtrl.text.trim(),
        'storeUrlIos': _storeIosCtrl.text.trim(),
        'latestVersion': _latestVersionCtrl.text.trim(),
        'panelUpdateMessage': _panelMessageCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Configuração salva. Quem estiver com versão antiga verá um aviso premium com link para a Play Store (sem bloquear o app).',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red.shade700),
      );
    }
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
                padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom + ThemeCleanPremium.spaceXl),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_rounded, color: ThemeCleanPremium.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Aviso de nova versão (Play Store)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a versão mínima em config/appVersion. Quem estiver abaixo vê um diálogo premium '
                  'com mensagem e botão para a Play Store (Android: com.gestaoyahweh.app). '
                  'O uso do app não é bloqueado — o usuário pode tocar em Depois.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versão atual do app: $appVersion',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
        TextField(
          controller: _minVersionCtrl,
          decoration: const InputDecoration(
            labelText: 'Versão mínima obrigatória',
            hintText: 'ex: 11.0.7',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.tag_rounded),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _messageCtrl,
          decoration: InputDecoration(
            labelText: 'Mensagem no aviso (opcional)',
            hintText: kDefaultVersionUpdateMessage('11.3.0'),
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Text(
          'Se deixar em branco, o app usa a mensagem padrão “ultra premium” com convite à Play Store.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Web: recarregar ao atualizar'),
          subtitle: const Text('Na web, ao clicar em Atualizar, recarrega a página.'),
          value: _webRefresh,
          onChanged: (v) => setState(() => _webRefresh = v),
          activeColor: ThemeCleanPremium.primary,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _latestVersionCtrl,
          decoration: const InputDecoration(
            labelText: 'Versão na loja (opcional — aviso no painel)',
            hintText: 'ex: 11.3.0 — se maior que o app, mostra faixa no painel Android',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.new_releases_outlined),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _panelMessageCtrl,
          decoration: const InputDecoration(
            labelText: 'Mensagem do aviso no painel (opcional)',
            hintText: 'Sobrescreve a mensagem curta na faixa laranja do painel da igreja',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _storeAndroidCtrl,
          decoration: InputDecoration(
            labelText: 'URL Play Store (Android)',
            hintText: kDefaultPlayStoreUrl,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _storeIosCtrl,
          decoration: const InputDecoration(
            labelText: 'URL App Store (iOS)',
            hintText: 'https://apps.apple.com/...',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Salvando...' : 'Salvar configuração'),
            style: FilledButton.styleFrom(
              backgroundColor: ThemeCleanPremium.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    ),
      ),
    );
  }
}
