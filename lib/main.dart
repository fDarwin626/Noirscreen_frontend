import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noirscreen/constants/app_colors.dart';
import 'package:noirscreen/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(               
    const ProviderScope(
      child: NoirScreenApp(),
    ),
  );
}
class NoirScreenApp extends StatelessWidget {
  const NoirScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoirScreen',
      debugShowCheckedModeBanner: false,
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


