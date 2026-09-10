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

class CallService extends ChangeNotifier {
  Client? _client;
  VoIP? _voip;
  CallSession? _activeCall;
  StreamSubscription<CallState>? _callStateSub;

  CallPhase _phase = CallPhase.idle;
  CallPhase get phase => _phase;
  bool get inCall => _phase != CallPhase.idle;

  CallSession? get activeCall => _activeCall;
  bool get isVideoCall => _activeCall?.type == CallType.kVideo;
  bool get isMuted => _activeCall?.isMicrophoneMuted ?? false;
  bool get isCameraOff => _activeCall?.isLocalVideoMuted ?? false;

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

  Future<void> switchCamera() async {
    final tracks = _activeCall?.localUserMediaStream?.stream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    await webrtc.Helper.switchCamera(tracks.first);
  }

  // ── Internal: wiring a CallSession's state stream to our CallPhase ─────

  void _setActiveCall(CallSession? call) {
    _callStateSub?.cancel();
    _callStateSub = null;
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
