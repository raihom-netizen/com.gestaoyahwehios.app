import 'package:flutter/material.dart';

/// Modelos visuais de fundo para certificados (luxo).
///
/// **Storage (alta resolução):** envie PNG ou JPG em
/// `igrejas/{tenantId}/templates/certificados/{storageStem}.png` (ou `.jpg`).
/// Nomes sugeridos no painel de configuração / documentação interna.
class CertificateVisualTemplate {
  final String id;
  final String storageStem;
  final String nome;
  final String descricao;
  final List<Color> previewGradient;
  final Color previewBorder;
  final Color previewAccent;

  const CertificateVisualTemplate({
    required this.id,
    required this.storageStem,
    required this.nome,
    required this.descricao,
    required this.previewGradient,
    required this.previewBorder,
    required this.previewAccent,
  });
}

/// Três modelos pedidos: clássico dourado, pergaminho, moderno geométrico.
const List<CertificateVisualTemplate> kCertificateVisualTemplates = [
  CertificateVisualTemplate(
    id: 'classico_dourado',
    storageStem: 'modelo_classico_dourado',
    nome: 'Clássico',
    descricao: 'Moldura ornamental dourada e fundo creme',
    previewGradient: [
      Color(0xFFFFF8E7),
      Color(0xFFF5E6C8),
    ],
    previewBorder: Color(0xFFC9A227),
    previewAccent: Color(0xFFB8860B),
  ),
  CertificateVisualTemplate(
    id: 'pergaminho',
    storageStem: 'modelo_pergaminho',
    nome: 'Pergaminho',
    descricao: 'Papel envelhecido com selo (upload no Storage)',
    previewGradient: [
      Color(0xFFE8D4B8),
      Color(0xFFD4B896),
    ],
    previewBorder: Color(0xFF8B4513),
    previewAccent: Color(0xFF6B3410),
  ),
  CertificateVisualTemplate(
    id: 'moderno_geometrico',
    storageStem: 'modelo_moderno',
    nome: 'Moderno',
    descricao: 'Linhas minimalistas e bordas geométricas',
    previewGradient: [
      Color(0xFFFFFFFF),
      Color(0xFFF1F5F9),
    ],
    previewBorder: Color(0xFF94A3B8),
    previewAccent: Color(0xFF334155),
  ),
];

CertificateVisualTemplate? certificateVisualTemplateById(String id) {
  for (final t in kCertificateVisualTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
