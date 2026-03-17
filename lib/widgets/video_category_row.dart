import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'dart:io';
import '../models/video_model.dart';
import '../constants/app_colors.dart';

class VideoCategoryRow extends ConsumerWidget {
  final String title;
  final dynamic provider;

  const VideoCategoryRow({
    super.key,
    required this.title,
    required this.provider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(provider) as AsyncValue<List<VideoModel>>;
    
    return videosAsync.when(
      data: (videos) {
        if (videos.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: AppTextStyles.header3.copyWith(
                  color: AppColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Horizontal scrolling videos
            SizedBox(
              height: 210, // Fixed height
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return _buildVideoCard(video);
                },
              ),
            ),
          ],
        );
      },
      loading: () => _buildLoadingSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildVideoCard(VideoModel video) {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () {
          // TODO: Navigate to video player or series detail
          print('Play video: ${video.title}');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 170,
                width: 130,
                color: AppColors.backgroundCard,
                child: video.thumbnailPath != null
                    ? Image.file(
                        File(video.thumbnailPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),

            const SizedBox(height: 6),

            // Video title (fixed height to prevent overflow)
            SizedBox(
              height: 30,
              child: Text(
                video.title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textWhite,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.darkGray,
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 40,
          color: AppColors.ashGray.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 20,
            width: 150,
            decoration: BoxDecoration(
              color: AppColors.darkGray,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (context, index) {
              return Container(
                width: 130,
                height: 170,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.darkGray,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}