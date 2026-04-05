import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:noirscreen/models/user_model.dart';
import 'package:noirscreen/services/user_cache_service.dart';

class ApiService {

  final UserCacheService _cache = UserCacheService();

  static String get baseUrl {
    const customUrl = String.fromEnvironment('API_URL');
    if (customUrl.isNotEmpty) {
      print('📡 API: Using custom URL');
      return customUrl;
    }

    const isRelease = bool.fromEnvironment('dart.vm.product');
    if (isRelease) {
      print('📡 API: Production');
      return 'https://noirscreen-server.onrender.com';
    }

    print('📡 API: Using emulator URL');
    return 'http://10.0.2.2:3000';
  }

  // Register Users
  Future<UserModel?> registerUser({
    required String username,
    required String avatarType,
    int? avatarId,
    File? avatarPhoto,
  }) async {
    try {
      print('🚀 API: Registering user at $baseUrl/api/users/register');

      final uri = Uri.parse('$baseUrl/api/users/register');
      final request = http.MultipartRequest('POST', uri);

      request.fields['username'] = username;
      request.fields['avatar_type'] = avatarType;

      if (avatarType == 'default' && avatarId != null) {
        request.fields['avatar_id'] = avatarId.toString();
      }

      if (avatarType == 'custom' && avatarPhoto != null) {
        final mimeType = lookupMimeType(avatarPhoto.path) ?? 'image/jpeg';
        final mimeTypeParts = mimeType.split('/');

        final file = await http.MultipartFile.fromPath(
          'avatar_photo',
          avatarPhoto.path,
          contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
        );
        request.files.add(file);
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print('📥 API: Response status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final jsonData = json.decode(responseBody);
        final user = UserModel.fromJson(jsonData['user']);
        await _cache.saveUser(user);
        print('✅ API: User registered and cached successfully');
        return user;
      } else {
        final errorData = json.decode(responseBody);
        print('❌ API: Registration failed - ${errorData['error']}');
        throw Exception(errorData['error'] ?? 'Registration failed');
      }
    } catch (e) {
      print('❌ API: Register error: $e');
      rethrow;
    }
  }

  // Get user by ID
  Future<UserModel?> getUser(String userId) async {
    try {
      print('🔍 API: Getting user $userId from $baseUrl/api/users/$userId');

      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId'),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final user = UserModel.fromJson(jsonData['user']);
        await _cache.saveUser(user);
        print('✅ API: User retrieved and cache updated');
        return user;
      } else {
        print('❌ API: User not found (${response.statusCode})');
        return null;
      }
    } catch (e) {
      print('⚠️ API: Network error, falling back to cache — $e');
      return await _cache.getCachedUser();
    }
  }
}

    // Real device: flutter run --dart-define=API_URL=https://noirscreen-server.onrender.com
    // Release apk: flutter build apk --dart-define=API_URL=https://noirscreen-server.onrender.com