import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;
import 'package:image_picker/image_picker.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';

/// Folha para trocar foto de um membro (próprio ou equipe no módulo Membros).
Future<MemberProfilePhotoUpdateResult?> showMemberProfilePhotoEditorSheet(
  BuildContext context, {
  required String tenantId,
  required String memberDocId,
  Map<String, dynamic>? initialData,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Faça login para alterar a foto.')),
    );
    return null;
  }
  Map<String, dynamic> data = Map<String, dynamic>.from(initialData ?? {});
  if (data.isEmpty) {
    final op = await ChurchOperationalPaths.resolveCached(tenantId.trim());
    final snap = await         ChurchUiCollections.membros(op)
        .doc(memberDocId)
        .get();
    if (!context.mounted) return null;
    if (!snap.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro de membro não encontrado.')),
      );
      return null;
    }
    data = snap.data() ?? {};
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<MemberProfilePhotoUpdateResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ChurchChatProfilePhotoSheet(
      tenantId: tenantId,
      memberId: memberDocId,
      initialData: data,
    ),
  );
}

/// Folha para trocar a foto de perfil — actualiza o cadastro do membro e o chat (iOS/Android/web).
Future<MemberProfilePhotoUpdateResult?> showChurchChatProfilePhotoSheet(
  BuildContext context, {
  required String tenantId,
  String? cpfDigits,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Faça login para alterar a foto.')),
    );
    return null;
  }
  final mem = await MemberProfilePhotoUpdateService.resolveMemberDoc(
    tenantId: tenantId,
    authUid: uid,
    cpfDigits: cpfDigits,
  );
  if (!context.mounted) return null;
  if (mem == null || !mem.exists) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cadastro de membro não encontrado. Peça ao gestor para vincular a sua conta.',
        ),
      ),
    );
    return null;
  }

  return showMemberProfilePhotoEditorSheet(
    context,
    tenantId: tenantId,
    memberDocId: mem.id,
    initialData: mem.data() ?? {},
  );
}

class _ChurchChatProfilePhotoSheet extends StatefulWidget {
  final String tenantId;
  final String memberId;
  final Map<String, dynamic> initialData;

  const _ChurchChatProfilePhotoSheet({
    required this.tenantId,
    required this.memberId,
    required this.initialData,
  });

  @override
  State<_ChurchChatProfilePhotoSheet> createState() =>
      _ChurchChatProfilePhotoSheetState();
}

class _ChurchChatProfilePhotoSheetState extends State<_ChurchChatProfilePhotoSheet> {
  Uint8List? _previewBytes;
  bool _uploading = false;
  MemberProfilePhotoUpdateResult? _uploadedResult;

  @override
  void initState() {
    super.initState();
    unawaited(ImmediateMediaWarm.warmFeed());
  }

  Future<void> _uploadInBackground(Uint8List bytes) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final op = await ChurchOperationalPaths.resolveCached(widget.tenantId.trim());
      final snap = await           ChurchUiCollections.membros(op)
          .doc(widget.memberId)
          .get();
      final data = snap.data() ?? widget.initialData;
      await           ChurchUiCollections.membros(op)
          .doc(widget.memberId)
          .set(
        MemberProfilePhotoUpdateService.pendingUploadPatchFields(),
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() => _uploading = false);
      ImmediateMediaAttachFeedback.showEnviadoEVinculado(context);
      MemberProfilePhotoUpdateService.scheduleBackgroundPhotoUpload(
        tenantId: widget.tenantId,
        memberDocId: widget.memberId,
        memberData: data,
        rawBytes: bytes,
        onSuccess: (result) {
          if (!mounted) return;
          setState(() => _uploadedResult = result);
        },
        onError: (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.feedbackSnackBar('Erro ao enviar foto: $e'),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao enviar foto: $e'),
      );
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_uploading) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (file == null) return;
      final bytes = await SafeImageBytes.memberProfileFromPicker(file);
      if (!mounted) return;
      setState(() => _previewBytes = bytes);
      ImmediateMediaAttachFeedback.showArquivoAnexado(
        context,
        file.name.isNotEmpty ? file.name : 'foto_perfil.jpg',
      );
      unawaited(_uploadInBackground(bytes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível escolher a imagem: $e')),
      );
    }
  }

  Future<void> _save() async {
    final done = _uploadedResult;
    if (done != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Foto actualizada no chat e no cadastro de membro.',
        ),
      );
      Navigator.pop(context, done);
      return;
    }
    final bytes = _previewBytes;
    if (bytes == null || bytes.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    try {
      final op = await ChurchOperationalPaths.resolveCached(widget.tenantId.trim());
      final snap = await           ChurchUiCollections.membros(op)
          .doc(widget.memberId)
          .get();
      final data = snap.data() ?? widget.initialData;
      final result = await MemberProfilePhotoUpdateService.uploadAndPatchMember(
        tenantId: widget.tenantId,
        memberDocId: widget.memberId,
        memberData: data,
        rawBytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _previewBytes = null;
        _uploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Foto actualizada no chat e no cadastro de membro.',
        ),
      );
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao enviar foto: $e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.38,
      maxChildSize: 0.88,
      expand: false,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:                 ChurchUiCollections.membros(widget.tenantId)
                .doc(widget.memberId)
                .watchSafe(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? widget.initialData;
              final nome = (data['NOME_COMPLETO'] ?? data['nome'] ?? 'Membro')
                  .toString()
                  .trim();
              final authUid =
                  (data['authUid'] ?? data['firebaseUid'] ?? '').toString();
              return ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Foto de perfil',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A mesma foto do módulo Membros — actualiza automaticamente no chat (conversas, grupos e mensagens).',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FotoMembroWidget(
                      size: 120,
                      tenantId: widget.tenantId,
                      memberId: widget.memberId,
                      memberData: data,
                      authUid: authUid.isEmpty ? null : authUid,
                      imageUrl: imageUrlFromMap(data),
                      memoryPreviewBytes: _previewBytes,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      preferListThumbnail: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      nome,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _uploading
                              ? null
                              : () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeria'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _uploading
                              ? null
                              : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Câmera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (_previewBytes != null && !_uploading)
                        ? _save
                        : null,
                    icon: _uploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _uploading ? 'A enviar…' : 'Guardar foto',
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
