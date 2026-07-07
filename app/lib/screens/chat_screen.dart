import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../widgets/disappearing_timer_dialog.dart';

// Available AIM-era fonts
const _kFonts = ['Arial', 'Verdana', 'Times New Roman', 'Courier New', 'Comic Sans MS', 'Georgia'];
const _kSizes = [14.0, 16.0, 18.0, 20.0, 22.0, 24.0];
const _kDefaultFont = 'Arial';
const _kDefaultSize = 16.0;

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

  // Per-conversation font prefs
  String _fontFamily = _kDefaultFont;
  double _fontSize   = _kDefaultSize;

  String get _prefKey => 'chat_font_${widget.roomId}';

  Room? get _room =>
      context.read<ClientManager>().roomById(Uri.decodeComponent(widget.roomId));

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadTimeline();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fontFamily = prefs.getString('${_prefKey}_family') ?? _kDefaultFont;
      _fontSize   = prefs.getDouble('${_prefKey}_size')   ?? _kDefaultSize;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefKey}_family', _fontFamily);
    await prefs.setDouble('${_prefKey}_size', _fontSize);
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

  void _openFontPicker() {
    showDialog(
      context: context,
      builder: (_) => _FontPickerDialog(
        currentFamily: _fontFamily,
        currentSize: _fontSize,
        onChanged: (family, size) {
          setState(() { _fontFamily = family; _fontSize = size; });
          _savePrefs();
        },
      ),
    );
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

    // events are newest-first from the SDK; reverse: true puts index-0 at bottom
    final events = _timeline?.events ?? [];
    final msgEvents = events
        .where((e) => e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
        .toList();

    return Scaffold(
      body: Column(children: [
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
                        style: TextStyle(fontSize: 16,
                          color: isDark ? Colors.grey[500] : Colors.grey[600])))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,          // newest (index 0) at bottom ✓
                        padding: const EdgeInsets.all(8),
                        itemCount: msgEvents.length,
                        itemBuilder: (_, i) {
                          final event = msgEvents[i];
                          final isMe = event.senderId == myId;
                          return _AimMessageLine(
                            event: event, isMe: isMe, isDark: isDark,
                            fontFamily: _fontFamily, fontSize: _fontSize,
                          );
                        },
                      ),
          ),
        ),

        // ── Toolbar strip ─────────────────────────────────────────────
        Container(
          height: 28,
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
            const SizedBox(width: 4),
            // Font button — shows current font info
            InkWell(
              onTap: _openFontPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: isDark ? AimColors.darkBorder : AimColors.winBorder),
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('A', style: TextStyle(
                    fontFamily: _fontFamily, fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AimColors.darkText : Colors.black)),
                  const SizedBox(width: 4),
                  Text('$_fontFamily · ${_fontSize.toInt()}pt',
                    style: TextStyle(fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600])),
                ]),
              ),
            ),
          ]),
        ),

        // ── Input area ────────────────────────────────────────────────
        Container(
          color: isDark ? AimColors.darkInputBg : AimColors.inputBg,
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? AimColors.darkInputBg : Colors.white,
                  border: Border.all(color: isDark ? AimColors.darkBorder : AimColors.inputBorder),
                ),
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(fontFamily: _fontFamily, fontSize: _fontSize,
                    color: isDark ? AimColors.darkText : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(fontSize: _fontSize * 0.85,
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
              height: 34,
              child: ElevatedButton(
                onPressed: _sending ? null : _sendText,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: _sending
                    ? const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Font picker dialog ─────────────────────────────────────────────────────────
class _FontPickerDialog extends StatefulWidget {
  final String currentFamily;
  final double currentSize;
  final void Function(String family, double size) onChanged;

  const _FontPickerDialog({
    required this.currentFamily,
    required this.currentSize,
    required this.onChanged,
  });

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  late String _family;
  late double _size;

  @override
  void initState() {
    super.initState();
    _family = widget.currentFamily;
    _size   = widget.currentSize;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Text('Font Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Font', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? AimColors.darkBorder : AimColors.winBorder)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _family,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                style: TextStyle(fontSize: 16, color: isDark ? AimColors.darkText : Colors.black),
                dropdownColor: isDark ? AimColors.darkInputBg : Colors.white,
                items: _kFonts.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f, style: TextStyle(fontFamily: f, fontSize: 16)),
                )).toList(),
                onChanged: (v) => setState(() => _family = v!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Size', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _kSizes.map((s) {
              final selected = s == _size;
              return GestureDetector(
                onTap: () => setState(() => _size = s),
                child: Container(
                  width: 44, height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF17369C)
                        : (isDark ? AimColors.darkInputBg : Colors.white),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF17369C)
                          : (isDark ? AimColors.darkBorder : AimColors.winBorder)),
                  ),
                  child: Text('${s.toInt()}',
                    style: TextStyle(fontSize: 14,
                      color: selected ? Colors.white : (isDark ? AimColors.darkText : Colors.black),
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Live preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AimColors.darkChatBg : Colors.white,
              border: Border.all(color: isDark ? AimColors.darkBorder : AimColors.winBorder)),
            child: RichText(text: TextSpan(children: [
              TextSpan(text: 'You: ',
                style: TextStyle(fontFamily: _family, fontSize: _size,
                  fontWeight: FontWeight.bold, color: AimColors.myNameColor)),
              TextSpan(text: 'hey, how are you?',
                style: TextStyle(fontFamily: _family, fontSize: _size,
                  color: isDark ? AimColors.darkText : AimColors.msgTextColor)),
            ])),
          ),
          const SizedBox(height: 12),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            widget.onChanged(_family, _size);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ── AIM-style message line ─────────────────────────────────────────────────────
class _AimMessageLine extends StatelessWidget {
  final Event event;
  final bool isMe;
  final bool isDark;
  final String fontFamily;
  final double fontSize;

  const _AimMessageLine({
    required this.event, required this.isMe, required this.isDark,
    required this.fontFamily, required this.fontSize,
  });

  String get _senderName =>
      event.senderId.split(':').first.replaceFirst('@', '');

  @override
  Widget build(BuildContext context) {
    final nameColor = isMe
        ? (isDark ? AimColors.darkMyName    : AimColors.myNameColor)
        : (isDark ? AimColors.darkTheirName : AimColors.theirNameColor);
    final textColor = isDark ? AimColors.darkText : AimColors.msgTextColor;
    final t = event.originServerTs;
    final timeStr = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

    if (event.type == EventTypes.Encrypted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(text: TextSpan(children: [
          TextSpan(text: '[$timeStr] ',
            style: TextStyle(fontSize: fontSize * 0.75, color: Colors.grey[500], fontFamily: fontFamily)),
          TextSpan(text: '$_senderName: ',
            style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: FontWeight.bold, color: nameColor)),
          TextSpan(text: '🔒 Encrypted',
            style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, color: Colors.grey[500], fontStyle: FontStyle.italic)),
        ])),
      );
    }

    final msgType = event.messageType;
    String displayText;
    if (msgType == MessageTypes.Image) {
      displayText = '[Image: ${event.body}]';
    } else if (msgType == MessageTypes.Audio) {
      displayText = '[Audio: ${event.body}]';
    } else if (msgType == MessageTypes.Video) {
      displayText = '[Video: ${event.body}]';
    } else if (msgType == MessageTypes.File) {
      displayText = '[File: ${event.body}]';
    } else {
      displayText = event.body;
    }

    final isAttachment = msgType != MessageTypes.Text && msgType != MessageTypes.Notice;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '[$timeStr] ',
          style: TextStyle(fontSize: fontSize * 0.75, color: Colors.grey[500], fontFamily: fontFamily)),
        TextSpan(text: '$_senderName: ',
          style: TextStyle(fontFamily: fontFamily, fontSize: fontSize, fontWeight: FontWeight.bold, color: nameColor)),
        TextSpan(text: displayText,
          style: TextStyle(
            fontFamily: fontFamily, fontSize: fontSize,
            color: isAttachment ? Colors.grey[600] : textColor,
            fontStyle: isAttachment ? FontStyle.italic : FontStyle.normal)),
      ])),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────
