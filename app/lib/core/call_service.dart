// Core voice/video calling service — Phase 1 of Veil's call feature.
//
// Wraps matrix_dart_sdk's VoIP/CallSession machinery (Matrix's standard
// 1:1 call signaling over m.call.* room/to-device events) with
// flutter_webrtc as the actual media backend, and exposes a small state
// machine + control surface (start/answer/reject/hangup/mute/camera) for
// the UI layer to drive.
//
// This file is UI-free by design — Phase 2 adds the incoming-call screen,
// in-call screen, and a call button in the chat title bar, all driven off
// `CallService.phase` / `CallService.onIncomingCall` / `CallService.activeCall`.
// Group calls are out of scope for now; `handleNewGroupCall` is a no-op.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:matrix/matrix.dart';
// The WebRTCDelegate contract (from matrix/voip) is typed against
// webrtc_interface's abstract MediaDevices/RTCPeerConnection, not
// flutter_webrtc's own re-exports (flutter_webrtc.dart hides MediaDevices to
// provide its own deprecated static-method shim under that name) — so pull
// those interface types from here directly.
import 'package:webrtc_interface/webrtc_interface.dart';

/// High-level phase of the current call, collapsed from CallSession's more
/// granular `CallState` into what the UI actually needs to branch on.
enum CallPhase {
  idle, // no call in progress
  outgoing, // we invited, waiting for the other side to answer
  incoming, // someone is calling us, not yet answered
  connecting, // answered (by either side), ICE/media negotiating
  connected, // media is flowing
}

/// Trade-off for a screen share. Motion favors smoothness/low latency
/// (games, video: 60fps, drops resolution first under pressure); detail
/// favors sharpness (text, slides: 30fps, drops framerate first).
enum ScreenShareQuality { motion, detail }

class CallService extends ChangeNotifier {
  Client? _client;
  VoIP? _voip;
  CallSession? _activeCall;
  StreamSubscription<CallState>? _callStateSub;
  StreamSubscription<CallStateChange>? _callEventSub;

  CallPhase _phase = CallPhase.idle;
  CallPhase get phase => _phase;
  bool get inCall => _phase != CallPhase.idle;

  CallSession? get activeCall => _activeCall;
  bool get isVideoCall => _activeCall?.type == CallType.kVideo;
  bool get isMuted => _activeCall?.isMicrophoneMuted ?? false;
  bool get isCameraOff => _activeCall?.isLocalVideoMuted ?? false;

  // ── Screen sharing state ─────────────────────────────────────────────
  // Sharing is desktop + web only: Android needs a MediaProjection
  // foreground service that isn't wired up, and iOS needs a broadcast
  // extension. Receiving a share works on every platform.
  static bool get platformCanShareScreen =>
      kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  bool get isScreenSharing => _activeCall?.localScreenSharingStream != null;
  /// Whether a share could start right now (call fully connected).
  bool get canShareScreen =>
      platformCanShareScreen && _phase == CallPhase.connected;
  WrappedMediaStream? get remoteScreenShare =>
      _activeCall?.remoteScreenSharingStream;

  /// Fires whenever the SDK hands us a fresh incoming call, so the UI can
  /// push an incoming-call screen without polling `activeCall`.
  final _incomingCallController = StreamController<CallSession>.broadcast();
  Stream<CallSession> get onIncomingCall => _incomingCallController.stream;

  // ── Lifecycle: attach/detach the logged-in Matrix client ───────────────
  // Mirrors VeilUserPrefs.attachClient/detachClient in main.dart — call
  // these from the same login-state listener.

  void attachClient(Client client) {
    if (_client == client) return;
    _client = client;
    _voip = VoIP(client, _VeilWebRTCDelegate(this));
  }

  void detachClient() {
    _voip = null;
    _client = null;
    _setActiveCall(null);
  }

  // ── Outgoing call ────────────────────────────────────────────────────

  /// Starts a 1:1 call in [room]. For a direct chat, the other member is
  /// inferred automatically so only that user's devices ring (otherwise
  /// every member of the room — including our own other devices — would).
  Future<void> startCall(Room room, {required bool video}) async {
    final voip = _voip;
    if (voip == null) {
      throw StateError('CallService: not attached to a logged-in client');
    }
    if (_activeCall != null) {
      throw StateError('CallService: a call is already in progress');
    }
    final call = await voip.inviteToCall(
      room,
      video ? CallType.kVideo : CallType.kVoice,
      userId: room.isDirectChat ? room.directChatMatrixID : null,
    );
    _setActiveCall(call);
  }

