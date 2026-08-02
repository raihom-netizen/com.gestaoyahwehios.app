import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/ui/pages/compromisso_form_page.dart';
import 'package:gestao_yahweh/utils/premium_upgrade.dart';
import 'express_compromisso_agenda_sync.dart';
import 'post_save_background_coordinator.dart';
import 'scale_entry_save_service.dart';
import 'scales_entries_hub.dart';
import 'user_profile_startup_cache.dart';
import 'yearly_commitment_repeat_service.dart';

/// Compromisso expresso = **mesma tela do módulo Compromissos**
/// ([CompromissoFormPage]) no Painel Inicial e em Escalas (dia do calendário).
/// Grava pela mesma via do expresso: `users/{uid}/reminders` + espelho
/// `agenda_{id}` em `scales` — painel «em aberto», Agenda e calendário juntos.
class CompromissoExpressFullForm {
  CompromissoExpressFullForm._();

  static Future<UserProfile?> _resolveProfile(String uid) async {
    final cached = UserProfileStartupCache.resolveForShell(shellUid: uid);
    if (cached != null) return cached;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return UserProfile.fromFirestoreMap(uid, snap.data() ?? {});
    } catch (_) {
      return null;
    }
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Abre a tela do módulo Compromissos para criar compromisso particular.
  ///
  /// Retorna `true` = salvo, `false` = cancelado pelo usuário e `null` quando
  /// não foi possível abrir (sem perfil) — o chamador deve usar o fallback.
  static Future<bool?> openNew({
    required BuildContext context,
    required String uid,
    List<DateTime>? initialDates,
    bool lockDate = false,
  }) async {
    if (uid.trim().isEmpty) return null;
    final profile = await _resolveProfile(uid);
    if (profile == null || !context.mounted) return null;
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return false;
    }

    final result =
        await Navigator.of(context, rootNavigator: true).push<CompromissoFormResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CompromissoFormPage(
          profile: profile,
          hasActiveLicense: profile.hasActiveLicense,
          existingDoc: null,
          initialDates: initialDates,
          lockDate: lockDate,
        ),
      ),
    );
    if (result == null) return false;

    final timeStr = _hhmm(result.time);
    final endTimeStr = _hhmm(result.endTime);
    final dates = result.dates.isEmpty ? [result.date] : result.dates;
    final offline = await ScaleEntrySaveService.isOffline();

    // Feedback imediato (offline-first); gravação segue em background.
    if (context.mounted) {
      final baseMsg = result.repeatYearly
          ? '${result.title} salvo — repete automaticamente todo ano.'
          : (dates.length == 1
              ? '${result.title} gravado — aparece no painel, Agenda e Escalas.'
              : '${dates.length} compromissos gravados — painel, Agenda e Escalas.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('$baseMsg${ScaleEntrySaveService.offlineSuffix(offline)}'),
        ),
      );
    }

    unawaited(_persistBackground(
      uid: uid,
      result: result,
      dates: dates,
      timeStr: timeStr,
      endTimeStr: endTimeStr,
    ));
    return true;
  }

  static Future<void> _persistBackground({
    required String uid,
    required CompromissoFormResult result,
    required List<DateTime> dates,
    required String timeStr,
    required String endTimeStr,
  }) async {
    try {
      if (result.repeatYearly) {
        await YearlyCommitmentRepeatService.createWithYearlyRepeat(
          userDocId: uid,
          title: result.title,
          notes: result.notes,
          anchorCalendarDay: result.date,
          startHHmm: timeStr,
          endHHmm: endTimeStr,
          colorHex: result.colorHex,
          yearlyRepeatWeekdays: result.yearlyRepeatWeekdays,
          reminderLeads: result.reminderLeads,
          notificationSoundId: result.notificationSoundId,
          notificationDeliveryMode: result.notificationDeliveryMode,
          linkLocalizacao: result.linkLocalizacao,
          contatoWhatsApp: result.contatoWhatsApp,
        );
        ScalesEntriesHub.notifyMutated(uid: uid, month: result.date);
        return;
      }

      final savedReminderIds = <String>[];
      for (final day in dates) {
        final reminderId = await ExpressCompromissoAgendaSync.upsertFromExpress(
          userDocId: uid,
          title: result.title,
          date: day,
          startHHmm: timeStr,
          endHHmm: endTimeStr,
          colorHex: result.colorHex,
          notes: result.notes,
          linkLocalizacao: result.linkLocalizacao,
          contatoWhatsApp: result.contatoWhatsApp,
          reminderLeads: result.reminderLeads,
          notificationSoundId: result.notificationSoundId,
          notificationDeliveryMode: result.notificationDeliveryMode,
          deferBackground: true,
        );
        if (reminderId.isNotEmpty) savedReminderIds.add(reminderId);
      }

      if (savedReminderIds.isNotEmpty) {
        PostSaveBackgroundCoordinator.schedule(
          uid,
          notifications: true,
          widget: true,
          fullNotificationRefresh: savedReminderIds.length > 12,
          reminderDocIds: savedReminderIds,
        );
      }
      ScalesEntriesHub.notifyMutated(
        uid: uid,
        month: dates.isNotEmpty ? dates.first : null,
      );
    } catch (_) {}
  }
}
