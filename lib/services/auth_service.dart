import 'dart:core';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:noirscreen/services/user_cache_service.dart'; // ← CHANGED: import cache

class AuthService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();

  static const String _userIdKey = 'user_id';

  String generateUserId() {
    return _uuid.v4();
  }

  Future<void> saveUserId(String userId) async {
    await _secureStorage.write(key: _userIdKey, value: userId);
  }

  Future<String?> getUserId() async {
    return await _secureStorage.read(key: _userIdKey);
  }

  Future<void> clearUserId() async {
    await _secureStorage.delete(key: 'user_id');
  }

  Future<bool> isAuthenticated() async {
    final userId = await getUserId();
    return userId != null && userId.isNotEmpty;
  }

  Future<void> deleteUserId() async {
    await _secureStorage.delete(key: _userIdKey);
  }

  /// Full reset — wipes both the secure userId AND the cached user profile.
  /// Call this on logout or account deletion.
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await UserCacheService().clearUser(); // ← CHANGED: keep both storages in sync
    print('🔐 AUTH: All auth data and user cache cleared');
  }
}