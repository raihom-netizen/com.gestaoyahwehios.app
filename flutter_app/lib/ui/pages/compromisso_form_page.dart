import 'package:flutter/material.dart';

import 'package:gestao_yahweh/models/user_profile.dart';

/// Resultado ao salvar [CompromissoFormPage].
class CompromissoFormResult {
  const CompromissoFormResult({
    required this.title,
    required this.notes,
    required this.date,
    required this.dates,
    required this.time,
    required this.endTime,
    required this.colorHex,
    this.repeatYearly = false,
    this.yearlyRepeatWeekdays = const [],
    this.reminderLeads,
    this.notificationSoundId,
    this.notificationDeliveryMode,
    this.linkLocalizacao = '',
    this.contatoWhatsApp = '',
  });

  final String title;
  final String notes;
  final DateTime date;
  final List<DateTime> dates;
  final TimeOfDay time;
  final TimeOfDay endTime;
  final String colorHex;
  final bool repeatYearly;
  final List<int> yearlyRepeatWeekdays;
  final List<int>? reminderLeads;
  final String? notificationSoundId;
  final String? notificationDeliveryMode;
  final String linkLocalizacao;
  final String contatoWhatsApp;
}

/// Formulário mínimo de compromisso particular (Controle Total).
class CompromissoFormPage extends StatefulWidget {
  const CompromissoFormPage({
    super.key,
    required this.profile,
    required this.hasActiveLicense,
    this.existingDoc,
    this.initialDates,
    this.lockDate = false,
  });

  final UserProfile profile;
  final bool hasActiveLicense;
  final Object? existingDoc;
  final List<DateTime>? initialDates;
  final bool lockDate;

  @override
  State<CompromissoFormPage> createState() => _CompromissoFormPageState();
}

class _CompromissoFormPageState extends State<CompromissoFormPage> {
  final _titleCtrl = TextEditingController(text: 'Compromisso');
  final _notesCtrl = TextEditingController();
  late DateTime _date;
  final TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDates?.isNotEmpty == true
        ? widget.initialDates!.first
        : DateTime.now();
    _date = DateTime(initial.year, initial.month, initial.day);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim().isEmpty ? 'Compromisso' : _titleCtrl.text.trim();
    Navigator.of(context).pop(
      CompromissoFormResult(
        title: title,
        notes: _notesCtrl.text.trim(),
        date: _date,
        dates: widget.initialDates?.isNotEmpty == true
            ? List<DateTime>.from(widget.initialDates!)
            : [_date],
        time: _start,
        endTime: _end,
        colorHex: '#12B5A5',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compromisso'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Salvar')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Título'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Observações'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Data: ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
            trailing: widget.lockDate
                ? null
                : IconButton(
                    icon: const Icon(Icons.calendar_today_rounded),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
