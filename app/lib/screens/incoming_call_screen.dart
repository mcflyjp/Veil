// Full-screen incoming-call prompt — Phase 2 of Veil's call feature.
//
// Pushed automatically by VeilApp (see main.dart) whenever CallService fires
// onIncomingCall, so it shows up over whatever screen the user is currently
// on. Purely a thin view over CallService: it answers/rejects and lets the
// service's own state machine drive what happens next (InCallScreen takes
// over once answered — see CallService.answer / core/call_service.dart).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../core/call_service.dart';
import '../core/client_manager.dart';
import '../core/veil_user_prefs.dart';
import '../widgets/buddy_avatar.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _resolving = false; // answer()/reject() in flight — disable both buttons

  Future<void> _answer(CallService calls) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    await calls.answer();
    if (!mounted) return;
    context.pushReplacement('/call/active');
  }

  Future<void> _decline(CallService calls) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    await calls.reject();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallService>();
    final call = calls.activeCall;

    // The call vanished from under us — caller hung up before we answered,
    // or it was answered on another of our devices. Bail out.
    if (call == null || calls.phase != CallPhase.incoming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GoRouter.of(context).canPop()) context.pop();
      });
    }

    final client = context.read<ClientManager>().client;
    final tc = context.watch<VeilUserPrefs>().colors;
    final remoteUser = call?.remoteUserId != null
        ? call!.room.unsafeGetUserFromMemoryOrFallback(call.remoteUserId!)
        : null;
    final name = remoteUser?.calcDisplayname() ??
        call?.room.getLocalizedDisplayname() ??
        'Unknown caller';
    final isVideo = call?.type == CallType.kVideo;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F1A),
        body: SafeArea(
          child: Column(
            children: [
              // ── Caller identity ──────────────────────────────────────────
              const Spacer(flex: 2),
              BuddyAvatar(
                initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
                tc: tc,
                size: 120,
                avatarUrl: remoteUser?.avatarUrl,
                client: client,
              ),
              const SizedBox(height: 24),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                isVideo ? 'Incoming video call…' : 'Incoming voice call…',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const Spacer(flex: 3),

              // ── Answer / decline ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end,
                      background: const Color(0xFFE53935),
                      onTap: call == null ? null : () => _decline(calls),
                    ),
                    _CallActionButton(
                      icon: isVideo ? Icons.videocam : Icons.call,
                      background: const Color(0xFF43A047),
                      onTap: call == null ? null : () => _answer(calls),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final VoidCallback? onTap;
  const _CallActionButton({required this.icon, required this.background, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onTap == null ? background.withAlpha(120) : background,
            boxShadow: [BoxShadow(color: background.withAlpha(100), blurRadius: 16, spreadRadius: 2)],
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      );
}
