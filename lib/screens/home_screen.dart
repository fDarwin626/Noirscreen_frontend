import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:noirscreen/screens/room_screen.dart';
import 'package:noirscreen/services/video_manager_service.dart';
import '../constants/app_colors.dart';
import '../providers/home_provider.dart';
import '../widgets/continue_watching_carousel.dart';
import '../widgets/video_category_row.dart';
import '../widgets/series_card_widget.dart';
import '../screens/series_details_screen.dart';
import '../services/auth_service.dart';
import '../services/api_services.dart';
import '../models/user_model.dart';

class _SpotlightPainter extends CustomPainter {
  final Color color;
  const _SpotlightPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX     = size.width / 2;
    const originY     = 0.0;
    final spreadHalf  = size.width * 0.55;

    final path = Path()
      ..moveTo(centerX - 14, originY)
      ..lineTo(centerX + 14, originY)
      ..lineTo(centerX + spreadHalf, size.height)
      ..lineTo(centerX - spreadHalf, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withOpacity(0.30),
            color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.color != color;
}

class HomeScreen extends ConsumerStatefulWidget {
  final bool shouldRefresh;
  const HomeScreen({super.key, this.shouldRefresh = false});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {

  UserModel? _currentUser;
  bool _isLoadingUser = true;
  int _currentNavIndex = 0;

  List<AnimationController>? _navControllers;
  List<AnimationController>? _spotControllers;
  List<Animation<double>>?   _navScaleAnims;
  List<Animation<double>>?   _navFadeAnims;
  List<Animation<double>>?   _spotAnims;

  AnimationController? _pageCtrl;
  Animation<double>?   _pageAnim;

  AnimationController _navCtrl(int i)   => _navControllers![i];
  AnimationController _spotCtrl(int i)  => _spotControllers![i];
  double _navScale(int i)  => _navScaleAnims?[i].value  ?? 1.0;
  double _navFade(int i)   => _navFadeAnims?[i].value   ?? 1.0;
  double _spotFade(int i)  => _spotAnims?[i].value      ?? 0.0;
  Animation<double> get _pageFade => _pageAnim ?? const AlwaysStoppedAnimation(1.0);

  @override
  void initState() {
    super.initState();

    // FIX: set systemNavigationBarColor to match AppColors.backgroundCard
    // so the Android nav bar visually merges with our bottom nav bar
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF141318), // matches AppColors.backgroundCard
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _navControllers = List.generate(
      5,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );

    _navScaleAnims = _navControllers!.map((c) =>
      Tween<double>(begin: 1.0, end: 1.18).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOutBack),
      ),
    ).toList();

