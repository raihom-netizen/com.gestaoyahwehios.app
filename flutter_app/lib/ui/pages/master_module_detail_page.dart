import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

class MasterModuleDetailPage extends StatelessWidget {
  const MasterModuleDetailPage({
    super.key,
    required this.tenantId,
    required this.moduleLabel,
  });
  final String tenantId;
  final String moduleLabel;

  String? get _collection {
    switch (moduleLabel) {
      case 'Membros':
        return ChurchDataPaths.membros;
      case 'Cartões de membro':
        return ChurchDataPaths.cartoes;
      case 'Eventos':
        return ChurchDataPaths.eventos;
      case 'Visitantes':
        return 'visitantes';
      case 'Orações':
        return ChurchDataPaths.pedidosOracao;
      case 'Patrimônio':
        return ChurchDataPaths.patrimonio;
      case 'Financeiro':
        return ChurchDataPaths.financeiro;
      default:
        return null;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final collection = _collection;
    if (collection == null || tenantId.trim().isEmpty) {
      return const [];
    }
    final snap = await firebaseDefaultFirestore
        .collection(ChurchDataPaths.rootCollection)
        .doc(tenantId.trim())
        .collection(collection)
        .limit(80)
        .get();
    return snap.docs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        title: Text(moduleLabel),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Não foi possível carregar $moduleLabel.'),
            );
          }
          final docs = snap.data ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Text('Nenhum registro encontrado em $moduleLabel.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final title = _title(data, docs[index].id);
              final subtitle = _subtitle(data);
              final photo = _photo(data);
              return Card(
                elevation: 0,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: photo.isEmpty
                      ? CircleAvatar(
                          child: Text(
                            title.isEmpty ? '?' : title[0].toUpperCase(),
                          ),
                        )
                      : CircleAvatar(backgroundImage: NetworkImage(photo)),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showRecord(context, data, title),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _title(Map<String, dynamic> data, String fallback) {
    for (final key in const [
      'NOME_COMPLETO',
      'nome',
      'title',
      'titulo',
      'descricao',
      'description',
      'fornecedor',
      'categoria',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  String _subtitle(Map<String, dynamic> data) {
    for (final key in const [
      'TELEFONES',
      'telefone',
      'whatsapp',
      'status',
      'STATUS',
      'local',
      'location',
      'valor',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return 'Registro do módulo';
  }

  String _photo(Map<String, dynamic> data) {
    for (final key in const [
      'fotoUrl',
      'photoUrl',
      'photoURL',
      'imageUrl',
      'coverUrl',
      'url',
    ]) {
      final value = (data[key] ?? '').toString().trim();
      if (value.startsWith('http')) return value;
    }
    return '';
  }

  void _showRecord(
    BuildContext context,
    Map<String, dynamic> data,
    String title,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                ...data.entries
                    .where(
                      (e) =>
                          e.value != null &&
                          e.value.toString().trim().isNotEmpty,
                    )
                    .take(24)
                    .map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
