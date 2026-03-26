import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:noirscreen/services/room_watch_service.dart';

/// Peer-to-peer WebRTC voice chat.
/// Max 5 participants — no SFU needed.
/// Signaling goes through Socket.io via RoomWatchService.
class WebRTCService {
  final String localUserId;
  final RoomWatchService watchService;
  final void Function(String userId, bool speaking) onSpeakingChanged;
  final void Function(String userId) onPeerDisconnected;

  final Map<String, RTCPeerConnection> _peers = {};
  MediaStream? _localStream;
  bool _isMuted = false;
  bool _isInitialized = false;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCService({
    required this.localUserId,
    required this.watchService,
    required this.onSpeakingChanged,
    required this.onPeerDisconnected,
  });

  Future<bool> initialize() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ WEBRTC: Microphone permission denied');
        return false;
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      _isInitialized = true;
      print('✅ WEBRTC: Local audio stream ready');
      return true;
    } catch (e) {
      print('❌ WEBRTC: Initialize error - $e');
      return false;
    }
  }

  Future<void> createOffer(String remoteUserId) async {
    if (!_isInitialized || _localStream == null) return;
    if (_peers.containsKey(remoteUserId)) return;

    try {
      final pc = await _createPeerConnection(remoteUserId);
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      final offer = await pc.createOffer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);

      watchService.sendWebRTCOffer(
        targetUserId: remoteUserId,
        sdp: offer.toMap(),
      );
      print('✅ WEBRTC: Offer sent to $remoteUserId');
    } catch (e) {
      print('❌ WEBRTC: createOffer error - $e');
    }
  }

  Future<void> handleOffer(String fromUserId, Map<String, dynamic> sdp) async {
    if (!_isInitialized || _localStream == null) return;

    try {
      final pc = await _createPeerConnection(fromUserId);
      for (final track in _localStream!.getAudioTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );

      final answer = await pc.createAnswer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(answer);

      watchService.sendWebRTCAnswer(
        targetUserId: fromUserId,
        sdp: answer.toMap(),
      );
      print('✅ WEBRTC: Answer sent to $fromUserId');
    } catch (e) {
      print('❌ WEBRTC: handleOffer error - $e');
    }
  }

  Future<void> handleAnswer(String fromUserId, Map<String, dynamic> sdp) async {
    try {
      final pc = _peers[fromUserId];
      if (pc == null) return;
      await pc.setRemoteDescription(
        RTCSessionDescription(sdp['sdp'], sdp['type']),
      );
      print('✅ WEBRTC: Answer received from $fromUserId');
    } catch (e) {
      print('❌ WEBRTC: handleAnswer error - $e');
    }
  }

  Future<void> handleIceCandidate(
    String fromUserId,
    Map<String, dynamic> candidate,
  ) async {
    try {
      final pc = _peers[fromUserId];
      if (pc == null) return;
      await pc.addCandidate(RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      ));
    } catch (e) {
      print('❌ WEBRTC: handleIceCandidate error - $e');
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String remoteUserId) async {
    final pc = await createPeerConnection(_iceConfig);
    _peers[remoteUserId] = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      watchService.sendWebRTCIce(
        targetUserId: remoteUserId,
        candidate: candidate.toMap(),
      );
    };

pc.onTrack = (event) {
  if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
    print('✅ WEBRTC: Receiving audio from $remoteUserId — stream: ${event.streams[0].id}');
    // For audio-only WebRTC in flutter_webrtc, the remote audio track
    // plays automatically through the device speaker once the stream
    // is registered. We must call Helper.setSpeakerphoneOn to ensure
    // audio comes from speaker not earpiece during a room session.
    Helper.setSpeakerphoneOn(true);
  }
};
    pc.onConnectionState = (state) {
      print('📡 WEBRTC: $remoteUserId → $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _peers.remove(remoteUserId);
        onPeerDisconnected(remoteUserId);
      }
    };

    return pc;
  }

  void setMuted(bool muted) {
    _isMuted = muted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
    watchService.sendSpeaking(!muted);
  }

  bool get isMuted => _isMuted;

  Future<void> removePeer(String userId) async {
    final pc = _peers.remove(userId);
    if (pc != null) await pc.close();
  }

  Future<void> dispose() async {
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;
    _isInitialized = false;
    print('🛑 WEBRTC: Disposed');
  }
}