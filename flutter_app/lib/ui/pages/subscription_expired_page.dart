import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionExpiredPage extends StatelessWidget {
  final String churchName;
  final String? logoUrl;
  final VoidCallback onRenew;
  final VoidCallback onLogout;

  const SubscriptionExpiredPage({
    super.key,
    required this.churchName,
    required this.onRenew,
    required this.onLogout,
    this.logoUrl,
  });

  Future<void> _openSupportWhatsApp() async {
    final phone = AppConstants.masterSupportWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) return;
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent('Olá, preciso de suporte para renovar a assinatura do sistema.')}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = (logoUrl ?? '').trim().isNotEmpty;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEFF4FF), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.white.withOpacity(0.10)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color(0xFFF3F4F6),
                        child: ClipOval(
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: hasLogo
                                ? SafeNetworkImage(
                                    imageUrl: logoUrl!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 180,
                                    memCacheHeight: 180,
                                    errorWidget: const Icon(Icons.church_rounded, color: Color(0xFF0052CC), size: 32),
                                  )
                                : const Icon(Icons.church_rounded, color: Color(0xFF0052CC), size: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Icon(Icons.lock_rounded, color: Color(0xFFDC2626), size: 34),
                      const SizedBox(height: 10),
                      const Text(
                        'Assinatura Suspensa',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$churchName está com acesso bloqueado após o período de carência.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: onRenew,
                          icon: const Icon(Icons.workspace_premium_rounded),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          label: const Text('Renovar Licença / Pagar Agora'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (AppConstants.masterSupportWhatsApp.trim().isNotEmpty)
                        TextButton.icon(
                          onPressed: _openSupportWhatsApp,
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('Falar com suporte no WhatsApp'),
                        ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: onLogout,
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
