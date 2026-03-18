import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/screens/video_player_screen.dart';
import 'dart:io';
import '../models/series_model.dart';
import '../models/video_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_style.dart';
import '../providers/home_provider.dart';

class SeriesDetailScreen extends ConsumerWidget {
  final SeriesModel series;

  const SeriesDetailScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Make status bar transparent so header bleeds into it
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    final episodesAsync = ref.watch(episodesProvider(series.id));
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: episodesAsync.when(
        data: (episodes) => _buildBody(context, episodes, statusBarHeight),
        loading: () => _buildLoadingState(),
        error: (_, __) => _buildErrorState(context),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<VideoModel> episodes,
    double statusBarHeight,
  ) {
    // Figure out which episode to show in the header:
    // 1. If user is currently watching an episode (has progress) → show that
    // 2. If nothing in progress → show first available episode
    final headerEpisode =
        series.currentEpisode ?? (episodes.isNotEmpty ? episodes.first : null);

    return CustomScrollView(
      slivers: [
        // ── Header section (full bleed thumbnail + play button) ──────
        SliverToBoxAdapter(
          child: _buildHeader(context, headerEpisode, statusBarHeight, episodes),
        ),

        // ── Series info bar ──────────────────────────────────────────
        SliverToBoxAdapter(child: _buildInfoBar(episodes)),

        // ── Episodes section title ───────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text(
              'EPISODES',
              style: AppTextStyles.header3.copyWith(
                color: AppColors.textWhite,
                fontSize: 18,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),

        // ── Episode list (vertical) ──────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final episode = episodes[index];
            final isLast = index == episodes.length - 1;
            return _buildEpisodeRow(context, episode, isLast, episodes);
          }, childCount: episodes.length),
        ),

        // Bottom padding so last episode isn't hidden behind nav bar
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  // Full bleed thumbnail with gradient overlay, series title, and play button
  Widget _buildHeader(
    BuildContext context,
    VideoModel? headerEpisode,
    double statusBarHeight,
    List<VideoModel> episodes,
  ) {
    final headerHeight = MediaQuery.of(context).size.height * 0.45;

    return SizedBox(
      height: headerHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Thumbnail ──────────────────────────────────────────────
          // Shows the exact frame where user stopped watching
          // or episode 1 thumbnail if never watched
          _buildHeaderThumbnail(headerEpisode),

          // ── Top gradient (status bar protection) ──────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.black,
                    AppColors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 1.0],
                ),
              ),
            ),
          ),

          // ── Bottom gradient (content readability) ─────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.charcoal.withOpacity(0.7),
                    AppColors.black,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ── Back button ────────────────────────────────────────────
          Positioned(
            top: statusBarHeight + 8,
            left: 8,
            child: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.black.withOpacity(0.5),
                  border: Border.all(
                    color: AppColors.ashGray.withOpacity(0.2),
                    width: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ── Series title + episode info + play button ──────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Series title
                Text(
                  series.title,
                  style: AppTextStyles.header2.copyWith(
                    color: AppColors.textWhite,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Currently watching episode info
                if (headerEpisode != null) ...[
                  Text(
                    _getHeaderSubtitle(headerEpisode),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.ashGray,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Play button
                GestureDetector(
                  onTap: () {
                    //  navigate to video player
                    if (headerEpisode == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          video: headerEpisode,
                          seriesEpisodes: episodes,
                          series: series,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.charcoal.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          // Show "Continue" if episode has progress
                          // or "Watch Now" if starting fresh
                          (headerEpisode?.watchProgress ?? 0) > 0
                              ? 'Continue Watching'
                              : 'Watch Now',
                          style: AppTextStyles.button.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _buildHeaderThumbnail(VideoModel? episode) {
    if (episode?.thumbnailPath != null) {
      return Image.file(
        File(episode!.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildHeaderPlaceholder(),
      );
    }
    return _buildHeaderPlaceholder();
  }

  Widget _buildHeaderPlaceholder() {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Icon(
          Icons.tv_rounded,
          size: 80,
          color: AppColors.ashGray.withOpacity(0.2),
        ),
      ),
    );
  }

  // Returns subtitle text for the header
  // e.g. "S01E03 • Continuing" or "S01E01 • Start Watching"
  String _getHeaderSubtitle(VideoModel episode) {
    final epTag =
        episode.seasonEpisode ?? 'Episode ${episode.episodeNumber ?? 1}';
    if ((episode.watchProgress ?? 0) > 0) {
      final minutes = (episode.watchProgress! / 60).floor();
      return '$epTag  •  Resume from ${minutes}m';
    }
    return '$epTag  •  Start Watching';
  }

  // ── Info bar (episode count, watched count) ──────────────────────────────
  Widget _buildInfoBar(List<VideoModel> episodes) {
    final watchedCount = episodes.where((e) => e.isCompleted).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      color: AppColors.charcoal,
      child: Row(
        children: [
          _buildInfoChip(
            Icons.video_library_rounded,
            '${series.totalEpisodes} Episodes',
          ),
          const SizedBox(width: 16),
          _buildInfoChip(
            Icons.check_circle_outline_rounded,
            '$watchedCount Watched',
          ),
          const Spacer(),
          // Progress percentage
          if (series.totalEpisodes > 0)
            Text(
              '${((watchedCount / series.totalEpisodes) * 100).toInt()}% complete',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.ashGray,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.ashGray, size: 14),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.ashGray,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ── Episode row (vertical list) ──────────────────────────────────────────
  // Each row: thumbnail | episode info | play button | divider
  Widget _buildEpisodeRow(
    BuildContext context,
    VideoModel episode,
    bool isLast,
    List<VideoModel> episodes,
  ) {
    final isCurrent = series.currentEpisode?.id == episode.id;
    final epLabel = episode.seasonEpisode ?? 'E${episode.episodeNumber ?? '?'}';
    final hasProgress =
        (episode.watchProgress ?? 0) > 0 && episode.duration > 0;

    return Container(
      color: AppColors.charcoal,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // ── Episode thumbnail ────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 65,
                    child: episode.thumbnailPath != null
                        ? Image.file(
                            File(episode.thumbnailPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildEpPlaceholder(),
                          )
                        : _buildEpPlaceholder(),
                  ),
                ),

                const SizedBox(width: 12),

                // ── Episode info ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Episode label (S01E02)
                      Text(
                        epLabel,
                        style: AppTextStyles.caption.copyWith(
                          color: isCurrent
                              ? AppColors.niorRed
                              : AppColors.ashGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Episode title
                      Text(
                        episode.title,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: isCurrent
                              ? AppColors.textWhite
                              : AppColors.textGray,
                          fontSize: 13,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Progress bar if partially watched
                      if (hasProgress) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: episode.watchProgress! / episode.duration,
                            minHeight: 2,
                            backgroundColor: AppColors.ashGray.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.niorRed,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── Play button ──────────────────────────────────────
                GestureDetector(
                  onTap: () {
                    // navigate to video player
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          video: episode,
                          seriesEpisodes: episodes,
                          series: series,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCurrent ? AppColors.niorRed : AppColors.darkGray,
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.niorRed
                            : AppColors.ashGray.withOpacity(0.2),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.textWhite,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Divider (not shown after last episode) ───────────────
          if (!isLast)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: AppColors.ashGray.withOpacity(0.12),
            ),
        ],
      ),
    );
  }

  Widget _buildEpPlaceholder() {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 24,
          color: AppColors.ashGray.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 16),
          Text(
            'Could not load series',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textGray),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              'Go Back',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.niorRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
