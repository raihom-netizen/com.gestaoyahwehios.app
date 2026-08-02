import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/constants/commitment_presets.dart';
import 'package:gestao_yahweh/constants/field_text_limits.dart';
import 'package:gestao_yahweh/models/scale_entry.dart';
import 'package:gestao_yahweh/core/finance_app_colors.dart';
import 'text_case_preserving_utils.dart';

export '../constants/field_text_limits.dart'
    show
        kAudienciaRelatoMaxLength,
        kScaleNotesGridCollapsedChars,
        kScaleNotesGridExpandChars,
        kScaleNotesMaxLength,
        clampTextToMaxLength,
        normalizeAudienciaRelatoForSave,
        normalizeScaleNotesForSave;

/// SEI e RAI (ocorrência) — somente módulo Audiências/Compromissos (e espelho na Escalas).
class ScaleEntrySeiOcorrencia {
  const ScaleEntrySeiOcorrencia({required this.sei, required this.oco});

  final String sei;
  final String oco;

  bool get hasSei => sei.isNotEmpty;
  bool get hasOco => oco.isNotEmpty;
}

/// Nº do **plantão** (Escalas) — com ou sem financeiro; não é SEI nem RAI.
String scalePlantaoNumberFromEntry(ScaleEntry e) {
  if (e.isAgendaMirror) return '';
  return (e.scaleNumber ?? '').trim();
}

/// SEI/RAI no documento Firestore (espelho `agenda_*` ou leitura legada).
ScaleEntrySeiOcorrencia seiOcoFromFirestoreMap(Map<String, dynamic> d) {
  final sei = (d['numeroSei'] ?? '').toString().trim();
  final oco = (d['numeroOcorrencia'] ?? '').toString().trim();
  return ScaleEntrySeiOcorrencia(sei: sei, oco: oco);
}

/// SEI/RAI só para espelho da Agenda na lista de Escalas.
ScaleEntrySeiOcorrencia? seiOcoFromAgendaMirrorEntry(ScaleEntry e) {
  if (!e.isAgendaMirror) return null;
  var sei = (e.numeroSei ?? '').trim();
  var oco = (e.numeroOcorrencia ?? '').trim();
  if (sei.isEmpty && oco.isEmpty) {
    final sn = (e.scaleNumber ?? '').trim();
    if (sn.isNotEmpty && !sn.toUpperCase().startsWith('OCO')) {
      sei = sn;
    }
  }
  return ScaleEntrySeiOcorrencia(sei: sei, oco: oco);
}

@Deprecated('Use scalePlantaoNumberFromEntry ou seiOcoFromAgendaMirrorEntry')
ScaleEntrySeiOcorrencia seiOcoFromScaleEntry(ScaleEntry e) {
  final mirror = seiOcoFromAgendaMirrorEntry(e);
  if (mirror != null) return mirror;
  final plantao = scalePlantaoNumberFromEntry(e);
  return ScaleEntrySeiOcorrencia(sei: '', oco: plantao);
}

/// Linhas no card: plantão/compromisso (Escalas) → Nº Escala; audiência → Nº Ocorrência.
List<String> scaleEntryResumoNumberLines(ScaleEntry e) {
  if (e.isAgendaMirror) {
    final isAud =
        (e.agendaType ?? '').toString().trim().toLowerCase() == 'audiencia';
    final n = seiOcoFromAgendaMirrorEntry(e);
    if (n == null) return [];
    if (isAud) {
      return scaleEntryAudienciaResumoLines(n);
    }
    final sn = (e.scaleNumber ?? '').trim();
    if (sn.isEmpty) return const [];
    return ['🏷️ Nº Escala: $sn'];
  }
  final num = scalePlantaoNumberFromEntry(e);
  if (num.isEmpty) {
    return const [];
  }
  return ['🏷️ Nº Escala: $num'];
}

/// Mensagem quando não há número no card (Escalas).
String scaleEntryResumoNumberEmptyLabel(ScaleEntry e) {
  if (e.isAgendaMirror &&
      (e.agendaType ?? '').toString().trim().toLowerCase() == 'audiencia') {
    return 'Sem nº ocorrência';
  }
  return 'Sem nº escala';
}

