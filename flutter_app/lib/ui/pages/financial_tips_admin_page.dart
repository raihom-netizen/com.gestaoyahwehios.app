import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'package:gestao_yahweh/data/biblical_finance_tips.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/utils/insights_engine.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Painel MASTER — cadastro/edição das "Dicas inteligentes" (financeiras e
/// evangélicas) exibidas no módulo Financeiro dos usuários. Escreve na coleção
/// raiz `financial_tips` (mesma lida por FinancialTipsCatalogService).
///
/// Campos por dica: título, descrição, categoria (rótulo do chip), versículo
/// (referência) e texto do versículo. `ativo` controla se aparece.
class FinancialTipsAdminPage extends StatelessWidget {
  const FinancialTipsAdminPage({super.key});

  static void open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinancialTipsAdminPage()),
    );
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection(InsightsEngine.kFinancialTipsCollection);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Dicas inteligentes',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Importar dicas bíblicas (WisdomApp)',
              icon: const Icon(Icons.cloud_download_rounded),
              onPressed: () => _importBiblical(ctx),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context, null, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova dica',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.orderBy('ordem').watchSafe(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('Nenhuma dica cadastrada.',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Toque em «Nova dica» para criar a primeira.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final titulo = (data['titulo'] ?? '').toString();
              final descricao = (data['descricao'] ?? '').toString();
              final categoria =
                  (data['categoria'] ?? data['categoriaSlug'] ?? '').toString();
              final versiculo =
                  (data['referenciaBiblica'] ?? data['versiculo'] ?? '')
                      .toString();
              final ativo = data['ativo'] != false;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Opacity(
                  opacity: ativo ? 1 : 0.55,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.lightbulb_rounded,
                          color: AppColors.primary),
                    ),
                    title: Text(
                      titulo.isEmpty ? '(sem título)' : titulo,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (categoria.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            child: Text(categoria,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                          ),
                        Text(descricao,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (versiculo.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text('📖 $versiculo',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade600)),
                          ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _openEditor(context, d.id, data);
                        } else if (v == 'toggle') {
                          await d.reference.update({'ativo': !ativo});
                        } else if (v == 'delete') {
                          final ok = await _confirmDelete(context, titulo);
                          if (ok) await d.reference.delete();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Editar')),
                        PopupMenuItem(
                            value: 'toggle',
                            child: Text(ativo ? 'Desativar' : 'Ativar')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Excluir')),
                      ],
                    ),
                    onTap: () => _openEditor(context, d.id, data),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Importa o catálogo bíblico (WisdomApp) para o Firestore, criando apenas as
  /// dicas que ainda não existem — nunca sobrescreve edições feitas no painel.
  Future<void> _importBiblical(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Importando dicas bíblicas...')),
    );
    try {
      final existing = await _col.get();
      final existingIds = existing.docs.map((d) => d.id).toSet();
      final batch = YahwehBatch();
      var novas = 0;
      for (final tip in kBiblicalFinanceTips) {
        if (existingIds.contains(tip.id)) continue;
        batch.set(_col.doc(tip.id), {
          'titulo': tip.titulo,
          'descricao': tip.descricao,
          'categoria': tip.categoriaSlug,
          'icone': tip.iconKey,
          'cor': tip.colorKey,
          'ordem': tip.ordem,
          'referenciaBiblica': tip.referenciaBiblica,
          'textoVersiculo': tip.textoVersiculo,
          'ativo': true,
          'origem': 'wisdom_biblical',
          'atualizadoEm': YahwehFv.serverTimestamp,
        });
        novas++;
      }
      if (novas > 0) await batch.commit();
      messenger.showSnackBar(
        SnackBar(
          content: Text(novas == 0
              ? 'Todas as dicas bíblicas já estavam cadastradas.'
              : '$novas dica(s) bíblica(s) importada(s) com sucesso.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao importar: $e')),
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String titulo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir dica'),
        content: Text('Excluir «${titulo.isEmpty ? 'esta dica' : titulo}»?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _openEditor(
      BuildContext context, String? id, Map<String, dynamic>? data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TipEditorSheet(col: _col, docId: id, data: data),
    );
  }
}

class _TipEditorSheet extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> col;
  final String? docId;
  final Map<String, dynamic>? data;
  const _TipEditorSheet({required this.col, this.docId, this.data});

  @override
  State<_TipEditorSheet> createState() => _TipEditorSheetState();
}

class _TipEditorSheetState extends State<_TipEditorSheet> {
  late final TextEditingController _titulo;
  late final TextEditingController _descricao;
  late final TextEditingController _categoria;
  late final TextEditingController _versiculo;
  late final TextEditingController _textoVersiculo;
  late final TextEditingController _ordem;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data ?? const {};
    _titulo = TextEditingController(text: (d['titulo'] ?? '').toString());
    _descricao = TextEditingController(text: (d['descricao'] ?? '').toString());
    _categoria = TextEditingController(
        text: (d['categoria'] ?? d['categoriaSlug'] ?? '').toString());
    _versiculo = TextEditingController(
        text: (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString());
    _textoVersiculo = TextEditingController(
        text: (d['textoVersiculo'] ?? d['citacao'] ?? '').toString());
    _ordem = TextEditingController(
        text: (d['ordem'] ?? '').toString().replaceAll('null', ''));
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    _categoria.dispose();
    _versiculo.dispose();
    _textoVersiculo.dispose();
    _ordem.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titulo.text.trim().isEmpty || _descricao.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título e descrição são obrigatórios.')),
      );
      return;
    }
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'descricao': _descricao.text.trim(),
      'categoria': _categoria.text.trim(),
      'referenciaBiblica': _versiculo.text.trim(),
      'textoVersiculo': _textoVersiculo.text.trim(),
      'ordem': int.tryParse(_ordem.text.trim()) ?? 999,
      'ativo': true,
      'atualizadoEm': FieldValue.serverTimestamp(),
    };
    try {
      if (widget.docId == null) {
        await widget.col.add(payload);
      } else {
        await widget.col.doc(widget.docId).set(payload, SetOptions(merge: true));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Voltar'),
                  ),
                  Expanded(
                    child: Text(
                      widget.docId == null ? 'Nova dica' : 'Editar dica',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 64),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
                children: [
                  _field(_titulo, 'Título', icon: Icons.title_rounded),
                  _field(_descricao, 'Descrição / conselho',
                      icon: Icons.notes_rounded, maxLines: 4),
                  _field(_categoria, 'Categoria (ex.: Para você, Evangélica)',
                      icon: Icons.label_rounded),
                  _field(_versiculo, 'Versículo (referência) — opcional',
                      icon: Icons.menu_book_rounded),
                  _field(_textoVersiculo, 'Texto do versículo — opcional',
                      icon: Icons.format_quote_rounded, maxLines: 3),
                  _field(_ordem, 'Ordem (número) — opcional',
                      icon: Icons.sort_rounded, number: true),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded),
                label: const Text('Salvar',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {IconData? icon, int maxLines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
