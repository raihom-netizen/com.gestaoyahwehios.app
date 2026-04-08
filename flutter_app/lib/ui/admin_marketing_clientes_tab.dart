import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/marketing_clientes_showcase_section.dart';

DocumentReference<Map<String, dynamic>> get _marketingClientesDocRef =>
    FirebaseFirestore.instance
        .collection(MarketingStorageLayout.firestoreCollection)
        .doc(MarketingStorageLayout.firestoreMarketingClientesDocId);

List<Map<String, dynamic>> _cloneItems(Map<String, dynamic>? data) {
  final raw = data?['items'];
  if (raw is! List) return [];
  return raw
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

String _uniqueEntryId(String base, List<Map<String, dynamic>> existing) {
  var id = MarketingStorageLayout.sanitizeClienteEntryId(base);
  if (id == 'cliente' || id.isEmpty) {
    id = 'igreja_${DateTime.now().millisecondsSinceEpoch}';
  }
  final ids = existing.map((e) => (e['id'] ?? '').toString()).toSet();
  if (!ids.contains(id)) return id;
  var n = 2;
  while (ids.contains('${id}_$n')) {
    n++;
  }
  return '${id}_$n';
}

int _parseOrdem(dynamic v) {
  if (v is num) return v.toInt();
  return 0;
}

/// Aba Master: igrejas em destaque no site (`app_public/marketing_clientes` + Storage em `igrejas/{tenantId}/marketing_destaque/`).
class AdminMarketingClientesTab extends StatefulWidget {
  const AdminMarketingClientesTab({super.key});

  @override
  State<AdminMarketingClientesTab> createState() =>
      _AdminMarketingClientesTabState();
}

class _AdminMarketingClientesTabState extends State<AdminMarketingClientesTab> {
  final _sectionTitleCtrl = TextEditingController();
  bool _titleDirty = false;

  @override
  void dispose() {
    _sectionTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSectionTitle() async {
    final t = _sectionTitleCtrl.text.trim();
    try {
      await _marketingClientesDocRef.set(
        {
          'sectionTitle': t,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() => _titleDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Título da seção atualizado.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  Future<void> _persistItems(List<Map<String, dynamic>> items) async {
    await _marketingClientesDocRef.set(
      {
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _openEditor({
    required List<Map<String, dynamic>> currentItems,
    Map<String, dynamic>? existing,
  }) async {
    final ref = existing;
    final isEdit = ref != null;
    final idCtrl = TextEditingController(
      text: (ref?['id'] ?? '').toString(),
    );
    final nomeCtrl = TextEditingController(
      text: (ref?['nomeIgreja'] ?? '').toString(),
    );
    final pastorCtrl = TextEditingController(
      text: (ref?['pastor'] ?? '').toString(),
    );
    final gestorCtrl = TextEditingController(
      text: (ref?['gestor'] ?? '').toString(),
    );
    final whatsCtrl = TextEditingController(
      text: (ref?['whatsapp'] ?? '').toString(),
    );
    final siteCtrl = TextEditingController(
      text: (ref?['sitePublico'] ?? '').toString(),
    );
    final locCtrl = TextEditingController(
      text: (ref?['localizacao'] ?? '').toString(),
    );
    final igrejaTenantIdCtrl = TextEditingController(
      text: (ref?['igrejaTenantId'] ?? ref?['tenantId'] ?? '').toString(),
    );
    final ordemCtrl = TextEditingController(
      text: '${_parseOrdem(ref?['ordem'])}',
    );
    var ativo = ref?['ativo'] != false;
    String? pendingFotoPath = (ref?['fotoPath'] as String?)?.trim();
    String? pendingFotoUrl = (ref?['fotoUrl'] as String?)?.trim();
    Uint8List? pendingBytes;
    var uploading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          final tidHint = igrejaTenantIdCtrl.text.trim();
          final pathPreview = tidHint.isNotEmpty
              ? ChurchStorageLayout.marketingClienteShowcaseCapaPath(tidHint)
              : 'Legado (só leitura): ${MarketingStorageLayout.legacyClienteShowcasePhotoPath(
                  idCtrl.text.trim().isEmpty
                      ? 'id_lista'
                      : MarketingStorageLayout.sanitizeClienteEntryId(
                          idCtrl.text.trim(),
                        ),
                )}';
          return AlertDialog(
            title: Text(isEdit ? 'Editar igreja em destaque' : 'Nova igreja em destaque'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Capa canónica: só capa.jpg (sem thumb_capa). Com ID da igreja: igrejas/{id}/marketing_destaque/capa.jpg. '
                      'Legado: ${MarketingStorageLayout.clientesRootPrefix}/[id_pasta]/capa.jpg — mesmo URL que o site público usa.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Resolvido: $pathPreview',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: igrejaTenantIdCtrl,
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(
                        labelText: 'ID Firestore da igreja (obrigatório ao enviar capa)',
                        hintText: 'ex.: igreja_o_brasil_para_cristo_jardim_goiano',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idCtrl,
                      onChanged: (_) => setLocal(() {}),
                      enabled: !isEdit,
                      decoration: InputDecoration(
                        labelText: 'ID da pasta (único)',
                        hintText: isEdit
                            ? null
                            : 'Opcional — se vazio, gera a partir do nome',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nomeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nome da igreja',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pastorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pastor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: gestorCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Gestor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: whatsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp',
                        hintText: 'DDD + número',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: siteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Site público',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Localização',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ordemCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ordem (menor aparece primeiro)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativo no site'),
                      value: ativo,
                      onChanged: (v) => setLocal(() => ativo = v),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: uploading
                          ? null
                          : () async {
                              final pick = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: const [
                                  'jpg',
                                  'jpeg',
                                  'png',
                                  'webp',
                                ],
                                withData: true,
                              );
                              if (pick == null ||
                                  pick.files.isEmpty ||
                                  pick.files.first.bytes == null) {
                                return;
                              }
                              setLocal(() {
                                pendingBytes = pick.files.first.bytes;
                              });
                            },
                      icon: const Icon(Icons.photo_outlined),
                      label: Text(
                        pendingBytes != null
                            ? 'Nova foto selecionada'
                            : 'Escolher foto de capa',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: uploading ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: uploading
                    ? null
                    : () async {
                        late String entryId;
                        if (!isEdit) {
                          final rawId = idCtrl.text.trim();
                          if (rawId.isNotEmpty) {
                            entryId = _uniqueEntryId(rawId, currentItems);
                          } else {
                            final base = nomeCtrl.text.trim().isNotEmpty
                                ? nomeCtrl.text.trim()
                                : 'igreja';
                            entryId = _uniqueEntryId(base, currentItems);
                          }
                        } else {
                          var raw = idCtrl.text.trim();
                          raw = MarketingStorageLayout.sanitizeClienteEntryId(
                            raw.isNotEmpty ? raw : 'cliente',
                          );
                          entryId = raw;
                        }

                        final nome = nomeCtrl.text.trim();
                        if (nome.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Informe o nome da igreja.'),
                            ),
                          );
                          return;
                        }

                        final tenantRaw = igrejaTenantIdCtrl.text.trim();
                        if (pendingBytes != null &&
                            pendingBytes!.isNotEmpty &&
                            tenantRaw.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Informe o ID Firestore da igreja (igrejas/…) para gravar a capa no Storage correto.',
                              ),
                            ),
                          );
                          return;
                        }

                        setLocal(() => uploading = true);
                        String? photoPath;

                        try {
                          if (pendingBytes != null && pendingBytes!.isNotEmpty) {
                            photoPath = ChurchStorageLayout
                                .marketingClienteShowcaseCapaPath(tenantRaw);
                            final oldPath =
                                (ref?['fotoPath'] ?? '').toString().trim();
                            if (oldPath.isNotEmpty && oldPath != photoPath) {
                              try {
                                await FirebaseStorage.instance
                                    .ref(oldPath)
                                    .delete();
                              } catch (_) {}
                              if (oldPath.endsWith('/capa.jpg')) {
                                final parent = oldPath.substring(
                                    0, oldPath.length - '/capa.jpg'.length);
                                try {
                                  await FirebaseStorage.instance
                                      .ref('$parent/thumb_capa.jpg')
                                      .delete();
                                } catch (_) {}
                              }
                            }
                            final storageRef =
                                FirebaseStorage.instance.ref(photoPath);
                            final task = storageRef.putData(
                              pendingBytes!,
                              SettableMetadata(
                                contentType: 'image/jpeg',
                                cacheControl: 'public, max-age=31536000',
                              ),
                            );
                            await task;
                            String? downloadUrl;
                            try {
                              downloadUrl = await storageRef.getDownloadURL();
                            } catch (_) {}
                            pendingFotoPath = photoPath;
                            pendingFotoUrl = downloadUrl;
                            AppStorageImageService.instance.invalidate(
                              storagePath: photoPath,
                            );
                            if (downloadUrl != null &&
                                downloadUrl!.trim().isNotEmpty) {
                              AppStorageImageService.instance.invalidate(
                                imageUrl: downloadUrl!.trim(),
                              );
                            }
                            final prevUrl =
                                (ref?['fotoUrl'] as String?)?.trim() ?? '';
                            if (prevUrl.isNotEmpty &&
                                prevUrl != (downloadUrl ?? '').trim()) {
                              AppStorageImageService.instance.invalidate(
                                imageUrl: prevUrl,
                              );
                            }
                          }

                          final ordem = int.tryParse(ordemCtrl.text.trim()) ?? 0;
                          final next = Map<String, dynamic>.from(ref ?? {});
                          next.addAll({
                            'id': entryId,
                            'nomeIgreja': nome,
                            'igrejaTenantId': tenantRaw,
                            'pastor': pastorCtrl.text.trim(),
                            'gestor': gestorCtrl.text.trim(),
                            'whatsapp': whatsCtrl.text.trim(),
                            'sitePublico': siteCtrl.text.trim(),
                            'localizacao': locCtrl.text.trim(),
                            'ordem': ordem,
                            'ativo': ativo,
                            if (pendingFotoPath != null && pendingFotoPath!.isNotEmpty)
                              'fotoPath': pendingFotoPath,
                            if (pendingFotoUrl != null && pendingFotoUrl!.isNotEmpty)
                              'fotoUrl': pendingFotoUrl,
                          });

                          final list = _cloneItems(
                            (await _marketingClientesDocRef.get()).data(),
                          );
                          if (ref != null) {
                            final oldId = (ref['id'] ?? '').toString();
                            final idx = list.indexWhere(
                              (e) => (e['id'] ?? '').toString() == oldId,
                            );
                            if (idx >= 0) {
                              list[idx] = next;
                            } else {
                              list.add(next);
                            }
                          } else {
                            list.add(next);
                          }
                          list.sort(
                            (a, b) => _parseOrdem(a['ordem'])
                                .compareTo(_parseOrdem(b['ordem'])),
                          );

                          await _marketingClientesDocRef.set(
                            {
                              'items': list,
                              'updatedAt': FieldValue.serverTimestamp(),
                            },
                            SetOptions(merge: true),
                          );

                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setLocal(() => uploading = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erro: $e')),
                            );
                          }
                        }
                      },
                child: uploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Lista de igrejas atualizada.'),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover igreja em destaque?'),
        content: Text(
          'Será removida da lista no site. A foto em Storage pode ser apagada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeCleanPremium.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final path = (item['fotoPath'] as String?)?.trim();
      if (path != null && path.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(path).delete();
        } catch (_) {}
        if (path.endsWith('/capa.jpg')) {
          final parent = path.substring(0, path.length - '/capa.jpg'.length);
          try {
            await FirebaseStorage.instance.ref('$parent/thumb_capa.jpg').delete();
          } catch (_) {}
        }
      } else {
        final tenant = (item['igrejaTenantId'] ?? item['tenantId'] ?? '')
            .toString()
            .trim();
        if (tenant.isNotEmpty) {
          final p =
              ChurchStorageLayout.marketingClienteShowcaseCapaPath(tenant);
          try {
            await FirebaseStorage.instance.ref(p).delete();
          } catch (_) {}
          try {
            await FirebaseStorage.instance
                .ref(
                    '${p.substring(0, p.length - '/capa.jpg'.length)}/thumb_capa.jpg')
                .delete();
          } catch (_) {}
        } else {
          final id = (item['id'] ?? '').toString();
          if (id.isNotEmpty) {
            final leg = MarketingStorageLayout.legacyClienteShowcasePhotoPath(id);
            try {
              await FirebaseStorage.instance.ref(leg).delete();
            } catch (_) {}
            try {
              await FirebaseStorage.instance
                  .ref(
                      '${leg.substring(0, leg.length - '/capa.jpg'.length)}/thumb_capa.jpg')
                  .delete();
            } catch (_) {}
          }
        }
      }

      final list = _cloneItems(
        (await _marketingClientesDocRef.get()).data(),
      );
      list.removeWhere(
        (e) => (e['id'] ?? '').toString() == (item['id'] ?? '').toString(),
      );
      await _persistItems(list);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Removido.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = ThemeCleanPremium.pagePadding(context);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _marketingClientesDocRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final items = _cloneItems(data);
        items.sort(
          (a, b) =>
              _parseOrdem(a['ordem']).compareTo(_parseOrdem(b['ordem'])),
        );

        if (!_titleDirty && snap.hasData) {
          final st = (data?['sectionTitle'] as String?) ?? '';
          if (_sectionTitleCtrl.text != st) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_titleDirty) {
                _sectionTitleCtrl.text = st;
              }
            });
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: pad.copyWith(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Igrejas em destaque',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Capas: igrejas/{ID Firestore}/marketing_destaque/capa.jpg (padrão). Entradas antigas em ${MarketingStorageLayout.clientesRootPrefix}/[id]/ continuam a ser lidas até reenviar a foto com o ID da igreja.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sectionTitleCtrl,
                    onChanged: (_) => setState(() => _titleDirty = true),
                    decoration: const InputDecoration(
                      labelText: 'Título da seção no site',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: _titleDirty ? _saveSectionTitle : null,
                      child: const Text('Salvar título'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, 8),
              child: FilledButton.icon(
                onPressed: snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData
                    ? null
                    : () => _openEditor(currentItems: items),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar igreja'),
              ),
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        pad.left,
                        0,
                        pad.right,
                        pad.bottom + 24,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: ThemeCleanPremium.spaceSm),
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final id = (it['id'] ?? '').toString();
                        final nome = (it['nomeIgreja'] ?? '').toString();
                        final active = it['ativo'] != false;
                        return Container(
                          decoration: BoxDecoration(
                            color: ThemeCleanPremium.cardBackground,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: ThemeCleanPremium.softUiCardShadow,
                            border: Border.all(
                              color: Colors.black.withOpacity(0.05),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MarketingClienteCapaThumb(
                                  key: ValueKey<String>(
                                    'adm_mkt_${id}_${it['fotoPath']}_${it['fotoUrl']}_${it['igrejaTenantId']}',
                                  ),
                                  item: Map<String, dynamic>.from(it),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(12),
                                  placeholder: Container(
                                    width: 72,
                                    height: 72,
                                    color: ThemeCleanPremium.surfaceVariant,
                                    child: const Icon(Icons.church_outlined),
                                  ),
                                  errorWidget: Container(
                                    width: 72,
                                    height: 72,
                                    color: ThemeCleanPremium.surfaceVariant,
                                    child: const Icon(Icons.church_outlined),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              nome.isEmpty ? id : nome,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          if (!active)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Inativo',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      Colors.orange.shade800,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: $id',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Editar',
                                  onPressed: () => _openEditor(
                                    currentItems: items,
                                    existing: Map<String, dynamic>.from(it),
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Excluir',
                                  onPressed: () => _confirmDelete(it),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: ThemeCleanPremium.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
