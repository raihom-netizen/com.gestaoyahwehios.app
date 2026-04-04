import 'dart:convert';

import 'package:http/http.dart' as http;

class CitySuggestion {
  final String city;
  final String state;

  const CitySuggestion({required this.city, required this.state});

  String get label => '$city - $state';
}

/// Busca cidades brasileiras por nome (IBGE).
/// Usado como autocomplete para preencher cidade + UF mesmo sem CEP.
Future<List<CitySuggestion>> searchBrazilCities(String query, {int limit = 8}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  try {
    final uri = Uri.parse(
      'https://servicodados.ibge.gov.br/api/v1/localidades/municipios?nome=${Uri.encodeQueryComponent(q)}',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return const [];
    final raw = jsonDecode(response.body);
    if (raw is! List) return const [];

    final startsWith = <CitySuggestion>[];
    final contains = <CitySuggestion>[];
    final seen = <String>{};
    final qLower = q.toLowerCase();

    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final city = (m['nome'] ?? '').toString().trim();
      final uf = (((m['microrregiao'] ?? const {})['mesorregiao'] ?? const {})['UF'] ?? const {});
      final state = (uf is Map ? (uf['sigla'] ?? '') : '').toString().trim().toUpperCase();
      if (city.isEmpty || state.isEmpty) continue;

      final key = '${city.toLowerCase()}|$state';
      if (seen.contains(key)) continue;
      seen.add(key);

      final suggestion = CitySuggestion(city: city, state: state);
      if (city.toLowerCase().startsWith(qLower)) {
        startsWith.add(suggestion);
      } else if (city.toLowerCase().contains(qLower)) {
        contains.add(suggestion);
      }
    }

    final merged = <CitySuggestion>[...startsWith, ...contains];
    return merged.take(limit).toList();
  } catch (_) {
    return const [];
  }
}
