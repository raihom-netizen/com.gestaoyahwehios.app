import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/shift_location.dart';

class EmployerVinculoChips {
  EmployerVinculoChips._();

  static Widget selectionRow({
    required BuildContext context,
    bool dense = false,
    required EmployerType selected,
    required ValueChanged<EmployerType> onChanged,
  }) {
    return Wrap(
      spacing: 8,
      children: EmployerType.values.map((t) {
        final active = t == selected;
        return ChoiceChip(
          label: Text(ShiftLocation.employerTypeLabel(t)),
          selected: active,
          onSelected: (_) => onChanged(t),
          visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
        );
      }).toList(),
    );
  }
}
