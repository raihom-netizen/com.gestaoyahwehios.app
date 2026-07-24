import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show BuildContext, Rect, ScaffoldMessenger;
import 'package:gestao_yahweh/core/noticia_share_links.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart';
import 'package:gestao_yahweh/core/yahweh_contact_greeting.dart';
import 'package:gestao_yahweh/services/church_member_contact_chat.dart';
import 'package:gestao_yahweh/services/yahweh_share_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_post_rich_text_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fluxo único WhatsApp — 1 toque abre o app com mensagem pronta.
abstract final class YahwehWhatsAppService {
  YahwehWhatsAppService._();

  static String get defaultContactDraft =>
      YahwehContactGreeting.faleComigoDraft();

  /// Normaliza telefone BR (55 + DDD + número).
  static String normalizeBrazilDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return '';
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length <= 11 && !digits.startsWith('55')) {
      digits = '55$digits';
    }
    return digits;
  }

  /// Abre WhatsApp — com [phoneDigits] (contato) ou broadcast (escolher destino).
  static Future<bool> openWithMessage({
    required String message,
    String? phoneDigits,
  }) async {
    final text = message.trim();
    if (text.isEmpty && (phoneDigits ?? '').trim().isEmpty) return false;

    final digits = phoneDigits != null ? normalizeBrazilDigits(phoneDigits) : '';
    final enc = Uri.encodeComponent(
      text.isEmpty ? defaultContactDraft : text,
    );

    final uris = <Uri>[
      if (!kIsWeb && digits.length >= 12)
        Uri.parse('whatsapp://send?phone=$digits&text=$enc'),
      if (digits.length >= 12)
        Uri.parse('https://wa.me/$digits?text=$enc')
      else
        Uri.parse('https://wa.me/?text=$enc'),
      if (digits.length >= 12)
        Uri.parse('https://api.whatsapp.com/send?phone=$digits&text=$enc'),
    ];

    for (final uri in uris) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {}
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (launched) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Convite aviso/evento — abre WhatsApp já com texto + link OG.
  static Future<bool> openNoticiaBroadcast(String message) =>
      openWithMessage(message: message);

  /// Monta mensagem de convite a partir do documento Firestore.
  static String buildNoticiaMessage({
    required String churchName,
    required String churchSlug,
    required String tenantId,
    required String noticiaId,
    required Map<String, dynamic> postData,
    String? noticiaKindOverride,
  }) {
    DateTime? startAt;
    try {
      startAt = (postData['startAt'] as Timestamp).toDate();
    } catch (_) {}

    final kindRaw = (noticiaKindOverride ??
            postData['type'] ??
            postData['kind'] ??
            'aviso')
        .toString()
        .trim()
        .toLowerCase();
    final kind = kindRaw == 'evento' ? 'evento' : 'aviso';

    final lat = postData['locationLat'];
    final lng = postData['locationLng'];
    final slug = resolveChurchPublicSlug(
      churchSlug: churchSlug,
      tenantId: tenantId,
      churchData: postData,
    );
    final links = resolveNoticiaShareLinks(
      tenantId: tenantId,
      noticiaId: noticiaId,
      churchSlug: slug,
      churchData: postData,
    );

    return buildNoticiaInviteShareMessage(
      churchName: churchName.trim().isNotEmpty ? churchName.trim() : 'Nossa igreja',
      noticiaKind: kind,
      title: (postData['title'] ?? '').toString(),
      bodyText: churchPostPlainText(Map<String, dynamic>.from(postData)),
      startAt: startAt,
      location: (postData['location'] ?? '').toString(),
      locationLat: lat is num
          ? lat.toDouble()
          : (lat != null ? double.tryParse(lat.toString()) : null),
      locationLng: lng is num
          ? lng.toDouble()
          : (lng != null ? double.tryParse(lng.toString()) : null),
      publicSiteUrl: links.publicSiteUrl,
      inviteCardUrl: links.socialPreviewUrl,
      tenantId: tenantId,
      noticiaId: noticiaId,
      churchSlug: slug,
      churchData: postData,
    );
  }

  /// WhatsApp / folha nativa com fotos e vídeo + texto completo (web + Android + iOS).
  static Future<bool> sendNoticiaWithMedia({
    required String message,
    required Map<String, dynamic> postData,
    Rect? sharePositionOrigin,
  }) async {
    try {
      final media = await fetchNoticiaShareMediaBundle(postData);
      if (media.isNotEmpty) {
        await YahwehShareService.shareMediaBundle(
          files: media,
          message: message,
          subject: 'Convite',
          sharePositionOrigin: sharePositionOrigin,
        );
        return true;
      }
    } catch (_) {}
    return openNoticiaBroadcast(message);
  }

  /// 1 clique: convite premium + mídia (web + Android + iOS); fallback texto.
  static Future<bool> sendNoticiaOneTap({
    required String churchName,
    required String churchSlug,
    required String tenantId,
    required String noticiaId,
    required Map<String, dynamic> postData,
    String? noticiaKindOverride,
  }) {
    final msg = buildNoticiaMessage(
      churchName: churchName,
      churchSlug: churchSlug,
      tenantId: tenantId,
      noticiaId: noticiaId,
      postData: postData,
      noticiaKindOverride: noticiaKindOverride,
    );
    return sendNoticiaWithMedia(message: msg, postData: postData);
  }

  /// Parabéns de aniversário — 1 clique para o membro.
  static Future<void> openBirthdayWish(
    BuildContext context, {
    required String firstName,
    required String phoneDigits,
  }) async {
    final digits = normalizeBrazilDigits(phoneDigits);
    if (digits.length < 12) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Cadastre o telefone/WhatsApp do membro para parabenizar.',
        ),
      );
      return;
    }
    final nome = firstName.trim();
    final msg =
        'Feliz aniversário${nome.isNotEmpty ? ', $nome' : ''}! Que Deus te abençoe. 🎂';
    final ok = await openWithMessage(message: msg, phoneDigits: digits);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Não foi possível abrir o WhatsApp.',
        ),
      );
    }
  }

  /// Contato direto com membro/líder (enriquece telefone se necessário).
  static Future<void> openForMember(
    BuildContext context,
    Map<String, dynamic> memberData, {
    String? message,
    String? tenantId,
    String? memberDocId,
  }) =>
      ChurchMemberContactChat.openWhatsAppFaleComigo(
        context,
        memberData,
        message: message ?? defaultContactDraft,
        tenantId: tenantId,
        memberDocId: memberDocId,
      );

  /// Agenda interna — abre chat com responsável do evento.
  static Future<bool> openPhoneDigits(String digits, {String message = ''}) =>
      openWithMessage(message: message, phoneDigits: digits);

  static void showOpenFailedSnack(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar(
        'Não foi possível abrir o WhatsApp. Verifique se o app está instalado.',
      ),
    );
  }
}
