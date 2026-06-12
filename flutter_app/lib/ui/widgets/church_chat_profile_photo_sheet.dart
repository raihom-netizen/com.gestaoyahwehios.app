import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/member_profile_photo_pick_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart' show imageUrlFromMap;

/// Abre editor de foto de perfil (tela cheia — estável com galeria Android).
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
  final churchId = ChurchRepository.churchId(tenantId.trim());
  if (data.isEmpty && churchId.isNotEmpty) {
    final snap =
        await ChurchUiCollections.membros(churchId).doc(memberDocId).get();
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
  return Navigator.of(context, rootNavigator: true).push<MemberProfilePhotoUpdateResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MemberProfilePhotoEditorPage(
        tenantId: tenantId,
        churchId: churchId.isNotEmpty ? churchId : tenantId.trim(),
        memberId: memberDocId,
        initialData: data,
      ),
    ),
  );
}

/// Folha para trocar a foto de perfil — actualiza cadastro + chat.
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

/// Editor premium — foto de perfil membro (Membros + chat).
class MemberProfilePhotoEditorPage extends StatefulWidget {
  const MemberProfilePhotoEditorPage({
    super.key,
    required this.tenantId,
    required this.churchId,
    required this.memberId,
    required this.initialData,
  });

  final String tenantId;
  final String churchId;
  final String memberId;
  final Map<String, dynamic> initialData;

  @override
  State<MemberProfilePhotoEditorPage> createState() =>
      _MemberProfilePhotoEditorPageState();
}

class _MemberProfilePhotoEditorPageState extends State<MemberProfilePhotoEditorPage> {
  Uint8List? _previewBytes;
  bool _uploading = false;
  bool _picking = false;
  String? _pickedFileName;

  @override
  void initState() {
    super.initState();
    unawaited(ImmediateMediaWarm.warmFeed());
  }

  String get _memberName =>
      (widget.initialData['NOME_COMPLETO'] ?? widget.initialData['nome'] ?? 'Membro')
          .toString()
          .trim();

  String? get _authUid {
    final u = (widget.initialData['authUid'] ?? widget.initialData['firebaseUid'] ?? '')
        .toString()
        .trim();
    return u.isEmpty ? null : u;
  }

  Future<void> _pickFromGallery() async {
    if (_uploading || _picking) return;
    setState(() => _picking = true);
    try {
      final hit = await MemberProfilePhotoPickService.pickFromGallery(context);
      if (!mounted) return;
      if (hit == null) return;
      setState(() {
        _previewBytes = hit.bytes;
        _pickedFileName = hit.displayName;
      });
      ImmediateMediaAttachFeedback.showArquivoAnexado(context, hit.displayName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Não foi possível escolher a imagem: $e'),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_uploading || _picking || kIsWeb) return;
    setState(() => _picking = true);
    try {
      final hit = await MemberProfilePhotoPickService.pickFromCamera(context);
      if (!mounted) return;
      if (hit == null) return;
      setState(() {
        _previewBytes = hit.bytes;
        _pickedFileName = hit.displayName;
      });
      ImmediateMediaAttachFeedback.showArquivoAnexado(context, hit.displayName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Não foi possível usar a câmera: $e'),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final bytes = _previewBytes;
    if (bytes == null || bytes.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    try {
      final snap = await ChurchUiCollections.membros(widget.churchId)
          .doc(widget.memberId)
          .get();
      final data = snap.data() ?? widget.initialData;
      final result = await MemberProfilePhotoUpdateService.uploadAndPatchMember(
        tenantId: widget.churchId,
        memberDocId: widget.memberId,
        memberData: data,
        rawBytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Foto de perfil actualizada!'),
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

  Widget _previewAvatar() {
    final preview = _previewBytes;
    if (preview != null && preview.isNotEmpty) {
      return Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(color: ThemeCleanPremium.primary.withValues(alpha: 0.25), width: 3),
        ),
        child: ClipOval(
          child: Image.memory(
            preview,
            key: ValueKey<int>(preview.length),
            width: 132,
            height: 132,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: FotoMembroWidget(
        size: 132,
        tenantId: widget.churchId,
        memberId: widget.memberId,
        memberData: widget.initialData,
        authUid: _authUid,
        imageUrl: imageUrlFromMap(widget.initialData),
        memCacheWidth: 320,
        memCacheHeight: 320,
        preferListThumbnail: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPreview = _previewBytes != null && _previewBytes!.isNotEmpty;
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: ThemeCleanPremium.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Voltar',
          onPressed: _uploading ? null : () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Foto de perfil',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: ThemeCleanPremium.pagePadding(context),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                children: [
                  Text(
                    'A mesma foto no módulo Membros e no chat — actualiza automaticamente em conversas e grupos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ThemeCleanPremium.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      _previewAvatar(),
                      if (_picking)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _memberName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (hasPreview && (_pickedFileName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _pickedFileName!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PhotoSourceCard(
                    icon: Icons.photo_library_rounded,
                    label: kIsWeb ? 'Arquivo' : 'Galeria',
                    tint: const Color(0xFF5B8DEF),
                    onTap: (_uploading || _picking) ? null : _pickFromGallery,
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PhotoSourceCard(
                      icon: Icons.photo_camera_rounded,
                      label: 'Câmera',
                      tint: const Color(0xFF34A853),
                      onTap: (_uploading || _picking) ? null : _pickFromCamera,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: (hasPreview && !_uploading && !_picking) ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                ),
              ),
              icon: _uploading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_uploading ? 'A enviar…' : 'Guardar foto'),
            ),
            if (!hasPreview)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Escolha uma foto na galeria ou câmera para activar «Guardar foto».',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.9),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceCard extends StatelessWidget {
  const _PhotoSourceCard({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            border: Border.all(color: tint.withValues(alpha: 0.22)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tint, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.onSurface,
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
