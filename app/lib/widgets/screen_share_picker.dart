// Source picker shown before a screen share starts on desktop.
//
// Lists every screen and open window (with live-ish thumbnails from
// flutter_webrtc's desktopCapturer), lets the user choose motion-vs-detail
// quality and whether to include audio, and returns their choice for
// CallService.startScreenShare. Not used on web — the browser shows its own
// picker there.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/call_service.dart';
import '../core/veil_theme.dart';

class ScreenShareChoice {
  final String sourceId;
  final ScreenShareQuality quality;
  final bool audio;
  const ScreenShareChoice(this.sourceId, this.quality, this.audio);
}

Future<ScreenShareChoice?> showScreenSharePicker(
  BuildContext context,
  VeilThemeColors tc,
) {
  return showDialog<ScreenShareChoice>(
    context: context,
    builder: (_) => _ScreenSharePicker(tc: tc),
  );
}

class _ScreenSharePicker extends StatefulWidget {
  final VeilThemeColors tc;
  const _ScreenSharePicker({required this.tc});

  @override
  State<_ScreenSharePicker> createState() => _ScreenSharePickerState();
}

class _ScreenSharePickerState extends State<_ScreenSharePicker> {
  List<DesktopCapturerSource> _sources = [];
  DesktopCapturerSource? _selected;
  bool _loading = true;
  String? _error;
  SourceType _tab = SourceType.Screen;
  ScreenShareQuality _quality = ScreenShareQuality.motion;
  bool _audio = true;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // Thumbnails go stale; re-list every few seconds while the dialog is open.
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(320, 180),
      );
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _loading = false;
        // Keep the selection across refreshes (matched by id).
        if (_selected != null) {
          final still = sources.where((s) => s.id == _selected!.id);
          _selected = still.isEmpty ? null : still.first;
        }
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = "Couldn't list screens: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = widget.tc;
    final visible = _sources.where((s) => s.type == _tab).toList();
    return Dialog(
      backgroundColor: tc.scaffold,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share your screen',
                  style: TextStyle(
                      color: tc.nameText, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SegmentedButton<SourceType>(
                segments: const [
                  ButtonSegment(value: SourceType.Screen, label: Text('Screens')),
                  ButtonSegment(value: SourceType.Window, label: Text('Windows')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() {
                  _tab = v.first;
                  _selected = null;
                }),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!, style: TextStyle(color: tc.nameText)))
                        : visible.isEmpty
                            ? Center(
                                child: Text('Nothing to share here',
                                    style: TextStyle(color: tc.previewText)))
                            : GridView.builder(
                                shrinkWrap: true,
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
                                  childAspectRatio: 1.35,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: visible.length,
                                itemBuilder: (_, i) => _tile(visible[i], tc),
                              ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<ScreenShareQuality>(
                    segments: const [
                      ButtonSegment(
                        value: ScreenShareQuality.motion,
                        label: Text('Smooth (games, video)'),
                      ),
                      ButtonSegment(
                        value: ScreenShareQuality.detail,
                        label: Text('Sharp (text, slides)'),
                      ),
                    ],
                    selected: {_quality},
                    onSelectionChanged: (v) => setState(() => _quality = v.first),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                        value: _audio,
                        onChanged: (v) => setState(() => _audio = v ?? true)),
                    Text('Share audio', style: TextStyle(color: tc.nameText)),
                  ]),
                ],
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(
                          ScreenShareChoice(_selected!.id, _quality, _audio)),
                  child: const Text('Share'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(DesktopCapturerSource s, VeilThemeColors tc) {
    final selected = _selected?.id == s.id;
    return InkWell(
      onTap: () => setState(() => _selected = s),
      onDoubleTap: () => Navigator.of(context)
          .pop(ScreenShareChoice(s.id, _quality, _audio)),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: tc.inputBg,
          border: Border.all(
              color: selected ? tc.badgeBg : tc.divider, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Expanded(
            child: s.thumbnail == null
                ? const SizedBox.expand()
                : Image.memory(s.thumbnail!,
                    fit: BoxFit.contain, gaplessPlayback: true),
          ),
          const SizedBox(height: 4),
          Text(s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tc.nameText, fontSize: 12)),
        ]),
      ),
    );
  }
}
