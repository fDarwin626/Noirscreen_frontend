import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:io';
import '../models/series_model.dart';
import '../models/video_model.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_style.dart';

class SeriesCardWidget extends StatelessWidget {
  final SeriesModel series;
  final List<VideoModel> previewEpisodes; // First 3 episodes to show inside card
  final VoidCallback onTap;

  const SeriesCardWidget({
    super.key,
    required this.series,
    required this.previewEpisodes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 320,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Dark fallback if no poster
          color: AppColors.darkGray,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Background poster image ──────────────────────────────
              // Shows the series poster (resume frame or episode 1 thumbnail)
              _buildPoster(),

              // ── Dark gradient from middle to bottom ──────────────────
              // Makes the glass card at the bottom readable
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 220,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.black.withOpacity(0.6),
                        AppColors.black.withOpacity(0.95),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Glassmorphism card at bottom ─────────────────────────
              // Frosted glass effect containing series info + episode list
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildGlassCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoster() {
    // Use series poster (which is the resume frame thumbnail)
    if (series.posterUrl != null && series.posterUrl!.isNotEmpty) {
      final file = File(series.posterUrl!);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPosterPlaceholder(),
      );
    }
    return _buildPosterPlaceholder();
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Icon(
          Icons.tv_rounded,
          size: 60,
          color: AppColors.ashGray.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildGlassCard() {
    return ClipRect(
      // ClipRect is required for BackdropFilter to work correctly
      child: BackdropFilter(
        // sigmaX and sigmaY control the blur intensity
        // 12 gives a nice frosted glass look without being too heavy
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // Semi-transparent white gives the glass tint
            color: Colors.white.withOpacity(0.08),
            border: Border(
              top: BorderSide(
                // Thin bright line at the top of the glass — classic glassmorphism
                color: Colors.white.withOpacity(0.2),
                width: 0.8,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Series title + episode count ───────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      series.title,
                      style: AppTextStyles.bodyBold.copyWith(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        letterSpacing: 0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Episode count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.niorRed.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.niorRed.withOpacity(0.5),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      '${series.totalEpisodes} EP',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accentVioletLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Episode preview list (max 3) ───────────────────────
              // Shows first 3 episodes inside the glass card
              ...previewEpisodes.take(3).map(
                    (ep) => _buildEpisodePreviewRow(ep),
                  ),

              // ── "More episodes" hint if series has more than 3 ────
              if (series.totalEpisodes > 3) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+ ${series.totalEpisodes - 3} more episodes',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.ashGray.withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.ashGray.withOpacity(0.7),
                      size: 14,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodePreviewRow(VideoModel episode) {
    // Format episode label e.g. "E1" or use seasonEpisode if available
    final epLabel = episode.seasonEpisode ?? 'E${episode.episodeNumber ?? '?'}';

    // Check if this is the currently watching episode
    final isCurrent = series.currentEpisode?.id == episode.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // Colored dot — violet if currently watching, gray otherwise
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? AppColors.niorRed
                  : AppColors.ashGray.withOpacity(0.4),
            ),
          ),

          // Episode label (e.g. S01E02)
          Text(
            epLabel,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.ashGray,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(width: 6),

          // Episode title
          Expanded(
            child: Text(
              episode.title,
              style: AppTextStyles.caption.copyWith(
                color: isCurrent
                    ? AppColors.textWhite
                    : AppColors.textGray,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Progress bar if episode has been partially watched
          if ((episode.watchProgress ?? 0) > 0 && episode.duration > 0)
            SizedBox(
              width: 30,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: episode.watchProgress! / episode.duration,
                  minHeight: 2,
                  backgroundColor: AppColors.ashGray.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
                ),
              ),
            ),
        ],
      ),
    );
  }
}