import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/data/yahweh_doc_write.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart' show YahwehFv;
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/tenant/church_tenant_override.dart';
import 'package:gestao_yahweh/services/master_churches_list_service.dart';
import 'package:gestao_yahweh/ui/pages/igreja_cadastro_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';

/// Id de igreja a partir do nome — mesmas regras dos ids que já existem em
/// produção (minúsculas, sem acento, `_` entre palavras).
String masterChurchIdFromName(String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return '';
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buf = StringBuffer();
  for (final ch in n.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  final slug = buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (slug.isEmpty) return '';
  return slug.startsWith('igreja_') ? slug : 'igreja_$slug';
}

/// Cadastro de igreja nova pelo painel master.
///
/// Dois passos: aqui ficam só os campos que definem a igreja (nome, id, plano,
/// vencimento) — o resto (logo, endereço, responsável, links públicos) é a
/// mesma tela «Cadastro da Igreja» que o gestor usa, aberta logo a seguir já
/// apontada para a igreja criada. Um só lugar para manter.
class MasterNovaIgrejaPage extends StatefulWidget {
  const MasterNovaIgrejaPage({super.key});

  @override
  State<MasterNovaIgrejaPage> createState() => _MasterNovaIgrejaPageState();
}

class _MasterNovaIgrejaPageState extends State<MasterNovaIgrejaPage> {
  final _nomeCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _gestorNomeCtrl = TextEditingController();
  final _gestorEmailCtrl = TextEditingController();
  final _gestorTelefoneCtrl = TextEditingController();
  String _plano = 'free';
  DateTime? _vencimento;
  bool _idEditadoManualmente = false;
  bool _saving = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nomeCtrl.addListener(() {
      if (_idEditadoManualmente) return;
      final derivado = masterChurchIdFromName(_nomeCtrl.text);
      if (_idCtrl.text != derivado) {
        _idCtrl.text = derivado;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _idCtrl.dispose();
    _gestorNomeCtrl.dispose();
    _gestorEmailCtrl.dispose();
    _gestorTelefoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    final nome = _nomeCtrl.text.trim();
    final id = _idCtrl.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Informe o nome da igreja.');
      return;
    }
    if (id.isEmpty || !RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      setState(
        () => _erro =
            'ID inválido. Use apenas letras minúsculas, números e "_".',
      );
      return;
    }
    setState(() {
      _saving = true;
      _erro = null;
    });
    try {
      // `resolveExactChurchId` — NÃO `ChurchRepository.churchId`. Este último
      // dá prioridade ao override do seletor «Trocar de igreja»: com uma igreja
      // aberta, o id novo era descartado e a criação apontava para a igreja
      // atual (que já existe), respondendo sempre «já existe uma igreja com
      // este slug» — e nunca deixando criar nada.
      final exactId = ChurchContext.resolveExactChurchId(id);
      final ref = ChurchUiCollections.churchDocExact(exactId);
      final exists = (await ref.get()).exists;
      if (exists) {
        setState(() {
          _saving = false;
          _erro = 'Já existe uma igreja com o ID "$exactId". Escolha outro.';
        });
        return;
      }

      final data = <String, dynamic>{
        'name': nome,
        'nome': nome,
        'slug': exactId.replaceAll('_', '-'),
        'alias': exactId.replaceAll('_', '-'),
        'igrejaId': exactId,
        'tenantId': exactId,
        'churchId': exactId,
        'plano': _plano,
        'planId': _plano,
        'status': 'ativa',
        'ativa': true,
        if (_gestorNomeCtrl.text.trim().isNotEmpty)
          'gestorNome': _gestorNomeCtrl.text.trim(),
        if (_gestorEmailCtrl.text.trim().isNotEmpty)
          'gestorEmail': _gestorEmailCtrl.text.trim().toLowerCase(),
        if (_gestorTelefoneCtrl.text.trim().isNotEmpty)
          'gestorTelefone': _gestorTelefoneCtrl.text.trim(),
        if (_vencimento != null) ...{
          'data_vencimento': Timestamp.fromDate(_vencimento!),
          'licenseExpiresAt': Timestamp.fromDate(_vencimento!),
        },
        // `createdAt` é obrigatório: o índice da lista do master ordena por ele,
        // e o Firestore omite quem não tem o campo — a igreja existiria mas não
        // apareceria na lista.
        'createdAt': YahwehFv.serverTimestamp,
        'updatedAt': YahwehFv.serverTimestamp,
      };
      await YahwehDocWrite.set(ref, data, merge: false);

      // O resolvedor aceita ids fora do padrão só depois de os conhecer.
      ChurchTenantOverride.registerKnown(exactId);
      await MasterChurchesListService.invalidateAll();

      if (!mounted) return;
      // Segue direto para o cadastro completo da igreja recém-criada.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => IgrejaCadastroPage(
            tenantId: exactId,
            role: 'adm',
            exactTenant: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _erro = 'Não foi possível criar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(title: const Text('Nova igreja')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 40),
        children: [
          MasterPremiumCard(
            expandWidth: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Identidade da igreja',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Depois de criar, abre o cadastro completo para logo, '
                  'endereço, contactos e links públicos.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nomeCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo da igreja *',
                    prefixIcon: Icon(Icons.church_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _idCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                  ],
                  onChanged: (_) => _idEditadoManualmente = true,
                  decoration: const InputDecoration(
                    labelText: 'ID único (Firestore e Storage) *',
                    helperText:
                        'Gerado do nome. Não muda depois — a mídia fica em '
                        'igrejas/{id}/, renomear partiria os ficheiros.',
                    helperMaxLines: 3,
                    prefixIcon: Icon(Icons.key_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _plano,
                  decoration: const InputDecoration(
                    labelText: 'Plano',
                    prefixIcon: Icon(Icons.card_membership_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'inicial', child: Text('Inicial')),
                    DropdownMenuItem(value: 'premium', child: Text('Premium')),
                  ],
                  onChanged: (v) => setState(() => _plano = v ?? 'free'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _vencimento ?? now.add(const Duration(days: 30)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365 * 5)),
                    );
                    if (d != null) setState(() => _vencimento = d);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    alignment: Alignment.centerLeft,
                  ),
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    _vencimento == null
                        ? 'Vencimento (opcional)'
                        : 'Vence em ${_vencimento!.day.toString().padLeft(2, '0')}/'
                              '${_vencimento!.month.toString().padLeft(2, '0')}/'
                              '${_vencimento!.year}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          MasterPremiumCard(
            expandWidth: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Responsável (opcional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quem vai gerir a igreja. Pode ficar para depois — o acesso '
                  'é dado em «Ativar gestores».',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: ThemeCleanPremium.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _gestorNomeCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome do gestor',
                    prefixIcon: Icon(Icons.person_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gestorEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do gestor',
                    prefixIcon: Icon(Icons.mail_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gestorTelefoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone / WhatsApp',
                    prefixIcon: Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ThemeCleanPremium.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ThemeCleanPremium.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: ThemeCleanPremium.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _erro!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ThemeCleanPremium.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _criar,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add_business_rounded),
            label: Text(
              _saving ? 'A criar…' : 'Criar e abrir cadastro completo',
            ),
          ),
        ],
      ),
    );
  }
}
