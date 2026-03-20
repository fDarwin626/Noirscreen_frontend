import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scheduled_room_model.dart';
import 'api_services.dart';
import 'auth_service.dart';

class RoomsService {
  final AuthService _authService = AuthService();

  // Get all scheduled rooms for current user
  // Returns active + upcoming rooms, excludes completed/cancelled
  Future<List<ScheduledRoomModel>> getScheduledRooms() async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) return [];

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/rooms/scheduled/$userId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List rooms = data['rooms'] as List;
        return rooms
            .map((r) => ScheduledRoomModel.fromJson(r))
            .toList();
      }

      return [];
    } catch (e) {
      print('❌ ROOMS SERVICE: getScheduledRooms error - $e');
      return [];
    }
  }

  // Create a new scheduled room
  Future<ScheduledRoomModel?> createRoom({
    required String videoHash,
    required String videoTitle,
    required String videoThumbnailPath,
    required String videoFilePath,
    required String streamType,
    required DateTime scheduledAt,
    required int videoDuration,
  }) async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) throw Exception('Not authenticated');

      // Security: validate scheduled time
      // Minimum 2 minutes from now
      // Maximum 5 days from now
      final now = DateTime.now();
      final minTime = now.add(const Duration(minutes: 2));
      final maxTime = now.add(const Duration(days: 5));

      if (scheduledAt.isBefore(minTime)) {
        throw Exception('Room must be scheduled at least 2 minutes from now');
      }

      if (scheduledAt.isAfter(maxTime)) {
        throw Exception('Room cannot be scheduled more than 5 days in advance');
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/rooms/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'host_id': userId,
          'video_hash': videoHash,
          'video_title': videoTitle,
          'video_thumbnail_path': videoThumbnailPath,
          'video_file_path': videoFilePath,
          'stream_type': streamType,
          'scheduled_at': scheduledAt.toIso8601String(),
          'video_duration': videoDuration,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return ScheduledRoomModel.fromJson(data['room']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to create room');
      }
    } catch (e) {
      print('❌ ROOMS SERVICE: createRoom error - $e');
      rethrow;
    }
  }

  // Cancel a scheduled room
  Future<bool> cancelRoom(String roomId) async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) return false;

      final response = await http.patch(
        Uri.parse('${ApiService.baseUrl}/api/rooms/$roomId/cancel'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'host_id': userId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ ROOMS SERVICE: cancelRoom error - $e');
      return false;
    }
  }

  // Join a room via shareable link
  // Returns the room data if link is valid and not expired
  Future<ScheduledRoomModel?> joinViaLink(String shareableLink) async {
    try {
      // Security: validate link format before sending to server
      // Links follow format: noirscreen://room/ROOM_ID
      if (!shareableLink.startsWith('noirscreen://room/')) {
        throw Exception('Invalid room link format');
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/rooms/join'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'link': shareableLink}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ScheduledRoomModel.fromJson(data['room']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Could not join room');
      }
    } catch (e) {
      print('❌ ROOMS SERVICE: joinViaLink error - $e');
      rethrow;
    }
  }

  // Get the most recently completed room for history display
  // Shown at the bottom of the Rooms screen replacing the illustration
  // after at least one room has been completed
  Future<List<ScheduledRoomModel>> getCompletedRooms() async {
    try {
      final userId = await _authService.getUserId();
      if (userId == null) return [];

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/rooms/completed/$userId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List rooms = data['rooms'] as List;
        return rooms
            .map((r) => ScheduledRoomModel.fromJson(r))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ ROOMS SERVICE: getCompletedRooms - $e');
      return [];
    }
  }
}