/// Valores da edição rápida de **plantão** (Escalas).
class ScalePlantaoEditValues {
  const ScalePlantaoEditValues({
    required this.scaleNumber,
    required this.notes,
  });

  final String scaleNumber;
  final String notes;
}

/// Remove prefixo «Compromisso » de rótulos que são plantão profissional.
String scaleEntryStripErroneousCompromissoPrefix(String label) {
  var l = label.trim();
  if (l.isEmpty) return l;
  final upper = l.toUpperCase();
  if (!upper.startsWith('COMPROMISSO ')) return l;
  final rest = l.substring('Compromisso '.length).trim();
  if (rest.isEmpty) return l;
  if (RegExp(
    r'PLANT[AÃ]O|ORDIN[AÁ]RIO|CASE|REFOR[CÇ]O|CPU|NOTURNO|DIURNO|EXTRA',
    caseSensitive: false,
  ).hasMatch(rest)) {
    return rest;
  }
  return l;
}

/// Patch Firestore — plantão: só `scaleNumber` + `notes` (remove SEI/RAI se existirem).
Map<String, dynamic> scalePlantaoFirestorePatch(ScalePlantaoEditValues values) {
  final scaleNumber = values.scaleNumber.trim().toUpperCase();
  final notes = normalizeScaleNotesForSave(values.notes);

  return {
    'scaleNumber': scaleNumber.isEmpty ? FieldValue.delete() : scaleNumber,
    'notes': notes.isEmpty ? FieldValue.delete() : notes,
    'numeroSei': FieldValue.delete(),
    'numeroOcorrencia': FieldValue.delete(),
  };
}

/// Título no resumo do dia — sem repetir SEI/ocorrência; compromisso = texto do usuário.
String scaleEntryResumoDisplayTitle(ScaleEntry e) {
  final tipo = (e.agendaType ?? '').toString().trim().toLowerCase();
  if (e.isAgendaMirror && tipo == 'audiencia') return 'Audiência';
  if (e.isAgendaMirror && tipo == 'compromisso') {
    final label = stripLeadingCompromissoWord(_cleanScaleEntryTitleLabel(e.label));
    if (scaleEntryLooksLikePlantaoProfissional(e)) {
      final stripped = scaleEntryStripErroneousCompromissoPrefix(label);
      return stripped.isNotEmpty ? stripped : 'Plantão';
    }
    if (label.isEmpty) return 'Compromisso';
    return label;
  }
  var label = (e.label ?? 'Plantão').trim();
  if (label.isEmpty) return 'Plantão';
  final seiMatch =
      RegExp(r'\s*·\s*SEI\s', caseSensitive: false).firstMatch(label);
  if (seiMatch != null) {
    label = label.substring(0, seiMatch.start).trim();
  }
  final ocoMatch =
      RegExp(r'\s*·\s*OCO\s', caseSensitive: false).firstMatch(label);
  if (ocoMatch != null) {
    label = label.substring(0, ocoMatch.start).trim();
  }
  if (label.toUpperCase().startsWith('AUDIÊNCIA')) return 'Audiência';
  if (scaleEntryIsCompromissoParticular(e)) {
    label = stripLeadingCompromissoWord(label);
    if (label.isEmpty) return 'Compromisso';
    return label;
  }
  if (label.toUpperCase() == 'COMPROMISSO') {
    return scaleEntryIsPlantaoEscala(e) ? 'Plantão' : 'Compromisso';
  }
  if (scaleEntryIsPlantaoEscala(e)) {
    label = scaleEntryStripErroneousCompromissoPrefix(label);
  }
  return label;
}

/// Ícone + cor padronizados no resumo do dia (Escalas): plantão VTR, audiência,
/// compromisso colorido, folga/dispensa, etc.
@immutable
class ScaleEntryResumoVisual {
  const ScaleEntryResumoVisual({
    this.icon,
    this.emoji,
    required this.color,
  }) : assert(icon != null || emoji != null);

