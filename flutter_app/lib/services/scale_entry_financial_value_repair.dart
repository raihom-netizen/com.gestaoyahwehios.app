import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/models/scale_entry.dart';
import 'package:gestao_yahweh/models/scale_rates.dart';
import 'package:gestao_yahweh/models/shift_location.dart';
import 'package:gestao_yahweh/utils/scale_entry_hours.dart';
import 'package:gestao_yahweh/utils/scale_entry_sei_ocorrencia.dart';
import 'scale_rates_service.dart';
import 'package:gestao_yahweh/core/data/yahweh_write_batch.dart';

/// Corrige plantões ligados a pré-cadastro com financeiro ativo mas salvos com
/// `totalValue` zero (legado / falha na geração). Restaura valores no resumo
/// Estado ? Município ? Particular sem afetar plantão ordinário sem financeiro.
class ScaleEntryFinancialValueRepair {
  static final Set<String> _repairedSessions = {};
  static final Set<String> _fullRepairUids = {};

  static bool _isExpressWithoutFinance(Map<String, dynamic> data) {
    if (data['createdByLancamentoExpresso'] != true) return false;
    final src = (data['source'] ?? '').toString().trim().toLowerCase();
    final origem = (data['lancamentoOrigem'] ?? '').toString().trim().toLowerCase();
    if (src == 'lancamento_expresso' || origem == 'lancamento_expresso') {
      final tv = _parseDouble(data['totalValue']);
      return tv <= 0;
    }
    return false;
  }

  static bool _looksLikeFinancialPlantaoSource(Map<String, dynamic> data) {
    final src = (data['source'] ?? '').toString().trim().toLowerCase();
    final origem = (data['lancamentoOrigem'] ?? '').toString().trim().toLowerCase();
    if (data['createdByMagic'] == true) return true;
    return src.contains('recorrente') ||
        src.contains('escala') ||
        origem.contains('recorrente') ||
        origem.contains('escala') ||
        origem.contains('magic');
  }

