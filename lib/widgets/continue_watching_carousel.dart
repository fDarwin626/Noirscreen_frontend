import 'package:flutter/material.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'dart:async';
import 'dart:io';
import '../models/video_model.dart';
import '../constants/app_colors.dart';

class ContinueWatchingCarousel extends StatefulWidget {
  final List<VideoModel> videos;

  const ContinueWatchingCarousel({
    super.key,
    required this.videos,
  });

  @override
  State<ContinueWatchingCarousel> createState() =>
      _ContinueWatchingCarouselState();
}

class _ContinueWatchingCarouselState extends State<ContinueWatchingCarousel>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController!,
      curve: Curves.easeOut,
    );
    _fadeController!.forward();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || widget.videos.isEmpty) return;
      if (!_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % widget.videos.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _fadeController?.reset();
    _fadeController?.forward();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _fadeController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final carouselHeight = screenHeight * 0.62;

    // ── Rounded bottom corners only — top stays flush with screen edge ──
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: SizedBox(
        height: carouselHeight,
        width: screenWidth,
        child: Stack(
          children: [
            // ── PageView ──────────────────────────────────────────────
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.videos.length,
              itemBuilder: (context, index) =>
                  _buildCarouselItem(widget.videos[index]),
            ),

            // ── Left arrow ────────────────────────────────────────────
            Positioned(
              left: 12,
              top: 0,
              bottom: 80,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    if (_currentPage > 0 && _pageController.hasClients) {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                ),
              ),
            ),

            // ── Right arrow ───────────────────────────────────────────
            Positioned(
              right: 12,
              top: 0,
              bottom: 80,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () {
                    if (_currentPage < widget.videos.length - 1 &&
                        _pageController.hasClients) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                ),
              ),
            ),

            // ── Dot indicators ────────────────────────────────────────
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.videos.length > 7 ? 7 : widget.videos.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    width: _currentPage == i ? 20 : 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: _currentPage == i
                          ? AppColors.niorRed
                          : AppColors.ashGray.withOpacity(0.35),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselItem(VideoModel video) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Poster / thumbnail ─────────────────────────────────────
        video.thumbnailPath != null
            ? Image.file(
                File(video.thumbnailPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),

        // ── Top vignette ───────────────────────────────────────────

       // ── Top vignette ───────────────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.black,
                  AppColors.black.withOpacity(0.75),
                  AppColors.black.withOpacity(0.3),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.6, 1.0],
              ),
            ),
          ),
        ),

        // ── Bottom charcoal/black gradient overlay ─────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.charcoal.withOpacity(0.6),
                  AppColors.charcoal.withOpacity(0.88),
                  AppColors.black,
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // ── Content ───────────────────────────────────────────────
        Positioned(
          left: 20,
          right: 20,
          bottom: 44,
          child: FadeTransition(
            opacity: _fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category chip
                if (video.category.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.niorRed.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.niorRed.withOpacity(0.45),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      video.category.toUpperCase(),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accentVioletLight,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Title
                Text(
                  video.title,
                  style: AppTextStyles.header2.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // Episode tag
                if (video.seasonEpisode != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    video.seasonEpisode!,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.ashGray,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // ── Action row ──────────────────────────────────────
                Row(
                  children: [
                    _WatchButton(
                      hasProgress: (video.watchProgress ?? 0) > 0,
                    ),
                    const SizedBox(width: 12),
                    _IconCircleButton(
                      icon: Icons.info_outline_rounded,
                      onTap: () {},
                    ),
                    const SizedBox(width: 10),
                    _IconCircleButton(
                      icon: Icons.bookmark_border_rounded,
                      onTap: () {},
                    ),
                    const Spacer(),
                    if ((video.watchProgress ?? 0) > 0 &&
                        video.duration > 0) ...[
                      SizedBox(
                        width: 48,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${((video.watchProgress! / video.duration) * 100).toInt()}%',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.ashGray,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: video.watchProgress! / video.duration,
                                minHeight: 3,
                                backgroundColor:
                                    AppColors.ashGray.withOpacity(0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.niorRed),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 80,
          color: AppColors.ashGray.withOpacity(0.2),
        ),
      ),
    );
  }
}

// ─── Watch button ─────────────────────────────────────────────────────────────
class _WatchButton extends StatelessWidget {
  final bool hasProgress;
  final VoidCallback? onTap;

  const _WatchButton({this.hasProgress = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.ashGray.withOpacity(0.18),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, color: AppColors.textWhite, size: 18),
            const SizedBox(width: 7),
            Text(
              hasProgress ? 'Continue' : 'Watch Now',
              style: AppTextStyles.button.copyWith(
                color: AppColors.textWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Icon circle button ───────────────────────────────────────────────────────
class _IconCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.charcoal.withOpacity(0.75),
          border: Border.all(
            color: AppColors.ashGray.withOpacity(0.15),
            width: 0.8,
          ),
        ),
        child: Icon(icon, color: AppColors.textWhite, size: 18),
      ),
    );
  }
}

// ─── Arrow button ─────────────────────────────────────────────────────────────
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.black.withOpacity(0.45),
          border: Border.all(
            color: AppColors.ashGray.withOpacity(0.12),
            width: 0.8,
          ),
        ),
        child: Icon(
          icon,
          color: AppColors.textWhite.withOpacity(0.8),
          size: 22,
        ),
      ),
    );
  }
}