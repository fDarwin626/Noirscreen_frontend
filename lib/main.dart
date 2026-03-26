import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:noirscreen/constants/app_colors.dart';
import 'package:noirscreen/screens/splash_screen.dart';
import 'package:noirscreen/screens/home_screen.dart';
import 'package:noirscreen/screens/room_watch_screen.dart';
import 'package:noirscreen/screens/waiting_room_screen.dart';
import 'package:noirscreen/services/rooms_service.dart';
import 'package:noirscreen/services/auth_service.dart';
import 'package:noirscreen/services/api_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // BUG 3 FIX: make the app draw edge-to-edge so our bottom nav bar sits
  // ABOVE the system navigation bar (circle/square/triangle buttons) instead
  // of being hidden behind it. Flutter will report the correct bottom inset
  // via MediaQuery.padding.bottom so our nav bar padding adjusts automatically.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    // Transparent nav bar so our dark bottom nav shows through cleanly
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Tell Android to draw behind the system bars (edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    const ProviderScope(
      child: NoirScreenApp(),
    ),
  );
}

class NoirScreenApp extends StatefulWidget {
  const NoirScreenApp({super.key});

  @override
  State<NoirScreenApp> createState() => _NoirScreenAppState();
}

class _NoirScreenAppState extends State<NoirScreenApp> {
  final _appLinks = AppLinks();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'noirscreen' || uri.host != 'room') return;

    final roomId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (roomId == null || roomId.isEmpty) return;

    print('🔗 DEEP LINK: Received room link for $roomId');

    try {
      final roomsService = RoomsService();
      final authService = AuthService();
      final apiService = ApiService();

      final userId = await authService.getUserId();
      if (userId == null) return;
      final user = await apiService.getUser(userId);
      if (user == null) return;

      final link = 'noirscreen://room/$roomId';
      final room = await roomsService.joinViaLink(link);
      if (room == null) return;

      if (room.status != 'active') {
        _navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => WaitingRoomScreen(
            room: room, currentUser: user, isOwner: false),
        ));
        return;
      }
      _navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => RoomWatchScreen(
          room: room, currentUser: user, isOwner: false,
          localFilePath: null,
          hlsStreamUrl: '${ApiService.baseUrl}/api/rooms/${room.roomId}/stream.m3u8',
        ),
      ));
    } catch (e) {
      print('❌ DEEP LINK: Error handling link - $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoirScreen',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        primaryColor: AppColors.niorRed,
        colorScheme: ColorScheme.dark(
          primary: AppColors.niorRed,
          secondary: AppColors.ashGray,
          surface: AppColors.darkGray,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}