  final IconData? icon;
  final String? emoji;
  final Color color;
}

ScaleEntryResumoVisual scaleEntryResumoVisual(ScaleEntry e) {
  if (e.isProdutividadeFolgaMirror) {
    return const ScaleEntryResumoVisual(
      icon: Icons.beach_access_rounded,
      color: Color(0xFF43A047),
    );
  }

  if (scaleEntryIsAudienciaEfetiva(e)) {
    return const ScaleEntryResumoVisual(
      icon: Icons.gavel_rounded,
      color: Color(0xFFD4AF37),
    );
  }

  final isAgendaCompromisso = e.isAgendaMirror &&
      (e.agendaType ?? '').toString().trim().toLowerCase() == 'compromisso';

  if (scaleEntryIsCompromissoParticular(e) ||
      (isAgendaCompromisso && !scaleEntryLooksLikePlantaoProfissional(e))) {
    final visual = resolveCommitmentVisual(e.label);
    return ScaleEntryResumoVisual(
      icon: visual.icon,
      color: visual.color,
    );
  }

  final labelHay = (e.label ?? e.abbreviation ?? '').toUpperCase();
  if (labelHay.contains('FOLGA') || labelHay.contains('DISPENSA')) {
    return const ScaleEntryResumoVisual(
      icon: Icons.event_busy_rounded,
      color: Color(0xFF66BB6A),
    );
  }

  if (scaleEntryIsPlantaoEscala(e) || scaleEntryLooksLikePlantaoProfissional(e)) {
    final accent = e.color;
    return ScaleEntryResumoVisual(
      emoji: '🚓',
      color: accent.alpha > 0 ? accent : const Color(0xFF2563EB),
    );
  }

  return ScaleEntryResumoVisual(
    emoji: '🚓',
    color: e.color.alpha > 0 ? e.color : const Color(0xFF2563EB),
  );
}

/// Caixinha colorida com ícone moderno — sempre exibida no resumo do dia.
Widget scaleEntryResumoIconBadge(
  ScaleEntry e, {
  double size = 36,
}) {
  final visual = scaleEntryResumoVisual(e);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: visual.color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(size * 0.28),
      border: Border.all(color: visual.color.withValues(alpha: 0.42)),
    ),
    child: visual.emoji != null
        ? Text(
            visual.emoji!,
            style: TextStyle(fontSize: size * 0.52, height: 1.0),
          )
        : Icon(visual.icon, color: visual.color, size: size * 0.52),
  );
}

/// Ícone inline (resumo do mês / cards compactos).
Widget scaleEntryResumoIconContent(
  ScaleEntry e, {
  double size = 20,
  Color? color,
}) {
  final visual = scaleEntryResumoVisual(e);
  final fg = color ?? visual.color;
  if (visual.emoji != null) {
    return Text(
      visual.emoji!,
      style: TextStyle(fontSize: size, height: 1.0),
    );
  }
  return Icon(
    visual.icon ?? Icons.event_available_rounded,
    color: fg,
    size: size,
  );
}

/// Ícone colorido do compromisso (presets do banco + fallback estável).
@Deprecated('Use scaleEntryResumoIconBadge')
Widget? scaleEntryCompromissoIconBadge(
  ScaleEntry e, {
  double size = 36,
}) => scaleEntryResumoIconBadge(e, size: size);

String _cleanScaleEntryTitleLabel(String? raw) {
  var label = (raw ?? '').trim();
  if (label.isEmpty) return '';
  final seiMatch =
      RegExp(r'\s*·\s*SEI\s', caseSensitive: false).firstMatch(label);
  if (seiMatch != null) {
    label = label.substring(0, seiMatch.start).trim();
  }
  final ocoMatch =
      RegExp(r'\s*·\s*OCO\s', caseSensitive: false).firstMatch(label);
  if (ocoMatch != null) {
    label = label.substring(0, ocoMatch.start).trim();
  }
  return label;
}

