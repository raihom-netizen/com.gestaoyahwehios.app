import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Ícones Font Awesome para os departamentos base (fallback: Material em [DepartmentsPage]).
IconData? churchDepartmentFaIcon(String iconKey) {
  switch (iconKey) {
    case 'pastoral':
      return FontAwesomeIcons.cross;
    case 'louvor':
      return FontAwesomeIcons.music;
    case 'jovens':
      return FontAwesomeIcons.bolt;
    case 'criancas':
    case 'kids':
      return FontAwesomeIcons.child;
    case 'evangelismo':
      return FontAwesomeIcons.bullhorn;
    case 'intercessao':
    case 'oracao':
    case 'prayer':
      return FontAwesomeIcons.handsPraying;
    case 'media':
      return FontAwesomeIcons.video;
    case 'recepcao':
    case 'welcome':
      return FontAwesomeIcons.doorOpen;
    case 'finance':
    case 'tesouraria':
      return FontAwesomeIcons.wallet;
    case 'escola_biblica':
      return FontAwesomeIcons.bookOpenReader;
    case 'varoes':
    case 'men':
      return FontAwesomeIcons.mars;
    default:
      return null;
  }
}
