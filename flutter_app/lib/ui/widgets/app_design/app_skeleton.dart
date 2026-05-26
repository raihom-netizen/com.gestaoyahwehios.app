import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';

export 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart'
    show YahwehSkeletonLoading;

/// Skeleton padronizado — usar em carregamentos iniciais.
abstract final class AppSkeleton {
  AppSkeleton._();

  static Widget feed({int count = 3}) =>
      YahwehSkeletonLoading.avisosFeed(postCount: count);

  static Widget list({int count = 8}) =>
      YahwehSkeletonLoading.membrosList(itemCount: count);

  static Widget chatThreads({int count = 10}) =>
      YahwehSkeletonLoading.chatThreads(count: count);

  static Widget chatMessages({int count = 7}) =>
      YahwehSkeletonLoading.chatMessages(count: count);
}
