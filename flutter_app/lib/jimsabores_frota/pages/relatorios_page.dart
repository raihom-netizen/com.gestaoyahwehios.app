import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/pdf_super_premium_theme.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});
  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> {
  String _filtroFrota = "";
  String _filtroPlaca = "";
  String _filtroCpf = "";
  /// mes_atual | mes_anterior | periodo
  String _filtroPeriodo = 'mes_atual';
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  TimeOfDay? _horaInicial;
  TimeOfDay? _horaFinal;

  static DateTime _inicioDoDia(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _fimDoDia(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
  static DateTime _inicioDoMes(DateTime d) => DateTime(d.year, d.month, 1);
  static DateTime _fimDoMes(DateTime d) => DateTime(d.year, d.month + 1, 0, 23, 59, 59);

  /// Retorna o intervalo efetivo para filtrar conforme o tipo de período selecionado.
  (DateTime?, DateTime?) get _intervaloEfetivo {
    final now = DateTime.now();
    switch (_filtroPeriodo) {
      case 'mes_atual':
        return (_inicioDoMes(now), _fimDoMes(now));
      case 'mes_anterior':
        final prev = DateTime(now.year, now.month - 1);
        return (_inicioDoMes(prev), _fimDoMes(prev));
      case 'periodo':
        if (_dataInicial != null && _dataFinal != null) {
          return (_inicioDoDia(_dataInicial!), _fimDoDia(_dataFinal!));
        }
        if (_dataInicial != null) return (_inicioDoDia(_dataInicial!), null);
        if (_dataFinal != null) return (null, _fimDoDia(_dataFinal!));
        return (null, null);
      default:
        return (null, null);
    }
  }

  Future<String> _getNivel() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'motorista';
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
    return doc.data()?['nivel'] ?? 'motorista';
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  // FUNÇÃO PARA GERAR E EXPORTAR PDF — Padrão Super Premium (compartilhar, imprimir, salvar)
  Future<void> _exportarPDF(BuildContext context, List<QueryDocumentSnapshot> dados) async {
    final pdf = pw.Document();
    final data = dados.map((d) {
      var map = d.data() as Map<String, dynamic>;
      final placa = (map['placa'] ?? map['veiculo'] ?? '').toString();
      final combustivel = (map['combustivel'] ?? map['tipo_combustivel'] ?? '').toString();
      final dt = map['data_hora']?.toDate();
      final dataStr = dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '';
      final valor = map['valor_total'] ?? map['valor'] ?? '';
      return [dataStr, placa, (map['motorista'] ?? '').toString(), combustivel, 'R\$ $valor'];
    }).toList();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: PdfSuperPremiumTheme.pageMargin,
        header: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: PdfSuperPremiumTheme.header('Relatório de Abastecimentos — Frotas'),
        ),
        footer: (ctx) => PdfSuperPremiumTheme.footer(ctx),
        build: (ctx) => [
          PdfSuperPremiumTheme.fromTextArray(
            headers: const ['Data', 'Placa', 'Motorista', 'Combustível', 'Valor'],
            data: data,
          ),
        ],
      ),
    );
    final bytes = Uint8List.fromList(await pdf.save());
    if (context.mounted) await showPdfActions(context, bytes: bytes, filename: 'relatorio_frotas_abastecimentos.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getNivel(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final nivel = snap.data!;
        if (nivel == 'motorista') {
          return Scaffold(
            appBar: AppBar(title: const Text('Relatórios'), backgroundColor: const Color(0xFF0056b3)),
            body: const Center(child: Text('Motorista não tem acesso aos relatórios. Apenas lançar abastecimento.')),
          );
        }
        // ADM e Usuário: ver e puxar relatórios
        return Scaffold(
          appBar: AppBar(
            title: const Text('Relatórios Completos'),
            backgroundColor: const Color(0xFF0056b3),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: () {}, // Será chamado dentro do builder com os dados reais
              )
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Período: Mês atual, Mês anterior, Por período (data inicial / final)
                    Row(
                      children: [
                        _chip('Mês atual', _filtroPeriodo == 'mes_atual', () => setState(() => _filtroPeriodo = 'mes_atual')),
                        const SizedBox(width: 8),
                        _chip('Mês anterior', _filtroPeriodo == 'mes_anterior', () => setState(() => _filtroPeriodo = 'mes_anterior')),
                        const SizedBox(width: 8),
                        _chip(
                          _filtroPeriodo == 'periodo' && _dataInicial != null && _dataFinal != null
                              ? '${_dataInicial!.day.toString().padLeft(2, '0')}/${_dataInicial!.month.toString().padLeft(2, '0')} - ${_dataFinal!.day.toString().padLeft(2, '0')}/${_dataFinal!.month.toString().padLeft(2, '0')}'
                              : 'Por período',
                          _filtroPeriodo == 'periodo',
                          () async {
                            setState(() => _filtroPeriodo = 'periodo');
                            final start = await showDatePicker(
                              context: context,
                              initialDate: _dataInicial ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (start == null || !mounted) return;
                            final end = await showDatePicker(
                              context: context,
                              initialDate: _dataFinal ?? start,
                              firstDate: start,
                              lastDate: DateTime(2100),
                            );
                            if (mounted && end != null) setState(() {
                              _dataInicial = start;
                              _dataFinal = end;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Frota',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _filtroFrota = v.toUpperCase()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Placa',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _filtroPlaca = v.toUpperCase()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'CPF',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => _filtroCpf = v.replaceAll(RegExp(r'\D'), '')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _dataInicial ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null && mounted) setState(() => _dataInicial = d);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Data inicial',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_dataInicial == null ? 'Selecione' : '${_dataInicial!.day.toString().padLeft(2, '0')}/${_dataInicial!.month.toString().padLeft(2, '0')}/${_dataInicial!.year}'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _dataFinal ?? _dataInicial ?? DateTime.now(),
                                firstDate: _dataInicial ?? DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (d != null && mounted) setState(() => _dataFinal = d);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Data final',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(_dataFinal == null ? 'Selecione' : '${_dataFinal!.day.toString().padLeft(2, '0')}/${_dataFinal!.month.toString().padLeft(2, '0')}/${_dataFinal!.year}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(_horaInicial == null ? 'Horário Inicial' : _horaInicial!.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                              if (picked != null) setState(() => _horaInicial = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.access_time),
                            label: Text(_horaFinal == null ? 'Horário Final' : _horaFinal!.format(context)),
                            onPressed: () async {
                              final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                              if (picked != null) setState(() => _horaFinal = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('abastecimentos').orderBy('data_hora', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    
                    // Aplicação de Filtros: período (mês atual, mês anterior ou por data inicial/final)
                    final (periodoInicio, periodoFim) = _intervaloEfetivo;
                    var docs = snapshot.data!.docs.where((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      final placa = (data['placa'] ?? data['veiculo'] ?? '').toString().toUpperCase();
                      final frota = (data['frota'] ?? '').toString().toUpperCase();
                      final cpf = (data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
                      final dataHora = data['data_hora']?.toDate();
                      bool filtro = true;
                      if (_filtroFrota.isNotEmpty) filtro &= frota.contains(_filtroFrota);
                      if (_filtroPlaca.isNotEmpty) filtro &= placa.contains(_filtroPlaca);
                      if (_filtroCpf.isNotEmpty) filtro &= cpf.contains(_filtroCpf);
                      if (periodoInicio != null && dataHora != null) filtro &= !dataHora.isBefore(periodoInicio);
                      if (periodoFim != null && dataHora != null) filtro &= !dataHora.isAfter(periodoFim);
                      if (_horaInicial != null && dataHora != null) filtro &= dataHora.hour >= _horaInicial!.hour && dataHora.minute >= _horaInicial!.minute;
                      if (_horaFinal != null && dataHora != null) filtro &= dataHora.hour <= _horaFinal!.hour && dataHora.minute <= _horaFinal!.minute;
                      return filtro;
                    }).toList();

                    return Column(
                      children: [
                        FilledButton.icon(
                          onPressed: () => _exportarPDF(context, docs),
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('Exportar PDF'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E40AF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Depois: compartilhar, imprimir ou salvar no dispositivo.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              var data = docs[index].data() as Map<String, dynamic>;
                              final placa = data['placa'] ?? data['veiculo'] ?? '-';
                              final combustivel = data['combustivel'] ?? data['tipo_combustivel'] ?? '';
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.local_gas_station, color: Color(0xFF0056b3)),
                                  title: Text('$placa - ${data['motorista'] ?? '-'}'),
                                  subtitle: Text('Posto: ${data['posto'] ?? '-'} | Valor: R\$ ${data['valor_total'] ?? data['valor'] ?? '-'}'),
                                  trailing: Text(combustivel),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
