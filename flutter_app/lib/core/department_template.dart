import 'package:cloud_firestore/cloud_firestore.dart';

/// Modelo de departamento padrão (kit de boas-vindas) — cores, ícone e nome editável depois no Firestore.
class DepartmentTemplate {
  const DepartmentTemplate({
    required this.docId,
    required this.defaultName,
    required this.iconKey,
    required this.bgColor1,
    required this.bgColor2,
    required this.description,
    required this.sortOrder,
  });

  /// ID estável do documento em `igrejas/{id}/departamentos/{docId}`.
  final String docId;

  /// Nome exibido até o gestor personalizar o campo `name`.
  final String defaultName;

  /// Chave visual existente em [departments_page] (`iconKey` / `themeKey`).
  final String iconKey;

  final int bgColor1;
  final int bgColor2;
  final String description;
  final int sortOrder;

  /// Payload para `set` no Firestore (mesma forma dos presets legados).
  Map<String, dynamic> toFirestoreMap(Timestamp now) => <String, dynamic>{
        'name': defaultName,
        'description': description,
        'iconKey': iconKey,
        'themeKey': iconKey,
        'bgColor1': bgColor1,
        'bgColor2': bgColor2,
        'bgImageUrl': '',
        'leaderCpf': '',
        'leaderUid': '',
        'permissions': <String>[],
        'createdAt': now,
        'updatedAt': now,
        'active': true,
        'isDefaultPreset': true,
        'isWelcomeKit': true,
        'welcomeKitOrder': sortOrder,
      };
}

/// Seis departamentos temáticos criados automaticamente quando a subcoleção está vazia.
const List<DepartmentTemplate> kDepartmentWelcomeKit = [
  DepartmentTemplate(
    docId: 'welcome_kids',
    defaultName: 'Kids — Ministério Infantil',
    iconKey: 'criancas',
    bgColor1: 0xFFE91E63,
    bgColor2: 0xFFFF9800,
    description: 'Ambiente lúdico e acolhedor para crianças.',
    sortOrder: 0,
  ),
  DepartmentTemplate(
    docId: 'welcome_jovens',
    defaultName: 'Jovens (Youth)',
    iconKey: 'jovens',
    bgColor1: 0xFF1A237E,
    bgColor2: 0xFF7C4DFF,
    description: 'Conexão, culto e vida em comunidade.',
    sortOrder: 1,
  ),
  DepartmentTemplate(
    docId: 'welcome_mulheres',
    defaultName: 'Mulheres — Círculo de Oração',
    iconKey: 'mulheres',
    bgColor1: 0xFFC2185B,
    bgColor2: 0xFFF48FB1,
    description: 'Unidade, oração e cuidado mútuo.',
    sortOrder: 2,
  ),
  DepartmentTemplate(
    docId: 'welcome_homens',
    defaultName: 'Homens (Varões)',
    iconKey: 'varoes',
    bgColor1: 0xFF0D47A1,
    bgColor2: 0xFF455A64,
    description: 'Discipulado e serviço com responsabilidade.',
    sortOrder: 3,
  ),
  DepartmentTemplate(
    docId: 'welcome_louvor',
    defaultName: 'Louvor e Música',
    iconKey: 'louvor',
    bgColor1: 0xFFE65100,
    bgColor2: 0xFFFFB300,
    description: 'Adoração e ensaios do time de música.',
    sortOrder: 4,
  ),
  DepartmentTemplate(
    docId: 'welcome_social',
    defaultName: 'Ação Social',
    iconKey: 'social',
    bgColor1: 0xFFD84315,
    bgColor2: 0xFF6D4C41,
    description: 'Projetos sociais e acolhimento à comunidade.',
    sortOrder: 5,
  ),
];
