import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Configuração de versão mínima e forçar atualização (estilo Controle Total).
/// Edita o documento Firestore config/appVersion.
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

  bool _forceUpdate = false;
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
        _forceUpdate = data?['forceUpdate'] == true;
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
        'forceUpdate': _forceUpdate,
        'message': _messageCtrl.text.trim(),
        'webRefresh': _webRefresh,
        'storeUrlAndroid': _storeAndroidCtrl.text.trim(),
        'storeUrlIos': _storeIosCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Configuração salva. Usuários com versão anterior serão obrigados a atualizar.'),
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
                      'Forçar atualização de versão',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Igual ao Controle Total: define a versão mínima no Firestore (config/appVersion). '
                  'Quem estiver abaixo verá tela de bloqueio até atualizar.',
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
          decoration: const InputDecoration(
            labelText: 'Mensagem (opcional)',
            hintText: 'Ex: Atualize para a versão mais recente para continuar.',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Forçar atualização (bloquear app até atualizar)'),
          subtitle: const Text('Se ativo, usuários com versão antiga não conseguem usar o app.'),
          value: _forceUpdate,
          onChanged: (v) => setState(() => _forceUpdate = v),
          activeColor: ThemeCleanPremium.primary,
        ),
        SwitchListTile(
          title: const Text('Web: recarregar ao atualizar'),
          subtitle: const Text('Na web, ao clicar em Atualizar, recarrega a página.'),
          value: _webRefresh,
          onChanged: (v) => setState(() => _webRefresh = v),
          activeColor: ThemeCleanPremium.primary,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _storeAndroidCtrl,
          decoration: const InputDecoration(
            labelText: 'URL Play Store (Android)',
            hintText: 'https://play.google.com/store/apps/...',
            border: OutlineInputBorder(),
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
