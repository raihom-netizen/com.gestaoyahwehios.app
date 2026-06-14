import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/skeleton_loader.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton loading — sensação de velocidade (sem spinner sozinho no carregamento inicial).
abstract final class YahwehSkeletonLoading {
  YahwehSkeletonLoading._();

  static const Color _base = Color(0xFFE2E8F0);
  static const Color _hi = Color(0xFFF8FAFC);

  static Widget _shimmer({required Widget child}) {
    return Shimmer.fromColors(
      baseColor: _base,
      highlightColor: _hi,
      period: const Duration(milliseconds: 1150),
      child: child,
    );
  }

  /// Mural de avisos / feed social.
  static Widget avisosFeed({int postCount = 3}) =>
      YahwehPremiumFeedShimmer.muralFeedSkeleton(postCount: postCount);

  /// Lista de eventos (mesmo layout de post).
  static Widget eventosFeed({int postCount = 3}) =>
      YahwehPremiumFeedShimmer.muralFeedSkeleton(postCount: postCount);

  /// Lista de membros (avatar + 2 linhas).
  static Widget membrosList({int itemCount = 8, double itemHeight = 72}) {
    return SkeletonLoader(itemCount: itemCount, itemHeight: itemHeight);
  }

  /// Dashboard — blocos KPI + destaques.
  static Widget dashboardHome() {
    return _shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(
              2,
              (_) => Expanded(
                child: Container(
                  height: 88,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
          ),
          const SizedBox(height: 16),
          YahwehPremiumFeedShimmer.segmentedBarSkeleton(height: 44),
          const SizedBox(height: 12),
          YahwehPremiumFeedShimmer.birthdayStoriesSkeleton(
            avatarCount: 6,
            listHeight: 120,
          ),
        ],
      ),
    );
  }

  /// Card de aniversariantes no painel.
  static Widget aniversariantes() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shimmer(
            child: Container(
              height: 28,
              width: 160,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 14),
          YahwehPremiumFeedShimmer.segmentedBarSkeleton(height: 46),
          const SizedBox(height: 14),
          YahwehPremiumFeedShimmer.birthdayStoriesSkeleton(
            listHeight: 148,
            avatarRingRadius: 32,
          ),
        ],
      ),
    );
  }

  /// Lista de conversas (chat hub).
  static Widget chatThreads({int count = 10}) {
    return _shimmer(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: count,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bolhas de mensagem (thread).
  static Widget chatMessages({int count = 7}) {
    return _shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemCount: count,
        itemBuilder: (_, i) {
          final sent = i.isOdd;
          return Align(
            alignment:
                sent ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: sent ? 220 : 260,
              height: sent ? 44 : 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(sent ? 14 : 4),
                  bottomRight: Radius.circular(sent ? 4 : 14),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Site público — cartão de publicação.
  static Widget publicFeedPost() {
    return _shimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 160,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cadastro da Igreja — campos do formulário enquanto getDoc() resolve.
  static Widget cadastroForm() {
    return _shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 158,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(
            4,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Genérico para [ChurchPanelLoadingBody] e painéis.
  static Widget panelList({int itemCount = 5}) {
    return membrosList(itemCount: itemCount);
  }
}