/// Título com primeira letra maior (resumo Escalas). [allCaps] = resumo do dia.
Widget scaleEntryResumoTitleText(
  ScaleEntry e, {
  required double fontSize,
  Color color = AppColors.textPrimary,
  bool allCaps = false,
}) {
  var title = scaleEntryResumoDisplayTitle(e);
  if (allCaps) {
    title = uppercaseLatinPreservingEmoji(title);
    return Text(
      title,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.25,
        color: color,
        letterSpacing: 0.2,
      ),
    );
  }
  return buildResumoTitleWithFirstLetterEmphasis(
    title: title,
    fontSize: fontSize,
    color: color,
  );
}

/// Estilo destacado para data e horário no resumo do dia.
TextStyle scaleEntryResumoMetaTextStyle({
  required double fontSize,
  Color color = AppColors.deepBlue,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    height: 1.35,
    color: color,
    letterSpacing: 0.15,
  );
}

/// Dia da semana · data · horário (resumo Escalas).
String scaleEntryDiaSemanaDataHorario(ScaleEntry e) {
  final raw = DateFormat('EEEE', 'pt_BR').format(e.date);
  final diaSemana =
      raw.isEmpty ? raw : '${raw[0].toUpperCase()}${raw.substring(1)}';
  final data = DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date);
  return '$diaSemana · $data · ${e.start}–${e.end}';
}

/// Linhas SEI / nº ocorrência (módulo Audiências).
List<String> scaleEntryAudienciaResumoLines(ScaleEntrySeiOcorrencia n) {
  final out = <String>[];
  if (n.hasSei) out.add('📂 Processo (SEI): ${n.sei}');
  if (n.hasOco) out.add('🏷️ Nº Ocorrência: ${n.oco}');
  return out;
}

@Deprecated('Use scaleEntryAudienciaResumoLines')
List<String> scaleEntrySeiOcoLines(ScaleEntrySeiOcorrencia n) {
  return scaleEntryAudienciaResumoLines(n);
}

/// Audiência / compromisso da Agenda (espelho ou legado) — edição completa, não nº escala.
bool scaleEntryUsesAgendaFullEditor(ScaleEntry e) {
  if (e.isAgendaMirror) return true;
  final id = e.id?.trim() ?? '';
  if (id.startsWith('agenda_')) return true;
  final t = (e.agendaType ?? '').trim().toLowerCase();
  if (t == 'audiencia' || t == 'compromisso') return true;
  final label = (e.label ?? '').trim().toUpperCase();
  if (label.startsWith('AUDIÊNCIA') || label.startsWith('AUDIENCIA')) {
    return true;
  }
  return false;
}

/// Audiência (espelho Agenda ou legado) — barra dourada no resumo do mês.
bool scaleEntryIsAudienciaEfetiva(ScaleEntry e) {
  if (e.isProdutividadeFolgaMirror) return false;
  if (e.isAgendaMirror) {
    return (e.agendaType ?? '').trim().toLowerCase() == 'audiencia';
  }
  final t = (e.agendaType ?? '').trim().toLowerCase();
  if (t == 'audiencia') return true;
  final label = (e.label ?? '').trim().toUpperCase();
  return label.startsWith('AUDIÊNCIA') || label.startsWith('AUDIENCIA');
}

/// Compromisso particular real (Agenda / folga pessoal).
/// Plantões da Escalas — com ou sem financeiro — **não** entram aqui,
/// inclusive legado `isCompromisso: true` salvo por engano.
bool scaleEntryIsCompromissoParticular(ScaleEntry e) {
  if (e.isProdutividadeFolgaMirror) return false;

  if (e.isAgendaMirror) {
    final tipo = (e.agendaType ?? '').trim().toLowerCase();
    if (tipo != 'compromisso') return false;
    // Espelho Agenda com tipo compromisso — confiar no espelho (não descartar por employerType private).
    return true;
  }

  if (scaleEntryUsesAgendaFullEditor(e)) {
    if (!e.isCompromisso) return false;
    return !scaleEntryLooksLikePlantaoProfissional(e);
  }

  if (!e.isCompromisso) return false;
  return !scaleEntryLooksLikePlantaoProfissional(e);
}

