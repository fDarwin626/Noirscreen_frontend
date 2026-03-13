import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

// Provider for AuthService (singleton)
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// Provider to check authentication status
final authStateProvider = FutureProvider<bool>((ref) async {
  final authService = ref.read(authServiceProvider);
  return await authService.isAuthenticated();
});

// Provider for current user ID
final userIdProvider = FutureProvider<String?>((ref) async {
  final authService = ref.read(authServiceProvider);
  return await authService.getUserId();
});