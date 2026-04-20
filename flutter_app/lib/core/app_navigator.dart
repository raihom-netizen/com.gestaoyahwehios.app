import 'package:flutter/material.dart';

/// Chave do [Navigator] raiz do [MaterialApp].
///
/// Usada por diálogos disparados fora da subárvore do `Navigator` (ex.: [UpdateChecker]
/// envolvendo o app) e por handlers globais — evita `showDialog` com contexto sem
/// `Navigator` ancestral, que no mobile pode aparecer como barrier escuro + caixa branca vazia.
final GlobalKey<NavigatorState> appRootNavigatorKey = GlobalKey<NavigatorState>();
