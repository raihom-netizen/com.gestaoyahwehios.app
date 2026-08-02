import 'package:gestao_yahweh/models/scale_entry.dart';

/// Espelhos Produtividade/Folga — não misturar com compromissos da Agenda.
abstract final class ProdutividadeScaleMirrorService {
  ProdutividadeScaleMirrorService._();

  static bool isProdutividadeFolgaEntry(ScaleEntry e) {
    final src = (e.source ?? '').trim().toLowerCase();
    if (src.contains('produtividade') || src.contains('folga')) return true;
    final tipo = (e.agendaType ?? '').trim().toLowerCase();
    return tipo == 'folga' || tipo == 'produtividade';
  }
}