/// Plantão / escala (não é compromisso particular da Agenda).
bool scaleEntryIsPlantaoEscala(ScaleEntry e) {
  if (e.isAgendaMirror) {
    final tipo = (e.agendaType ?? '').trim().toLowerCase();
    return tipo != 'compromisso' && tipo != 'audiencia';
  }
  return !scaleEntryIsCompromissoParticular(e);
}

/// Plantão profissional/ordinário (com ou sem financeiro). Muitos sem financeiro
/// ficam com `isCompromisso: true` no Firestore — não são compromisso da Agenda.
bool scaleEntryIsPlantaoParaEdicaoRapida(ScaleEntry e) {
  if (e.isAgendaMirror) return false;
  final id = e.id?.trim() ?? '';
  if (id.startsWith('agenda_')) return false;

  if (!e.isCompromisso) return true;

  return scaleEntryLooksLikePlantaoProfissional(e);
}

bool scaleEntryLooksLikePlantaoProfissional(ScaleEntry e) {
  if (e.isAgendaMirror) {
    final tipo = (e.agendaType ?? '').trim().toLowerCase();
    if (tipo == 'compromisso') return false;
  }

  if (e.createdByLancamentoExpresso && !e.isAgendaMirror) return true;

  final label = (e.label ?? '').trim().toUpperCase();
  if (RegExp(
    r'PLANT[AÃ]O|ORDIN[AÁ]RIO|CASE|REFOR[CÇ]O|CPU|MOT\.|NOTURNO|DIURNO|EXTRA',
    caseSensitive: false,
  ).hasMatch(label)) {
    return true;
  }

  // Compromisso explícito (formulário/pré-cadastro): só plantão se o título for claramente escala.
  if (e.isCompromisso && !e.isAgendaMirror) {
    return false;
  }

  final et = (e.employerType ?? '').trim().toLowerCase();
  if (et == 'state' || et == 'municipality' || et == 'private') {
    return true;
  }

  final abbr = (e.abbreviation ?? '').trim().toUpperCase();
  if (abbr.length >= 2 &&
      abbr.length <= 12 &&
      RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(abbr)) {
    return true;
  }

  final src = (e.source ?? '').trim().toLowerCase();
  final origem = (e.lancamentoOrigem ?? '').trim().toLowerCase();
  if (src.contains('plantao') ||
      src.contains('escala') ||
      src.contains('recorrente') ||
      src.contains('magic') ||
      origem.contains('plantao') ||
      origem.contains('escala') ||
      origem.contains('recorrente') ||
      origem.contains('lancamento_expresso') ||
      origem.contains('magic')) {
    return true;
  }

  return false;
}

/// Firestore legado: `isCompromisso:true` em plantão da Escalas → corrigir para false.
bool scaleEntryNeedsCompromissoFlagRepair(Map<String, dynamic> data, String docId) {
  if (data['isAgendaMirror'] == true) return false;
  if (docId.startsWith('agenda_')) return false;
  if (data['isCompromisso'] != true) return false;

  final fake = ScaleEntry(
    id: docId,
    date: DateTime.now(),
    start: (data['start'] ?? '08:00').toString(),
    end: (data['end'] ?? '18:00').toString(),
    label: data['label']?.toString(),
    abbreviation: data['abbreviation']?.toString(),
    isCompromisso: true,
    employerType: data['employerType']?.toString(),
    source: data['source']?.toString(),
    lancamentoOrigem: data['lancamentoOrigem']?.toString(),
    createdByLancamentoExpresso: data['createdByLancamentoExpresso'] == true,
  );
  return scaleEntryLooksLikePlantaoProfissional(fake);
}

/// Compromisso particular real, audiência ou espelho Agenda — tela cheia.
bool scaleEntryRequiresFullEditor(ScaleEntry e) {
  if (scaleEntryUsesAgendaFullEditor(e)) return true;
  return scaleEntryIsCompromissoParticular(e);
}
