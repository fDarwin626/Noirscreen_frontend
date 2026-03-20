import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'api_services.dart';

class RoomWatchService {
  final String roomId;
  final String userId;
  final bool isOwner;

  IO.Socket? _socket;
  bool _connected = false;

  RoomWatchService({
    required this.roomId,
    required this.userId,
    required this.isOwner,
  });

  Future<void> connect({
    required void Function(int position) onPlay,
    required void Function(int position) onPause,
    required void Function(int position) onSeek,
    required void Function(String userId, String username, String? avatarPath)
        onParticipantJoined,
    required void Function(String userId) onParticipantLeft,
    required void Function(String userId, bool isSpeaking) onSpeaking,
    required void Function(String userId) onMuted,
    required void Function(String userId) onKicked,
    required void Function() onRoomEnded,
  }) async {
    try {
      _socket = IO.io(
        ApiService.baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .setQuery({'userId': userId, 'roomId': roomId})
            .build(),
      );

      _socket!.connect();

      _socket!.onConnect((_) {
        _connected = true;
        print('✅ ROOM SERVICE: Connected to room $roomId');
        _socket!.emit('join_room', {
          'roomId': roomId,
          'userId': userId,
        });
      });

      _socket!.onDisconnect((_) {
        _connected = false;
        print('⚠️ ROOM SERVICE: Disconnected from room $roomId');
      });

      _socket!.onConnectError((data) {
        print('❌ ROOM SERVICE: Connection error - $data');
      });

      // Receive play command from owner
      _socket!.on('room_play', (data) {
        if (isOwner) return;
        onPlay(_safeInt(data['position']));
      });

      // Receive pause command from owner
      _socket!.on('room_pause', (data) {
        if (isOwner) return;
        onPause(_safeInt(data['position']));
      });

      // Receive seek command from owner
      _socket!.on('room_seek', (data) {
        if (isOwner) return;
        onSeek(_safeInt(data['position']));
      });

      // Someone joined the room
      _socket!.on('participant_joined', (data) {
        final uid = data['userId'] as String? ?? '';
        final uname = data['username'] as String? ?? 'User';
        final avatar = data['avatarPath'] as String?;
        if (uid.isEmpty) return;
        onParticipantJoined(uid, uname, avatar);
      });

      // Someone left the room
      _socket!.on('participant_left', (data) {
        final uid = data['userId'] as String? ?? '';
        if (uid.isEmpty) return;
        onParticipantLeft(uid);
      });

      // Speaking indicator — rings pulse on avatar
      _socket!.on('speaking', (data) {
        final uid = data['userId'] as String? ?? '';
        final speaking = data['speaking'] as bool? ?? false;
        if (uid.isEmpty) return;
        onSpeaking(uid, speaking);
      });

      // Owner muted someone
      _socket!.on('user_muted', (data) {
        final uid = data['userId'] as String? ?? '';
        if (uid.isEmpty) return;
        onMuted(uid);
      });

      // Owner kicked someone
      _socket!.on('user_kicked', (data) {
        final uid = data['userId'] as String? ?? '';
        if (uid.isEmpty) return;
        onKicked(uid);
      });

      // Owner ended the room
      _socket!.on('room_ended', (_) => onRoomEnded());

    } catch (e) {
      print('❌ ROOM SERVICE: connect error - $e');
    }
  }

  // Owner sends play
  void sendPlay(int positionSeconds) {
    if (!_connected || !isOwner) return;
    _socket!.emit('room_play', {
      'roomId': roomId,
      'userId': userId,
      'position': positionSeconds,
    });
  }

  // Owner sends pause
  void sendPause(int positionSeconds) {
    if (!_connected || !isOwner) return;
    _socket!.emit('room_pause', {
      'roomId': roomId,
      'userId': userId,
      'position': positionSeconds,
    });
  }

  // Owner sends seek
  void sendSeek(int positionSeconds) {
    if (!_connected || !isOwner) return;
    _socket!.emit('room_seek', {
      'roomId': roomId,
      'userId': userId,
      'position': positionSeconds,
    });
  }

  // Owner mutes a participant
  void sendMute(String targetUserId) {
    if (!_connected || !isOwner) return;
    _socket!.emit('mute_user', {
      'roomId': roomId,
      'userId': userId,
      'targetUserId': targetUserId,
    });
  }

  // Owner kicks a participant
  void sendKick(String targetUserId) {
    if (!_connected || !isOwner) return;
    _socket!.emit('kick_user', {
      'roomId': roomId,
      'userId': userId,
      'targetUserId': targetUserId,
    });
  }

  // Owner ends the room for everyone
  void sendRoomEnd() {
    if (!_connected || !isOwner) return;
    _socket!.emit('end_room', {
      'roomId': roomId,
      'userId': userId,
    });
  }

  // Called by voice system when mic activity detected
  void sendSpeaking(bool isSpeaking) {
    if (!_connected) return;
    _socket!.emit('speaking', {
      'roomId': roomId,
      'userId': userId,
      'speaking': isSpeaking,
    });
  }

  void disconnect() {
    if (_connected) {
      _socket!.emit('leave_room', {
        'roomId': roomId,
        'userId': userId,
      });
    }
    _socket?.disconnect();
    _socket?.dispose();
    _connected = false;
  }

  // Socket data can arrive as int, double or string — handle all
  int _safeInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }
}