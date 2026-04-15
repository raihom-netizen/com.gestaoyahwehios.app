import 'dart:convert';

import 'package:http/http.dart' as http;

/// Dados públicos de CNPJ via [BrasilAPI](https://brasilapi.com.br/docs).
class BrasilCnpjResult {
  final bool ok;
  final String? razaoSocial;
  final String? nomeFantasia;
  final String? logradouro;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? municipio;
  final String? uf;
  final String? cep;
  final String? telefone;
  final String? email;
  final String? rawError;

  const BrasilCnpjResult({
    required this.ok,
    this.razaoSocial,
    this.nomeFantasia,
    this.logradouro,
    this.numero,
    this.complemento,
    this.bairro,
    this.municipio,
    this.uf,
    this.cep,
    this.telefone,
    this.email,
    this.rawError,
  });

  static BrasilCnpjResult fail(String msg) =>
      BrasilCnpjResult(ok: false, rawError: msg);
}

String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Busca CNPJ (14 dígitos) — preenche razão social, fantasia e endereço quando disponível.
Future<BrasilCnpjResult> fetchCnpjBrasilApi(String cnpj) async {
  final d = _onlyDigits(cnpj);
  if (d.length != 14) {
    return BrasilCnpjResult.fail('Informe 14 dígitos do CNPJ.');
  }
  try {
    final uri = Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$d');
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      return BrasilCnpjResult.fail('CNPJ não encontrado ou indisponível (${res.statusCode}).');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>?;
    if (map == null) return BrasilCnpjResult.fail('Resposta inválida.');
    final razao = (map['razao_social'] ?? '').toString().trim();
    final fantasia = (map['nome_fantasia'] ?? '').toString().trim();
    return BrasilCnpjResult(
      ok: true,
      razaoSocial: razao.isEmpty ? null : razao,
      nomeFantasia: fantasia.isEmpty ? null : fantasia,
      logradouro: _s(map['descricao_tipo_logradouro'], map['logradouro']),
      numero: nullIfEmpty(map['numero']),
      complemento: nullIfEmpty(map['complemento']),
      bairro: nullIfEmpty(map['bairro']),
      municipio: nullIfEmpty(map['municipio']),
      uf: nullIfEmpty(map['uf']),
      cep: nullIfEmpty(map['cep']),
      telefone: _fone(map),
      email: nullIfEmpty(map['email']),
    );
  } catch (e) {
    return BrasilCnpjResult.fail('$e');
  }
}

String? nullIfEmpty(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

String? _s(dynamic tipo, dynamic log) {
  final t = (tipo ?? '').toString().trim();
  final l = (log ?? '').toString().trim();
  if (l.isEmpty) return null;
  if (t.isEmpty) return l;
  return '$t $l';
}

String? _fone(Map<String, dynamic> map) {
  final ddd = (map['ddd_telefone_1'] ?? '').toString().trim();
  final tel = (map['telefone_1'] ?? '').toString().trim();
  if (tel.isEmpty) return null;
  if (ddd.isEmpty) return tel;
  return '($ddd) $tel';
}
