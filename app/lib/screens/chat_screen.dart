import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../core/client_manager.dart';
import '../core/aim_theme.dart';
import '../core/disappearing_message_service.dart';
import '../core/notification_service.dart';
import '../core/html_span.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';
import '../widgets/disappearing_timer_dialog.dart';

const _kFonts = ['Arial', 'Verdana', 'Times New Roman', 'Courier New', 'Comic Sans MS', 'Georgia'];
const _kSizes = [14.0, 16.0, 18.0, 20.0, 22.0, 24.0];

class ChatScreen extends StatefulWidget {
  final String roomId;
  const ChatScreen({super.key, required this.roomId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  Timeline? _timeline;
  bool _loadingTimeline = true;
  bool _sending         = false;
  XFile?     _pendingImage;
  Uint8List? _pendingImageBytes;

  // Typing indicator state
  Timer? _typingTimer;
  bool   _isTyping = false;

  // Per-message disappear timer (0 = off)
  int _disappearAfterSecs = 0;

  String get _disappearLabel => _disappearAfterSecs == 0 ? ''
      : _disappearAfterSecs < 60 ? '${_disappearAfterSecs}s'
      : '${_disappearAfterSecs ~/ 60}m';

  Room? get _room =>
      context.read<ClientManager>().roomById(Uri.decodeComponent(widget.roomId));

  @override
  void initState() {
    super.initState();
    NotificationService.instance.activeRoomId = Uri.decodeComponent(widget.roomId);
    _inputCtrl.addListener(_onTypingChanged);
    context.read<ClientManager>().addListener(_scheduleVisibleDisappearing);

    // If the timeline is already cached, use it immediately — no spinner, no freeze.
    final cached = context.read<ClientManager>().getTimeline(Uri.decodeComponent(widget.roomId));
    if (cached != null) {
      _timeline = cached;
      _loadingTimeline = false;
      _setReadMarker();
      _scheduleVisibleDisappearing();
    } else {
      _loadTimeline();
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _room?.setTyping(false);
    NotificationService.instance.activeRoomId = null;
    context.read<ClientManager>().removeListener(_scheduleVisibleDisappearing);
    // Timeline is owned by ClientManager — do NOT cancel it here.
    // Cancelling would break re-entry into the same chat without a full reload.
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    final mgr    = context.read<ClientManager>();
    final roomId = Uri.decodeComponent(widget.roomId);
    try {
      final tl = await mgr.getOrCreateTimeline(roomId);
      if (!mounted) return;
      setState(() { _timeline = tl; _loadingTimeline = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTimeline = false);
    }
    await _setReadMarker();
    _scheduleVisibleDisappearing();
  }

  // Called on every ClientManager notification (each sync) while this chat is open.
  // Starts the disappear timer for any messages with veil_disappear_secs that haven't
  // been scheduled yet. Idempotent — DisappearingMessageService guards against
  // double-scheduling. This is what makes the timer "start on view": no timer is
  // started until the user actually opens the conversation.
  void _scheduleVisibleDisappearing() => _doScheduleVisible();

  Future<void> _doScheduleVisible() async {
    final timeline = _timeline;
    final room = _room;
    if (timeline == null || room == null) return;
    if (!mounted) return;
    final client = context.read<ClientManager>().client;
    for (final event in List.of(timeline.events)) {
      if (event.type != EventTypes.Message) continue;
      final content = event.content;
      final secs    = content['veil_disappear_secs'];
      final expAt   = content['veil_expire_at'];
      if (secs == null && expAt == null) continue;
      if (DisappearingMessageService.instance.isArmed(event.eventId)) continue;
      final Duration dur;
      if (secs is int) {
        dur = Duration(seconds: secs);
      } else if (expAt is int) {
        final ms = expAt - DateTime.now().millisecondsSinceEpoch;
        if (ms <= 0) continue;
        dur = Duration(milliseconds: ms);
      } else {
        continue;
      }
      if (!mounted) return;
      await DisappearingMessageService.instance.schedule(
        eventId: event.eventId, roomId: room.id,
        after: dur, client: client,
      );
    }
  }

  Future<void> _setReadMarker() async {
    final room = _room;
    final tl   = _timeline;
    if (room == null || tl == null) return;
    final latest = tl.events.where((e) => e.type == EventTypes.Message).firstOrNull;
    if (latest != null) {
      try { await room.setReadMarker(latest.eventId); } catch (_) {}
    }
  }

  void _onTypingChanged() {
    final room = _room;
    if (room == null) return;
    if (_inputCtrl.text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _typingTimer?.cancel();
        room.setTyping(false);
      }
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      room.setTyping(true, timeout: 30000);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 5), () {
      _isTyping = false;
      room.setTyping(false);
    });
  }

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
    // data-pt is Veil-specific; also emit standard CSS font-size for other clients
    return '<font face="${prefs.fontFamily}" data-pt="${prefs.fontSize.toInt()}" style="font-size:${prefs.fontSize.toInt()}pt">$html</font>';
  }

  Future<void> _sendText(VeilUserPrefs prefs) async {
    final text = _inputCtrl.text.trim();
    final room = _room;
    if (room == null) return;
    if (text.isEmpty && _pendingImage == null) return;

    _inputCtrl.clear();
    _isTyping = false;
    _typingTimer?.cancel();
    room.setTyping(false);

    if (_pendingImage != null) await _sendStagedImage(room);
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final html = _buildHtml(text, prefs);
      await room.sendEvent(<String, dynamic>{
        'msgtype': MessageTypes.Text,
        'body': text,
        if (html != null) ...{
          'format': 'org.matrix.custom.html',
          'formatted_body': html,
        },
        if (_disappearAfterSecs > 0)
          'veil_disappear_secs': _disappearAfterSecs,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickMedia() async {
    final tc = context.read<VeilUserPrefs>().colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tc.inputBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
                color: tc.previewText.withAlpha(80),
                borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: Icon(Icons.image_outlined, color: tc.toolbarText),
            title: Text('Photo', style: TextStyle(color: tc.nameText, fontSize: 16)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await _sendImage();
            },
          ),
          ListTile(
            leading: Icon(Icons.videocam_outlined, color: tc.toolbarText),
            title: Text('Video', style: TextStyle(color: tc.nameText, fontSize: 16)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await _sendVideo();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (mounted) setState(() { _pendingImage = picked; _pendingImageBytes = bytes; });
  }

  Future<void> _sendVideo() async {
    final room = _room;
    if (room == null) return;
    // Use ImagePicker so we never load the whole file into memory upfront
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final f = File(picked.path);
    final size = await f.length();
    if (size > 100 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video too large (max 100 MB)'), duration: Duration(seconds: 3)));
      return;
    }
    setState(() => _sending = true);
    try {
      final bytes = await f.readAsBytes();
      final ext  = picked.name.split('.').last.toLowerCase();
      final mime = ext == 'webm' ? 'video/webm'
                 : ext == 'mov'  ? 'video/quicktime'
                 : 'video/mp4';
      await room.sendFileEvent(MatrixFile(bytes: bytes, name: picked.name, mimeType: mime));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send video: $e'), duration: const Duration(seconds: 4)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addMember() async {
    final room = _room;
    if (room == null) return;
    final tc   = context.read<VeilUserPrefs>().colors;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.inputBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add person', style: TextStyle(color: tc.nameText, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: tc.nameText, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Screen name (e.g. alice)',
            hintStyle: TextStyle(color: tc.previewText),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: tc.toolbarActive)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: tc.toolbarActive, width: 2)),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tc.previewText))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: tc.badgeBg, foregroundColor: tc.badgeText),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Invite')),
        ],
      ),
    );
    final input = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed != true || input.isEmpty) return;
    String userId = input;
    if (!userId.startsWith('@')) userId = '@$userId:veilmsg.com';
    else if (!userId.contains(':')) userId = '$userId:veilmsg.com';
    try {
      await room.invite(userId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invited $userId'), duration: const Duration(seconds: 2)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not invite: $e'), duration: const Duration(seconds: 4)));
    }
  }

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
    // withData: false — read from disk path to avoid OOM on large files
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) return;
    final f = File(path);
    final size = await f.length();
    if (size > 100 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File too large (max 100 MB)'), duration: Duration(seconds: 3)));
      return;
    }
    setState(() => _sending = true);
    try {
      final bytes = await f.readAsBytes();
      await room.sendFileEvent(MatrixFile(
        bytes: bytes, name: file.name,
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

  Future<void> _pickDisappearTimer() async {
    const options = [
      (0,  'Off'),
      (3,  '3 seconds'),
      (5,  '5 seconds'),
      (10, '10 seconds'),
      (60, '1 minute'),
    ];
    final tc = context.read<VeilUserPrefs>().colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: tc.inputBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            decoration: BoxDecoration(
                color: tc.previewText.withAlpha(80),
                borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Next message disappears after…',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: tc.nameText))),
          ...options.map((o) {
            final (secs, label) = o;
            final active = secs == _disappearAfterSecs;
            return ListTile(
              leading: Icon(
                secs == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                color: active ? Colors.orange : tc.toolbarText, size: 22),
              title: Text(label,
                  style: TextStyle(fontSize: 16, color: tc.nameText,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal)),
              trailing: active ? const Icon(Icons.check, color: Colors.orange) : null,
              onTap: () {
                setState(() => _disappearAfterSecs = secs);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
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
            _MsgMenuTile(icon: Icons.copy, label: 'Copy text', color: tc.nameText,
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: event.body));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
              }),
          _MsgMenuTile(icon: Icons.timer_outlined, label: 'Disappear in…', color: tc.nameText,
            onTap: () async {
              Navigator.pop(ctx);
              await _pickEventDisappearTimer(ctx, event, room);
            }),
          _MsgMenuTile(icon: Icons.delete_outline, label: 'Delete for everyone', color: Colors.red,
            onTap: () async {
              Navigator.pop(ctx);
              try { await room.redactEvent(event.eventId); } catch (_) {}
            }),
        ]),
      ),
    );
  }

  Future<void> _pickEventDisappearTimer(BuildContext ctx, Event event, Room room) async {
    const options = [
      (3,  '3 seconds'),
      (5,  '5 seconds'),
      (10, '10 seconds'),
      (60, '1 minute'),
    ];
    final picked = await showDialog<int>(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('Disappear in…', style: TextStyle(fontSize: 18)),
        children: options.map((o) {
          final (secs, label) = o;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogCtx, secs),
            child: Text(label, style: const TextStyle(fontSize: 16)));
        }).toList(),
      ),
    );
    if (picked == null) return;
    await DisappearingMessageService.instance.schedule(
      eventId: event.eventId, roomId: room.id,
      after: Duration(seconds: picked), client: room.client);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Message will disappear in ${options.firstWhere((o) => o.$1 == picked).$2}'),
        duration: const Duration(seconds: 2)));
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
        onChanged: (family, size, bold, italic, underline) =>
          prefs.setFont(family: family, size: size, bold: bold, italic: italic, underline: underline),
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
        onPopInvokedWithResult: (didPop, _) { if (!didPop) context.go('/buddylist'); },
        child: Scaffold(
          body: Column(children: [
            _ChatTitleBar(title: 'Chat', tc: tc, onBack: () => context.go('/buddylist')),
            Expanded(child: Container(color: tc.chatBg,
              child: const Center(child: Text('Room not found')))),
          ]),
        ),
      );
    }

    final events    = _timeline?.events ?? [];
    final msgEvents = events
        .where((e) => e.type == EventTypes.Message || e.type == EventTypes.Encrypted)
        .toList();

    // Who is typing right now (excluding ourselves)
    final typingUsers = room.typingUsers
        .where((u) => u.id != myId)
        .map((u) => u.id.split(':').first.replaceFirst('@', ''))
        .toList();

    final toolbarBorderColor = tc.divider == Colors.transparent
        ? tc.scaffold.withAlpha(60) : tc.divider;
    final toolbarBorder = BorderSide(color: toolbarBorderColor);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) context.go('/buddylist'); },
      child: Scaffold(
        body: Column(children: [
          _ChatTitleBar(
            title: room.getLocalizedDisplayname(),
            tc: tc,
            onBack: () => context.go('/buddylist'),
            onTimer: _setDisappearing,
            onAddMember: room.isDirectChat ? null : _addMember,
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
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                          itemCount: msgEvents.length,
                          itemBuilder: (_, i) {
                            final event = msgEvents[i];
                            final isMe  = event.senderId == myId;
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

          // ── Typing indicator ──────────────────────────────────────────
          if (typingUsers.isNotEmpty)
            Container(
              width: double.infinity,
              color: tc.chatBg,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Text(
                '${typingUsers.join(', ')} ${typingUsers.length == 1 ? 'is' : 'are'} typing…',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: tc.previewText)),
            ),

          // ── Disappear timer indicator ─────────────────────────────────
          if (_disappearAfterSecs > 0)
            Container(
              color: Colors.orange.withAlpha(25),
              padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
              child: Row(children: [
                const Icon(Icons.timer, color: Colors.orange, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Next message disappears after $_disappearLabel',
                  style: const TextStyle(fontSize: 12, color: Colors.orange))),
                GestureDetector(
                  onTap: () => setState(() => _disappearAfterSecs = 0),
                  child: const Icon(Icons.close, color: Colors.orange, size: 16)),
              ]),
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
            decoration: BoxDecoration(border: Border(top: toolbarBorder, bottom: toolbarBorder)),
            child: Row(children: [
              _BarBtn(icon: Icons.perm_media_outlined, tooltip: 'Send photo or video',
                  color: tc.toolbarText, onTap: _sending ? null : _pickMedia),
              _BarBtn(icon: Icons.attach_file, tooltip: 'Send file',
                  color: tc.toolbarText, onTap: _sending ? null : _sendFile),
              // Per-message disappear toggle (orange when active)
              _BarBtn(
                icon: _disappearAfterSecs > 0 ? Icons.timer : Icons.timer_outlined,
                tooltip: _disappearAfterSecs > 0
                    ? 'Disappear: $_disappearLabel — tap to change'
                    : 'Send as disappearing message',
                color: _disappearAfterSecs > 0 ? Colors.orange : tc.toolbarText,
                onTap: _pickDisappearTimer,
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _openFontPicker(prefs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: toolbarBorderColor),
                    color: tc.inputBg.withAlpha(180),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('A', style: TextStyle(fontFamily: prefs.fontFamily, fontSize: 16,
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
            padding: EdgeInsets.fromLTRB(10, 10, 10,
                10 + MediaQuery.viewPaddingOf(context).bottom),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  decoration: BoxDecoration(
                    border: Border.all(color: toolbarBorderColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocus,
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
                      filled: true,
                      fillColor: tc.inputBg,
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

// ── B / I / U toggle ──────────────────────────────────────────────────────────
class _FormatToggle extends StatelessWidget {
  final String label;
  final bool active;
  final TextStyle style;
  final VeilThemeColors tc;
  final VoidCallback onTap;
  const _FormatToggle({required this.label, required this.active, required this.style,
      required this.tc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor  = tc.toolbarActive;
    final borderColor  = tc.divider == Colors.transparent ? tc.scaffold.withAlpha(60) : tc.divider;
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
          style: style.copyWith(fontFamily: 'Arial',
            color: active ? tc.badgeText : tc.toolbarText)),
      ),
    );
  }
}

// ── Font picker dialog ────────────────────────────────────────────────────────
class _FontPickerDialog extends StatefulWidget {
  final String currentFamily;
  final double currentSize;
  final bool currentBold, currentItalic, currentUnderline;
  final void Function(String, double, bool, bool, bool) onChanged;
  const _FontPickerDialog({
    required this.currentFamily, required this.currentSize,
    required this.currentBold, required this.currentItalic, required this.currentUnderline,
    required this.onChanged,
  });
  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  late String _family;
  late double _size;
  late bool   _bold, _italic, _underline;

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
    final borderColor = tc.divider == Colors.transparent ? tc.scaffold.withAlpha(80) : tc.divider;

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
                value: _family, isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                style: TextStyle(fontSize: 16, color: tc.nameText),
                dropdownColor: tc.inputBg,
                items: _kFonts.map((f) => DropdownMenuItem(value: f,
                  child: Text(f, style: TextStyle(fontFamily: f, fontSize: 16, color: tc.nameText)))).toList(),
                onChanged: (v) => setState(() => _family = v!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Size', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tc.nameText)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8,
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: tc.chatBg, border: Border.all(color: borderColor)),
            child: RichText(text: TextSpan(children: [
              TextSpan(text: 'You: ',
                style: TextStyle(fontFamily: _family, fontSize: _size,
                  fontWeight: FontWeight.bold, color: tc.myNameColor)),
              TextSpan(text: 'hey, how are you?',
                style: TextStyle(fontFamily: _family, fontSize: _size,
                  fontWeight:  _bold      ? FontWeight.bold   : FontWeight.normal,
                  fontStyle:   _italic    ? FontStyle.italic  : FontStyle.normal,
                  decoration:  _underline ? TextDecoration.underline : TextDecoration.none,
                  color: tc.nameText)),
            ])),
          ),
          const SizedBox(height: 12),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.previewText))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: tc.badgeBg, foregroundColor: tc.badgeText),
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
  const _DialogToggle({required this.label, required this.active, required this.tc,
      required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = tc.toolbarActive;
    final borderColor = tc.divider == Colors.transparent ? tc.scaffold.withAlpha(80) : tc.divider;
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
          style: style.copyWith(fontFamily: 'Arial',
            color: active ? tc.badgeText : tc.nameText)),
      ),
    );
  }
}

// ── Message line ──────────────────────────────────────────────────────────────
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

  bool get _isDisappearing =>
      event.content['veil_disappear_secs'] != null ||
      event.content['veil_expire_at'] != null;

  @override
  Widget build(BuildContext context) {
    // Glass theme gets modern bubble layout
    if (tc.useGlass) return _buildGlassBubble(context);
    return _buildAimLine(context);
  }

  // ── Glass bubble ────────────────────────────────────────────────────────────
  Widget _buildGlassBubble(BuildContext context) {
    final t = event.originServerTs;
    final timeStr = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

    Widget body;
    if (event.type == EventTypes.Encrypted) {
      body = Text('🔒 Encrypted',
        style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 15));
    } else if (event.messageType == MessageTypes.Image) {
      body = _buildNetworkImage(context, height: 200);
    } else if (event.messageType == MessageTypes.Video) {
      body = _buildVideoMessage(context);
    } else {
      final formattedBody = event.content['formatted_body'] as String?;
      if (formattedBody != null && formattedBody.isNotEmpty) {
        final base = const TextStyle(fontSize: 15, color: Colors.white);
        final spans = htmlToSpans(formattedBody, base);
        body = RichText(text: TextSpan(children: spans));
      } else {
        body = Text(event.body, style: const TextStyle(fontSize: 15, color: Colors.white));
      }
    }

    final bubbleBg = isMe
        ? const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF4C1D95)])
        : const LinearGradient(colors: [Color(0x22FFFFFF), Color(0x14FFFFFF)]);

    final borderRadius = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4))
        : const BorderRadius.only(
            topLeft: Radius.circular(4), topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18));

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(gradient: bubbleBg, borderRadius: borderRadius,
        border: isMe ? null : Border.all(color: Colors.white.withAlpha(30))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: body,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(_senderName,
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600)),
            ),
          bubble,
          if (_isDisappearing && event.messageType != MessageTypes.Image)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: _DisappearingCountdown(eventId: event.eventId),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ── AIM flat text layout ────────────────────────────────────────────────────
  Widget _buildAimLine(BuildContext context) {
    final nameColor  = isMe ? tc.myNameColor : tc.theirNameColor;
    final t          = event.originServerTs;
    final timeStr    = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

    // Timestamps always use a small neutral font
    final timeSpan = TextSpan(
      text: '[$timeStr] ',
      style: TextStyle(fontSize: 11, color: tc.timestampText, fontFamily: 'Arial'),
    );
    // Apply local font prefs only to own messages; default for received
    final bodyFamily = isMe ? myFontFamily : 'Arial';
    final bodySize   = isMe ? myFontSize   : 16.0;
    final nameSpan   = TextSpan(
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

    if (event.messageType == MessageTypes.Image) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(children: [timeSpan, nameSpan])),
          const SizedBox(height: 4),
          _buildNetworkImage(context, height: 200),
        ]),
      );
    }

    if (event.messageType == MessageTypes.Video) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(children: [timeSpan, nameSpan])),
          const SizedBox(height: 4),
          _buildVideoMessage(context),
        ]),
      );
    }

    if (event.messageType == MessageTypes.Audio || event.messageType == MessageTypes.File) {
      final label = event.messageType == MessageTypes.Audio ? '[Audio: ${event.body}]'
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

    // Text — HTML carries the sender's formatting; plain messages fall through
    final formattedBody = event.content['formatted_body'] as String?;
    if (formattedBody != null && formattedBody.isNotEmpty) {
      final base  = TextStyle(fontFamily: bodyFamily, fontSize: bodySize, color: tc.nameText);
      final spans = htmlToSpans(formattedBody, base);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichText(text: TextSpan(children: [timeSpan, nameSpan, ...spans])),
          if (_isDisappearing) _DisappearingCountdown(eventId: event.eventId),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(children: [
          timeSpan, nameSpan,
          TextSpan(text: event.body,
            style: TextStyle(fontFamily: bodyFamily, fontSize: bodySize, color: tc.nameText)),
        ])),
        if (_isDisappearing) _DisappearingCountdown(eventId: event.eventId),
      ]),
    );
  }

  // ── Network image with tap-to-enlarge and save ─────────────────────────────
  Widget _buildNetworkImage(BuildContext context, {required double height}) {
    final client = event.room.client;
    final fileMap = event.content['file'];
    String? mxcUrl;
    if (fileMap is Map) mxcUrl = fileMap['url'] as String?;
    mxcUrl ??= event.content['url'] as String?;

    if (mxcUrl == null || !mxcUrl.startsWith('mxc://')) {
      return Text('[Image]', style: TextStyle(fontStyle: FontStyle.italic, color: tc.previewText));
    }

    final mxcUri  = Uri.parse(mxcUrl);
    final httpUrl = '${client.homeserver}/_matrix/media/v3/download/${mxcUri.host}${mxcUri.path}';
    final token   = client.accessToken ?? '';

    // E2E encrypted images: the media bytes at the URL are AES-CTR encrypted;
    // Image.network can't display them. Show a tap-to-open indicator instead.
    final isEncrypted = fileMap is Map && (fileMap as Map)['key'] is Map;
    if (isEncrypted) {
      return Container(
        height: height,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock, size: 18, color: tc.previewText),
          const SizedBox(width: 6),
          Text('Encrypted image',
              style: TextStyle(fontStyle: FontStyle.italic, color: tc.previewText)),
        ]),
      );
    }

    // Disappearing images cannot be saved
    final isDisappearing = event.content['veil_disappear_secs'] != null ||
        event.content['veil_expire_at'] != null;

    final img = Image.network(
      httpUrl,
      headers: {'Authorization': 'Bearer $token'},
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Text('[Image — encrypted or unavailable]',
        style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: tc.previewText)),
    );

    // Disappearing images: blur + clock overlay (Telegram-style).
    // Tapping still opens the unblurred fullscreen dialog.
    final Widget thumbnail = isDisappearing
        ? SizedBox(
            height: height, width: 250,
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Image.network(httpUrl,
                    headers: {'Authorization': 'Bearer $token'},
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey.shade900)),
                ),
                Container(color: Colors.black.withAlpha(70)),
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.timer, color: Colors.white, size: 40),
                  const SizedBox(height: 6),
                  _DisappearingCountdown(eventId: event.eventId, color: Colors.white),
                ])),
              ]),
            ),
          )
        : img;

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (dialogCtx) {
          Future<void> saveImage() async {
            try {
              final resp = await http.get(
                  Uri.parse(httpUrl), headers: {'Authorization': 'Bearer $token'});
              if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
              final dir  = await getApplicationDocumentsDirectory();
              final name = 'veil_${DateTime.now().millisecondsSinceEpoch}.jpg';
              await File('${dir.path}/$name').writeAsBytes(resp.bodyBytes);
              // Notify sender
              final myName = client.userID?.split(':').first.replaceFirst('@', '') ?? 'Someone';
              await event.room.sendEvent({
                'msgtype': 'm.notice',
                'body': '💾 $myName saved your image',
              });
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(
                  content: Text('Image saved to Veil folder'),
                  duration: Duration(seconds: 2)));
              }
            } catch (e) {
              if (dialogCtx.mounted) {
                ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
                  content: Text('Save failed: $e'),
                  duration: const Duration(seconds: 3)));
              }
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(12),
            child: Stack(children: [
              InteractiveViewer(child: Image.network(httpUrl,
                headers: {'Authorization': 'Bearer $token'},
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text('[Image unavailable]',
                  style: TextStyle(color: Colors.white)))),
              // Close button
              Positioned(top: 0, right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(dialogCtx))),
              // Save button — hidden for disappearing images
              if (!isDisappearing)
                Positioned(bottom: 0, right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8)),
                    child: IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 24),
                      tooltip: 'Save image',
                      onPressed: saveImage))),
              if (isDisappearing)
                const Positioned(bottom: 8, left: 0, right: 0,
                  child: Center(child: Text('⏱ Disappearing — cannot save',
                    style: TextStyle(color: Colors.white70, fontSize: 12)))),
            ]),
          );
        },
      ),
      child: thumbnail,
    );
  }

  // ── Video message card ────────────────────────────────────────────────────
  Widget _buildVideoMessage(BuildContext context) {
    final client = event.room.client;
    String? mxcUrl;
    final fileMap = event.content['file'];
    if (fileMap is Map) mxcUrl = fileMap['url'] as String?;
    mxcUrl ??= event.content['url'] as String?;

    if (mxcUrl == null || !mxcUrl.startsWith('mxc://')) {
      return Text('[Video — unavailable]',
          style: TextStyle(fontStyle: FontStyle.italic, color: tc.previewText));
    }

    final mxcUri  = Uri.parse(mxcUrl);
    final httpUrl = '${client.homeserver}/_matrix/media/v3/download/${mxcUri.host}${mxcUri.path}';
    final token   = client.accessToken ?? '';

    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _InlineVideoDialog(httpUrl: httpUrl, token: token),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: tc.rowBg.withAlpha(200),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.divider == Colors.transparent
              ? tc.nameText.withAlpha(30) : tc.divider),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_circle_outline, color: tc.toolbarActive, size: 36),
          const SizedBox(width: 10),
          Flexible(child: Text(event.body,
            style: TextStyle(color: tc.previewText, fontSize: 14),
            overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

// ── Inline video player dialog ────────────────────────────────────────────────
class _InlineVideoDialog extends StatefulWidget {
  final String httpUrl;
  final String token;
  const _InlineVideoDialog({required this.httpUrl, required this.token});

  @override
  State<_InlineVideoDialog> createState() => _InlineVideoDialogState();
}

class _InlineVideoDialogState extends State<_InlineVideoDialog> {
  late final VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.httpUrl),
      httpHeaders: {'Authorization': 'Bearer ${widget.token}'},
    );
    _ctrl.initialize().then((_) {
      if (mounted) setState(() => _initialized = true);
      _ctrl.play();
    }).catchError((_) {
      if (mounted) setState(() => _error = true);
    });
    _ctrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(children: [
        if (_error)
          const Padding(padding: EdgeInsets.all(32),
            child: Text('Could not play video', style: TextStyle(color: Colors.white70)))
        else if (!_initialized)
          const SizedBox(
            width: double.infinity,
            height: 240,
            child: Center(child: CircularProgressIndicator(color: Colors.white)))
        else
          Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(
              aspectRatio: _ctrl.value.aspectRatio,
              child: VideoPlayer(_ctrl)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: Icon(
                  _ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 32),
                onPressed: () {
                  _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
                }),
              Text(
                '${_formatDur(_ctrl.value.position)} / ${_formatDur(_ctrl.value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ]),
        Positioned(top: 0, right: 0,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context))),
      ]),
    );
  }

  String _formatDur(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

// ── Chat title bar ────────────────────────────────────────────────────────────
class _ChatTitleBar extends StatelessWidget {
  final String title;
  final VeilThemeColors tc;
  final VoidCallback onBack;
  final VoidCallback? onTimer;
  final VoidCallback? onAddMember;
  const _ChatTitleBar({required this.title, required this.tc, required this.onBack,
      this.onTimer, this.onAddMember});

  @override
  Widget build(BuildContext context) {
    final isWide  = MediaQuery.of(context).size.width >= 700;
    final topPad  = MediaQuery.of(context).padding.top;
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd])),
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
        if (onAddMember != null)
          InkWell(onTap: onAddMember,
            child: Padding(padding: const EdgeInsets.all(8),
              child: Icon(Icons.person_add_outlined, color: tc.titleOnColor, size: 24))),
        if (onTimer != null)
          InkWell(onTap: onTimer,
            child: Padding(padding: const EdgeInsets.all(8),
              child: Icon(Icons.timer_outlined, color: tc.titleOnColor, size: 24))),
      ]),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
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
  Widget build(BuildContext context) => Tooltip(
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

// ── Disappearing message countdown ────────────────────────────────────────────
/// Shows a live countdown (⏱ Xs) for a message with a scheduled disappear timer.
/// Loads the remaining duration from [DisappearingMessageService] asynchronously,
/// then ticks down every second. Used inside message rows and image overlays.
class _DisappearingCountdown extends StatefulWidget {
  final String eventId;
  final Color color;
  const _DisappearingCountdown({required this.eventId, this.color = Colors.orange});

  @override
  State<_DisappearingCountdown> createState() => _DisappearingCountdownState();
}

class _DisappearingCountdownState extends State<_DisappearingCountdown> {
  Duration? _remaining;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final r = await DisappearingMessageService.instance.remaining(widget.eventId);
    if (!mounted) return;
    if (r == null) {
      // Timer not started yet — wait briefly for _doScheduleVisible to fire, then retry.
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final r2 = await DisappearingMessageService.instance.remaining(widget.eventId);
      if (!mounted || r2 == null) return;
      setState(() => _remaining = r2);
      _startTicker();
      return;
    }
    setState(() => _remaining = r);
    _startTicker();
  }

  void _startTicker() {
    final r = _remaining;
    if (r == null || r <= Duration.zero) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _ticker?.cancel(); return; }
      setState(() {
        final cur = _remaining;
        if (cur != null && cur.inSeconds > 0) {
          _remaining = cur - const Duration(seconds: 1);
        } else {
          _ticker?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.inSeconds <= 0) return '0s';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final r = _remaining;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(r == null ? Icons.timer_outlined : Icons.timer, size: 12, color: widget.color),
      const SizedBox(width: 3),
      Text(r == null ? '…' : _fmt(r),
          style: TextStyle(fontSize: 11, color: widget.color, fontWeight: FontWeight.w600)),
    ]);
  }
}

