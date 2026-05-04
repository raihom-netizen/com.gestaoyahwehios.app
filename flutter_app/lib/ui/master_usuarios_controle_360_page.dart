import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/master_premium_surfaces.dart';
import 'package:intl/intl.dart';

/// Painel Master — visão 360: utilizadores `users/`, filtro por igreja e plataforma,
/// pesquisa moderna e remapeamento de UID de membro (Firebase Auth + ficha).
class MasterUsuariosControle360Page extends StatefulWidget {
  const MasterUsuariosControle360Page({super.key});

  @override
  State<MasterUsuariosControle360Page> createState() =>
      _MasterUsuariosControle360PageState();
}

class _User360Row {
  final String uid;
  final Map<String, dynamic> data;
  _User360Row(this.uid, this.data);

  String get email =>
      (data['email'] ?? data['EMAIL'] ?? '').toString().trim();
  String get nome =>
      (data['nome'] ?? data['displayName'] ?? data['name'] ?? '').toString().trim();
  String get tenantId =>
      (data['tenantId'] ?? data['igrejaId'] ?? '').toString().trim();
  String get role => (data['role'] ?? data['nivel'] ?? '').toString().trim();
  String get platform =>
      (data['lastClientPlatform'] ?? '').toString().trim().toLowerCase();
  DateTime? get platformAt {
    final v = data['lastClientPlatformAt'];
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

class _MasterUsuariosControle360PageState extends State<MasterUsuariosControle360Page> {
  bool _loading = true;
  List<_User360Row> _rows = [];
  final Map<String, String> _igrejaNomePorId = {};
  String _search = '';
  String? _filtroIgrejaId;
  String _filtroPlataforma = 'todos';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final igSnap =
          await FirebaseFirestore.instance.collection('igrejas').get();
      final map = <String, String>{};
      for (final d in igSnap.docs) {
        final n =
            (d.data()['name'] ?? d.data()['nome'] ?? d.id).toString().trim();
        map[d.id] = n.isEmpty ? d.id : n;
      }

      final usersSnap =
          await FirebaseFirestore.instance.collection('users').limit(1200).get();
      final list = usersSnap.docs
          .map((d) => _User360Row(d.id, d.data()))
          .toList()
        ..sort((a, b) {
          final ta = a.platformAt;
          final tb = b.platformAt;
          if (ta != null && tb != null) return tb.compareTo(ta);
          if (ta != null) return -1;
          if (tb != null) return 1;
          return a.email.toLowerCase().compareTo(b.email.toLowerCase());
        });

      setState(() {
        _igrejaNomePorId
          ..clear()
          ..addAll(map);
        _rows = list;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _rows = [];
        _loading = false;
      });
    }
  }

