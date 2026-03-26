import 'dart:core';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';


class AuthService {
  // Secure storage instance for user ID (encrypted)
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();

  // Strorage key for user ID
  static const String _userIdKey = 'user_id';

  // generate a new user ID and store it securely
  String  generateUserId(){
    return _uuid.v4();
  }

  // Save user ID to secure storage
  Future<void> saveUserId(String userId) async {
    await _secureStorage.write(key: _userIdKey, value: userId);
  }

  // Retrieve user ID from secure storage
  Future<String?> getUserId() async {
    return await _secureStorage.read(key: _userIdKey);
  }

// Clears the saved userId (used when backend cannot find user)
Future<void>clearUserId()async{
  await _secureStorage.delete(key: 'user_id');
}

  // Check if user is authenticated (has user ID saved)
  Future<bool> isAuthenticated() async {
    final userId = await getUserId();
    return userId != null && userId.isNotEmpty;
  }
  
  // Delete user ID (logout / account deletion)
  Future<void> deleteUserId() async {
    await _secureStorage.delete(key: _userIdKey);
  }
  
  // Clear all secure storage (full reset)
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }

}