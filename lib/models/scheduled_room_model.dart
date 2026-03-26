// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

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
  final String? videoFilePath; // Local path to downloaded video file (not from API)

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
     this.videoFilePath,
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
      scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      status: json['status'] as String,
      linkExpiresAt: DateTime.parse(json['link_expires_at'] as String).toLocal(),
      shareableLink: json['shareable_link'] as String,
     videoFilePath: json['video_file_path'] as String?,
     createdAt: DateTime.parse(json['created_at'] as String).toLocal(),

    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schedule_id': scheduleId,
      'room_id': roomId,
      'host_id': hostId,
      'video_hash': videoHash,
      'video_title': videoTitle,
      'video_file_path': videoFilePath,
      'video_thumbnail_path': videoThumbnailPath,
      'stream_type': streamType,
      'scheduled_at': scheduledAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'status': status,
      'shareable_link': shareableLink,
      'link_expires_at': linkExpiresAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'scheduleId': scheduleId,
      'roomId': roomId,
      'hostId': hostId,
      'videoHash': videoHash,
      'videoTitle': videoTitle,
      'videoThumbnailPath': videoThumbnailPath,
      'streamType': streamType,
      'scheduledAt': scheduledAt.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status,
      'shareableLink': shareableLink,
      'linkExpiresAt': linkExpiresAt.millisecondsSinceEpoch,
      'videoFilePath': videoFilePath,
    };
  }

  factory ScheduledRoomModel.fromMap(Map<String, dynamic> map) {
    return ScheduledRoomModel(
      scheduleId: map['scheduleId'] as String,
      roomId: map['roomId'] as String,
      hostId: map['hostId'] as String,
      videoHash: map['videoHash'] as String,
      videoTitle: map['videoTitle'] as String,
      videoThumbnailPath: map['videoThumbnailPath'] != null ? map['videoThumbnailPath'] as String : null,
      streamType: map['streamType'] as String,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(map['scheduledAt'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      status: map['status'] as String,
      shareableLink: map['shareableLink'] as String,
      linkExpiresAt: DateTime.fromMillisecondsSinceEpoch(map['linkExpiresAt'] as int),
      videoFilePath: map['videoFilePath'] != null ? map['videoFilePath'] as String : null,
    );
  }


  ScheduledRoomModel copyWith({
    String? scheduleId,
    String? roomId,
    String? hostId,
    String? videoHash,
    String? videoTitle,
    String? videoThumbnailPath,
    String? streamType,
    DateTime? scheduledAt,
    DateTime? createdAt,
    String? status,
    String? shareableLink,
    DateTime? linkExpiresAt,
    String? videoFilePath,
  }) {
    return ScheduledRoomModel(
      scheduleId: scheduleId ?? this.scheduleId,
      roomId: roomId ?? this.roomId,
      hostId: hostId ?? this.hostId,
      videoHash: videoHash ?? this.videoHash,
      videoTitle: videoTitle ?? this.videoTitle,
      videoThumbnailPath: videoThumbnailPath ?? this.videoThumbnailPath,
      streamType: streamType ?? this.streamType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      shareableLink: shareableLink ?? this.shareableLink,
      linkExpiresAt: linkExpiresAt ?? this.linkExpiresAt,
      videoFilePath: videoFilePath ?? this.videoFilePath,
    );
  }
}