  List<_User360Row> get _filtrados {
    final q = _search.trim().toLowerCase();
    return _rows.where((r) {
      if (_filtroIgrejaId != null && _filtroIgrejaId!.isNotEmpty) {
        if (r.tenantId != _filtroIgrejaId) return false;
      }
      if (_filtroPlataforma != 'todos') {
        final p = r.platform.isEmpty ? 'desconhecido' : r.platform;
        if (_filtroPlataforma == 'desconhecido') {
          if (r.platform.isNotEmpty) return false;
        } else if (p != _filtroPlataforma) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return r.uid.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.nome.toLowerCase().contains(q) ||
          r.tenantId.toLowerCase().contains(q) ||
          (_igrejaNomePorId[r.tenantId] ?? '')
              .toLowerCase()
              .contains(q);
    }).toList();
  }

  Future<void> _abrirRemapearUid() async {
    final tenantCtrl = TextEditingController();
    final memberCtrl = TextEditingController();
    final newUidCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Text('Remapear UID do membro (master)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Associa a ficha em igrejas/{tenant}/membros ao UID já existente no Firebase Auth. '
                'O login antigo deixa de existir para esse membro.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tenantCtrl,
                decoration: const InputDecoration(
                  labelText: 'tenantId da igreja',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: memberCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID do documento membros (ou authUid antigo)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newUidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Novo UID (Firebase Auth)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Executar'),
          ),
        ],
      ),
    );
    final tid = tenantCtrl.text.trim();
    final mid = memberCtrl.text.trim();
    final nu = newUidCtrl.text.trim();
    tenantCtrl.dispose();
    memberCtrl.dispose();
    newUidCtrl.dispose();
    if (ok != true || !mounted) return;
    if (tid.isEmpty || mid.isEmpty || nu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Preencha todos os campos.'),
      );
      return;
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('masterRelinkMembroAuthUid')
          .call({
        'tenantId': tid,
        'memberId': mid,
        'newAuthUid': nu,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('UID remapeado. Peça novo login ao utilizador.'),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha: $e')),
        );
      }
    }
  }

  IconData _platformIcon(String p) {
    switch (p) {
      case 'web':
        return Icons.language_rounded;
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final filtrados = _filtrados;

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: const Text('Controle 360 — Utilizadores'),
        actions: [
          IconButton(
            tooltip: 'Atualizar lista',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _abrirRemapearUid,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Remapear UID membro'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: pad,
                    child: MasterPremiumCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.threesixty_rounded,
                                  color: ThemeCleanPremium.primary, size: 28),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Todos os utilizadores com doc em users/',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Plataforma = última sessão no painel da igreja (web / Android / iOS). '
                            'Abra o app para popular dados.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText:
                                  'Pesquisar por e-mail, nome, UID, igreja…',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: kIsWeb ? 320 : double.infinity,
                                child: DropdownButtonFormField<String?>(
                                  decoration: InputDecoration(
                                    labelText: 'Igreja',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  value: _filtroIgrejaId,
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Todas as igrejas'),
                                    ),
                                    ..._igrejaNomePorId.entries.map(
                                      (e) => DropdownMenuItem<String?>(
                                        value: e.key,
                                        child: Text(
                                          e.value,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _filtroIgrejaId = v),
                                ),
                              ),
                              ChoiceChip(
                                label: const Text('Todos'),
                                selected: _filtroPlataforma == 'todos',
                                onSelected: (_) => setState(
                                    () => _filtroPlataforma = 'todos'),
                              ),
                              ChoiceChip(
                                avatar: Icon(_platformIcon('web'), size: 18),
                                label: const Text('Web'),
                                selected: _filtroPlataforma == 'web',
                                onSelected: (_) => setState(
                                    () => _filtroPlataforma = 'web'),
                              ),
                              ChoiceChip(
                                avatar: Icon(_platformIcon('android'), size: 18),
                                label: const Text('Android'),
                                selected: _filtroPlataforma == 'android',
                                onSelected: (_) => setState(
                                    () => _filtroPlataforma = 'android'),
                              ),
                              ChoiceChip(
                                avatar: Icon(_platformIcon('ios'), size: 18),
                                label: const Text('iOS'),
                                selected: _filtroPlataforma == 'ios',
                                onSelected: (_) =>
                                    setState(() => _filtroPlataforma = 'ios'),
                              ),
                              ChoiceChip(
                                label: const Text('Sem dados'),
                                selected:
                                    _filtroPlataforma == 'desconhecido',
                                onSelected: (_) => setState(() =>
                                    _filtroPlataforma = 'desconhecido'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 8),
                    child: Text(
                      'Mostrando ${filtrados.length} de ${_rows.length} carregados',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtrados.isEmpty
                        ? ThemeCleanPremium.premiumEmptyState(
                            icon: Icons.people_outline_rounded,
                            title: 'Nenhum resultado',
                            subtitle: 'Ajuste filtros ou pesquisa.',
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                                pad.left, 0, pad.right, 24),
                            itemCount: filtrados.length,
                            itemBuilder: (_, i) {
                              final r = filtrados[i];
                              final igNome =
                                  _igrejaNomePorId[r.tenantId] ?? r.tenantId;
                              final plat =
                                  r.platform.isEmpty ? '—' : r.platform;
                              final when = r.platformAt != null
                                  ? df.format(r.platformAt!)
                                  : '—';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: MasterPremiumCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: ThemeCleanPremium.primary
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _platformIcon(
                                            r.platform.isEmpty
                                                ? 'out'
                                                : r.platform,
                                          ),
                                          color: ThemeCleanPremium.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.nome.isEmpty
                                                  ? '(sem nome)'
                                                  : r.nome,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              r.email.isEmpty
                                                  ? 'sem e-mail'
                                                  : r.email,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            SelectableText(
                                              'UID: ${r.uid}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Igreja: $igNome',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            if (r.role.isNotEmpty)
                                              Text(
                                                'Papel: ${r.role}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              plat.toUpperCase(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11,
                                                color: Color(0xFF4338CA),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            when,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Copiar UID',
                                            icon: const Icon(
                                                Icons.copy_rounded, size: 20),
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                ClipboardData(text: r.uid),
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  ThemeCleanPremium
                                                      .successSnackBar(
                                                    'UID copiado',
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
