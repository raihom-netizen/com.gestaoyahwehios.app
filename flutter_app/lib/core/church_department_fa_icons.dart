import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Ícones Font Awesome para os departamentos base (fallback: Material em [DepartmentsPage]).
IconData? churchDepartmentFaIcon(String iconKey) {
  switch (iconKey) {
    case 'pastoral':
      return FontAwesomeIcons.cross;
    case 'louvor':
    case 'worship':
      return FontAwesomeIcons.music;
    case 'jovens':
    case 'youth':
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
    case 'escola_dominical':
    case 'ebd':
      return FontAwesomeIcons.bookOpen;
    case 'varoes':
    case 'men':
      return FontAwesomeIcons.mars;
    case 'diaconal':
      return FontAwesomeIcons.handHoldingHeart;
    case 'mulheres':
    case 'women':
      return FontAwesomeIcons.venus;
    case 'missionarios':
      return FontAwesomeIcons.earthAmericas;
    case 'obreiros':
      return FontAwesomeIcons.helmetSafety;
    case 'comunicacao':
      return FontAwesomeIcons.towerBroadcast;
    case 'presbiteros':
      return FontAwesomeIcons.scaleBalanced;
    case 'secretarios':
      return FontAwesomeIcons.fileLines;
    case 'social':
      return FontAwesomeIcons.handHoldingHeart;
    case 'auxiliares':
      return FontAwesomeIcons.handshakeAngle;
    default:
      return null;
  }
}
