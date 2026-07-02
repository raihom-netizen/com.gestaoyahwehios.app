import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Carrossel premium de avisos — painel e site público.
class ChurchAvisosCarousel extends StatefulWidget {
  const ChurchAvisosCarousel({
    super.key,
    required this.churchIdHint,
    this.onManageTap,
    this.compact = false,
  });

  final String churchIdHint;
  final VoidCallback? onManageTap;
  final bool compact;

  @override
  State<ChurchAvisosCarousel> createState() => _ChurchAvisosCarouselState();
}

class _ChurchAvisosCarouselState extends State<ChurchAvisosCarousel> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChurchAvisoItem>>(
      stream: ChurchAvisosLoadService.watchActive(
        churchIdHint: widget.churchIdHint,
      ),
      builder: (context, snap) {
        final items = (snap.data ?? const <ChurchAvisoItem>[])
            .where((a) => a.hasImages)
            .toList();
        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.campaign_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Avisos da igreja',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (widget.onManageTap != null)
                    TextButton.icon(
                      onPressed: widget.onManageTap,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Gerir'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: widget.compact ? 200 : 240,
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) {
                    final aviso = items[index];
                    final urls = aviso.imageUrls;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(ThemeCleanPremium.radiusMd),
                            child: urls.length <= 1
                                ? SafeNetworkImage(
                                    imageUrl: urls.first,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  )
                                : PageView.builder(
                                    itemCount: urls.length,
                                    itemBuilder: (_, pi) => SafeNetworkImage(
                                      imageUrl: urls[pi],
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          aviso.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (aviso.body.isNotEmpty)
                          Text(
                            aviso.body,
                            maxLines: widget.compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (items.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    items.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _page == i ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _page == i
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
