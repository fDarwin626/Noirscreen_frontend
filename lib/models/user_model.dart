class UserModel {
  final String userId;
  final String username;
  final String avatarType; // 'default' or 'custom'
  final int? avatarId; // ID of default avatar (1-12)
  final String? photoUrl; // URL if custom photo
  final DateTime createdAt;
  final DateTime lastActive;
  final int totalRoomsCreated;
  final int totalWatchTime; // in seconds

  UserModel({
    required this.userId,
    required this.username,
    required this.avatarType,
    this.avatarId,
    this.photoUrl,
    required this.createdAt,
    required this.lastActive,
    this.totalRoomsCreated = 0,
    this.totalWatchTime = 0,
  });

  // Convert from JSON (API response)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['user_id'],
      username: json['username'],
      avatarType: json['avatar_type'],
      avatarId: json['avatar_id'],
      photoUrl: json['photo_url'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      lastActive: DateTime.parse(json['last_active'] ?? json['created_at'] ?? DateTime.now().toIso8601String()),
      totalRoomsCreated: json['total_rooms_created'] ?? 0,
      totalWatchTime: json['total_watch_time'] ?? 0,
    );
  }

  // Convert to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'avatar_type': avatarType,
      'avatar_id': avatarId,
      'photo_url': photoUrl,
      'created_at': createdAt.toIso8601String(),
      'last_active': lastActive.toIso8601String(),
      'total_rooms_created': totalRoomsCreated,
      'total_watch_time': totalWatchTime,
    };
  }

  // Create a copy with updated fields
  UserModel copyWith({
    String? userId,
    String? username,
    String? avatarType,
    int? avatarId,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? lastActive,
    int? totalRoomsCreated,
    int? totalWatchTime,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarType: avatarType ?? this.avatarType,
      avatarId: avatarId ?? this.avatarId,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
      totalRoomsCreated: totalRoomsCreated ?? this.totalRoomsCreated,
      totalWatchTime: totalWatchTime ?? this.totalWatchTime,
    );
  }
}