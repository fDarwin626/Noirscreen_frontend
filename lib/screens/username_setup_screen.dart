import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noirscreen/constants/app_text_style.dart';
import 'package:noirscreen/services/api_services.dart';
import 'package:noirscreen/services/auth_service.dart';
import 'dart:io';
import '../constants/app_colors.dart';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  int _selectedIndex = -1;
  File? _selectedImage;
  bool _isLoading = false;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // Each entry maps to the exact file format present in assets/avatar/
  // SVG = true, PNG = false
  // Update this list as you add more avatars
  final List<_AvatarAsset> _avatars = const [
    _AvatarAsset(path: 'assets/avatar/avatar (1).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (2).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (3).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (4).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (5).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (6).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (7).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (8).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (9).svg',  isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (10).png', isSvg: false),
    _AvatarAsset(path: 'assets/avatar/avatar (11).svg', isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (12).svg', isSvg: true),
    _AvatarAsset(path: 'assets/avatar/avatar (13).png', isSvg: false),
    _AvatarAsset(path: 'assets/avatar/avatar (14).png', isSvg: false),
    _AvatarAsset(path: 'assets/avatar/avatar (15).png', isSvg: false),
    _AvatarAsset(path: 'assets/avatar/avatar (16).png', isSvg: false),
    // ↓ Add your remaining avatars here as you create them
    // _AvatarAsset(path: 'assets/avatar/avatar (17).svg', isSvg: true),
    // _AvatarAsset(path: 'assets/avatar/avatar (18).png', isSvg: false),
    // _AvatarAsset(path: 'assets/avatar/avatar (19).png', isSvg: false),
    // _AvatarAsset(path: 'assets/avatar/avatar (20).png', isSvg: false),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _selectedIndex = -1;
      });
    }
  }

Future<void> _handleDone() async {
  // Validate username
  if (_usernameController.text.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please enter a username',
            style: AppTextStyles.bodyMedium),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
    return;
  }

  // Validate avatar/photo selection
  if (_selectedIndex == -1 && _selectedImage == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Please choose an avatar',
            style: AppTextStyles.bodyMedium),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    final apiService = ApiService();
    final authService = AuthService();

    // Determine avatar type
    final avatarType = _selectedImage != null ? 'custom' : 'default';
    final avatarId = _selectedIndex != -1 ? _selectedIndex + 1 : null;

    // Register user with backend
    final user = await apiService.registerUser(
      username: _usernameController.text.trim(),
      avatarType: avatarType,
      avatarId: avatarId,
      avatarPhoto: _selectedImage,
    );

    if (user == null) {
      throw Exception('Failed to create user');
    }

    // Save user ID to secure storage
    await authService.saveUserId(user.userId);

    if (!mounted) return;

    // Success! Show welcome message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Account created! Welcome @${user.username}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textWhite,
            )),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );

    // TODO: Navigate to home screen
    // await Future.delayed(const Duration(seconds: 2));
    // Navigator.pushReplacement(
    //   context,
    //   MaterialPageRoute(builder: (context) => const HomeScreen()),
    // );

  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textWhite,
            )),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
  @override
  Widget build(BuildContext context) {
    final double avatarSize =
        (MediaQuery.of(context).size.width - 48 - (3 * 16)) / 4;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: GestureDetector(
            onTap: _focusNode.unfocus,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Logo ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Image.asset(
                    'assets/images/NOIR logo white.png',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                ),

                const SizedBox(height: 28),

                // ── Heading ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Who's going on\nan adventure?",
                    style: AppTextStyles.header1.copyWith(
                      color: AppColors.textWhite,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Avatar grid ──────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1,
                      ),
                      // 20 avatars + 1 upload tile
                      itemCount: _avatars.length + 1,
                      itemBuilder: (context, index) {
                        // Last tile = upload from gallery
                        if (index == _avatars.length) {
                          return _UploadTile(
                            size: avatarSize,
                            selectedImage: _selectedImage,
                            onTap: _pickImage,
                          );
                        }
                        return _AvatarTile(
                          size: avatarSize,
                          asset: _avatars[index],
                          isSelected: _selectedIndex == index,
                          onTap: () => setState(() {
                            _selectedIndex = index;
                            _selectedImage = null;
                          }),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Divider ──────────────────────────────────────────────
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 24,
                  endIndent: 24,
                  color: AppColors.ashGray.withOpacity(0.1),
                ),

                const SizedBox(height: 20),

                // ── Username field ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _UsernameField(
                    controller: _usernameController,
                    focusNode: _focusNode,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Done button ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.niorRed,
                        foregroundColor: AppColors.textWhite,
                        disabledBackgroundColor: AppColors.darkGray,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text(
                              'Done',
                              style: AppTextStyles.button.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar asset model
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarAsset {
  const _AvatarAsset({required this.path, required this.isSvg});
  final String path;
  final bool isSvg;
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar tile
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.size,
    required this.asset,
    required this.isSelected,
    required this.onTap,
  });

  final double size;
  final _AvatarAsset asset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1C24),
          border: Border.all(
            color: isSelected ? AppColors.accentGold : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipOval(
          child: asset.isSvg
              ? SvgPicture.asset(
                  asset.path,
                  fit: BoxFit.cover,
                  placeholderBuilder: (_) => Icon(
                    Icons.person_outline,
                    size: 24,
                    color: AppColors.ashGray,
                  ),
                )
              : Image.asset(
                  asset.path,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person_outline,
                    size: 24,
                    color: AppColors.ashGray,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload tile
// ─────────────────────────────────────────────────────────────────────────────
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.size,
    required this.selectedImage,
    required this.onTap,
  });

  final double size;
  final File? selectedImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool hasImage = selectedImage != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1C24),
          border: Border.all(
            color: hasImage
                ? AppColors.niorRed
                : AppColors.ashGray.withOpacity(0.25),
            width: hasImage ? 2.5 : 1.5,
          ),
        ),
        child: ClipOval(
          child: hasImage
              ? Image.file(selectedImage!, fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: AppColors.ashGray.withOpacity(0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Photo',
                      style: TextStyle(
                        color: AppColors.ashGray.withOpacity(0.45),
                        fontSize: 9,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Username field
// ─────────────────────────────────────────────────────────────────────────────
class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: AppTextStyles.bodyLarge.copyWith(
        color: AppColors.textWhite,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      maxLength: 20,
      cursorColor: AppColors.niorRed,
      decoration: InputDecoration(
        hintText: 'your_username',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textGray.withOpacity(0.3),
          fontSize: 18,
        ),
        prefixText: '@  ',
        prefixStyle: AppTextStyles.bodyLarge.copyWith(
          color: AppColors.accentVioletLight.withOpacity(0.5),
          fontSize: 18,
        ),
        labelText: 'USERNAME',
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textGray,
          fontSize: 11,
          letterSpacing: 2.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textGray,
          fontSize: 11,
          letterSpacing: 2.5,
          fontWeight: FontWeight.w600,
        ),
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.ashGray.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.ashGray.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: AppColors.niorRed,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.only(bottom: 8, top: 20),
        counterStyle: AppTextStyles.caption.copyWith(
          color: AppColors.textGray.withOpacity(0.3),
          fontSize: 10,
        ),
      ),
    );
  }
}