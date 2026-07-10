import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/member_profile_photo_save_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_pick_service.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/member_signup_premium_ui.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, sanitizeImageUrl;

/// Abre editor de foto de perfil (Membros + chat) com permissões explícitas.
Future<MemberProfilePhotoUpdateResult?> showMemberProfilePhotoEditorSheet(
  BuildContext context, {
  required String tenantId,
  required String memberDocId,
  Map<String, dynamic>? initialData,
  required bool canChangePhoto,
  required bool canRemovePhoto,
}) async {
  final uid = firebaseDefaultAuth.currentUser?.uid;
  if (uid == null || uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Faça login para alterar a foto.')),
    );
    return null;
  }
  if (!canChangePhoto && !canRemovePhoto) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sem permissão para alterar esta foto.')),
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
  return Navigator.of(context, rootNavigator: true)
      .push<MemberProfilePhotoUpdateResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MemberProfilePhotoEditorPage(
        tenantId: tenantId,
        churchId: churchId.isNotEmpty ? churchId : tenantId.trim(),
        memberId: memberDocId,
        initialData: data,
        canChangePhoto: canChangePhoto,
        canRemovePhoto: canRemovePhoto,
      ),
    ),
  );
}

/// Folha para trocar a foto de perfil — actualiza cadastro + chat.
Future<MemberProfilePhotoUpdateResult?> showChurchChatProfilePhotoSheet(
  BuildContext context, {
  required String tenantId,
  String? cpfDigits,
  bool canChangePhoto = true,
  bool canRemovePhoto = true,
}) async {
  final uid = firebaseDefaultAuth.currentUser?.uid;
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
    canChangePhoto: canChangePhoto,
    canRemovePhoto: canRemovePhoto,
  );
}

/// Editor — foto perfil membro (`igrejas/{churchId}/membros/…` + Storage canónico).
class MemberProfilePhotoEditorPage extends StatefulWidget {
  const MemberProfilePhotoEditorPage({
    super.key,
    required this.tenantId,
    required this.churchId,
    required this.memberId,
    required this.initialData,
    required this.canChangePhoto,
    required this.canRemovePhoto,
  });

  final String tenantId;
  final String churchId;
  final String memberId;
  final Map<String, dynamic> initialData;
  final bool canChangePhoto;
  final bool canRemovePhoto;

  @override
  State<MemberProfilePhotoEditorPage> createState() =>
      _MemberProfilePhotoEditorPageState();
}

class _MemberProfilePhotoEditorPageState extends State<MemberProfilePhotoEditorPage> {
  Uint8List? _previewBytes;
  bool _busy = false;
  bool _picking = false;
  String? _pickedFileName;
  String _phaseLabel = '';

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

  bool get _hasExistingPhoto {
    final url = sanitizeImageUrl(imageUrlFromMap(widget.initialData));
    if (url.isNotEmpty) return true;
    final path = (widget.initialData['photoStoragePath'] ??
            widget.initialData['fotoPath'] ??
            '')
        .toString()
        .trim();
    return path.isNotEmpty;
  }

