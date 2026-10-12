import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../theme/app_colors.dart';
import 'banner_actions.dart';
import 'featured_carousel.dart' show heroHeightFor;
import 'featured_hero.dart' show HeroMeta;
import 'image_fade.dart';
import 'mobile_hero_art.dart';
import 'native_cover_provider.dart';

/// Full-bleed Home banner with centered title art and one details action.
class FeaturedBannerEdge extends StatefulWidget {
  const FeaturedBannerEdge({
    super.key,
    required this.items,
    required this.onInfo,
    this.meta,
    this.reading = false,
  });

  final List<MediaItem> items;
  final void Function(MediaItem) onInfo;
  final Future<HeroMeta?> Function(MediaItem)? meta;
  final bool reading;

  @override
  State<FeaturedBannerEdge> createState() => _FeaturedBannerEdgeState();
}

class _FeaturedBannerEdgeState extends State<FeaturedBannerEdge> {
  late List<MediaItem> _pages;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pages = widget.items.take(6).toList();
    _startTimer();
  }

  @override
  void didUpdateWidget(FeaturedBannerEdge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.items.take(6).toList();
    final changed =
        next.length != _pages.length ||
        (next.isNotEmpty &&
            _pages.isNotEmpty &&
            next.first.id != _pages.first.id);
    if (changed) {
      setState(() {
        _pages = next;
        _index = 0;
      });
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_pages.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _go(1));
    }
  }

  void _go(int delta) {
    if (!mounted || _pages.isEmpty) return;
    setState(() => _index = (_index + delta + _pages.length) % _pages.length);
  }

  @override
  Widget build(BuildContext context) {
    final height = heroHeightFor(context);
    if (_pages.isEmpty) return SizedBox(height: height);

    final item = _pages[_index];
    return RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('featuredEdgeBanner'),
        width: double.infinity,
        height: height,
        child: GestureDetector(
          key: const ValueKey('edgeBannerGesture'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -80) {
              _go(1);
              _startTimer();
            } else if (velocity > 80) {
              _go(-1);
              _startTimer();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(item.id),
                  child: _artwork(item),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x33000000),
                        Color(0xCC0B0B0F),
                        AppColors.bg,
                      ],
                      stops: [0, 0.28, 0.74, 1],
                    ),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  key: ValueKey('edgeBannerContent-${item.id}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 64),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BannerTitleLogo(
                          item: item,
                          maxHeight: 84,
                          maxWidthFactor: 0.78,
                          fontSize: 30,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 18,
                          child: Center(
                            child: BannerMetaLine(
                              metaFuture: widget.meta?.call(item),
                              reading: widget.reading,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: 148,
                          height: 48,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              key: const ValueKey('edgeBannerViewButton'),
                              onTap: () => widget.onInfo(item),
                              borderRadius: BorderRadius.circular(24),
                              child: Center(
                                child: Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: AppColors.bg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
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
              ),
              if (_pages.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (index) {
                      final active = index == _index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: active ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: active ? 1 : 0.55,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artwork(MediaItem item) {
    final url = mobileHeroArt(item.cover, item.banner);
    final provider = url == null || url.isEmpty
        ? null
        : nativeCoverProvider(url, item.coverHeaders);
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF473958), Color(0xFF15151D)],
            ),
          ),
        ),
        if (provider != null)
          Image(
            image: ResizeImage(provider, width: width),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            frameBuilder: imageFadeIn,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}
