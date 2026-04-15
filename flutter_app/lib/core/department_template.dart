import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_department_visual_mapper.dart';

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
        ChurchDepartmentFirestoreFields.iconName: iconKey,
        ChurchDepartmentFirestoreFields.colorHex:
            ChurchDepartmentVisualMapper.hexStringFromArgb(bgColor1),
        ChurchDepartmentFirestoreFields.colorHexSecondary:
            ChurchDepartmentVisualMapper.hexStringFromArgb(bgColor2),
        'bgColor1': bgColor1,
        'bgColor2': bgColor2,
        'bgImageUrl': '',
        'leaderCpfs': <String>[],
        'leaderCpf': '',
        'viceLeaderCpf': '',
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

/// Onze departamentos base criados quando `departamentos` está vazio (estrutura enxuta).
const List<DepartmentTemplate> kDepartmentWelcomeKit = [
  DepartmentTemplate(
    docId: 'pastoral',
    defaultName: 'Pastoral',
    iconKey: 'pastoral',
    bgColor1: 0xFF0D47A1,
    bgColor2: 0xFF1976D2,
    description: 'Direção espiritual e pastoreio',
    sortOrder: 0,
  ),
  DepartmentTemplate(
    docId: 'louvor',
    defaultName: 'Louvor',
    iconKey: 'louvor',
    bgColor1: 0xFFFF6F00,
    bgColor2: 0xFFFFA726,
    description: 'Adoração e ministério de música',
    sortOrder: 1,
  ),
  DepartmentTemplate(
    docId: 'jovens',
    defaultName: 'Jovens',
    iconKey: 'jovens',
    bgColor1: 0xFFFF5722,
    bgColor2: 0xFFFF7043,
    description: 'Ministério com jovens',
    sortOrder: 2,
  ),
  DepartmentTemplate(
    docId: 'criancas',
    defaultName: 'Crianças',
    iconKey: 'criancas',
    bgColor1: 0xFF00ACC1,
    bgColor2: 0xFF4DD0E1,
    description: 'Ministério infantil',
    sortOrder: 3,
  ),
  DepartmentTemplate(
    docId: 'evangelismo',
    defaultName: 'Evangelismo',
    iconKey: 'evangelismo',
    bgColor1: 0xFF6A1B9A,
    bgColor2: 0xFFAB47BC,
    description: 'Alcance e novos convertidos',
    sortOrder: 4,
  ),
  DepartmentTemplate(
    docId: 'intercessao',
    defaultName: 'Intercessão',
    iconKey: 'intercessao',
    bgColor1: 0xFFE53935,
    bgColor2: 0xFFFF5252,
    description: 'Oração e intercessão',
    sortOrder: 5,
  ),
  DepartmentTemplate(
    docId: 'media',
    defaultName: 'Mídia',
    iconKey: 'media',
    bgColor1: 0xFF1565C0,
    bgColor2: 0xFF42A5F5,
    description: 'Som, imagem e comunicação digital',
    sortOrder: 6,
  ),
  DepartmentTemplate(
    docId: 'recepcao',
    defaultName: 'Recepção',
    iconKey: 'recepcao',
    bgColor1: 0xFFFF9800,
    bgColor2: 0xFFFFB74D,
    description: 'Boas-vindas e acolhimento',
    sortOrder: 7,
  ),
  DepartmentTemplate(
    docId: 'finance',
    defaultName: 'Financeiro',
    iconKey: 'finance',
    bgColor1: 0xFF37474F,
    bgColor2: 0xFF546E7A,
    description: 'Recursos e tesouraria',
    sortOrder: 8,
  ),
  DepartmentTemplate(
    docId: 'escola_biblica',
    defaultName: 'Escola Bíblica',
    iconKey: 'escola_biblica',
    bgColor1: 0xFF00695C,
    bgColor2: 0xFF26A69A,
    description: 'Ensino da Palavra e EBD',
    sortOrder: 9,
  ),
  DepartmentTemplate(
    docId: 'varoes',
    defaultName: 'Varões',
    iconKey: 'varoes',
    bgColor1: 0xFF283593,
    bgColor2: 0xFF3F51B5,
    description: 'Ministério com homens',
    sortOrder: 10,
  ),
];
