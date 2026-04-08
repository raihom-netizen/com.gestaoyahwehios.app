import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ✅ Landing Premium Clean (fundo branco, logo grande, módulos modernos)
/// - Campo CPF (11 dígitos) → consulta via Cloud Function `resolveCpfToEmail`
/// - Se encontrar: mostra o tenant e habilita botão "Entrar"
class PremiumCleanHomePage extends StatefulWidget {
  const PremiumCleanHomePage({super.key});

  @override
  State<PremiumCleanHomePage> createState() => _PremiumCleanHomePageState();
}

class _PremiumCleanHomePageState extends State<PremiumCleanHomePage> {
  final _cpfCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _profile;

  String _prettyTenant(String tenantId) {
    if (tenantId == 'brasilparacristo_sistema') return 'Brasil para Cristo (BPC)';
    return tenantId.replaceAll('_', ' ');
  }

  Future<Map<String, dynamic>?> _loadTenantPublic(String tenantId) async {
    try {
      final snap = await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get();
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      // Mantém somente o necessário para a landing
      return {
        'name': (data['name'] ?? data['nome'] ?? '').toString(),
        'logoUrl': (data['logoUrl'] ?? '').toString(),
        'planId': (data['planId'] ?? data['plan'] ?? '').toString(),
        'limits': data['limits'],
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadByCpf() async {
    setState(() {
      _loading = true;
      _error = null;
      _profile = null;
    });

    try {
      final cpf = _cpfCtrl.text;
      final clean = cpf.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length != 11) {
        throw 'CPF inválido (11 números).';
      }

      final callable = FirebaseFunctions.instance.httpsCallable('resolveCpfToEmail');
      final res = await callable.call({'cpf': clean});
      final data = Map<String, dynamic>.from(res.data as Map);
      final tenantId = (data['tenantId'] ?? '').toString().trim();
      if (tenantId.isEmpty) throw 'CPF não encontrado.';

      final tenant = await _loadTenantPublic(tenantId);

      setState(() {
        _profile = {
          ...data,
          if (tenant != null) 'tenant': tenant,
        };
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cpfCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 980;

    final logo = Row(
      children: [
        Image.asset('assets/logo.png', height: isWide ? 66 : 54),
        const SizedBox(width: 12),
        const Text(
          'Gestao YAHWEH',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
      ],
    );

    final topBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          logo,
          const Spacer(),
          TextButton(onPressed: () => Navigator.pushNamed(context, '/planos'), child: const Text('Planos')),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/app'),
            child: const Text('Entrar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/admin'),
            child: const Text('Painel ADM'),
          ),
        ],
      ),
    );

    Widget feature(IconData icon, String title, String subtitle) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8ECF3)),
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 10))],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF1D4ED8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF475467), height: 1.25)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final cpfCard = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8ECF3)),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 22, offset: Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Acessar minha igreja',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (_profile != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFC8E6C9)),
                  ),
                  child: const Text('Encontrado', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2E7D32))),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cpfCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'CPF (11 números)',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _loadByCpf(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _loading ? null : _loadByCpf,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('Carregar perfil'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ],
          if (_profile != null) ...[
            const SizedBox(height: 12),
            Text(
              'Igreja: ${_prettyTenant((_profile!['tenantId'] ?? '').toString())}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () {
                  final cpf = _cpfCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                  Navigator.pushNamed(context, '/igreja/login', arguments: {'cpf': cpf});
                },
                icon: const Icon(Icons.login),
                label: const Text('Entrar no sistema'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Se você for administrador, após login acesse o Painel ADM para liberar licenças, definir plano Free e configurar pagamentos.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.3, fontSize: 12),
          ),
        ],
      ),
    );

    final heroLeft = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Premium clean, moderno e do seu jeito.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          'Membros, escalas, mural, eventos tipo Instagram, notificações e painel ADM completo — pronto para vender.',
          style: TextStyle(color: Color(0xFF475467), fontSize: 16, height: 1.35, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/planos'),
              child: const Text('Ver planos'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/signup'),
              child: const Text('Testar 30 dias'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _Pill('Acesso por CPF'),
            _Pill('Eventos tipo feed'),
            _Pill('Mural e avisos'),
            _Pill('Painel ADM Master'),
          ],
        ),
      ],
    );

    final features = Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        SizedBox(width: isWide ? 360 : double.infinity, child: feature(Icons.people_alt_rounded, 'Membros', 'Cadastro rápido + fotos + status.')),
        SizedBox(width: isWide ? 360 : double.infinity, child: feature(Icons.event_note_rounded, 'Escalas', 'Montagem visual + avisos automáticos.')),
        SizedBox(width: isWide ? 360 : double.infinity, child: feature(Icons.auto_awesome_mosaic_rounded, 'Mural / Eventos', 'Feed moderno estilo Instagram.')),
        SizedBox(width: isWide ? 360 : double.infinity, child: feature(Icons.admin_panel_settings_rounded, 'Admin e Licenças', 'Liberar plano free, controlar pagamentos e configurações.')),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            topBar,
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: heroLeft),
                                const SizedBox(width: 16),
                                SizedBox(width: 420, child: cpfCard),
                              ],
                            )
                          else ...[
                            heroLeft,
                            const SizedBox(height: 14),
                            cpfCard,
                          ],
                          const SizedBox(height: 22),
                          const Text('Tudo o que sua igreja precisa, em um painel moderno', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          features,
                          const SizedBox(height: 26),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFE8ECF3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Segurança por perfil + regras no Firestore. Tudo preparado para licenças e pagamentos.',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475467)),
                                  ),
                                ),
                                if (kIsWeb) FilledButton.tonal(onPressed: () => Navigator.pushNamed(context, '/planos'), child: const Text('Começar')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3E7EF)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF344054))),
    );
  }
}
