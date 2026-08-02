import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/shift_location.dart';

class RecurringEntryKindSelector extends StatelessWidget {
  const RecurringEntryKindSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: ShiftLocation.entryKindEscala,
          label: Text('Plantão'),
          icon: Icon(Icons.work_history_rounded),
        ),
        ButtonSegment(
          value: ShiftLocation.entryKindCompromisso,
          label: Text('Compromisso'),
          icon: Icon(Icons.event_available_rounded),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) {
        if (s.isEmpty) return;
        onChanged(s.first);
      },
    );
  }
}
