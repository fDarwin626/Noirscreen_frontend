import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Persists the logged-in user's data to SharedPreferences so the app
/// can load the user profile even when there is no internet connection.
///
/// Write-through pattern:
///   • Every successful API response calls [saveUser] to keep the cache fresh.
///   • When the API call fails (offline), callers fall back to [getCachedUser].
class UserCacheService {
  static const String _userKey = 'cached_user';

  /// Saves [user] to local storage, overwriting any previous value.
  Future<void> saveUser(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      print('💾 CACHE: User saved — ${user.username}');
    } catch (e) {
      // Cache write failure is non-fatal — app still works, just won't
      // have a fresher offline copy next time.
      print('⚠️ CACHE: Failed to save user — $e');
    }
  }

  /// Returns the last successfully cached [UserModel], or null if nothing
  /// has been cached yet (e.g. first-ever launch with no internet).
  Future<UserModel?> getCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_userKey);
      if (raw == null) {
        print('💾 CACHE: No cached user found');
        return null;
      }
      final user = UserModel.fromJson(jsonDecode(raw));
      print('💾 CACHE: Loaded cached user — ${user.username}');
      return user;
    } catch (e) {
      // Corrupted cache — treat as empty rather than crashing.
      print('⚠️ CACHE: Failed to read user cache — $e');
      return null;
    }
  }

  /// Wipes the cached user. Call this on logout or when the backend
  /// confirms the user no longer exists (e.g. after a DB wipe).
  Future<void> clearUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      print('💾 CACHE: User cache cleared');
    } catch (e) {
      print('⚠️ CACHE: Failed to clear user cache — $e');
    }
  }
}