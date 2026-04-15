import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Índices do menu em [IgrejaCleanShell] para navegação a partir da busca.
const int kChurchShellIndexMembers = 2;
const int kChurchShellIndexMural = 6;
const int kChurchShellIndexEvents = 7;
const int kChurchShellIndexMySchedules = 10;
const int kChurchShellIndexPatrimonio = 21;

/// Resultado da busca global — [avisoDocForDirectEdit] abre o formulário sem passar pelo menu.
class ChurchGlobalSearchSelection {
  final int shellIndex;
  final String query;
  final QueryDocumentSnapshot<Map<String, dynamic>>? avisoDocForDirectEdit;

  const ChurchGlobalSearchSelection({
    required this.shellIndex,
    required this.query,
    this.avisoDocForDirectEdit,
  });
}

/// Mesma regra de edição do mural ([InstagramMural._canEdit]).
bool churchGlobalSearchCanOpenMuralAvisoEditor(String role) {
  final r = role.toLowerCase();
  return r == 'adm' ||
      r == 'admin' ||
      r == 'gestor' ||
      r == 'master' ||
      r == 'lider';
}

String _fieldStr(Map<String, dynamic>? m, List<String> keys) {
  if (m == null) return '';
  for (final k in keys) {
    final v = m[k];
    if (v != null) {
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

String _memberSearchBlob(Map<String, dynamic> m) {
  final name = _fieldStr(m, ['NOME_COMPLETO', 'nome', 'name']);
  final email = _fieldStr(m, ['EMAIL', 'email']);
  final cpf = _fieldStr(m, ['CPF', 'cpf']);
  return '$name $email $cpf'.toLowerCase();
}

String _eventSearchBlob(Map<String, dynamic> m) {
  final t = _fieldStr(m, ['title', 'titulo', 'nome']);
  final loc = _fieldStr(m, ['location', 'local', 'localizacao']);
  final body = _fieldStr(m, ['body', 'descricao', 'description', 'texto']);
  return '$t $loc $body'.toLowerCase();
}

String _patrimonioSearchBlob(Map<String, dynamic> m) {
  final nome = _fieldStr(m, ['nome']);
  final desc = _fieldStr(m, ['descricao']);
  final cat = _fieldStr(m, ['categoria']);
  final cod = _fieldStr(m, ['codigo', 'numeroSerie']);
  return '$nome $desc $cat $cod'.toLowerCase();
}

String _avisoSearchBlob(Map<String, dynamic> m) {
  final t = _fieldStr(m, ['title', 'titulo', 'nome']);
  final body = _fieldStr(m, ['text', 'texto', 'body', 'descricao']);
  return '$t $body'.toLowerCase();
}

String _trocaSearchBlob(Map<String, dynamic> m) {
  final title = _fieldStr(m, ['escalaTitle']);
  final date = _fieldStr(m, ['escalaDateLabel']);
  final sol = _fieldStr(m, ['solicitanteNome']);
  final st = _fieldStr(m, ['status']);
  return '$title $date $sol $st'.toLowerCase();
}

bool _trocaDocStillPendingForUser(Map<String, dynamic> m, String cpf11) {
  final st = (m['status'] ?? '').toString();
  if (st == 'aprovada' || st == 'recusada') return false;
  final alvo = (m['alvoCpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
  final sol = (m['solicitanteCpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
  return alvo == cpf11 || sol == cpf11;
}

bool _noticiaDocIsAviso(Map<String, dynamic> m) =>
    (m['type'] ?? 'aviso').toString().toLowerCase() == 'aviso';

/// Diálogo estilo “Comando K”: membros, eventos, avisos (mural), patrimônio.
class ChurchGlobalSearchDialog extends StatefulWidget {
  final String tenantId;
  final String userRole;
  /// CPF só dígitos (11) — habilita resultados em «trocas de escala» envolvendo o usuário.
  final String? userCpfDigits;
  final bool Function(int shellIndex) canAccessShellIndex;
  final void Function(ChurchGlobalSearchSelection selection) onSelect;

  const ChurchGlobalSearchDialog({
    super.key,
    required this.tenantId,
    required this.userRole,
    this.userCpfDigits,
    required this.canAccessShellIndex,
    required this.onSelect,
  });

  @override
  State<ChurchGlobalSearchDialog> createState() =>
      _ChurchGlobalSearchDialogState();
}

class _ChurchGlobalSearchDialogState extends State<ChurchGlobalSearchDialog> {
  final FocusNode _focus = FocusNode();
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _loadError;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _membrosDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _noticiasDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _avisoDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _patrimonioDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _trocaDocs = [];

  String _debouncedQ = '';

  static const int _debounceMs = 300;
  static const int _minChars = 2;
  static const int _maxHits = 12;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    _loadCaches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      setState(() => _debouncedQ = _ctrl.text.trim().toLowerCase());
    });
  }

  Future<void> _loadCaches() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Igreja inválida.';
        });
      }
      return;
    }

    final db = FirebaseFirestore.instance;
    final base = db.collection('igrejas').doc(tid);

    try {
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

      if (widget.canAccessShellIndex(kChurchShellIndexMembers)) {
        futures.add(base.collection('membros').limit(320).get());
      }
      if (widget.canAccessShellIndex(kChurchShellIndexEvents)) {
        futures.add(
          base
              .collection(ChurchTenantPostsCollections.noticias)
              .orderBy('startAt', descending: true)
              .limit(160)
              .get(),
        );
      }
      if (widget.canAccessShellIndex(kChurchShellIndexPatrimonio)) {
        futures.add(base.collection('patrimonio').limit(220).get());
      }
      if (widget.canAccessShellIndex(kChurchShellIndexMural)) {
        futures.add(
          base
              .collection(ChurchTenantPostsCollections.avisos)
              .orderBy('createdAt', descending: true)
              .limit(120)
              .get(),
        );
      }

      final cpfTroca = (widget.userCpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
      final loadTrocas = widget.canAccessShellIndex(kChurchShellIndexMySchedules) &&
          cpfTroca.length == 11;
      if (loadTrocas) {
        futures.add(
          base.collection('escala_trocas').where('alvoCpf', isEqualTo: cpfTroca).limit(40).get(),
        );
        futures.add(
          base
              .collection('escala_trocas')
              .where('solicitanteCpf', isEqualTo: cpfTroca)
              .limit(40)
              .get(),
        );
      }

      if (futures.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = 'Nenhum módulo pesquisável disponível para seu perfil.';
          });
        }
        return;
      }

      final snaps = await Future.wait(futures);
      var i = 0;
      if (widget.canAccessShellIndex(kChurchShellIndexMembers)) {
        _membrosDocs = snaps[i++].docs;
      }
      if (widget.canAccessShellIndex(kChurchShellIndexEvents)) {
        _noticiasDocs = snaps[i++].docs;
      }
      if (widget.canAccessShellIndex(kChurchShellIndexPatrimonio)) {
        _patrimonioDocs = snaps[i++].docs;
      }
      if (widget.canAccessShellIndex(kChurchShellIndexMural)) {
        _avisoDocs = snaps[i++].docs;
      }

      if (loadTrocas) {
        final a = snaps[i++].docs;
        final b = snaps[i++].docs;
        final seen = <String>{};
        _trocaDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in [...a, ...b]) {
          if (seen.add(d.id)) _trocaDocs.add(d);
        }
      } else {
        _trocaDocs = [];
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Falha ao carregar dados. Tente de novo.';
        });
      }
    }
  }

  void _pickMember(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final name = _fieldStr(m, ['NOME_COMPLETO', 'nome', 'name']);
    final q = name.isNotEmpty ? name : d.id;
    Navigator.of(context).pop();
    widget.onSelect(ChurchGlobalSearchSelection(
      shellIndex: kChurchShellIndexMembers,
      query: q,
    ));
  }

  void _pickEvent(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final title = _fieldStr(m, ['title', 'titulo', 'nome']);
    final q = title.isNotEmpty ? title : d.id;
    Navigator.of(context).pop();
    widget.onSelect(ChurchGlobalSearchSelection(
      shellIndex: kChurchShellIndexEvents,
      query: q,
    ));
  }

  void _pickPatrimonio(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final nome = _fieldStr(m, ['nome']);
    final q = nome.isNotEmpty ? nome : d.id;
    Navigator.of(context).pop();
    widget.onSelect(ChurchGlobalSearchSelection(
      shellIndex: kChurchShellIndexPatrimonio,
      query: q,
    ));
  }

  void _pickAviso(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final title = _fieldStr(m, ['title', 'titulo', 'nome']);
    final q = title.isNotEmpty ? title : d.id;
    final canEdit =
        churchGlobalSearchCanOpenMuralAvisoEditor(widget.userRole);
    Navigator.of(context).pop();
    if (canEdit) {
      widget.onSelect(ChurchGlobalSearchSelection(
        shellIndex: kChurchShellIndexMural,
        query: q,
        avisoDocForDirectEdit: d,
      ));
    } else {
      widget.onSelect(ChurchGlobalSearchSelection(
        shellIndex: kChurchShellIndexMural,
        query: q,
      ));
    }
  }

  void _pickTroca(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final title = _fieldStr(m, ['escalaTitle']);
    final q = title.isNotEmpty ? title : d.id;
    Navigator.of(context).pop();
    widget.onSelect(ChurchGlobalSearchSelection(
      shellIndex: kChurchShellIndexMySchedules,
      query: q,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxW = media.size.width < 560 ? media.size.width - 32.0 : 520.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: media.size.height * 0.72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: ThemeCleanPremium.primary, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: (widget.userCpfDigits ?? '').replaceAll(RegExp(r'\D'), '').length == 11
                              ? 'Membro, evento, aviso, patrimônio ou troca de escala…'
                              : 'Membro, evento, aviso ou patrimônio…',
                          border: InputBorder.none,
                          isDense: true,
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {},
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Fechar'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _loadError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                  ),
                )
              else
                Expanded(
                  child: _buildResults(),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Text(
                  'Atalhos: / · Ctrl+K ou Cmd+K · pausa ${_debounceMs}ms',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_debouncedQ.length < _minChars) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Digite pelo menos $_minChars caracteres.\n'
            'Os dados já foram carregados — a busca é instantânea após a pausa.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.35),
          ),
        ),
      );
    }

    final q = _debouncedQ;
    final hits = <Widget>[];

    void addHeader(String label) {
      if (hits.isNotEmpty) {
        hits.add(const SizedBox(height: 6));
      }
      hits.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    if (widget.canAccessShellIndex(kChurchShellIndexMembers)) {
      final matched = _membrosDocs
          .where((d) => _memberSearchBlob(d.data()).contains(q))
          .take(_maxHits)
          .toList();
      if (matched.isNotEmpty) {
        addHeader('MEMBROS');
        for (final d in matched) {
          final m = d.data();
          final name = _fieldStr(m, ['NOME_COMPLETO', 'nome', 'name']);
          final subtitle = _fieldStr(m, ['CPF', 'cpf']).isNotEmpty
              ? 'CPF ${_fieldStr(m, ['CPF', 'cpf'])}'
              : d.id;
          hits.add(_resultTile(
            icon: Icons.person_rounded,
            iconColor: const Color(0xFF6366F1),
            title: name.isEmpty ? 'Sem nome' : name,
            subtitle: subtitle,
            onTap: () => _pickMember(d),
          ));
        }
      }
    }

    if (widget.canAccessShellIndex(kChurchShellIndexEvents)) {
      final matched = _noticiasDocs
          .where((d) => !_noticiaDocIsAviso(d.data()))
          .where((d) => _eventSearchBlob(d.data()).contains(q))
          .take(_maxHits)
          .toList();
      if (matched.isNotEmpty) {
        addHeader('EVENTOS');
        for (final d in matched) {
          final m = d.data();
          final title = _fieldStr(m, ['title', 'titulo', 'nome']);
          hits.add(_resultTile(
            icon: Icons.event_rounded,
            iconColor: const Color(0xFF0EA5E9),
            title: title.isEmpty ? 'Evento' : title,
            subtitle: 'Abrir no Mural de Eventos',
            onTap: () => _pickEvent(d),
          ));
        }
      }
    }

    if (widget.canAccessShellIndex(kChurchShellIndexMural)) {
      final matched = _avisoDocs
          .where((d) => _avisoSearchBlob(d.data()).contains(q))
          .take(_maxHits)
          .toList();
      if (matched.isNotEmpty) {
        addHeader('AVISOS (MURAL)');
        for (final d in matched) {
          final m = d.data();
          final title = _fieldStr(m, ['title', 'titulo', 'nome']);
          final edit = churchGlobalSearchCanOpenMuralAvisoEditor(
              widget.userRole);
          hits.add(_resultTile(
            icon: Icons.campaign_rounded,
            iconColor: const Color(0xFF8B5CF6),
            title: title.isEmpty ? 'Aviso' : title,
            subtitle: edit ? 'Abrir para editar' : 'Abrir no Mural de Avisos',
            onTap: () => _pickAviso(d),
          ));
        }
      }
    }

    if (widget.canAccessShellIndex(kChurchShellIndexPatrimonio)) {
      final matched = _patrimonioDocs
          .where((d) => _patrimonioSearchBlob(d.data()).contains(q))
          .take(_maxHits)
          .toList();
      if (matched.isNotEmpty) {
        addHeader('PATRIMÔNIO');
        for (final d in matched) {
          final m = d.data();
          final nome = _fieldStr(m, ['nome']);
          final cat = _fieldStr(m, ['categoria']);
          hits.add(_resultTile(
            icon: Icons.inventory_2_rounded,
            iconColor: const Color(0xFF10B981),
            title: nome.isEmpty ? 'Item' : nome,
            subtitle: cat.isNotEmpty ? cat : 'Inventário',
            onTap: () => _pickPatrimonio(d),
          ));
        }
      }
    }

    final cpfQ = (widget.userCpfDigits ?? '').replaceAll(RegExp(r'\D'), '');
    if (widget.canAccessShellIndex(kChurchShellIndexMySchedules) &&
        cpfQ.length == 11 &&
        _trocaDocs.isNotEmpty) {
      final matched = _trocaDocs
          .where((d) => _trocaDocStillPendingForUser(d.data(), cpfQ))
          .where((d) => _trocaSearchBlob(d.data()).contains(q))
          .take(_maxHits)
          .toList();
      if (matched.isNotEmpty) {
        addHeader('TROCAS DE ESCALA');
        for (final d in matched) {
          final m = d.data();
          final title = _fieldStr(m, ['escalaTitle']);
          final date = _fieldStr(m, ['escalaDateLabel']);
          final st = _fieldStr(m, ['status']);
          hits.add(_resultTile(
            icon: Icons.swap_horiz_rounded,
            iconColor: const Color(0xFF7C3AED),
            title: title.isEmpty ? 'Troca' : title,
            subtitle: [
              if (date.isNotEmpty) date,
              if (st.isNotEmpty) st,
            ].join(' · '),
            onTap: () => _pickTroca(d),
          ));
        }
      }
    }

    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhum resultado para "$_debouncedQ".\n'
            'Tente outro termo ou abra o módulo correspondente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.35),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: hits,
    );
  }

  Widget _resultTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre o painel de busca global (use a partir do shell da igreja).
Future<void> showChurchGlobalSearchDialog({
  required BuildContext context,
  required String tenantId,
  required String userRole,
  String? userCpfDigits,
  required bool Function(int shellIndex) canAccessShellIndex,
  required void Function(ChurchGlobalSearchSelection selection) onSelect,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (ctx) => ChurchGlobalSearchDialog(
      tenantId: tenantId,
      userRole: userRole,
      userCpfDigits: userCpfDigits,
      canAccessShellIndex: canAccessShellIndex,
      onSelect: onSelect,
    ),
  );
}