  static double _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
    return 0;
  }

  static ScaleEntry _entryFromDoc(Map<String, dynamic> data, String docId) {
    return ScaleEntry(
      id: docId,
      date: DateTime.now(),
      start: (data['start'] ?? '08:00').toString(),
      end: (data['end'] ?? '18:00').toString(),
      dayRate: _parseDouble(data['dayRate']),
      nightRate: _parseDouble(data['nightRate']),
      hoursDay: _parseDouble(data['hoursDay']),
      hoursNight: _parseDouble(data['hoursNight']),
      totalValue: _parseDouble(data['totalValue']),
      label: data['label']?.toString(),
      abbreviation: data['abbreviation']?.toString(),
      isCompromisso: data['isCompromisso'] == true,
      employerType: data['employerType']?.toString(),
      source: data['source']?.toString(),
      lancamentoOrigem: data['lancamentoOrigem']?.toString(),
      createdByLancamentoExpresso: data['createdByLancamentoExpresso'] == true,
      isAgendaMirror: data['isAgendaMirror'] == true,
      isProdutividadeFolgaMirror: data['isProdutividadeFolgaMirror'] == true,
    );
  }

  static (DateTime, DateTime) _shiftBounds(ScaleEntry e) =>
      scaleEntryShiftBounds(
        startHHmm: e.start,
        endHHmm: e.end,
        day: e.date,
      );

  /// Plantão deve ter valor recalculado e persistido.
  static Future<Map<String, dynamic>?> repairPatchForDoc({
    required Map<String, dynamic> data,
    required String docId,
    required List<ShiftLocation> locations,
    required String uid,
  }) async {
    if (data['isAgendaMirror'] == true) return null;
    if (docId.startsWith('agenda_')) return null;
    if (data['isProdutividadeFolgaMirror'] == true ||
        docId.startsWith('produtividade_folga_')) {
      return null;
    }
    if (_isExpressWithoutFinance(data)) return null;

    final entry = _entryFromDoc(data, docId);
    if (entry.isCompromissoParticularEfetivo &&
        !scaleEntryLooksLikePlantaoProfissional(entry)) {
      return null;
    }

    // Só match FORTE (nome base / sigla exata) autoriza gravar financeiro.
    // Match fraco por sigla-substring já transformou plantão ordinário em
    // "horas extras" (pré-cadastro financeiro com abbr genérica tipo "PLANTÃ").
    final match = matchShiftLocationForScaleEntryDetailed(entry, locations);
    final loc = (match != null && match.strong) ? match.location : null;
    final patch = <String, dynamic>{};

    if (loc != null &&
        loc.isEscalaTemplate &&
        loc.financialEnabled &&
        entry.isCompromisso &&
        scaleEntryLooksLikePlantaoProfissional(entry)) {
      patch['isCompromisso'] = false;
    }

    final employerEmpty =
        (entry.employerType ?? '').trim().isEmpty;
    if (loc != null && loc.financialEnabled && employerEmpty) {
      patch['employerType'] = loc.employerType.name;
    }

    final total = entry.totalValue;
    final shouldRecalcValue = total <= 0 &&
        loc != null &&
        loc.isEscalaTemplate &&
        loc.financialEnabled &&
        !entry.isCompromissoParticularEfetivo;

    final shouldRecalcByEmployer = total <= 0 &&
        loc == null &&
        !entry.isCompromissoParticularEfetivo &&
        _looksLikeFinancialPlantaoSource(data) &&
        {
          'state',
          'municipality',
          'private',
        }.contains((entry.employerType ?? '').trim().toLowerCase());

    if (!shouldRecalcValue && !shouldRecalcByEmployer) {
      return patch.isEmpty ? null : patch;
    }

    final locForCalc = loc;
    double newTotal = 0;
    double newHoursDay = entry.hoursDay;
    double newHoursNight = entry.hoursNight;
    double newDayRate = entry.dayRate;
    double newNightRate = entry.nightRate;

    if (locForCalc != null &&
        locForCalc.paymentType == PaymentType.fixed &&
        locForCalc.baseValue > 0) {
      newTotal = (locForCalc.baseValue + locForCalc.bonus - locForCalc.discount)
          .clamp(0, double.infinity);
    } else {
      final (startDt, endDt) = _shiftBounds(entry);
      final res = await ScaleRatesService().computeShiftForUid(
        uid: uid,
        start: startDt,
        end: endDt,
        entryDate: entry.date,
      );
      newTotal = (res['total'] ?? 0).toDouble();
      newHoursDay = (res['hoursDay'] ?? 0).toDouble();
      newHoursNight = (res['hoursNight'] ?? 0).toDouble();
      final rates =
          await ScaleRatesService().getRatesForServiceDay(uid, entry.date);
      final wd = ScaleRates.weekdayToIndex(entry.date.weekday);
      newDayRate = rates.diurnoForWeekday(wd);
      newNightRate = rates.noturnoForWeekday(wd);
    }

    if (newTotal <= 0) {
      final hn = hoursDayNightFromScaleClock(
        startHHmm: entry.start,
        endHHmm: entry.end,
        anchorDay: entry.date,
      );
      if (newHoursDay <= 0 && newHoursNight <= 0) {
        newHoursDay = hn.$1;
        newHoursNight = hn.$2;
      }
      return patch.isEmpty ? null : patch;
    }

    patch['totalValue'] = newTotal;
    patch['hoursDay'] = newHoursDay;
    patch['hoursNight'] = newHoursNight;
    patch['dayRate'] = newDayRate;
    patch['nightRate'] = newNightRate;
    patch['financialValueRepairAt'] = FieldValue.serverTimestamp();
    if (locForCalc != null) {
      patch['employerType'] = locForCalc.employerType.name;
      patch['isCompromisso'] = false;
    }
    return patch;
  }

  /// Varredura leve (3 meses, cache-first) — 1x por usuário, adiada, fora do caminho crítico.
  static Future<void> repairAllMonthsIfNeeded({
    required String uid,
    required CollectionReference<Map<String, dynamic>> scalesRef,
    required List<ShiftLocation> locations,
    required DateTime anchorMonth,
  }) async {
    if (uid.isEmpty || locations.isEmpty || _fullRepairUids.contains(uid)) {
      return;
    }
    _fullRepairUids.add(uid);
    try {
      final prefs = await SharedPreferences.getInstance();
      final flagKey = 'scale_fin_full_repair_v1_$uid';
      if (prefs.getBool(flagKey) == true) return;

      // Adiar ? não compete com 1? paint do calendário.
      await Future<void>.delayed(const Duration(seconds: 30));
      if (locations.isEmpty) return;

      final anchor = DateTime(anchorMonth.year, anchorMonth.month, 1);
      final start = DateTime(anchor.year, anchor.month - 1, 1);
      final end = DateTime(anchor.year, anchor.month + 2, 0, 23, 59, 59);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await scalesRef
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .limit(350)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        return;
      }
      if (snap.docs.isEmpty) {
        await prefs.setBool(flagKey, true);
        return;
      }

      await repairDocsIfNeeded(
        uid: uid,
        monthKey: 'all-${anchor.year}-${anchor.month}',
        docs: snap.docs,
        scalesRef: scalesRef,
        locations: locations,
        force: true,
      );
      await prefs.setBool(flagKey, true);
    } catch (e, st) {
      debugPrint('ScaleEntryFinancialValueRepair.repairAllMonths: $e\n$st');
      _fullRepairUids.remove(uid);
    }
  }

  static Future<void> repairDocsIfNeeded({
    required String uid,
    required String monthKey,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required CollectionReference<Map<String, dynamic>> scalesRef,
    required List<ShiftLocation> locations,
    bool force = false,
  }) async {
    if (uid.isEmpty || docs.isEmpty || locations.isEmpty) return;
    final sessionKey = '$uid:$monthKey:fin';
    if (!force && _repairedSessions.contains(sessionKey)) return;

    final patches =
        <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};

    for (final doc in docs) {
      try {
        final patch = await repairPatchForDoc(
          data: doc.data(),
          docId: doc.id,
          locations: locations,
          uid: uid,
        );
        if (patch != null && patch.isNotEmpty) {
          patches[scalesRef.doc(doc.id)] = patch;
        }
      } catch (e) {
        debugPrint('ScaleEntryFinancialValueRepair doc ${doc.id}: $e');
      }
    }

    if (patches.isEmpty) {
      _repairedSessions.add(sessionKey);
      return;
    }

    try {
      const batchLimit = 400;
      final entries = patches.entries.toList();
      for (var i = 0; i < entries.length; i += batchLimit) {
        final batch = YahwehBatch();
        for (final e in entries.skip(i).take(batchLimit)) {
          batch.update(e.key, e.value);
        }
        await batch.commit();
      }
      _repairedSessions.add(sessionKey);
      ScaleRatesService().invalidateMemory(uid);
      debugPrint(
        'ScaleEntryFinancialValueRepair: ${patches.length} plantão(ões) com valor corrigido',
      );
    } catch (e) {
      debugPrint('ScaleEntryFinancialValueRepair: $e');
    }
  }
}
