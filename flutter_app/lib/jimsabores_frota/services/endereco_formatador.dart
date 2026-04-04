import 'package:geocoding/geocoding.dart';

/// Formata coordenadas como: Nome do Posto / Bairro / Cidade / Estado.
/// Usa nome do lugar; se vazio, usa logradouro (rua) para a primeira parte.
Future<String> formatarEnderecoCompleto(double latitude, double longitude) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      String nomePosto = (p.name ?? '').trim().toUpperCase();
      if (nomePosto.isEmpty && (p.thoroughfare ?? '').trim().isNotEmpty) {
        nomePosto = (p.thoroughfare ?? '').trim().toUpperCase();
        if ((p.subThoroughfare ?? '').trim().isNotEmpty) {
          nomePosto += ' ${(p.subThoroughfare ?? '').trim().toUpperCase()}';
        }
      }
      if (nomePosto.isEmpty) nomePosto = 'PONTO CAPTURADO';
      final bairro = (p.subLocality ?? '').trim().toUpperCase();
      final cidade = (p.locality ?? '').trim().toUpperCase();
      final estado = (p.administrativeArea ?? '').trim().toUpperCase();
      return [nomePosto, bairro, cidade, estado].where((e) => e.isNotEmpty).join(' / ');
    }
  } catch (_) {}
  return '';
}
