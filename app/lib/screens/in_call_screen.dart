// Full-screen active-call view — Phase 2 of Veil's call feature.
//
// Pushed after CallService.startCall() (outgoing) or from
// IncomingCallScreen.answer() (incoming). Renders local/remote video via
// flutter_webrtc's RTCVideoRenderer for video calls, or just a big avatar +
// timer for voice calls. Pops itself once CallService.phase returns to
// idle (either side hung up, or the call failed) — no other screen needs to
// know when a call ends.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../core/call_service.dart';
import '../core/client_manager.dart';
import '../core/veil_user_prefs.dart';
import '../widgets/buddy_avatar.dart';

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key});

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  StreamSubscription<WrappedMediaStream>? _streamAddSub;
  StreamSubscription<WrappedMediaStream>? _streamRemovedSub;
  CallSession? _watchedCall;

  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    setState(() => _renderersReady = true);
    // _watchCall's first run (during initState's synchronous first build)
    // happened before renderers were ready, so _refreshRenderers bailed out
    // immediately without attaching anything — and _watchCall only calls it
    // again for a genuinely NEW call, not this one we already saw. Without
    // this, a stream that was already attached to the CallSession before
    // this screen mounted (always true for the caller's own local stream,
    // set up by CallService.startCall() before InCallScreen ever pushes)
    // would never reach the renderer at all.
    _refreshRenderers(_watchedCall);
  }

  // Re-subscribes to the active call's stream-add/remove events whenever the
  // call itself changes (e.g. first build after CallService hands us one),
  // and refreshes the renderers to whatever streams already exist.
  void _watchCall(CallSession? call) {
    if (_watchedCall == call) return;
    _streamAddSub?.cancel();
    _streamRemovedSub?.cancel();
    _watchedCall = call;
    _refreshRenderers(call);
    if (call == null) return;
    _streamAddSub = call.onStreamAdd.stream.listen(
      (_) => _refreshRenderers(call),
    );
    _streamRemovedSub = call.onStreamRemoved.stream.listen(
      (_) => _refreshRenderers(call),
    );
  }

  void _refreshRenderers(CallSession? call) {
    if (!_renderersReady) return;
    _localRenderer.srcObject = call?.localUserMediaStream?.stream;
    _remoteRenderer.srcObject = call?.remoteUserMediaStream?.stream;
    if (mounted) setState(() {});
  }

  void _tickDurationTimerIfNeeded(CallPhase phase) {
    final connected = phase == CallPhase.connected;
    if (connected && !_wasConnected) {
      _elapsed = Duration.zero;
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    } else if (!connected && _wasConnected) {
      _durationTimer?.cancel();
    }
    _wasConnected = connected;
  }

  // Was previously wired straight to calls.switchCamera as onTap, so a
  // failure (native "video capturer not found" / camera busy / etc.) was
  // silently swallowed — the button just appeared to do nothing. Now shows
  // the user something instead of leaving them guessing whether they
  // mis-tapped it.
  Future<void> _switchCamera(CallService calls) async {
    final ok = await calls.switchCamera();
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't switch camera")));
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _streamAddSub?.cancel();
    _streamRemovedSub?.cancel();
    _durationTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallService>();
    final call = calls.activeCall;
    _watchCall(call);
    _tickDurationTimerIfNeeded(calls.phase);

    // Call ended (either side hung up, or it never connected) — leave.
    if (call == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GoRouter.of(context).canPop()) context.pop();
      });
    }

    final client = context.read<ClientManager>().client;
    final tc = context.watch<VeilUserPrefs>().colors;
    final remoteUser = call?.remoteUserId != null
        ? call!.room.unsafeGetUserFromMemoryOrFallback(call.remoteUserId!)
        : null;
    final name =
        remoteUser?.calcDisplayname() ??
        call?.room.getLocalizedDisplayname() ??
        'Unknown';
    final hasRemoteVideo =
        calls.isVideoCall && _remoteRenderer.srcObject != null;

    String statusLabel;
    switch (calls.phase) {
      case CallPhase.outgoing:
        statusLabel = 'Calling…';
        break;
      case CallPhase.connecting:
        statusLabel = 'Connecting…';
        break;
      case CallPhase.connected:
        statusLabel = _formatDuration(_elapsed);
        break;
      default:
        statusLabel = '';
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        // fit: StackFit.expand is required here — this Stack's children are
        // ALL Positioned/Positioned.fill (no plain non-positioned child), and
        // go_router's page-transition machinery (even NoTransitionPage, via
        // CustomTransitionPage) hands its child LOOSE constraints so it CAN
        // animate size. A Stack with only positioned children under loose
        // constraints collapses to the smallest size that fits its content
        // instead of filling the screen — which is exactly the "everything
        // crammed into a ~140px column" bug this fixes. StackFit.expand forces
        // it to always take the full available space regardless.
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video / avatar backdrop ─────────────────────────────────
            Positioned.fill(
              child: hasRemoteVideo
                  ? RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: const Color(0xFF0B0F1A),
                      child: Center(
                        child: BuddyAvatar(
                          initial: name.isNotEmpty
                              ? name[0].toUpperCase()
                              : '?',
                          tc: tc,
                          size: 140,
                          avatarUrl: remoteUser?.avatarUrl,
                          client: client,
                        ),
                      ),
                    ),
            ),

            // ── Local self-view (video calls only) ──────────────────────
            if (calls.isVideoCall &&
                !calls.isCameraOff &&
                _localRenderer.srcObject != null)
              Positioned(
                top: 56,
                right: 16,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // ── Name + status ────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Controls ─────────────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallControlButton(
                      icon: calls.isMuted ? Icons.mic_off : Icons.mic,
                      active: calls.isMuted,
                      onTap: calls.toggleMute,
                    ),
                    const SizedBox(width: 18),
                    if (calls.isVideoCall) ...[
                      _CallControlButton(
                        icon: calls.isCameraOff
                            ? Icons.videocam_off
                            : Icons.videocam,
                        active: calls.isCameraOff,
                        onTap: calls.toggleCamera,
                      ),
                      const SizedBox(width: 18),
                      _CallControlButton(
                        icon: Icons.cameraswitch,
                        onTap: () => _switchCamera(calls),
                      ),
                      const SizedBox(width: 18),
                    ],
                    _CallControlButton(
                      icon: Icons.call_end,
                      background: const Color(0xFFE53935),
                      onTap: calls.hangup,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final bool active; // "toggled on" visual state (e.g. muted) — filled white bg
  final Color? background;
  final VoidCallback? onTap;
  const _CallControlButton({
    required this.icon,
    this.active = false,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (active ? Colors.white : Colors.white24);
    final fg = background != null || !active ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: Icon(icon, color: fg, size: 26),
      ),
    );
  }
}
