import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
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

  Room? get _room =>
      context.read<ClientManager>().roomById(Uri.decodeComponent(widget.roomId));

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    final room = _room;
    if (room == null) return;
    final timeline = await room.getTimeline(onUpdate: () => setState(() {}));
    setState(() { _timeline = timeline; _loadingTimeline = false; });
    await timeline.requestHistory(historyCount: 50);
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
    try { await _room!.sendTextEvent(text); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || _room == null) return;
    setState(() => _sending = true);
    try {
      final bytes = await picked.readAsBytes();
      await _room!.sendFileEvent(MatrixFile(bytes: bytes, name: picked.name, mimeType: 'image/jpeg'));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || _room == null) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() => _sending = true);
    try {
      await _room!.sendFileEvent(MatrixFile(
        bytes: file.bytes!, name: file.name,
        mimeType: file.extension != null ? 'application/${file.extension}' : 'application/octet-stream'));
    } finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _setDisappearing() async {
    final room = _room;
    if (room == null) return;
    final seconds = await showDialog<int>(context: context, builder: (_) => const DisappearingTimerDialog());
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
        body: Column(children: [
          _ChatTitleBar(title: 'Chat', isDark: isDark, onBack: () => context.go('/buddylist')),
          const Expanded(child: Center(child: Text('Room not found'))),
        ]),
      );
    }

    final events = _timeline?.events.reversed.toList() ?? [];
    final msgEvents = events
        .where((e) => e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
        .toList();

    return Scaffold(
      body: Column(children: [
        // ── AIM chat title bar ─────────────────────────────────────────
        _ChatTitleBar(
          title: room.getLocalizedDisplayname(),
          isDark: isDark,
          onBack: () => context.go('/buddylist'),
          onTimer: _setDisappearing,
        ),

        // ── Message area ───────────────────────────────────────────────
        Expanded(
          child: Container(
            color: isDark ? AimColors.darkChatBg : AimColors.chatBg,
            child: _loadingTimeline
                ? const Center(child: CircularProgressIndicator())
                : msgEvents.isEmpty
                    ? Center(child: Text('No messages yet. Say something!',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[600])))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: msgEvents.length,
                        itemBuilder: (_, i) {
                          final event = msgEvents[i];
                          final isMe = event.senderId == myId;
                          return _AimMessageLine(event: event, isMe: isMe, isDark: isDark);
                        },
                      ),
          ),
        ),

        // ── Toolbar strip (like AIM's font/format bar) ────────────────
        Container(
          height: 26,
          color: isDark ? const Color(0xFF1A1A1A) : AimColors.toolbarBg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: isDark ? AimColors.darkBorder : AimColors.winBorder),
              bottom: BorderSide(color: isDark ? AimColors.darkBorder : AimColors.winBorder),
            ),
          ),
          child: Row(children: [
            _BarBtn(icon: Icons.image_outlined, tooltip: 'Send image', onTap: _sending ? null : _sendImage),
            _BarBtn(icon: Icons.attach_file, tooltip: 'Send file', onTap: _sending ? null : _sendFile),
            _BarBtn(icon: Icons.timer_outlined, tooltip: 'Disappearing messages', onTap: _setDisappearing),
          ]),
        ),

        // ── Input area ────────────────────────────────────────────────
        Container(
          color: isDark ? AimColors.darkInputBg : AimColors.inputBg,
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: isDark ? AimColors.darkInputBg : Colors.white,
                  border: Border.all(color: isDark ? AimColors.darkBorder : AimColors.inputBorder),
                ),
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(fontFamily: 'Arial', fontSize: 12,
                    color: isDark ? AimColors.darkText : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(fontSize: 11,
                      color: isDark ? Colors.grey[600] : Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(6),
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: _sending ? null : _sendText,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: _sending
                    ? const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── AIM-style message line: "ScreenName: message text" ────────────────────────
class _AimMessageLine extends StatelessWidget {
  final Event event;
  final bool isMe;
  final bool isDark;

  const _AimMessageLine({required this.event, required this.isMe, required this.isDark});

  String get _senderName {
    final id = event.senderId;
    return id.split(':').first.replaceFirst('@', '');
  }

  @override
  Widget build(BuildContext context) {
    final nameColor = isMe
        ? (isDark ? AimColors.darkMyName    : AimColors.myNameColor)
        : (isDark ? AimColors.darkTheirName : AimColors.theirNameColor);
    final textColor = isDark ? AimColors.darkText : AimColors.msgTextColor;
    final time = event.originServerTs;
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    if (event.type == EventTypes.Encrypted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '[$timeStr] ', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          TextSpan(text: '$_senderName: ', style: TextStyle(fontWeight: FontWeight.bold, color: nameColor, fontSize: 12)),
          TextSpan(text: '🔒 Encrypted message', style: TextStyle(color: Colors.grey[500], fontSize: 11, fontStyle: FontStyle.italic)),
        ])),
      );
    }

    final body = event.body;
    final msgType = event.messageType;

    Widget content;
    if (msgType == MessageTypes.Image) {
      content = Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          const Icon(Icons.image, size: 14),
          const SizedBox(width: 4),
          Text('[Image: ${event.body}]', style: TextStyle(color: textColor, fontSize: 11, fontStyle: FontStyle.italic)),
        ]),
      );
    } else if (msgType == MessageTypes.File || msgType == MessageTypes.Audio || msgType == MessageTypes.Video) {
      final label = msgType == MessageTypes.Audio ? 'Audio' : msgType == MessageTypes.Video ? 'Video' : 'File';
      content = Row(children: [
        const Icon(Icons.attach_file, size: 14),
        const SizedBox(width: 4),
        Text('[$label: ${event.body}]', style: TextStyle(color: textColor, fontSize: 11, fontStyle: FontStyle.italic)),
      ]);
    } else {
      content = Text(body, style: TextStyle(color: textColor, fontSize: 12));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('[$timeStr] ', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Expanded(child: RichText(text: TextSpan(children: [
          TextSpan(text: '$_senderName: ',
            style: TextStyle(fontWeight: FontWeight.bold, color: nameColor, fontSize: 12, fontFamily: 'Arial')),
          WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: content),
        ]))),
      ]),
    );
  }
}

class _ChatTitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback? onTimer;
  const _ChatTitleBar({required this.title, required this.isDark, required this.onBack, this.onTimer});

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: isDark
          ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
          : [AimColors.titleBarStart, AimColors.titleBarEnd]),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(children: [
      InkWell(onTap: onBack,
        child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.arrow_back, color: Colors.white, size: 14))),
      const Icon(Icons.lock, color: Colors.white, size: 12),
      const SizedBox(width: 4),
      Expanded(child: Text('Veil — $title',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis)),
      if (onTimer != null)
        InkWell(onTap: onTimer,
          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.timer_outlined, color: Colors.white, size: 14))),
    ]),
  );
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _BarBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Icon(icon, size: 16, color: onTap == null
              ? Colors.grey
              : (isDark ? Colors.grey[300] : Colors.black87)),
        ),
      ),
    );
  }
}
