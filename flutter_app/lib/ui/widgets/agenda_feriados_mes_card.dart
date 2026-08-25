import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:gestao_yahweh/shared/utils/holiday_helper.dart';

/// Feriados nacionais do mês que está no calendário.
///
/// Fica **entre o calendário e o resumo do dia**: quem está a marcar culto,
/// reunião ou escala precisa de ver o feriado antes de escolher o dia, não
/// depois. O rodapé antigo ([HolidayFooter]) desaparecia por completo nos meses
/// sem feriado — e «não aparece nada» lê-se como avaria, não como resposta.
/// Aqui o mês sem feriado diz que não tem.
class AgendaFeriadosDoMesCard extends StatelessWidget {
  const AgendaFeriadosDoMesCard({
    super.key,
    required this.visibleMonth,
    this.onDiaTocado,
  });

  /// Qualquer dia do mês visível (usa apenas ano e mês).
  final DateTime visibleMonth;

  /// Toque num feriado — normalmente selecionar aquele dia no calendário.
  final void Function(DateTime dia)? onDiaTocado;

  static const Color _vermelho = Color(0xFFDC2626);
  static const Color _tinta = Color(0xFF0F172A);
  static const Color _suave = Color(0xFF64748B);
  static const Color _borda = Color(0xFFE2E8F0);

  @override
  Widget build(BuildContext context) {
    final feriados = HolidayHelper.nationalHolidaysInMonth(
      visibleMonth.year,
      visibleMonth.month,
    );
    final mesLabel = DateFormat("MMMM 'de' y", 'pt_BR').format(
      DateTime(visibleMonth.year, visibleMonth.month),
    );
    final mesTitulo = mesLabel.isEmpty
        ? mesLabel
        : mesLabel.substring(0, 1).toUpperCase() + mesLabel.substring(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _vermelho.withValues(alpha: 0.16),
                      _vermelho.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  size: 18,
                  color: _vermelho,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Feriados do mês',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: _tinta,
                      ),
                    ),
                    Text(
                      mesTitulo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _suave,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: feriados.isEmpty
                      ? const Color(0xFFF1F5F9)
                      : _vermelho.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${feriados.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: feriados.isEmpty ? _suave : _vermelho,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (feriados.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borda),
              ),
              child: const Text(
                'Nenhum feriado nacional neste mês.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _suave,
                ),
              ),
            )
          else
            for (final f in feriados) _linha(f),
          const SizedBox(height: 4),
          const Text(
            'Sábados, domingos e feriados aparecem em vermelho no calendário.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(NationalHoliday f) {
    final diaSemana = DateFormat('EEEE', 'pt_BR').format(f.date);
    final semana = diaSemana.isEmpty
        ? diaSemana
        : diaSemana.substring(0, 1).toUpperCase() + diaSemana.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: f.isOptional ? const Color(0xFFFFF7ED) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onDiaTocado == null ? null : () => onDiaTocado!(f.date),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: f.isOptional
                    ? const Color(0xFFFED7AA)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: f.isOptional
                        ? const Color(0xFFEA580C)
                        : _vermelho,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${f.date.day}'.padLeft(2, '0'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _tinta,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        semana,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _suave,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDiaTocado != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFB6C2D2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
