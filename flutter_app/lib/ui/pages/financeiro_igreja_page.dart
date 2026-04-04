import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class FinanceiroIgrejaPage extends StatefulWidget {
  const FinanceiroIgrejaPage({super.key});

  @override
  State<FinanceiroIgrejaPage> createState() => _FinanceiroIgrejaPageState();
}

class _FinanceiroIgrejaPageState extends State<FinanceiroIgrejaPage> {
    List<BarChartGroupData> _gerarDadosGrafico() {
      // Exemplo: agrupando por mês do ano atual
      final now = DateTime.now();
      final Map<int, double> receitasPorMes = {};
      final Map<int, double> despesasPorMes = {};
      for (var r in _receitasLancadas) {
        if (r['data'].year == now.year) {
          receitasPorMes[r['data'].month] = (receitasPorMes[r['data'].month] ?? 0) + (r['valor'] as double);
        }
      }
      for (var d in _despesasLancadas) {
        if (d['data'].year == now.year) {
          despesasPorMes[d['data'].month] = (despesasPorMes[d['data'].month] ?? 0) + (d['valor'] as double);
        }
      }
      return List.generate(12, (i) {
        final mes = i + 1;
        return BarChartGroupData(
          x: mes,
          barRods: [
            BarChartRodData(toY: receitasPorMes[mes] ?? 0, color: Colors.green, width: 10),
            BarChartRodData(toY: despesasPorMes[mes] ?? 0, color: Colors.red, width: 10),
          ],
        );
      });
    }

    List<Map<String, dynamic>> get _receitasLancadas => _receitasLancamentos ?? [];
    List<Map<String, dynamic>> get _despesasLancadas => _despesasLancamentos ?? [];

    // Simulação de lançamentos (substitua pelo seu backend ou lista real)
    List<Map<String, dynamic>>? _receitasLancamentos = [];
    List<Map<String, dynamic>>? _despesasLancamentos = [];
  final List<Map<String, dynamic>> _receitas = [
    {'descricao': 'Dízimos', 'ativo': true},
    {'descricao': 'Ofertas', 'ativo': true},
    {'descricao': 'Campanhas', 'ativo': true},
    {'descricao': 'Doações', 'ativo': true},
    {'descricao': 'Eventos', 'ativo': true},
    {'descricao': 'Aluguéis', 'ativo': true},
  ];
    String _filtroPeriodo = 'Mensal';
    DateTimeRange? _periodoPersonalizado;
  final List<Map<String, dynamic>> _despesas = [
    {'descricao': 'Água', 'ativo': true},
    {'descricao': 'Luz', 'ativo': true},
    {'descricao': 'Internet', 'ativo': true},
    {'descricao': 'Manutenção', 'ativo': true},
    {'descricao': 'Folha de pagamento', 'ativo': true},
    {'descricao': 'Impostos', 'ativo': true},
    {'descricao': 'Material de limpeza', 'ativo': true},
    {'descricao': 'Eventos', 'ativo': true},
  ];
  final _novaCategoriaCtrl = TextEditingController();
  String _tipoNovaCategoria = 'Receita';

  final _formKey = GlobalKey<FormState>();
  String _tipo = 'Receita';
  String _descricao = '';
  double _valor = 0.0;
  DateTime _data = DateTime.now();

