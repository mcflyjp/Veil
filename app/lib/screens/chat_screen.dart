import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../core/disappearing_message_service.dart';
import '../core/notification_service.dart';
import '../core/html_span.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';
import '../widgets/disappearing_timer_dialog.dart';

// Available AIM-era fonts
const _kFonts = ['Arial', 'Verdana', 'Times New Roman', 'Courier New', 'Comic Sans MS', 'Georgia'];
const _kSizes = [14.0, 16.0, 18.0, 20.0, 22.0, 24.0];

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
  XFile?     _pendingImage;
  Uint8List? _pendingImageBytes;

  Room? get _room =>
      context.read<ClientManager>().roomById(Uri.decodeComponent(widget.roomId));

  @override
  void initState() {
    super.initState();
    NotificationService.instance.activeRoomId = Uri.decodeComponent(widget.roomId);
    _loadTimeline();
  }

  @override
  void dispose() {
    NotificationService.instance.activeRoomId = null;
    _timeline?.cancelSubscriptions();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    final room = _room;
    if (room == null) return;
    final timeline = await room.getTimeline(onUpdate: () => setState(() {}));
    setState(() { _timeline = timeline; _loadingTimeline = false; });
    await timeline.requestHistory(historyCount: 50);
  }

  /// Builds HTML-formatted body from the current text + user font prefs.
  /// Returns null when no formatting is active (plain message stays plain).
  String? _buildHtml(String text, VeilUserPrefs prefs) {
    final hasFormatting = prefs.bold || prefs.italic || prefs.underline
        || prefs.fontFamily != 'Arial'
        || prefs.fontSize   != 16.0;
    if (!hasFormatting) return null;

    var escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');

    var html = escaped;
    if (prefs.underline) html = '<u>$html</u>';
    if (prefs.italic)    html = '<i>$html</i>';
    if (prefs.bold)      html = '<b>$html</b>';
    return '<font face="${prefs.fontFamily}" data-pt="${prefs.fontSize.toInt()}">$html</font>';
  }

  Future<void> _sendText(VeilUserPrefs prefs) async {
    final text  = _inputCtrl.text.trim();
    final room  = _room;
    if (room == null) return;
    if (text.isEmpty && _pendingImage == null) return;

    _inputCtrl.clear();

    // Send staged image first, then any text.
    if (_pendingImage != null) await _sendStagedImage(room);
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final html = _buildHtml(text, prefs);
      final content = <String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': text,
        if (html != null) ...{
          'format': 'org.matrix.custom.html',
          'formatted_body': html,
        },
      };
      await room.sendEvent(content);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Stage an image for sending — does NOT send immediately.
  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() { _pendingImage = picked; _pendingImageBytes = bytes; });
  }

  /// Actually sends the staged image. Called from _sendText.
  Future<void> _sendStagedImage(Room room) async {
    final imgFile  = _pendingImage;
    final imgBytes = _pendingImageBytes;
    if (imgFile == null || imgBytes == null) return;
    setState(() { _pendingImage = null; _pendingImageBytes = null; _sending = true; });
    try {
      final ext  = imgFile.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : ext == 'gif' ? 'image/gif' : 'image/jpeg';
      await room.sendFileEvent(MatrixFile(bytes: imgBytes, name: imgFile.name, mimeType: mime));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send image: $e'), duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFile() async {
    final room = _room;
    if (room == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() => _sending = true);
    try {
      await room.sendFileEvent(MatrixFile(
        bytes: file.bytes!, name: file.name,
        mimeType: file.extension != null ? 'application/${file.extension}' : 'application/octet-stream'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send file: $e'), duration: const Duration(seconds: 4)));
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

  Future<void> _showMessageMenu(BuildContext ctx, Event event) async {
    final room = _room;
    if (room == null) return;
    final tc = context.read<VeilUserPrefs>().colors;
    final isText = event.messageType == MessageTypes.Text;

    await showModalBottomSheet(
      context: ctx,
      backgroundColor: tc.inputBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isText)
            _MsgMenuTile(
              icon: Icons.copy,
              label: 'Copy text',
              color: tc.nameText,
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: event.body));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
              },
            ),
          _MsgMenuTile(
            icon: Icons.timer_outlined,
            label: 'Disappear in…',
            color: tc.nameText,
            onTap: () async {
              Navigator.pop(ctx);
              await _pickDisappearTimer(ctx, event, room);
            },
          ),
          _MsgMenuTile(
            icon: Icons.delete_outline,
            label: 'Delete for everyone',
            color: Colors.red,
            onTap: () async {
              Navigator.pop(ctx);
              try { await room.redactEvent(event.eventId); } catch (_) {}
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickDisappearTimer(BuildContext ctx, Event event, Room room) async {
    const options = [
      (30, '30 seconds'),
      (60, '1 minute'),
      (300, '5 minutes'),
      (1800, '30 minutes'),
      (3600, '1 hour'),
      (86400, '24 hours'),
      (604800, '7 days'),
    ];

    final picked = await showDialog<int>(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Disappear in…', style: TextStyle(fontSize: 18)),
        children: options.map((o) {
          final (secs, label) = o;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, secs),
            child: Text(label, style: const TextStyle(fontSize: 16)),
          );
        }).toList(),
      ),
    );

    if (picked == null) return;
    await DisappearingMessageService.instance.schedule(
      eventId: event.eventId,
      roomId: room.id,
      after: Duration(seconds: picked),
      client: room.client,
    );
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Message will disappear in ${options.firstWhere((o) => o.$1 == picked).$2}'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _openFontPicker(VeilUserPrefs prefs) {
    showDialog(
      context: context,
      builder: (_) => _FontPickerDialog(
        currentFamily:    prefs.fontFamily,
        currentSize:      prefs.fontSize,
        currentBold:      prefs.bold,
        currentItalic:    prefs.italic,
        currentUnderline: prefs.underline,
        onChanged: (family, size, bold, italic, underline) {
          prefs.setFont(
            family:    family,
            size:      size,
            bold:      bold,
            italic:    italic,
            underline: underline,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr   = context.watch<ClientManager>();
    final prefs = context.watch<VeilUserPrefs>();
    final tc    = prefs.colors;
    final room  = mgr.roomById(Uri.decodeComponent(widget.roomId));
    final myId  = mgr.client.userID ?? '';

    if (room == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.go('/buddylist');
        },
        child: Scaffold(
          body: Column(children: [
            _ChatTitleBar(title: 'Chat', tc: tc, onBack: () => context.go('/buddylist')),
            Expanded(child: Container(
              color: tc.chatBg,
              child: const Center(child: Text('Room not found')),
            )),
          ]),
        ),
      );
    }

    final events = _timeline?.events ?? [];
    final msgEvents = events
        .where((e) => e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
        .toList();

    final toolbarBorderColor = tc.divider == Colors.transparent
        ? tc.scaffold.withAlpha(60)
        : tc.divider;
    final toolbarBorder = BorderSide(color: toolbarBorderColor);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/buddylist');
      },
      child: Scaffold(
        body: Column(children: [
          _ChatTitleBar(
            title: room.getLocalizedDisplayname(),
            tc: tc,
            onBack: () => context.go('/buddylist'),
            onTimer: _setDisappearing,
          ),

          // ── Message area ─────────────────────────────────────────────
          Expanded(
            child: Container(
              color: tc.chatBg,
              child: _loadingTimeline
                  ? Center(child: CircularProgressIndicator(color: tc.toolbarActive))
                  : msgEvents.isEmpty
                      ? Center(child: Text('No messages yet. Say something!',
                          style: TextStyle(fontSize: 16, color: tc.previewText)))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          reverse: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: msgEvents.length,
                          itemBuilder: (_, i) {
                            final event = msgEvents[i];
                            final isMe = event.senderId == myId;
                            return GestureDetector(
                              onLongPress: () => _showMessageMenu(context, event),
                              child: _AimMessageLine(
                                event: event, isMe: isMe, tc: tc,
                                myFontFamily: prefs.fontFamily,
                                myFontSize:   prefs.fontSize,
                              ),
                            );
                          },
                        ),
            ),
          ),

          // ── Pending image preview ─────────────────────────────────────
          if (_pendingImageBytes != null)
            Container(
              color: tc.inputBg,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(_pendingImageBytes!, height: 72, width: 72, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Image staged — press Send to send',
                  style: TextStyle(fontSize: 13, color: tc.previewText))),
                IconButton(
                  icon: Icon(Icons.close, color: tc.previewText, size: 20),
                  onPressed: () => setState(() { _pendingImage = null; _pendingImageBytes = null; }),
                ),
              ]),
            ),

          // ── Formatting toolbar ────────────────────────────────────────
          Container(
            height: 52,
            color: tc.toolbarBg,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(top: toolbarBorder, bottom: toolbarBorder),
            ),
            child: Row(children: [
              _BarBtn(icon: Icons.image_outlined, tooltip: 'Send image',
                  color: tc.toolbarText, onTap: _sending ? null : _sendImage),
              _BarBtn(icon: Icons.attach_file, tooltip: 'Send file',
                  color: tc.toolbarText, onTap: _sending ? null : _sendFile),
              _BarBtn(icon: Icons.timer_outlined, tooltip: 'Disappearing messages',
                  color: tc.toolbarText, onTap: _setDisappearing),
              const SizedBox(width: 4),
              // Font family + size picker
              InkWell(
                onTap: () => _openFontPicker(prefs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: toolbarBorderColor),
                    color: tc.inputBg.withAlpha(180),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('A', style: TextStyle(
                      fontFamily: prefs.fontFamily, fontSize: 16,
                      fontWeight: FontWeight.bold, color: tc.nameText)),
                    const SizedBox(width: 4),
                    Text('${prefs.fontFamily} · ${prefs.fontSize.toInt()}pt',
                      style: TextStyle(fontSize: 13, color: tc.previewText)),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              _FormatToggle(label: 'B', active: prefs.bold,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                tc: tc, onTap: () => prefs.setFont(bold: !prefs.bold)),
              const SizedBox(width: 3),
              _FormatToggle(label: 'I', active: prefs.italic,
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
                tc: tc, onTap: () => prefs.setFont(italic: !prefs.italic)),
              const SizedBox(width: 3),
              _FormatToggle(label: 'U', active: prefs.underline,
                style: const TextStyle(decoration: TextDecoration.underline, fontSize: 15),
                tc: tc, onTap: () => prefs.setFont(underline: !prefs.underline)),
            ]),
          ),

          // ── Input area ────────────────────────────────────────────────
          Container(
            color: tc.inputBg,
            padding: const EdgeInsets.all(10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    color: tc.inputBg,
                    border: Border.all(color: toolbarBorderColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      fontFamily:  prefs.fontFamily,
                      fontSize:    prefs.fontSize,
                      fontWeight:  prefs.bold      ? FontWeight.bold   : FontWeight.normal,
                      fontStyle:   prefs.italic    ? FontStyle.italic  : FontStyle.normal,
                      decoration:  prefs.underline ? TextDecoration.underline : TextDecoration.none,
                      color: tc.nameText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(fontSize: prefs.fontSize, color: tc.previewText),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _sending ? null : () => _sendText(prefs),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tc.badgeBg,
                    foregroundColor: tc.badgeText,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: _sending
                      ? SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: tc.badgeText))
                      : const Text('Send', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── B / I / U toggle button ────────────────────────────────────────────────────
class _FormatToggle extends StatelessWidget {
  final String label;
  final bool active;
  final TextStyle style;
  final VeilThemeColors tc;
  final VoidCallback onTap;

  const _FormatToggle({
    required this.label, required this.active, required this.style,
    required this.tc, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = tc.toolbarActive;
    final borderColor = tc.divider == Colors.transparent
        ? tc.scaffold.withAlpha(60) : tc.divider;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeColor : tc.inputBg.withAlpha(180),
          border: Border.all(color: active ? activeColor : borderColor),
        ),
        child: Text(label,
          style: style.copyWith(
            fontFamily: 'Arial',
            color: active ? tc.badgeText : tc.toolbarText,
          )),
      ),
    );
  }
}

// ── Font picker dialog ─────────────────────────────────────────────────────────
class _FontPickerDialog extends StatefulWidget {
  final String currentFamily;
  final double currentSize;
  final bool currentBold;
  final bool currentItalic;
  final bool currentUnderline;
  final void Function(String family, double size, bool bold, bool italic, bool underline) onChanged;

  const _FontPickerDialog({
    required this.currentFamily,
    required this.currentSize,
    required this.currentBold,
    required this.currentItalic,
    required this.currentUnderline,
    required this.onChanged,
  });

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  late String _family;
  late double _size;
  late bool   _bold;
  late bool   _italic;
  late bool   _underline;

  @override
  void initState() {
    super.initState();
    _family    = widget.currentFamily;
    _size      = widget.currentSize;
    _bold      = widget.currentBold;
    _italic    = widget.currentItalic;
    _underline = widget.currentUnderline;
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.read<VeilUserPrefs>().colors;
    final activeColor = tc.toolbarActive;
    final borderColor = tc.divider == Colors.transparent
        ? tc.scaffold.withAlpha(80) : tc.divider;

    return AlertDialog(
      backgroundColor: tc.inputBg,
      title: Text('Font Settings',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: tc.nameText)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Font', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tc.nameText)),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(border: Border.all(color: borderColor)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _family,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                style: TextStyle(fontSize: 16, color: tc.nameText),
                dropdownColor: tc.inputBg,
                items: _kFonts.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f, style: TextStyle(fontFamily: f, fontSize: 16, color: tc.nameText)),
                )).toList(),
                onChanged: (v) => setState(() => _family = v!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Size', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tc.nameText)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _kSizes.map((s) {
              final sel = s == _size;
              return GestureDetector(
                onTap: () => setState(() => _size = s),
                child: Container(
                  width: 44, height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? activeColor : tc.inputBg,
                    border: Border.all(color: sel ? activeColor : borderColor),
                  ),
                  child: Text('${s.toInt()}',
                    style: TextStyle(fontSize: 14,
                      color: sel ? tc.badgeText : tc.nameText,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('Style', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tc.nameText)),
          const SizedBox(height: 6),
          Row(children: [
            _DialogToggle(label: 'B', active: _bold, tc: tc,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              onTap: () => setState(() => _bold = !_bold)),
            const SizedBox(width: 6),
            _DialogToggle(label: 'I', active: _italic, tc: tc,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
              onTap: () => setState(() => _italic = !_italic)),
            const SizedBox(width: 6),
            _DialogToggle(label: 'U', active: _underline, tc: tc,
              style: const TextStyle(decoration: TextDecoration.underline, fontSize: 15),
              onTap: () => setState(() => _underline = !_underline)),
          ]),
          const SizedBox(height: 12),
          // Live preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tc.chatBg,
              border: Border.all(color: borderColor)),
            child: RichText(text: TextSpan(children: [
              TextSpan(text: 'You: ',
                style: TextStyle(fontFamily: _family, fontSize: _size,
                  fontWeight: FontWeight.bold, color: tc.myNameColor)),
              TextSpan(text: 'hey, how are you?',
                style: TextStyle(
                  fontFamily:  _family,
                  fontSize:    _size,
                  fontWeight:  _bold      ? FontWeight.bold   : FontWeight.normal,
                  fontStyle:   _italic    ? FontStyle.italic  : FontStyle.normal,
                  decoration:  _underline ? TextDecoration.underline : TextDecoration.none,
                  color: tc.nameText,
                )),
            ])),
          ),
          const SizedBox(height: 12),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.previewText)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.badgeBg, foregroundColor: tc.badgeText),
          onPressed: () {
            widget.onChanged(_family, _size, _bold, _italic, _underline);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _DialogToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VeilThemeColors tc;
  final TextStyle style;
  final VoidCallback onTap;

  const _DialogToggle({
    required this.label, required this.active, required this.tc,
    required this.style, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = tc.toolbarActive;
    final borderColor = tc.divider == Colors.transparent
        ? tc.scaffold.withAlpha(80) : tc.divider;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? activeColor : tc.inputBg,
          border: Border.all(color: active ? activeColor : borderColor),
        ),
        child: Text(label,
          style: style.copyWith(
            fontFamily: 'Arial',
            color: active ? tc.badgeText : tc.nameText,
          )),
      ),
    );
  }
}

// ── AIM-style message line ─────────────────────────────────────────────────────
class _AimMessageLine extends StatelessWidget {
  final Event event;
  final bool isMe;
  final VeilThemeColors tc;
  final String myFontFamily;
  final double myFontSize;

  const _AimMessageLine({
    required this.event, required this.isMe, required this.tc,
    required this.myFontFamily, required this.myFontSize,
  });

  String get _senderName =>
      event.senderId.split(':').first.replaceFirst('@', '');

  @override
  Widget build(BuildContext context) {
    final nameColor = isMe ? tc.myNameColor : tc.theirNameColor;
    final t = event.originServerTs;
    final timeStr = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

    // Timestamps always use a small neutral font — never affected by anyone's prefs.
    final timeSpan = TextSpan(
      text: '[$timeStr] ',
      style: TextStyle(fontSize: 11, color: tc.timestampText, fontFamily: 'Arial'),
    );

    // Apply the local user's font only to their OWN messages.
    // Other people's font is embedded in their formatted_body HTML.
    final bodyFamily = isMe ? myFontFamily : 'Arial';
    final bodySize   = isMe ? myFontSize   : 16.0;

    final nameSpan = TextSpan(
      text: '$_senderName: ',
      style: TextStyle(fontFamily: bodyFamily, fontSize: bodySize,
          fontWeight: FontWeight.bold, color: nameColor),
    );

    if (event.type == EventTypes.Encrypted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(text: TextSpan(children: [
          timeSpan, nameSpan,
          TextSpan(text: '🔒 Encrypted',
            style: TextStyle(fontFamily: bodyFamily, fontSize: bodySize,
              color: tc.previewText, fontStyle: FontStyle.italic)),
        ])),
      );
    }

    final msgType = event.messageType;
    if (msgType == MessageTypes.Image) {
      return _buildImageMessage(timeSpan, nameSpan, bodyFamily, bodySize);
    }
    if (msgType == MessageTypes.Audio || msgType == MessageTypes.Video ||
        msgType == MessageTypes.File) {
      final label = msgType == MessageTypes.Audio ? '[Audio: ${event.body}]'
                  : msgType == MessageTypes.Video ? '[Video: ${event.body}]'
                  : '[File: ${event.body}]';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(text: TextSpan(children: [
          timeSpan, nameSpan,
          TextSpan(text: label,
            style: TextStyle(fontFamily: bodyFamily, fontSize: bodySize,
              color: tc.previewText, fontStyle: FontStyle.italic)),
        ])),
      );
    }

    // Text message — HTML formatted_body carries the sender's chosen font.
    final format        = event.content['format']         as String?;
    final formattedBody = event.content['formatted_body'] as String?;

    if (format == 'org.matrix.custom.html' && formattedBody != null) {
      final base = TextStyle(fontFamily: bodyFamily, fontSize: bodySize, color: tc.nameText);
      final spans = htmlToSpans(formattedBody, base);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(text: TextSpan(children: [timeSpan, nameSpan, ...spans])),
      );
    }

    // Plain text message — use sender's own font for isMe, default for others.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(text: TextSpan(children: [
        timeSpan, nameSpan,
        TextSpan(text: event.body,
          style: TextStyle(fontFamily: bodyFamily, fontSize: bodySize, color: tc.nameText)),
      ])),
    );
  }

  Widget _buildImageMessage(TextSpan timeSpan, TextSpan nameSpan,
      String bodyFamily, double bodySize) {
    final client = event.room.client;

    // Matrix image events can carry the MXC URL in two places:
    //   - event.content['url']        for unencrypted rooms
    //   - event.content['file']['url'] for E2E-encrypted rooms
    String? mxcUrl;
    final fileMap = event.content['file'];
    if (fileMap is Map) mxcUrl = fileMap['url'] as String?;
    mxcUrl ??= event.content['url'] as String?;

    Widget imageWidget;
    if (mxcUrl != null && mxcUrl.startsWith('mxc://')) {
      final mxcUri    = Uri.parse(mxcUrl);
      final httpUrl   = '${client.homeserver}/_matrix/media/v3/download'
                        '/${mxcUri.host}${mxcUri.path}';
      final authToken = client.accessToken ?? '';
      imageWidget = Image.network(
        httpUrl,
        headers: {'Authorization': 'Bearer $authToken'},
        height: 220,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Text('[Image — encrypted or unavailable]',
            style: TextStyle(fontSize: bodySize, fontStyle: FontStyle.italic,
              color: tc.previewText, fontFamily: bodyFamily)),
        ),
      );
    } else {
      imageWidget = Text('[Image]',
        style: TextStyle(fontSize: bodySize, fontStyle: FontStyle.italic,
          color: tc.previewText, fontFamily: bodyFamily));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(children: [timeSpan, nameSpan])),
        const SizedBox(height: 4),
        imageWidget,
      ]),
    );
  }
}

