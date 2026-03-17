import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import '../providers/home_provider.dart';
import '../widgets/continue_watching_carousel.dart';
import '../widgets/video_category_row.dart';
import '../services/auth_service.dart';
import '../services/api_services.dart';
import '../models/user_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final bool shouldRefresh;

  const HomeScreen({super.key, this.shouldRefresh = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  UserModel? _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _loadUserData();

    if (widget.shouldRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('🔄 HOME SCREEN: Invalidating all providers (shouldRefresh=true)');
        ref.invalidate(allVideosProvider);
        ref.invalidate(downloadedVideosProvider);
        ref.invalidate(whatsappVideosProvider);
        ref.invalidate(mostStreamedProvider);
        ref.invalidate(recentlyWatchedProvider);
        ref.invalidate(moviesProvider);
        ref.invalidate(cameraVideosProvider);
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final authService = AuthService();
      final apiService = ApiService();

      final userId = await authService.getUserId();
      if (userId != null) {
        final user = await apiService.getUser(userId);
        if (mounted) {
          setState(() {
            _currentUser = user;
            _isLoadingUser = false;
          });
        }
      }
    } catch (e) {
      print('Error loading user: $e');
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentlyWatched = ref.watch(recentlyWatchedProvider);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: CustomScrollView(
        slivers: [
          // ── Hero: full-bleed carousel with floating header on top ──
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Carousel — full bleed from very top of screen
                recentlyWatched.when(
                  data: (videos) {
                    if (videos.isEmpty) {
                      return Consumer(
                        builder: (context, ref, child) {
                          final downloaded = ref.watch(downloadedVideosProvider);
                          return downloaded.when(
                            data: (vids) => vids.isNotEmpty
                                ? ContinueWatchingCarousel(
                                    videos: vids.take(5).toList())
                                : const SizedBox.shrink(),
                            loading: () => const _CarouselSkeleton(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      );
                    }
                    return ContinueWatchingCarousel(videos: videos);
                  },
                  loading: () => const _CarouselSkeleton(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // Header sits exactly below the status bar — no overlap
                Positioned(
                  top: statusBarHeight,
                  left: 0,
                  right: 0,
                  child: _buildHeader(),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 32)),

          // Downloaded Videos
          SliverToBoxAdapter(
            child: VideoCategoryRow(
              title: 'Downloaded Videos',
              provider: downloadedVideosProvider,
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          // Most Streamed
          SliverToBoxAdapter(
            child: VideoCategoryRow(
              title: 'Most Streamed',
              provider: mostStreamedProvider,
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          // WhatsApp Videos
          SliverToBoxAdapter(
            child: VideoCategoryRow(
              title: 'WhatsApp Videos',
              provider: whatsappVideosProvider,
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          // Movies
          SliverToBoxAdapter(
            child: VideoCategoryRow(
              title: 'Movies',
              provider: moviesProvider,
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 24)),

          // Camera Videos
          SliverToBoxAdapter(
            child: VideoCategoryRow(
              title: 'Camera Videos',
              provider: cameraVideosProvider,
            ),
          ),

          // Bottom padding
          SliverToBoxAdapter(child: const SizedBox(height: 100)),
        ],
      ),

      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.black.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(
            'assets/images/Noir.png',
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(
              'NOIRSCREEN',
              style: AppTextStyles.bodyBold.copyWith(
                color: AppColors.niorRed,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.cast_rounded, color: AppColors.textWhite, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: AppColors.textWhite, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        border: Border(
          top: BorderSide(
            color: AppColors.ashGray.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_rounded, 'Home', true, isAvatar: false),
          _buildNavItem(Icons.bookmark_rounded, 'My Library', false,
              isAvatar: false),
          _buildNavItem(Icons.grid_view_rounded, 'Rooms', false,
              isAvatar: false),
          _buildNavItem(Icons.auto_awesome_rounded, 'Discover', false,
              isAvatar: false),
          _buildNavItem(null, 'Account', false, isAvatar: true),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData? icon, String label, bool isActive,
      {required bool isAvatar}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isAvatar) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.niorRed : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: _isLoadingUser
                  ? Icon(Icons.person_rounded,
                      color: AppColors.textGray, size: 20)
                  : _currentUser != null
                      ? _buildUserAvatar()
                      : Icon(Icons.person_rounded,
                          color: AppColors.textGray, size: 20),
            ),
          ),
        ] else ...[
          Icon(
            icon,
            color: isActive ? AppColors.niorRed : AppColors.textGray,
            size: 24,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: isActive ? AppColors.niorRed : AppColors.textGray,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildUserAvatar() {
    if (_currentUser!.avatarType == 'custom' &&
        _currentUser!.photoUrl != null) {
      return Image.network(
        '${ApiService.baseUrl}${_currentUser!.photoUrl}',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person_rounded, color: AppColors.textGray, size: 20),
      );
    } else if (_currentUser!.avatarType == 'default' &&
        _currentUser!.avatarId != null) {
      final avatarId = _currentUser!.avatarId!;
      final isSvg = avatarId <= 9 || avatarId == 11 || avatarId == 12;
      final path =
          'assets/avatar/avatar ($avatarId).${isSvg ? 'svg' : 'png'}';
      if (isSvg) {
        return SvgPicture.asset(path, fit: BoxFit.cover);
      } else {
        return Image.asset(path, fit: BoxFit.cover);
      }
    }
    return Icon(Icons.person_rounded, color: AppColors.textGray, size: 20);
  }
}

// ── Carousel loading skeleton ─────────────────────────────────────────────────
class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.62;
    return Container(
      height: height,
      color: AppColors.darkGray,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
        ),
      ),
    );
  }
}