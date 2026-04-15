import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/roles_permissions.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Boas-vindas únicas no painel da igreja (gestor) — após OK grava em `igrejas/{tenantId}`.

class GestorWelcomeDialog {
  GestorWelcomeDialog._();

  static const _prefKeyPrefix = 'gestor_welcome_ok_';

  static const String _defaultTitulo = 'Seja bem-vindo ao Gestão YAHWEH.';

  static const String _defaultMensagem =
      'Um sistema desenvolvido para trazer organização, controle e excelência à administração da sua igreja, de forma simples, prática e segura.';

  static const String _defaultTemaHex = '#1976D2';

  static bool _eligeParaModal(String role) {
    final n = ChurchRolePermissions.normalize(role);

    return n == ChurchRoleKeys.gestor || n == ChurchRoleKeys.adm;
  }

  static Color _parseHex(String? raw) {
    var s = (raw ?? '').trim();

    if (s.isEmpty) s = _defaultTemaHex;

    if (s.startsWith('#')) s = s.substring(1);

    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);

      if (v != null) return Color(0xFF000000 | v);
    }

    return const Color(0xFF1976D2);
  }

  /// Chama após o primeiro frame do [IgrejaCleanShell] (gestor/adm).

  static Future<void> tryShowIfNeeded({
    required BuildContext context,
    required String tenantId,
    required String role,
  }) async {
    if (!context.mounted) return;

    if (!_eligeParaModal(role)) return;

    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool('$_prefKeyPrefix$tenantId') == true) return;

    try {
      final igrejaSnap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .get(const GetOptions(source: Source.server));

      final ig = igrejaSnap.data();

      if (ig != null && ig['gestorBoasVindasModalOkAt'] != null) {
        await prefs.setBool('$_prefKeyPrefix$tenantId', true);

        return;
      }
    } catch (_) {
      return;
    }

    if (!context.mounted) return;

    Map<String, dynamic> sistema = {};

    try {
      final sys = await FirebaseFirestore.instance
          .doc('config/sistema')
          .get(const GetOptions(source: Source.server));

      sistema = sys.data() ?? {};
    } catch (_) {}

    final titulo = (sistema['titulo'] ?? _defaultTitulo).toString().trim();

    final mensagem =
        (sistema['mensagemBoasVindas'] ?? _defaultMensagem).toString().trim();

    final temaHex = (sistema['temaCor'] ?? _defaultTemaHex).toString();

    final accent = _parseHex(temaHex);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GestorWelcomeBody(
        titulo: titulo.isNotEmpty ? titulo : _defaultTitulo,
        mensagem: mensagem.isNotEmpty ? mensagem : _defaultMensagem,
        accent: accent,
        onOk: () async {
          // Grava local primeiro e fecha já — o `set` no Firestore pode demorar ou
          // bloquear (rede/offline no Windows) e o utilizador ficava preso no modal.
          final p = await SharedPreferences.getInstance();
          await p.setBool('$_prefKeyPrefix$tenantId', true);
          if (!ctx.mounted) return;
          Navigator.of(ctx, rootNavigator: true).pop();
          unawaited(
            FirebaseFirestore.instance
                .collection('igrejas')
                .doc(tenantId)
                .set(
                  {
                    'gestorBoasVindasModalOkAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true),
                )
                .timeout(const Duration(seconds: 25))
                .catchError((_) {}),
          );
        },
      ),
    );
  }
}

class _GestorWelcomeBody extends StatelessWidget {
  final String titulo;

  final String mensagem;

  final Color accent;

  final Future<void> Function() onOk;

  const _GestorWelcomeBody({
    required this.titulo,
    required this.mensagem,
    required this.accent,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);

    final mq = MediaQuery.sizeOf(context);

    final maxH = (mq.height * 0.92).clamp(320.0, 900.0);

    final dialogW = (mq.width - 40).clamp(280.0, 460.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: dialogW,
        height: maxH,
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WelcomeHeader(
                accent: accent,
                titulo: titulo,
                onClose: () async {
                  await onOk();
                },
              ),
              Expanded(
                child: Material(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mensagem,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              'Cor do tema no sistema',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Personalização global é feita no Painel Master. '
                          'Esta mensagem é exibida uma vez por igreja.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.white,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          await onOk();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'OK — Continuar',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  final Color accent;

  final String titulo;

  final Future<void> Function() onClose;

  const _WelcomeHeader({
    required this.accent,
    required this.titulo,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 8, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent,
            Color.lerp(accent, const Color(0xFF0F172A), 0.25)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.waving_hand_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Bem-vindo',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () async {
                  await onClose();
                },
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.95),
                  size: 26,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
