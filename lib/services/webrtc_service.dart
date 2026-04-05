import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:noirscreen/services/room_watch_service.dart';

/// Peer-to-peer WebRTC voice chat.
/// Max 5 participants — no SFU needed.
/// Signaling goes through Socket.io via RoomWatchService.
class WebRTCService {
  String localUserId;
  RoomWatchService watchService;
  final void Function(String userId, bool speaking) onSpeakingChanged;
  final void Function(String userId) onPeerDisconnected;

  final Map<String, RTCPeerConnection> _peers = {};
  // ── FIX: Keep a renderer per remote peer so audio actually plays ──────
  // flutter_webrtc requires a MediaStream to be attached to an RTCVideoRenderer
  // (even for audio-only) for the native audio engine to route the track to
  // the device speaker. Without this the track is received but silently
  // discarded — which is why no one could hear each other.
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

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

  /// Called after the real RoomWatchService connects, replacing the
  /// deferred placeholder that was passed at construction time.
  void rewireWatchService(RoomWatchService realService) {
    watchService = realService;
  }


Future<bool> initialize() async {
  try {
    // If already initialized with a live stream, reuse it — don't
    // re-request mic permission or open a second audio session.
    // This handles the case where the waiting room's WebRTC was not
    // disposed before the watch screen calls initialize() again.
    if (_isInitialized && _localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      if (tracks.isNotEmpty && tracks.first.enabled) {
        print('✅ WEBRTC: Reusing existing audio stream');
        return true;
      }
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      print('❌ WEBRTC: Microphone permission denied');
      return false;
    }

    // Dispose any stale stream before opening a new one
    // Prevents duplicate audio sessions on Android
    if (_localStream != null) {
      _localStream!.getTracks().forEach((t) => t.stop());
      await _localStream!.dispose();
      _localStream = null;
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

    pc.onTrack = (event) async {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        print('✅ WEBRTC: Receiving audio from $remoteUserId');
        // Keep renderer to hold the stream reference alive
        // Without this the audio engine garbage-collects the track
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.srcObject = event.streams[0];
        _remoteRenderers[remoteUserId] = renderer;
        // Delay speakerphone call — on MIUI the audio session isn't
        // fully established when onTrack fires. 300ms lets it settle.
        Future.delayed(const Duration(milliseconds: 300), () async {
          try {
            await Helper.setSpeakerphoneOn(true);
            print('✅ WEBRTC: Speakerphone enabled for $remoteUserId');
          } catch (e) {
            print('⚠️ WEBRTC: setSpeakerphoneOn failed - $e');
          }
        });
      }
    };

    pc.onConnectionState = (state) {
      print('📡 WEBRTC: $remoteUserId → $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _cleanupPeer(remoteUserId);
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

  Future<void> _cleanupPeer(String userId) async {
    final pc = _peers.remove(userId);
    if (pc != null) await pc.close();
    final renderer = _remoteRenderers.remove(userId);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
  }

  Future<void> removePeer(String userId) async {
    await _cleanupPeer(userId);
  }

  Future<void> dispose() async {
    for (final userId in _peers.keys.toList()) {
      await _cleanupPeer(userId);
    }
    _peers.clear();
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;
    _isInitialized = false;
    print('🛑 WEBRTC: Disposed');
  }
}