class _ChatTitleBar extends StatelessWidget {
  final String title;
  final bool isDark;
  final VoidCallback onBack;
  final VoidCallback? onTimer;
  const _ChatTitleBar({required this.title, required this.isDark, required this.onBack, this.onTimer});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return Container(
      height: 28,
      decoration: BoxDecoration(gradient: LinearGradient(colors: isDark
          ? [AimColors.darkTitleBar, const Color(0xFF1A3A6A)]
          : [AimColors.titleBarStart, AimColors.titleBarEnd])),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        // Hide back button on wide layout — buddy list is always visible
        if (!isWide)
          InkWell(onTap: onBack,
            child: const Padding(padding: EdgeInsets.all(4),
              child: Icon(Icons.arrow_back, color: Colors.white, size: 14))),
        const Icon(Icons.lock, color: Colors.white, size: 12),
        const SizedBox(width: 4),
        Expanded(child: Text('Veil — $title',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis)),
        if (onTimer != null)
          InkWell(onTap: onTimer,
            child: const Padding(padding: EdgeInsets.all(4),
              child: Icon(Icons.timer_outlined, color: Colors.white, size: 14))),
      ]),
    );
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon, size: 16,
            color: onTap == null ? Colors.grey : (isDark ? Colors.grey[300] : Colors.black87)),
        ),
      ),
    );
  }
}
