import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../widgets/aim_title_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/disappearing_timer_dialog.dart';

class ChatScreen extends StatefulWidget {
  final String roomId;
  const ChatScreen({super.key, required this.roomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timeline? _timeline;
  bool _loadingTimeline = true;
  bool _sending = false;
  bool _showScrollToBottom = false;

  Room? get _room => context.read<ClientManager>().roomById(Uri.decodeComponent(widget.roomId));

  @override
  void initState() {
    super.initState();
    _loadTimeline();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.offset > 200 && !_showScrollToBottom) {
      setState(() => _showScrollToBottom = true);
    } else if (_scrollCtrl.offset <= 200 && _showScrollToBottom) {
      setState(() => _showScrollToBottom = false);
    }
  }

  Future<void> _loadTimeline() async {
    final room = _room;
    if (room == null) return;
    final timeline = await room.getTimeline(
      onUpdate: () => setState(() {}),
    );
    setState(() { _timeline = timeline; _loadingTimeline = false; });
    await timeline.requestHistory(historyCount: 30);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _timeline?.cancelSubscriptions();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _room == null) return;
    _inputCtrl.clear();
    setState(() => _sending = true);
    try {
      await _room!.sendTextEvent(text);
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || _room == null) return;
    setState(() => _sending = true);
    try {
      final bytes = await picked.readAsBytes();
      await _room!.sendFileEvent(
        MatrixFile(bytes: bytes, name: picked.name, mimeType: 'image/jpeg'),
        inReplyTo: null,
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || _room == null) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() => _sending = true);
    try {
      await _room!.sendFileEvent(
        MatrixFile(bytes: file.bytes!, name: file.name, mimeType: file.extension != null ? 'application/${file.extension}' : 'application/octet-stream'),
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _setDisappearing() async {
    final room = _room;
    if (room == null) return;
    final seconds = await showDialog<int>(
      context: context,
      builder: (_) => const DisappearingTimerDialog(),
    );
    if (seconds == null) return;
    final content = seconds == 0 ? <String, Object?>{} : {'max_lifetime': seconds * 1000};
    await room.client.setRoomStateWithKey(room.id, 'm.room.message_retention', '', content);
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<ClientManager>();
    final room = mgr.roomById(Uri.decodeComponent(widget.roomId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myId = mgr.client.userID ?? '';

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Room not found')),
      );
    }

    final events = _timeline?.events.reversed.toList() ?? [];
    final msgEvents = events.where((e) => e.type == EventTypes.Message || e.type == EventTypes.Encrypted).toList();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: AimTitleBar(
          title: room.getLocalizedDisplayname(),
          isDark: isDark,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 14, color: Colors.white),
            onPressed: () => context.go('/buddylist'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.timer, size: 14, color: Colors.white),
              onPressed: _setDisappearing,
              tooltip: 'Disappearing messages',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingTimeline
                ? const Center(child: CircularProgressIndicator())
                : msgEvents.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSay hello!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Colors.grey[500]),
                        ),
                      )
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollCtrl,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            itemCount: msgEvents.length,
                            itemBuilder: (context, i) {
                              final event = msgEvents[i];
                              final isMe = event.senderId == myId;
                              return MessageBubble(event: event, isMe: isMe, isDark: isDark);
                            },
                          ),
                          if (_showScrollToBottom)
                            Positioned(
                              bottom: 8, right: 8,
                              child: FloatingActionButton.small(
                                onPressed: () => _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                                backgroundColor: AimColors.aimBlue,
                                child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
          ),
          _InputBar(
            ctrl: _inputCtrl,
            sending: _sending,
            isDark: isDark,
            onSend: _sendText,
            onImage: _sendImage,
            onFile: _sendFile,
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final bool sending;
  final bool isDark;
  final VoidCallback onSend;
  final VoidCallback onImage;
  final VoidCallback onFile;

  const _InputBar({
    required this.ctrl,
    required this.sending,
    required this.isDark,
    required this.onSend,
    required this.onImage,
    required this.onFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AimColors.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF334466) : AimColors.aimBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.image_outlined, size: 18, color: isDark ? Colors.white60 : AimColors.aimBlue),
            onPressed: sending ? null : onImage,
            tooltip: 'Send image',
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.attach_file, size: 18, color: isDark ? Colors.white60 : AimColors.aimBlue),
            onPressed: sending ? null : onFile,
            tooltip: 'Send file',
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(fontFamily: 'Arial', fontSize: 13),
              decoration: const InputDecoration(hintText: 'Send a message...', hintStyle: TextStyle(fontFamily: 'Arial', fontSize: 12)),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: sending ? null : onSend,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            child: sending
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send'),
          ),
        ],
      ),
    );
  }
}