// ── Chat title bar ─────────────────────────────────────────────────────────────
class _ChatTitleBar extends StatelessWidget {
  final String title;
  final VeilThemeColors tc;
  final VoidCallback onBack;
  final VoidCallback? onTimer;
  const _ChatTitleBar({required this.title, required this.tc, required this.onBack, this.onTimer});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd])),
      padding: EdgeInsets.fromLTRB(8, topPad + 14, 8, 14),
      child: Row(children: [
        if (!isWide)
          InkWell(onTap: onBack,
            child: Padding(padding: const EdgeInsets.all(8),
              child: Icon(Icons.arrow_back, color: tc.titleOnColor, size: 24))),
        Icon(Icons.lock, color: tc.titleOnColor.withAlpha(200), size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('Veil — $title',
          style: TextStyle(color: tc.titleOnColor, fontSize: 18, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis)),
        if (onTimer != null)
          InkWell(onTap: onTimer,
            child: Padding(padding: const EdgeInsets.all(8),
              child: Icon(Icons.timer_outlined, color: tc.titleOnColor, size: 24))),
      ]),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────
class _MsgMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MsgMenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? (Theme.of(context).brightness == Brightness.dark ? AimColors.darkText : Colors.black87);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Icon(icon, size: 24, color: c),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(fontSize: 16, color: c)),
        ]),
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;
  const _BarBtn({required this.icon, required this.tooltip, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icon, size: 26,
            color: onTap == null ? color.withAlpha(80) : color),
        ),
      ),
    );
  }
}