  // ── Controls ─────────────────────────────────────────────────────────

  Future<void> answer() async {
    await _activeCall?.answer();
  }

  Future<void> reject() async {
    await _activeCall?.reject();
    _setActiveCall(null);
  }

  Future<void> hangup() async {
    // CallSession.hangup() -> terminate() fires CallState.kEnded on
    // onCallStateChanged, which _onCallStateChanged clears via
    // _setActiveCall(null) — no need to do it here too.
    await _activeCall?.hangup(reason: CallErrorCode.userHangup);
  }

  Future<void> toggleMute() async {
    final call = _activeCall;
    if (call == null) return;
    await call.setMicrophoneMuted(!call.isMicrophoneMuted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final call = _activeCall;
    if (call == null || call.type != CallType.kVideo) return;
    await call.setLocalVideoMuted(!call.isLocalVideoMuted);
    notifyListeners();
  }

  /// Returns whether the switch actually succeeded, so the UI can tell the
  /// user when it didn't — previously this was fire-and-forget from the
  /// button's onTap with no way to see a failure (silent no-op on tap).
  Future<bool> switchCamera() async {
    final tracks = _activeCall?.localUserMediaStream?.stream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return false;
    try {
      return await webrtc.Helper.switchCamera(tracks.first);
    } catch (e) {
      Logs().w('[CallService] switchCamera failed', e);
      return false;
    }
  }

  // ── Screen sharing ───────────────────────────────────────────────────

  /// Starts sharing [sourceId] (a desktopCapturer source id from the picker;
  /// null on web, where the browser shows its own picker). Adds the capture
  /// as a separate `m.call` Screenshare stream next to the camera/mic, so
  /// the other side can show it prominently instead of replacing the camera.
  /// System audio rides along by default: on Windows a whole-screen share
  /// excludes Veil's own process (no echo of the call back to the other
  /// side), a window share captures only that app's audio.
  /// Returns false (and logs) if capture couldn't start.
  Future<bool> startScreenShare({
    String? sourceId,
    ScreenShareQuality quality = ScreenShareQuality.motion,
    bool audio = true,
  }) async {
    final call = _activeCall;
    if (call == null || call.pc == null || !platformCanShareScreen) return false;
    if (call.localScreenSharingStream != null) return true;
    final fps = quality == ScreenShareQuality.motion ? 60 : 30;
    try {
      final stream = await webrtc.navigator.mediaDevices.getDisplayMedia({
        'audio': audio,
        'video': kIsWeb
            ? {'frameRate': fps}
            : {
                if (sourceId != null) 'deviceId': {'exact': sourceId},
                'mandatory': {'frameRate': fps},
              },
      });
      for (final track in stream.getTracks()) {
        // Source closed (window closed, OS "stop sharing" bar, ...)
        track.onEnded = () => stopScreenShare();
      }
      await call.addLocalStream(stream, SDPStreamMetadataPurpose.Screenshare);
      notifyListeners();
      // The sender only exists once addTrack ran; tune now, and once more
      // after negotiation settles in case the first attempt raced it.
      unawaited(_tuneScreenShareSender(call, stream, quality));
      Future.delayed(const Duration(seconds: 2),
          () => _tuneScreenShareSender(call, stream, quality));
      return true;
    } catch (e) {
      Logs().w('[CallService] startScreenShare failed', e);
      return false;
    }
  }

  Future<void> stopScreenShare() async {
    final call = _activeCall;
    if (call == null || call.localScreenSharingStream == null) return;
    try {
      await call.setScreensharingEnabled(false);
    } catch (e) {
      Logs().w('[CallService] stopScreenShare failed', e);
    }
    notifyListeners();
  }

  /// Raises the video sender's bitrate cap and picks what degrades first
  /// under congestion — WebRTC's defaults are tuned for a talking head and
  /// make screen content blurry or choppy.
  Future<void> _tuneScreenShareSender(
    CallSession call,
    MediaStream stream,
    ScreenShareQuality quality,
  ) async {
    try {
      final ids = stream.getVideoTracks().map((t) => t.id).toSet();
      final motion = quality == ScreenShareQuality.motion;
      for (final sender in await call.pc?.getSenders() ?? <RTCRtpSender>[]) {
        final track = sender.track;
        if (track == null || track.kind != 'video' || !ids.contains(track.id)) {
          continue;
        }
        final params = sender.parameters;
        final encodings = params.encodings ?? [RTCRtpEncoding()];
        for (final e in encodings) {
          e.maxBitrate = motion ? 10000000 : 6000000;
          e.maxFramerate = motion ? 60 : 30;
          e.scaleResolutionDownBy = 1.0;
        }
        params.encodings = encodings;
        params.degradationPreference = motion
            ? RTCDegradationPreference.MAINTAIN_FRAMERATE
            : RTCDegradationPreference.MAINTAIN_RESOLUTION;
        await sender.setParameters(params);
      }
    } catch (e) {
      Logs().w('[CallService] tuning screen share sender failed', e);
    }
  }

  // ── Internal: wiring a CallSession's state stream to our CallPhase ─────

  void _setActiveCall(CallSession? call) {
    _callStateSub?.cancel();
    _callStateSub = null;
    _callEventSub?.cancel();
    _callEventSub = null;
    _activeCall = call;

    if (call == null) {
      _phase = CallPhase.idle;
      notifyListeners();
      return;
    }

    _phase = call.direction == CallDirection.kOutgoing
        ? CallPhase.outgoing
        : CallPhase.incoming;
    _callStateSub = call.onCallStateChanged.stream.listen(_onCallStateChanged);
    // Streams (camera, screen shares) appearing/disappearing on either side
    // fire this; listeners read isScreenSharing/remoteScreenShare off us.
    _callEventSub = call.onCallEventChanged.stream.listen((event) {
      if (event == CallStateChange.kFeedsChanged) notifyListeners();
    });
    notifyListeners();
  }

  void _onCallStateChanged(CallState state) {
    switch (state) {
      case CallState.kWaitLocalMedia:
      case CallState.kCreateOffer:
      case CallState.kInviteSent:
      case CallState.kCreateAnswer:
      case CallState.kConnecting:
        _phase = CallPhase.connecting;
        notifyListeners();
        break;
      case CallState.kConnected:
        _phase = CallPhase.connected;
        notifyListeners();
        break;
      case CallState.kRinging:
        _phase = CallPhase.incoming;
        notifyListeners();
        break;
      case CallState.kEnding:
        break; // wait for kEnded to actually clear state
      case CallState.kEnded:
      case CallState.kFledgling:
        _setActiveCall(null);
        break;
    }
  }

  // Called by _VeilWebRTCDelegate when the SDK hands us ownership of a call
  // (incoming invite, or confirmation of our own outgoing one).
  void _handleNewCall(CallSession call) {
    if (_activeCall != null && _activeCall != call) {
      // We're already in a call — canHandleNewCall below should have made
      // the SDK auto-reject this before it got here, but guard anyway.
      return;
    }
    _setActiveCall(call);
    if (call.direction == CallDirection.kIncoming) {
      _incomingCallController.add(call);
    }
  }

  void _handleCallEnded(CallSession call) {
    if (_activeCall == call) {
      _setActiveCall(null);
    }
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _callEventSub?.cancel();
    _incomingCallController.close();
    super.dispose();
  }
}

/// Bridges matrix_dart_sdk's WebRTCDelegate contract to flutter_webrtc (for
/// media) and CallService (for app state). One instance per CallService.
class _VeilWebRTCDelegate implements WebRTCDelegate {
  _VeilWebRTCDelegate(this._service);
  final CallService _service;

  @override
  MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) =>
      webrtc.createPeerConnection(configuration, constraints);

  // No ringtone asset shipped yet — the incoming-call screen (Phase 2)
  // carries its own visual + haptic cue for now. Revisit once we add a
  // sound asset (mirrors how notification_service.dart currently has no
  // audio either, just system notifications).
  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {
    _service._handleNewCall(session);
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    _service._handleCallEnded(session);
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {
    _service._handleCallEnded(session);
  }

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {
    // Group calls are a later phase — 1:1 only for now.
  }

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {}

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => _service._activeCall == null;

  @override
  EncryptionKeyProvider? get keyProvider => null;
}
