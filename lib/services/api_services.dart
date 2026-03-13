import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:noirscreen/modals/user_model.dart';




class ApiService {
  // Development: Android Emulator - http://
  static const String baseUrl = 'http://10.0.2.2:3000';

  // Register Users
  Future<UserModel?> registerUser({
    required String username,
    required String avatarType,
    int? avatarId,
    File? avatarPhoto,
  }) async {
    try {
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
        var add = request.files.add(file);
      }

          // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final jsonData = json.decode(responseBody);
        return UserModel.fromJson(jsonData['user']);
      } else {
        final errorData = json.decode(responseBody);
        throw Exception(errorData['error'] ?? 'Registration failed');
      }
    } catch (e) {
      print('Register error: $e');
      rethrow;
    }
  }


  // Get user by ID
  Future<UserModel?> getUser(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/$userId'),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return UserModel.fromJson(jsonData['user']);
      } else {
        return null;
      }
    } catch (e) {
      print('Get user error: $e');
      return null;
    }
  }

  }


