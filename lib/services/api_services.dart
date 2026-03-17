import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:noirscreen/models/user_model.dart';

class ApiService {
  // Smart URL selection:
  // - Emulator: http://10.0.2.2:3000 (automatic)
  // - Real Device: http://192.168.0.113:3000 (use --dart-define=API_URL=...)
  // - Production: https://your-server.com (use --dart-define=API_URL=...)
  
  static String get baseUrl {
    // Check if a custom API URL was provided at runtime
    const customUrl = String.fromEnvironment('API_URL');
    
    if (customUrl.isNotEmpty) {
      print('📡 API: Using custom URL: $customUrl');
      return customUrl;
    }
    
    // Default: Use emulator URL (works for Android emulator)
    print('📡 API: Using emulator URL: http://10.0.2.2:3000');
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

      // Add text fields
      request.fields['username'] = username;
      request.fields['avatar_type'] = avatarType;
      
      if (avatarType == 'default' && avatarId != null) {
        request.fields['avatar_id'] = avatarId.toString();
      }
      
      // Add photo if custom avatar
      if (avatarType == 'custom' && avatarPhoto != null) {
        final file = await http.MultipartFile.fromPath(
          'avatar_photo',
          avatarPhoto.path,
        );
        request.files.add(file);
      }

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print('📥 API: Response status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final jsonData = json.decode(responseBody);
        print('✅ API: User registered successfully');
        return UserModel.fromJson(jsonData['user']);
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
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('✅ API: User retrieved successfully');
        return UserModel.fromJson(jsonData['user']);
      } else {
        print('❌ API: User not found (${response.statusCode})');
        return null;
      }
    } catch (e) {
      print('❌ API: Get user error: $e');
      return null;
    }
  }
}