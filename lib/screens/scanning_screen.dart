import 'package:flutter/material.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:noirscreen/screens/home_screen.dart';
import '../constants/app_colors.dart';
import '../services/video_manager_service.dart';

class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> {
  final VideoManagerService _videoManager = VideoManagerService();
  
  String _status = 'Initializing...';
  int _progress = 0;
  int _total = 100;
  bool _isScanning = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      print('🎬 SCANNING SCREEN: Starting scan...');
      
      await _videoManager.fullScan(
        onProgress: (status, current, total) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = current;
              _total = total;
            });
          }
        },
      );
      
      // Scan complete - navigate to home
      print('✅ SCANNING SCREEN: Scan complete! Navigating to home...');
      
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Force navigation with a flag to refresh data
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(shouldRefresh: true),
          ),
        );
      }
    } catch (e) {
      print('❌ SCANNING SCREEN: Error - $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/Asset 1.png',
                width: 50,
                height: 50,
              ),
              const SizedBox(height: 40),

              // Status text
              Text(
                _status,
                style: AppTextStyles.header3.copyWith(
                  color: AppColors.textWhite,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Progress bar
              if (_isScanning && _error == null) ...[
                LinearProgressIndicator(
                  value: _total > 0 ? _progress / _total : 0,
                  backgroundColor: AppColors.darkGray,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.niorRed),
                  minHeight: 6,
                ),

                const SizedBox(height: 16),

                Text(
                  '${_progress}%',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textGray,
                  ),
                ),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 24),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.error,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Error',
                        style: AppTextStyles.bodyBold.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textWhite,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isScanning = true;
                      _error = null;
                      _progress = 0;
                    });
                    _startScan();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.niorRed,
                    foregroundColor: AppColors.textWhite,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Retry',
                    style: AppTextStyles.button,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}