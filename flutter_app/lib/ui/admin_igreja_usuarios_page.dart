import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/pages/member_card_page.dart';
import 'package:gestao_yahweh/ui/pages/members_page.dart';

/// Painel Master — Usuários da igreja: lista todos os membros/usuários de um tenant para monitorar ou editar.
class AdminIgrejaUsuariosPage extends StatefulWidget {
  final String tenantId;
  final String nomeIgreja;

  const AdminIgrejaUsuariosPage({
    super.key,
    required this.tenantId,
    required this.nomeIgreja,
  });

  @override
  State<AdminIgrejaUsuariosPage> createState() => _AdminIgrejaUsuariosPageState();
}

class _MemberRow {
  final String id;
  final Map<String, dynamic> data;
  _MemberRow(this.id, this.data);

  String get nome => (data['NOME_COMPLETO'] ?? data['nome'] ?? data['name'] ?? id).toString();
  String get funcao => (data['funcao'] ?? data['FUNCAO'] ?? data['cargo'] ?? data['role'] ?? 'Membro').toString();
  String get status => (data['status'] ?? data['STATUS'] ?? data['ativo'] == true ? 'ativo' : 'inativo').toString();
}

class _AdminIgrejaUsuariosPageState extends State<AdminIgrejaUsuariosPage> {
  bool _loading = true;
  List<_MemberRow> _members = [];
  String _busca = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resolved = await TenantResolverService.resolveEffectiveTenantId(widget.tenantId);
      final tenantId = resolved.isNotEmpty ? resolved : widget.tenantId;
      List<String> allIds = await TenantResolverService.getAllTenantIdsWithSameSlugOrAlias(tenantId);
      if (widget.tenantId.trim().isNotEmpty && !allIds.contains(widget.tenantId)) allIds = [widget.tenantId, ...allIds];
      final db = FirebaseFirestore.instance;
      final seen = <String>{};
      final list = <_MemberRow>[];

      void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        if (seen.contains(d.id)) return;
        seen.add(d.id);
        list.add(_MemberRow(d.id, d.data()));
      }

      for (final tid in allIds) {
        try {
          final membrosSnap = await db.collection('igrejas').doc(tid).collection('membros').get();
          for (final d in membrosSnap.docs) addDoc(d);
        } catch (_) {}
        // Usuários dentro da igreja: subcoleção igrejas/{id}/users (painel da igreja)
        try {
          final usersInIgreja = await db.collection('igrejas').doc(tid).collection('users').get();
          for (final d in usersInIgreja.docs) addDoc(d);
        } catch (_) {}
        // users (raiz) com tenantId/igrejaId apontando para esta igreja
        try {
          final usersT = await db.collection('users').where('tenantId', isEqualTo: tid).get();
          for (final d in usersT.docs) addDoc(d);
        } catch (_) {}
        try {
          final usersI = await db.collection('users').where('igrejaId', isEqualTo: tid).get();
          for (final d in usersI.docs) addDoc(d);
        } catch (_) {}
      }

      list.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      setState(() {
        _members = list;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _members = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _busca.trim().toLowerCase();
    final filtrados = q.isEmpty
        ? _members
        : _members.where((m) =>
            m.nome.toLowerCase().contains(q) ||
            m.funcao.toLowerCase().contains(q) ||
            m.status.toLowerCase().contains(q)).toList();
    final isMobile = ThemeCleanPremium.isMobile(context);
    final padding = ThemeCleanPremium.pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Usuários — ${widget.nomeIgreja}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Abrir lista completa para editar',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MembersPage(tenantId: widget.tenantId, role: 'master'),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: padding,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar por nome, função ou status...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'Total: ${filtrados.length}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtrados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  _members.isEmpty
                                      ? 'Nenhum usuário/membro nesta igreja.'
                                      : 'Nenhum resultado para a busca.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: filtrados.length,
                            itemBuilder: (_, i) {
                              final m = filtrados[i];
                              final ativo = m.status.toLowerCase() == 'ativo';
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MemberCardPage(
                                          tenantId: widget.tenantId,
                                          role: 'master',
                                          memberId: m.id,
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: ativo
                                              ? ThemeCleanPremium.primary.withOpacity(0.15)
                                              : Colors.grey.shade300,
                                          child: Icon(
                                            Icons.person_rounded,
                                            color: ativo ? ThemeCleanPremium.primary : Colors.grey.shade600,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                m.nome,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${m.funcao} • ${m.status}',
                                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
                                      ],
                                    ),
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