  void _adicionarLancamento() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final lancamento = {
      'descricao': _descricao,
      'valor': _valor,
      'data': _data,
    };
    setState(() {
      if (_tipo == 'Receita') {
        _receitas.add(lancamento);
      } else {
        _despesas.add(lancamento);
      }
    });
    _descricao = '';
    _valor = 0.0;
    _data = DateTime.now();
    _formKey.currentState!.reset();
  }

  double get _totalReceitas => _receitas.fold(0.0, (s, e) => s + (e['valor'] as double));
  double get _totalDespesas => _despesas.fold(0.0, (s, e) => s + (e['valor'] as double));

  @override
  void dispose() {
    _novaCategoriaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Despesas e Receitas da Igreja')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Gráfico de Receitas e Despesas', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _filtroPeriodo,
                          items: const [
                            DropdownMenuItem(value: 'Diário', child: Text('Diário')),
                            DropdownMenuItem(value: 'Semanal', child: Text('Semanal')),
                            DropdownMenuItem(value: 'Mensal', child: Text('Mensal')),
                            DropdownMenuItem(value: 'Anual', child: Text('Anual')),
                            DropdownMenuItem(value: 'Personalizado', child: Text('Personalizado')),
                          ],
                          onChanged: (v) async {
                            if (v == 'Personalizado') {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(now.year - 5),
                                lastDate: DateTime(now.year + 1),
                              );
                              if (picked != null) {
                                setState(() {
                                  _filtroPeriodo = v!;
                                  _periodoPersonalizado = picked;
                                });
                              }
                            } else {
                              setState(() {
                                _filtroPeriodo = v!;
                                _periodoPersonalizado = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          barGroups: _gerarDadosGrafico(),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  const meses = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                                  if (value >= 1 && value <= 12) {
                                    return Text(meses[value.toInt() - 1]);
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(show: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Categorias padrão', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Receitas:'),
                              ..._receitas.asMap().entries.map((e) => Row(
                                children: [
                                  Checkbox(
                                    value: e.value['ativo'] == true,
                                    onChanged: (v) => setState(() => _receitas[e.key]['ativo'] = v ?? true),
                                  ),
                                  Expanded(child: Text(e.value['descricao'])),
                                ],
                              )),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Despesas:'),
                              ..._despesas.asMap().entries.map((e) => Row(
                                children: [
                                  Checkbox(
                                    value: e.value['ativo'] == true,
                                    onChanged: (v) => setState(() => _despesas[e.key]['ativo'] = v ?? true),
                                  ),
                                  Expanded(child: Text(e.value['descricao'])),
                                ],
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _tipoNovaCategoria,
                          items: const [
                            DropdownMenuItem(value: 'Receita', child: Text('Receita')),
                            DropdownMenuItem(value: 'Despesa', child: Text('Despesa')),
                          ],
                          onChanged: (v) => setState(() => _tipoNovaCategoria = v ?? 'Receita'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _novaCategoriaCtrl,
                            decoration: const InputDecoration(labelText: 'Nova categoria'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () {
                            final desc = _novaCategoriaCtrl.text.trim();
                            if (desc.isEmpty) return;
                            setState(() {
                              if (_tipoNovaCategoria == 'Receita') {
                                _receitas.add({'descricao': desc, 'ativo': true});
                              } else {
                                _despesas.add({'descricao': desc, 'ativo': true});
                              }
                            });
                            _novaCategoriaCtrl.clear();
                          },
                          child: const Text('Adicionar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DropdownButton<String>(
                            value: _tipo,
                            items: const [
                              DropdownMenuItem(value: 'Receita', child: Text('Receita')),
                              DropdownMenuItem(value: 'Despesa', child: Text('Despesa')),
                            ],
                            onChanged: (v) => setState(() => _tipo = v ?? 'Receita'),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              decoration: const InputDecoration(labelText: 'Descrição'),
                              onSaved: (v) => _descricao = v ?? '',
                              validator: (v) => (v == null || v.isEmpty) ? 'Informe a descrição' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              decoration: const InputDecoration(labelText: 'Valor'),
                              keyboardType: TextInputType.number,
                              onSaved: (v) => _valor = double.tryParse(v ?? '') ?? 0.0,
                              validator: (v) => (v == null || double.tryParse(v) == null) ? 'Valor inválido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Data: '),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _data,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _data = picked);
                            },
                            child: Text('${_data.day}/${_data.month}/${_data.year}'),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _adicionarLancamento,
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Chip(
                  label: Text('Total Receitas: R\$ ${_totalReceitas.toStringAsFixed(2)}'),
                  backgroundColor: Colors.green.shade100,
                ),
                Chip(
                  label: Text('Total Despesas: R\$ ${_totalDespesas.toStringAsFixed(2)}'),
                  backgroundColor: Colors.red.shade100,
                ),
                Chip(
                  label: Text('Saldo: R\$ ${(_totalReceitas - _totalDespesas).toStringAsFixed(2)}'),
                  backgroundColor: Colors.blue.shade100,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Receitas', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _receitas.length,
                            itemBuilder: (context, i) {
                              final r = _receitas[i];
                              return ListTile(
                                title: Text(r['descricao']),
                                subtitle: Text('R\$ ${r['valor'].toStringAsFixed(2)} - ${r['data'].day}/${r['data'].month}/${r['data'].year}'),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Despesas', style: TextStyle(fontWeight: FontWeight.bold)),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _despesas.length,
                            itemBuilder: (context, i) {
                              final d = _despesas[i];
                              return ListTile(
                                title: Text(d['descricao']),
                                subtitle: Text('R\$ ${d['valor'].toStringAsFixed(2)} - ${d['data'].day}/${d['data'].month}/${d['data'].year}'),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
