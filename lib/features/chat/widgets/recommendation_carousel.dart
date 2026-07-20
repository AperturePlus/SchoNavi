import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/system_share_platform.dart';
import '../../../domain/entities/favorite_item.dart';
import '../../../domain/entities/recommendation.dart';
import '../../../features/recommendation/mappers/recommendation_card_mapper.dart';
import '../../../shared/utils/share_text_builder.dart';
import '../../../shared/widgets/swipe_card_carousel.dart';
import '../../../shared/widgets/swipe_recommendation_card.dart';

/// 导师横滑轨道：SwipeCardCarousel + 导师收藏 watch 与回调注入。
class RecommendationCarousel extends ConsumerWidget {
  const RecommendationCarousel({
    super.key,
    required this.recommendations,
    required this.onTap,
    this.onOpenHomepage,
    this.onReportRecommendation,
    this.height,
  });

  final List<Recommendation> recommendations;
  final void Function(String professorId) onTap;
  final void Function(Recommendation recommendation)? onOpenHomepage;
  final void Function(Recommendation recommendation)? onReportRecommendation;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwipeCardCarousel<Recommendation>(
      items: recommendations,
      height: height,
      semanticsLabel: (r) => '${r.name}，${r.university}',
      itemBuilder: (context, r, _) {
        final isFavorite = ref
            .watch(favoriteStatusProvider(r.professorId))
            .maybeWhen(data: (v) => v, orElse: () => false);
        return SwipeRecommendationCard(
          data: r.toCardData(),
          isFavorite: isFavorite,
          onTap: () => onTap(r.professorId),
          onFavoritePressed: () => ref
              .read(favoriteRepositoryProvider)
              .toggle(FavoriteItem.fromRecommendation(r)),
          onOpenUrlPressed: onOpenHomepage == null
              ? null
              : () => onOpenHomepage!(r),
          onSharePressed: ref.read(systemSharePlatformProvider).isSupported
              ? () => _shareRecommendation(context, ref, r)
              : null,
          onLongPress: onReportRecommendation == null
              ? null
              : () => onReportRecommendation!(r),
        );
      },
    );
  }

  Future<void> _shareRecommendation(
    BuildContext context,
    WidgetRef ref,
    Recommendation recommendation,
  ) async {
    final result = await ref
        .read(systemSharePlatformProvider)
        .shareText(ShareTextBuilder.mentor(recommendation));
    if (!context.mounted) return;
    switch (result) {
      case SystemShareResult.launched:
        return;
      case SystemShareResult.unavailable:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前设备未找到可用的分享应用')),
        );
      case SystemShareResult.failed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('打开系统分享失败，请稍后重试')));
    }
  }
}
