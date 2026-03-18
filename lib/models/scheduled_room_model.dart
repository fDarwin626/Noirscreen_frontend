class ScheduledRoomModel {
  final String scheduleId;
  final String roomId;
  final String hostId;
  final String videoHash;
  final String videoTitle;
  final String? videoThumbnailPath;
  final String streamType;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final String status;
  final String shareableLink;
  final DateTime linkExpiresAt;

  ScheduledRoomModel({
    required this.scheduleId,
    required this.roomId,
    required this.hostId,
    required this.videoHash,
    required this.videoTitle,
    this.videoThumbnailPath,
    required this.streamType,
    required this.scheduledAt,
    required this.createdAt,
    required this.status,
    required this.shareableLink,
    required this.linkExpiresAt,
  });

  factory ScheduledRoomModel.fromJson(Map<String, dynamic> json) {
    return ScheduledRoomModel(
      scheduleId: json['schedule_id'] as String,
      roomId: json['room_id'] as String,
      hostId: json['host_id'] as String,
      videoHash: json['video_hash'] as String,
      videoTitle: json['video_title'] as String,
      videoThumbnailPath: json['video_thumbnail_path'] as String?,
      streamType: json['stream_type'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String,
      shareableLink: json['shareable_link'] as String,
      linkExpiresAt: DateTime.parse(json['link_expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schedule_id': scheduleId,
      'room_id': roomId,
      'host_id': hostId,
      'video_hash': videoHash,
      'video_title': videoTitle,
      'video_thumbnail_path': videoThumbnailPath,
      'stream_type': streamType,
      'scheduled_at': scheduledAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'shareable_link': shareableLink,
      'link_expires_at': linkExpiresAt.toIso8601String(),
    };
  }
}