import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/marketing_official_config.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Formulário Master — canais oficiais (Instagram, YouTube, WhatsApp) + nome de exibição.
/// Grava em [MarketingOfficialConfig.firestoreDocPath].
class AdminMarketingCanaisMasterCard extends StatefulWidget {
  const AdminMarketingCanaisMasterCard({super.key});

  @override
  State<AdminMarketingCanaisMasterCard> createState() =>
      _AdminMarketingCanaisMasterCardState();
}

class _AdminMarketingCanaisMasterCardState
    extends State<AdminMarketingCanaisMasterCard> {
  final _ref = FirebaseFirestore.instance
      .doc(MarketingOfficialConfig.firestoreDocPath);

  final _contactCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _contactCtrl.dispose();
    _instagramCtrl.dispose();
    _youtubeCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await _ref.get();
      if (snap.exists && snap.data() != null) {
        final d = snap.data()!;
        _contactCtrl.text = _trimOrEmpty(
          d['contactName'] ?? d['nomeExibicao'] ?? d['displayName'],
        );
        _instagramCtrl.text = _trimOrEmpty(
          d['instagramUrl'] ?? d['instagram'] ?? d['linkInstagram'],
        );
        _youtubeCtrl.text = _trimOrEmpty(
          d['youtubeUrl'] ?? d['youtube'] ?? d['linkYoutube'],
        );
        _whatsappCtrl.text = _trimOrEmpty(
          d['whatsapp'] ?? d['whatsappDigits'] ?? d['whatsappUrl'],
        );
      } else {
        _contactCtrl.clear();
        _instagramCtrl.text = AppConstants.marketingOfficialInstagramUrl;
        _youtubeCtrl.text = AppConstants.marketingOfficialYoutubeUrl;
        _whatsappCtrl.text = AppConstants.marketingOfficialWhatsAppDigits;
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _trimOrEmpty(dynamic v) => (v ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }


  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _ref.set(
        {
          'contactName': _contactCtrl.text.trim().isEmpty
              ? FieldValue.delete()
              : _contactCtrl.text.trim(),
          'instagramUrl': _instagramCtrl.text.trim().isEmpty
              ? FieldValue.delete()
              : _instagramCtrl.text.trim(),
          'youtubeUrl': _youtubeCtrl.text.trim().isEmpty
              ? FieldValue.delete()
              : _youtubeCtrl.text.trim(),
          'whatsapp': _whatsappCtrl.text.trim().isEmpty
              ? FieldValue.delete()
              : _whatsappCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Canais atualizados. Site e telas de login passam a usar estes dados.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: ThemeCleanPremium.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);

    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
        decoration: _cardDecoration(),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
        decoration: _cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: ThemeCleanPremium.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(color: ThemeCleanPremium.error, fontSize: 13),
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Tentar de novo')),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ThemeCleanPremium.primary,
                  Color.lerp(
                    ThemeCleanPremium.primary,
                    ThemeCleanPremium.primaryLight,
                    0.4,
                  )!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Canais oficiais — site e app',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: isMobile ? 17.5 : 18.5,
                          height: 1.2,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Instagram, YouTube e WhatsApp aparecem na página pública de divulgação e nas telas de login. O nome é opcional (ex.: o seu nome ao lado de «Canais oficiais»).',
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.94),
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('Nome de exibição (opcional)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _contactCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputDecoration(
                    hint:
                        'Ex.: Raihom — aparece no título dos canais no site e no app',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('Instagram'),
                const SizedBox(height: 6),
                TextField(
                  controller: _instagramCtrl,
                  keyboardType: TextInputType.url,
                  decoration: _inputDecoration(
                    hint: 'https://www.instagram.com/seu_perfil',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('YouTube'),
                const SizedBox(height: 6),
                TextField(
                  controller: _youtubeCtrl,
                  keyboardType: TextInputType.url,
                  decoration: _inputDecoration(
                    hint: 'https://www.youtube.com/@seu_canal',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('WhatsApp'),
                const SizedBox(height: 6),
                TextField(
                  controller: _whatsappCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    hint:
                        'DDI + número (ex.: 5562987654321) ou https://wa.me/5562987654321',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Campos vazios voltam aos valores padrão do código (AppConstants). Salve para publicar.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _saving ? 'Salvando…' : 'Salvar canais',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: ThemeCleanPremium.primary,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: ThemeCleanPremium.cardBackground,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: ThemeCleanPremium.onSurface,
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: ThemeCleanPremium.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