  Future<void> _pickUnified() async {
    if (!widget.canChangePhoto || _busy || _picking) return;
    setState(() => _picking = true);
    try {
      final hit = await MemberProfilePhotoPickService.pickForMemberEdit(context);
      if (!mounted || hit == null) return;
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
    if (!widget.canChangePhoto || _busy || _picking || kIsWeb) return;
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
    if (bytes == null || bytes.isEmpty || _busy || !widget.canChangePhoto) return;
    setState(() {
      _busy = true;
      _phaseLabel = 'A preparar…';
    });
    GlobalUploadProgress.instance.start('A enviar foto de perfil…');
    try {
      Future<MemberProfilePhotoUpdateResult> publish() =>
          MemberProfilePhotoUpdateService.uploadAndPatchMember(
            tenantId: widget.tenantId,
            memberDocId: widget.memberId,
            memberData: widget.initialData,
            rawBytes: bytes,
            onPhase: (label) {
              if (mounted) setState(() => _phaseLabel = label);
              GlobalUploadProgress.instance.updateLabel(label);
            },
            onProgress: (p) => GlobalUploadProgress.instance.update(p),
          );
      final result = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(
              publish,
              maxAttempts: 2,
            )
          : await publish();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Foto de perfil actualizada!'),
      );
      Navigator.pop(context, result);
    } on MemberProfilePhotoQueuedLocally {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Foto guardada no aparelho; envio automático quando houver internet.',
        ),
      );
      Navigator.pop(context);
    } catch (e, st) {
      unawaited(CrashlyticsService.record(e, st, reason: 'membro_foto_editor_save'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao enviar foto: $e'),
      );
    } finally {
      GlobalUploadProgress.instance.end();
      if (mounted) {
        setState(() {
          _busy = false;
          _phaseLabel = '';
        });
      }
    }
  }

  Future<void> _confirmRemove() async {
    if (!widget.canRemovePhoto || _busy || !_hasExistingPhoto) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Remover foto'),
          ],
        ),
        content: Text(
          'Remover a foto de perfil de «$_memberName»? '
          'A imagem será apagada do Storage e do cadastro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _remove();
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _phaseLabel = 'A remover…';
    });
    try {
      await AppFinalizeBootstrap.ensureSessionForPublish(
        logLabel: 'membro_foto_remove',
      );
      final result = await MemberProfilePhotoUpdateService.removeProfilePhoto(
        tenantId: widget.tenantId,
        memberDocId: widget.memberId,
        memberData: widget.initialData,
        onPhase: (label) {
          if (mounted) setState(() => _phaseLabel = label);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Foto removida.'),
      );
      Navigator.pop(context, result);
    } catch (e, st) {
      unawaited(CrashlyticsService.record(e, st, reason: 'membro_foto_editor_remove'));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phaseLabel = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao remover foto: $e'),
      );
    }
  }

  Widget _previewAvatar({double size = 132}) {
    final preview = _previewBytes;
    if (preview != null && preview.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: ThemeCleanPremium.softUiCardShadow,
          border: Border.all(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.25),
            width: 3,
          ),
        ),
        child: ClipOval(
          child: Image.memory(
            preview,
            key: ValueKey<int>(preview.length),
            width: size,
            height: size,
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
        size: size,
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
    final canPick = widget.canChangePhoto && !_busy && !_picking;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFDB2777)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Voltar',
          onPressed: _busy ? null : () => Navigator.maybePop(context),
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
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2563EB).withValues(alpha: 0.08),
                    const Color(0xFFDB2777).withValues(alpha: 0.07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                border: Border.all(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.18),
                ),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                children: [
                  Text(
                    'Toque abaixo: use automaticamente (centro) ou ajuste o corte. '
                    'Uma foto por membro — ao guardar, a anterior é substituída.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: canPick ? _pickUnified : null,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFFDB2777)],
                            ),
                          ),
                          child: _previewAvatar(),
                        ),
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
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _memberName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
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
                        color: const Color(0xFF2563EB).withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.canChangePhoto) ...[
              const SizedBox(height: 16),
              MemberSignupPhotoRequiredCard(
                hasPhoto: hasPreview,
                onGallery: canPick ? _pickUnified : null,
                onCamera: canPick ? _pickFromCamera : null,
                photoPreview: _previewAvatar(size: 80),
              ),
            ],
            if (_busy && _phaseLabel.isNotEmpty) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                minHeight: 3,
                color: const Color(0xFF7C3AED),
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              ),
              const SizedBox(height: 8),
              Text(
                _phaseLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                  fontSize: 13,
                ),
              ),
            ],
            if (widget.canChangePhoto) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: (hasPreview && !_busy && !_picking) ? _save : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  _busy
                      ? (_phaseLabel.isNotEmpty ? _phaseLabel : 'Salvando…')
                      : 'Guardar foto',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (!hasPreview)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Escolha uma foto para activar «Guardar foto».',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: ThemeCleanPremium.onSurfaceVariant.withValues(alpha: 0.9),
                    ),
                  ),
                ),
            ],
            if (widget.canRemovePhoto && _hasExistingPhoto) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _confirmRemove,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text(
                  'Remover foto',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            if (!widget.canChangePhoto && !widget.canRemovePhoto)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  'Sem permissão para alterar ou remover esta foto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