    _navFadeAnims = _navControllers!.map((c) =>
      Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      ),
    ).toList();

    _spotControllers = List.generate(
      5,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      ),
    );

    _spotAnims = _spotControllers!.map((c) =>
      CurvedAnimation(parent: c, curve: Curves.easeOut),
    ).toList();

    _pageCtrl = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _pageAnim = CurvedAnimation(parent: _pageCtrl!, curve: Curves.easeOut);

    _navControllers![0].forward();
    _spotControllers![0].forward();
    _pageCtrl!.forward();

    _loadUserData();

    if (widget.shouldRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _invalidateAll());
    }
  }

  void _invalidateAll() {
    ref.invalidate(allVideosProvider);
    ref.invalidate(downloadedVideosProvider);
    ref.invalidate(whatsappVideosProvider);
    ref.invalidate(mostStreamedProvider);
    ref.invalidate(recentlyWatchedProvider);
    ref.invalidate(moviesProvider);
    ref.invalidate(cameraVideosProvider);
    ref.invalidate(tvShowsProvider);
  }

  @override
  void dispose() {
    _navControllers?.forEach((c) => c.dispose());
    _spotControllers?.forEach((c) => c.dispose());
    _pageCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final uid  = await AuthService().getUserId();
      if (uid != null) {
        final user = await ApiService().getUser(uid);
        if (mounted) setState(() { _currentUser = user; _isLoadingUser = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    if (_navControllers == null || _spotControllers == null) return;
    HapticFeedback.selectionClick();

    _navCtrl(_currentNavIndex).reverse();
    _spotCtrl(_currentNavIndex).reverse();
    _navCtrl(index).forward();
    _spotCtrl(index).forward();

    _pageCtrl?.reverse().then((_) {
      if (!mounted) return;
      setState(() => _currentNavIndex = index);
      _pageCtrl?.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: FadeTransition(
        opacity: _pageFade,
        child: IndexedStack(
          index: _currentNavIndex,
          children: const [
            _HomeContent(),
            _PlaceholderScreen(label: 'My Library'),
            RoomsScreen(),
            _PlaceholderScreen(label: 'Discover'),
            _PlaceholderScreen(label: 'Account'),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context, bottomInset),
    );
  }

  Widget _buildBottomNav(BuildContext context, double bottomInset) {
    return Container(
      // Height covers nav items + system nav bar area so they merge visually
      height: 58,
      decoration: BoxDecoration(
        // FIX: same color as systemNavigationBarColor — merges into one bar
        color: AppColors.backgroundCard,
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(10),
          topRight: Radius.circular(10),
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06), width: 0.8),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft:  Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: Padding(
          // Pushes nav items up, bottom area stays backgroundCard color
          // which visually covers the system nav bar area beneath it
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(CupertinoIcons.house_alt_fill,'Home',     0),
              _buildNavItem(CupertinoIcons.bookmark_solid,'Library',  1),
              _buildNavItem(Icons.grid_view,    'Rooms',    2),
              _buildNavItem(CupertinoIcons.compass, 'Discover', 3),
              _buildNavItemAvatar(4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    if (_navControllers == null || _spotControllers == null) {
      return SizedBox(width: 64, child: Icon(icon, color: AppColors.textGray, size: 22));
    }

    final isActive = _currentNavIndex == index;

    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: AnimatedBuilder(
          animation: Listenable.merge([_navCtrl(index), _spotCtrl(index)]),
          builder: (_, __) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                if (_spotFade(index) > 0)
                  Positioned.fill(
                    child: Opacity(
                      opacity: _spotFade(index),
                      child: CustomPaint(
                        painter: _SpotlightPainter(color: AppColors.niorRed),
                      ),
                    ),
                  ),

                SizedBox(
                  height: 68,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 28 : 0,
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: AppColors.niorRed,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Transform.scale(
                        scale: _navScale(index),
                        child: Opacity(
                          opacity: _navFade(index),
                          child: Icon(
                            icon,
                            color: isActive ? AppColors.niorRed : const Color.fromARGB(255, 255, 255, 255),
                            size: 25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Opacity(
                        opacity: _navFade(index),
                        child: Text(
                          label,
                          style: AppTextStyles.caption.copyWith(
                            color: isActive ? AppColors.niorRed : AppColors.textGray,
                            fontSize: 9.5,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavItemAvatar(int index) {
    if (_navControllers == null || _spotControllers == null) {
      return SizedBox(
        width: 64,
        child: Icon(Icons.person_rounded, color: const Color.fromARGB(255, 255, 255, 255), size: 25),
      );
    }

    final isActive = _currentNavIndex == index;

    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: AnimatedBuilder(
          animation: Listenable.merge([_navCtrl(index), _spotCtrl(index)]),
          builder: (_, __) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                if (_spotFade(index) > 0)
                  Positioned.fill(
                    child: Opacity(
                      opacity: _spotFade(index),
                      child: CustomPaint(
                        painter: _SpotlightPainter(color: AppColors.niorRed),
                      ),
                    ),
                  ),

                SizedBox(
                  height: 68,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        width: isActive ? 28 : 0,
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: AppColors.niorRed,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Transform.scale(
                        scale: _navScale(index),
                        child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isActive ? AppColors.niorRed : Colors.transparent,
                            width: 1.8,
                          ),
                        ),
                        child: ClipOval(
                          child: _isLoadingUser
                              ? Icon(Icons.person_rounded, color: AppColors.textGray, size: 28)
                              : _currentUser != null
                                  ? _buildUserAvatar()
                                  : Icon(Icons.person_rounded, color: AppColors.textGray, size: 28),
                        ),
                      ),
                    ),
                      const SizedBox(height: 4),
                      Opacity(
                        opacity: _navFade(index),
                        child: Text(
                          'Account',
                          style: AppTextStyles.caption.copyWith(
                            color: isActive ? AppColors.niorRed : AppColors.textGray,
                            fontSize: 9.5,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildUserAvatar() {
    if (_currentUser!.avatarType == 'custom' && _currentUser!.photoUrl != null) {
      final photo = _currentUser!.photoUrl!;
      if (photo.startsWith('data:image')) {
        try {
          final b64 = photo.contains(',') ? photo.split(',').last : photo;
          final clean = b64.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');
          final rem  = clean.length % 4;
          final norm = rem == 0 ? clean : clean + '=' * (4 - rem);
          return Image.memory(
            base64Decode(norm),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: AppColors.textGray, size: 28),
          );
        } catch (_) {
          return Icon(Icons.person_rounded, color: AppColors.textGray, size: 28);
        }
      }
      return Image.network(
        '${ApiService.baseUrl}$photo',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person_rounded, color: AppColors.textGray, size: 28),
      );
    } else if (_currentUser!.avatarType == 'default' && _currentUser!.avatarId != null) {
      final id  = _currentUser!.avatarId!;
      final svg = id <= 9 || id == 11 || id == 12;
      final path = 'assets/avatar/avatar ($id).${svg ? 'svg' : 'png'}';
      return svg ? SvgPicture.asset(path, fit: BoxFit.cover) : Image.asset(path, fit: BoxFit.cover);
    }
    return Icon(Icons.person_rounded, color: AppColors.textGray, size: 28);
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyWatched = ref.watch(recentlyWatchedProvider);
    final tvShows         = ref.watch(tvShowsProvider);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return RefreshIndicator(
      color: AppColors.niorRed,
      backgroundColor: AppColors.darkGray,
      onRefresh: () async {
        try { await VideoManagerService().quickScan(); } catch (e) {
          debugPrint('⚠️ HOME: Refresh scan failed - $e');
        }
        ref.invalidate(allVideosProvider);
        ref.invalidate(downloadedVideosProvider);
        ref.invalidate(whatsappVideosProvider);
        ref.invalidate(mostStreamedProvider);
        ref.invalidate(recentlyWatchedProvider);
        ref.invalidate(moviesProvider);
        ref.invalidate(cameraVideosProvider);
        ref.invalidate(tvShowsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                recentlyWatched.when(
                  data: (videos) {
                    if (videos.isEmpty) {
                      return Consumer(builder: (ctx, ref, _) {
                        final dl = ref.watch(downloadedVideosProvider);
                        return dl.when(
                          data: (vids) => vids.isNotEmpty
                              ? ContinueWatchingCarousel(videos: vids.take(5).toList())
                              : const SizedBox.shrink(),
                          loading: () => const _CarouselSkeleton(),
                          error: (_, __) => const SizedBox.shrink(),
                        );
                      });
                    }
                    return ContinueWatchingCarousel(videos: videos);
                  },
                  loading: () => const _CarouselSkeleton(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                Positioned(
                  top: statusBarHeight, left: 0, right: 0,
                  child: _buildHeader(context),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Downloaded Videos', provider: downloadedVideosProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: tvShows.when(
              data: (seriesList) {
                if (seriesList.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('TV SHOWS',
                          style: AppTextStyles.header3.copyWith(
                              color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: seriesList.length,
                        itemBuilder: (context, i) {
                          final series   = seriesList[i];
                          final epAsync  = ref.watch(episodesProvider(series.id));
                          return epAsync.when(
                            data: (eps) => SeriesCardWidget(
                              series: series,
                              previewEpisodes: eps,
                              onTap: () => Navigator.push(
                                  context, _slideRoute(SeriesDetailScreen(series: series))),
                            ),
                            loading: () => Container(
                              width: 220, height: 320,
                              margin: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: AppColors.darkGray, borderRadius: BorderRadius.circular(16)),
                            ),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Most Streamed', provider: mostStreamedProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'WhatsApp Videos', provider: whatsappVideosProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Movies', provider: moviesProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverToBoxAdapter(
            child: VideoCategoryRow(title: 'Camera Videos', provider: cameraVideosProvider),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.black.withOpacity(0.5), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(
            'assets/images/NOIR logo white.png',
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text('NOIRSCREEN',
                style: AppTextStyles.bodyBold.copyWith(
                    color: AppColors.niorRed, fontSize: 13, letterSpacing: 1.2)),
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
}

Route _slideRoute(Widget page) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final slide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        final fade = CurvedAnimation(
            parent: anim, curve: const Interval(0.0, 0.6, curve: Curves.easeIn));
        return SlideTransition(position: slide, child: FadeTransition(opacity: fade, child: child));
      },
    );

class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: MediaQuery.of(context).size.height * 0.62,
        color: AppColors.darkGray,
        child: Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed)),
        ),
      );
}

class _PlaceholderScreen extends StatelessWidget {
  final String label;
  const _PlaceholderScreen({required this.label});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.black,
        body: Center(
          child: Text(label,
              style: AppTextStyles.header3.copyWith(color: AppColors.ashGray)),
        ),
      );
}