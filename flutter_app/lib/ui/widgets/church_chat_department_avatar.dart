import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gestao_yahweh/core/church_department_fa_icons.dart';
import 'package:gestao_yahweh/core/church_department_visual_mapper.dart';

/// Avatar circular com gradiente + ícone FA — mesmo conceito dos cards em `DepartmentsPage`.
class ChurchChatDepartmentAvatar extends StatelessWidget {
  final Map<String, dynamic>? deptData;
  final String fallbackName;
  final double radius;

  const ChurchChatDepartmentAvatar({
    super.key,
    required this.deptData,
    required this.fallbackName,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final raw = deptData != null
        ? ChurchDepartmentVisualMapper.rawIconStringFromDoc(deptData!)
        : '';
    var canonical =
        ChurchDepartmentVisualMapper.mapIconNameToCanonicalKey(raw);
    if (canonical.isEmpty) canonical = 'pastoral';
    final (c1, c2) = ChurchDepartmentThemeGradients.cardGradientArgbPair(
      deptData ?? {},
      canonical,
    );
    final fa = churchDepartmentFaIcon(canonical);
    final sz = radius * 0.88;
    final Widget iconWidget = fa != null
        ? FaIcon(fa, size: sz, color: Colors.white)
        : Icon(Icons.groups_rounded, size: sz, color: Colors.white);
    return Semantics(
      label: fallbackName.isNotEmpty ? fallbackName : 'Grupo do departamento',
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: ClipOval(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(c1), Color(c2)],
              ),
            ),
            alignment: Alignment.center,
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}
