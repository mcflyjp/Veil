import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../widgets/aim_title_bar.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _isGroup = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _start() async {
    final mgr = context.read<ClientManager>();
    final input = _ctrl.text.trim();
    if (input.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      String roomId;
      if (_isGroup) {
        roomId = await mgr.client.createRoom(name: input, preset: CreateRoomPreset.privateChat);
      } else {
        // Resolve screen name → full Matrix ID
        String userId = input;
        if (!userId.startsWith('@')) {
          userId = '@$userId:veilmsg.com';
        } else if (!userId.contains(':')) {
          userId = '$userId:veilmsg.com';
        }
        roomId = await mgr.client.startDirectChat(userId);
      }
      if (mounted) context.go('/buddylist/chat/${Uri.encodeComponent(roomId)}');
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: AimTitleBar(
          title: 'Send Instant Message',
          isDark: isDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 14, color: Colors.white),
            onPressed: () => context.go('/buddylist'),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TypeButton(label: 'Direct Message', selected: !_isGroup, onTap: () => setState(() => _isGroup = false)),
                const SizedBox(width: 8),
                _TypeButton(label: 'Group Chat', selected: _isGroup, onTap: () => setState(() => _isGroup = true)),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isGroup ? 'Group name' : 'Screen name',
              style: const TextStyle(fontFamily: 'Arial', fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _start(),
              style: const TextStyle(fontFamily: 'Arial', fontSize: 13),
              decoration: InputDecoration(
                hintText: _isGroup ? 'Enter group name' : 'e.g. jeremy or @jeremy:veilmsg.com',
                hintStyle: const TextStyle(fontFamily: 'Arial', fontSize: 11),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'Arial')),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _start,
              child: _loading
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isGroup ? 'Create Group' : 'Send Message'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AimColors.aimBlue : Colors.transparent,
          border: Border.all(color: AimColors.aimBlue),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Arial', fontSize: 11, color: selected ? Colors.white : AimColors.aimBlue, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
