import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/frota_firestore_paths.dart';
import '../services/data_formatador.dart';
import '../services/endereco_formatador.dart';

class _MotoristaOption {
  const _MotoristaOption({
    required this.value,
    required this.email,
    required this.nome,
  });

  final String value;
  final String email;
  final String nome;

  String get label => nome.isNotEmpty ? nome : email;
}

class AbastecimentoPage extends StatefulWidget {
  const AbastecimentoPage({super.key});

  @override
  State<AbastecimentoPage> createState() => _AbastecimentoPageState();
}

class _AbastecimentoPageState extends State<AbastecimentoPage> {
  String? veiculoSelecionado;
  String? motoristaSelecionado;
  String? tipoCombustivel;
  final TextEditingController kmController = TextEditingController();
  final TextEditingController postoController = TextEditingController();
  final TextEditingController valorLitroController = TextEditingController(text: '6,00');
  final TextEditingController litrosController = TextEditingController();
  final TextEditingController valorController = TextEditingController();
  DateTime dataHora = DateTime.now();
  bool _capturandoLocalizacao = false;
  double? _latitude;
  double? _longitude;
  String? _googleMapsUrl;
  String? _motoristaEmailLogado;

  List<String> veiculos = [];
  List<_MotoristaOption> motoristas = [];
  List<String> combustiveis = [];

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _motoristaEmailLogado = user.email;
    }
  }

  _MotoristaOption? _findMotorista(String? value) {
    if (value == null) return null;
    for (final m in motoristas) {
      if (m.value == value) return m;
    }
    return null;
  }

  Future<void> _carregarDadosIniciais() async {
    final veiculosSnapshot = await FrotaFirestorePaths.veiculos().get();
    final motoristasSnapshot = await FirebaseFirestore.instance.collection('usuarios').get();
    final combustiveisSnapshot = await FrotaFirestorePaths.combustiveis().get();

    final mapaMotoristas = <String, _MotoristaOption>{};
    for (final doc in motoristasSnapshot.docs) {
      final data = doc.data();
      final ativo = (data['ativo'] as bool?) ?? true;
      if (!ativo) continue;

      final emailOriginal = (data['email'] ?? '').toString().trim();
      final emailNormalizado = emailOriginal.toLowerCase();
      final nome = (data['nome'] ?? '').toString().trim();
      final cpf = (data['cpf'] ?? '').toString().trim();

      if (emailOriginal.isEmpty && nome.isEmpty) continue;

      final value = emailOriginal.isNotEmpty ? emailOriginal : doc.id;
      if (value.isEmpty) continue;

      final chave = emailNormalizado.isNotEmpty
          ? 'e:$emailNormalizado'
          : (cpf.isNotEmpty ? 'c:$cpf' : 'n:${nome.toLowerCase()}');

      final novo = _MotoristaOption(value: value, email: emailOriginal, nome: nome);
      final atual = mapaMotoristas[chave];
      if (atual == null || (atual.nome.isEmpty && novo.nome.isNotEmpty)) {
        mapaMotoristas[chave] = novo;
      }
    }

    final listaMotoristas = mapaMotoristas.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    String removerAcentos(String str) {
      const acentos = 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ';
      const semAcentos = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
      for (int i = 0; i < acentos.length; i++) {
        str = str.replaceAll(acentos[i], semAcentos[i]);
      }
      return str;
    }

    // Normalizar: uma entrada por tipo (só maiúsculas, sem acento). ALCOOL/Álcool unifica com ETANOL.
    final mapaNormalizado = <String, String>{};
    for (final doc in combustiveisSnapshot.docs) {
      final nome = (doc.data()['nome'] ?? '').toString().trim();
      if (nome.isEmpty) continue;
      final key = removerAcentos(nome).toUpperCase();
      final keyUnificado = (key == 'ALCOOL') ? 'ETANOL' : key;
      final atual = mapaNormalizado[keyUnificado];
      final ehMaiuscSemAcento = nome == nome.toUpperCase() && removerAcentos(nome) == nome;
      if (atual == null || ehMaiuscSemAcento) {
        mapaNormalizado[keyUnificado] = keyUnificado;
      }
    }
    final combustiveisDoBanco = mapaNormalizado.values
        .where((n) => n == n.toUpperCase() && removerAcentos(n) == n)
        .where((n) => n == 'ETANOL' || n == 'GASOLINA')
        .toList()
      ..sort((a, b) => a.compareTo(b));

    final listaCombustiveis = combustiveisDoBanco.isNotEmpty
      ? combustiveisDoBanco
      : <String>['GASOLINA', 'ETANOL'];

    if (!mounted) return;
    setState(() {
      veiculos = veiculosSnapshot.docs.map((doc) => doc['placa'] as String).toList();
      motoristas = listaMotoristas;
      combustiveis = listaCombustiveis;
      tipoCombustivel = combustiveis.first;

      if (motoristaSelecionado == null && _motoristaEmailLogado != null) {
        final emailLogado = _motoristaEmailLogado!.trim().toLowerCase();
        final match = motoristas.where((m) => m.email.trim().toLowerCase() == emailLogado).toList();
        if (match.isNotEmpty) {
          motoristaSelecionado = match.first.value;
        }
      }
    });
  }

  Future<void> _salvarAbastecimento() async {
    final erroValidacao = _validarCamposObrigatorios();
    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erroValidacao)));
      return;
    }

    final placa = veiculoSelecionado;
    final combustivel = tipoCombustivel ?? 'GASOLINA';
    final motorista = _findMotorista(motoristaSelecionado);
    final motoristaNome = (motorista?.label ?? motoristaSelecionado ?? '').trim();
    await FrotaFirestorePaths.abastecimentos().add({
      'veiculo': veiculoSelecionado,
      'placa': placa,
      'motorista': motoristaNome,
      'motorista_email': motorista?.email ?? '',
      'km_atual': kmController.text,
      'posto': postoController.text,
      'tipo_combustivel': combustivel,
      'combustivel': combustivel,
      'valor_litro': valorLitroController.text,
      'litros': litrosController.text,
      'valor_total': valorController.text,
      'data_hora': dataHora,
      'latitude': _latitude,
      'longitude': _longitude,
      'localizacao_google_maps': _googleMapsUrl,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abastecimento salvo!')));
  }

  String? _validarCamposObrigatorios() {
    if ((motoristaSelecionado ?? '').trim().isEmpty) {
      return 'Campo obrigatório: motorista.';
    }
    if (postoController.text.trim().isEmpty) {
      return 'Campo obrigatório: nome do posto.';
    }
    if ((tipoCombustivel ?? '').trim().isEmpty) {
      return 'Campo obrigatório: tipo de combustível.';
    }
    if (valorLitroController.text.trim().isEmpty) {
      return 'Campo obrigatório: valor do litro.';
    }
    if (litrosController.text.trim().isEmpty) {
      return 'Campo obrigatório: litros.';
    }
    if (valorController.text.trim().isEmpty) {
      return 'Campo obrigatório: valor total do abastecimento.';
    }
    return null;
  }

  Future<void> _capturarLocalizacao() async {
    setState(() => _capturandoLocalizacao = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ative o serviço de localização do dispositivo para capturar a posição.')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada.')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';

      // Buscar endereço formatado
      String enderecoCompleto = await formatarEnderecoCompleto(position.latitude, position.longitude);
      if (enderecoCompleto.isNotEmpty) {
        postoController.text = enderecoCompleto;
      }

      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _googleMapsUrl = mapsUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Localização capturada com sucesso (opcional).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível capturar a localização: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _capturandoLocalizacao = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Abastecimento'),
        backgroundColor: const Color(0xFF0056b3),
      ),
      body: Container(
        color: const Color(0xFFF5F2F8),
        width: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'LANÇAR COMBUSTÍVEL',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0056b3)),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: veiculoSelecionado,
                    items: veiculos.map((v) => DropdownMenuItem(value: v, child: Text(v.toUpperCase()))).toList(),
                    onChanged: (v) => setState(() => veiculoSelecionado = v),
                    decoration: const InputDecoration(
                      labelText: 'VEÍCULO',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: motoristaSelecionado,
                    items: motoristas.map((m) => DropdownMenuItem(value: m.value, child: Text(m.label.toUpperCase()))).toList(),
                    onChanged: (m) => setState(() => motoristaSelecionado = m),
                    decoration: const InputDecoration(
                      labelText: 'MOTORISTA',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: kmController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'KM ATUAL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Tooltip(
                    message: 'NOME DO POSTO, BAIRRO, CIDADE E ESTADO',
                    child: TextFormField(
                      controller: postoController,
                      decoration: const InputDecoration(
                        labelText: 'NOME DO POSTO',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (v) => postoController.value = postoController.value.copyWith(text: v.toUpperCase()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: tipoCombustivel,
                    items: combustiveis
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (t) => setState(() => tipoCombustivel = t),
                    decoration: const InputDecoration(
                      labelText: 'TIPO DE COMBUSTÍVEL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: valorLitroController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'VALOR DO LITRO (R\$)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: litrosController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'QUANTIDADE DE LITROS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: valorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'VALOR TOTAL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text('DATA/HORA: ${formatarDataHoraBR(dataHora)}')),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: dataHora,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (!context.mounted) return;
                            if (picked != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(dataHora),
                              );
                              if (!context.mounted) return;
                              if (time != null) {
                                setState(() {
                                  dataHora = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Localização Google (opcional)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    onPressed: _capturandoLocalizacao ? null : _capturarLocalizacao,
                    icon: const Icon(Icons.my_location),
                    label: Text(_capturandoLocalizacao ? 'Capturando...' : 'Capturar localização'),
                  ),
                  if (_latitude != null && _longitude != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Localização capturada: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Campos obrigatórios: motorista, nome do posto, data/hora, tipo de combustível, valor do litro, litros e valor total.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0056b3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      onPressed: _salvarAbastecimento,
                      child: const Text(
                        'Salvar Abastecimento',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
