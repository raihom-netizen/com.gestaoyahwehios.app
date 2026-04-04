import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resposta do ViaCEP (Brasil).
class CepResult {
  final String? logradouro;
  final String? bairro;
  final String? localidade;
  final String? uf;
  final String? cep;
  final bool ok;

  CepResult({
    this.logradouro,
    this.bairro,
    this.localidade,
    this.uf,
    this.cep,
    required this.ok,
  });
}

/// Busca endereço por CEP (ViaCEP).
Future<CepResult> fetchCep(String cep) async {
  final digits = cep.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 8) {
    return CepResult(ok: false);
  }
  CepResult? fromMap(Map<String, dynamic>? map, {required bool isViaCep}) {
    if (map == null) return null;
    if (isViaCep && map['erro'] == true) return null;
    final logradouro = ((map['logradouro'] ?? map['street'] ?? '').toString()).trim();
    final bairro = ((map['bairro'] ?? map['neighborhood'] ?? '').toString()).trim();
    final localidade = ((map['localidade'] ?? map['city'] ?? '').toString()).trim();
    final uf = ((map['uf'] ?? map['state'] ?? '').toString()).trim().toUpperCase();
    final cepResp = ((map['cep'] ?? '').toString()).trim();
    final hasAddressData = logradouro.isNotEmpty || bairro.isNotEmpty || localidade.isNotEmpty || uf.isNotEmpty;
    if (!hasAddressData) return null;
    return CepResult(
      logradouro: logradouro.isEmpty ? null : logradouro,
      bairro: bairro.isEmpty ? null : bairro,
      localidade: localidade.isEmpty ? null : localidade,
      uf: uf.isEmpty ? null : uf,
      cep: cepResp.isEmpty ? digits : cepResp,
      ok: true,
    );
  }
  try {
    // 1) ViaCEP (principal)
    final viaCepUri = Uri.parse('https://viacep.com.br/ws/$digits/json/');
    final viaCepResponse = await http.get(viaCepUri).timeout(const Duration(seconds: 8));
    if (viaCepResponse.statusCode == 200) {
      final viaCepMap = jsonDecode(viaCepResponse.body) as Map<String, dynamic>?;
      final result = fromMap(viaCepMap, isViaCep: true);
      if (result != null) return result;
    }
    // 2) BrasilAPI (fallback)
    final brasilApiUri = Uri.parse('https://brasilapi.com.br/api/cep/v1/$digits');
    final brasilApiResponse = await http.get(brasilApiUri).timeout(const Duration(seconds: 8));
    if (brasilApiResponse.statusCode == 200) {
      final brasilApiMap = jsonDecode(brasilApiResponse.body) as Map<String, dynamic>?;
      final result = fromMap(brasilApiMap, isViaCep: false);
      if (result != null) return result;
    }
    return CepResult(ok: false);
  } catch (_) {
    return CepResult(ok: false);
  }
}
