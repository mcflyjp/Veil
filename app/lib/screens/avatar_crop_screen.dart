import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Interactive profile-picture positioner. Shows the picked image full-size
// behind a fixed circular window the user pans (drag) and zooms (pinch or
// the slider) — the user decides what ends up inside the circle rather than
// the app auto-centering or auto-cropping. "Use Photo" captures exactly
// what's visible in the circle via RenderRepaintBoundary and pops it back
// as PNG bytes for the caller to upload (see ClientManager.setAvatar).
class AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const AvatarCropScreen({super.key, required this.imageBytes});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const double _viewport = 300;
  static const double _outputSize = 512;

  final _boundaryKey = GlobalKey();
  ui.Image? _decoded;
  double _scale = 1;
  double _minScale = 1;
  Offset _offset = Offset.zero;

  // Gesture tracking — captured at onScaleStart, applied as deltas in onScaleUpdate.
  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    // Minimum zoom = the image's shorter side exactly fills the viewport, so
    // the circle can never show empty space no matter how far the user zooms out.
    final shorter = (img.width < img.height ? img.width : img.height).toDouble();
    final minScale = _viewport / shorter;
    if (!mounted) return;
    setState(() {
      _decoded = img;
      _minScale = minScale;
      _scale = minScale;
      _offset = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startFocalPoint = d.focalPoint;
    _startOffset = _offset;
    _startScale = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final img = _decoded;
    if (img == null) return;
    final nextScale = (_startScale * d.scale).clamp(_minScale, _minScale * 4);
    setState(() {
      _scale = nextScale;
      _offset = _clampOffset(_startOffset + (d.focalPoint - _startFocalPoint), _scale, img);
    });
  }

  void _onZoomSlider(double v) {
    final img = _decoded;
    if (img == null) return;
    setState(() {
      _scale = v;
      _offset = _clampOffset(_offset, _scale, img);
    });
  }

  /// Keeps the scaled image covering the whole viewport at every pan
  /// position — the circle can never show empty space at its edges.
  Offset _clampOffset(Offset offset, double scale, ui.Image img) {
    final w = img.width * scale;
    final h = img.height * scale;
    final maxDx = ((w - _viewport) / 2).clamp(0.0, double.infinity);
    final maxDy = ((h - _viewport) / 2).clamp(0.0, double.infinity);
    return Offset(offset.dx.clamp(-maxDx, maxDx), offset.dy.clamp(-maxDy, maxDy));
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: _outputSize / _viewport);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      Navigator.pop(context, byteData.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Same transform state, reused for both the dimmed backdrop and the crisp
  // circular window so they always move together as one image.
  Widget _transformedImage(ui.Image img) => OverflowBox(
    minWidth: 0, minHeight: 0, maxWidth: double.infinity, maxHeight: double.infinity,
    child: Transform.translate(
      offset: _offset,
      child: Transform.scale(
        scale: _scale,
        child: RawImage(image: img, width: img.width.toDouble(), height: img.height.toDouble()),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final img = _decoded;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Position Photo'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: img == null || _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Use Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: img == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(children: [
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: SizedBox(
                      width: _viewport, height: _viewport,
                      child: Stack(alignment: Alignment.center, children: [
                        // Dimmed full-frame backdrop — shows what's just outside the circle.
                        ClipRect(
                          child: SizedBox(width: _viewport, height: _viewport,
                              child: Opacity(opacity: 0.35, child: _transformedImage(img))),
                        ),
                        // Crisp circular window — this exact region gets captured on confirm.
                        RepaintBoundary(
                          key: _boundaryKey,
                          child: ClipOval(
                            child: SizedBox(width: _viewport, height: _viewport,
                                child: _transformedImage(img)),
                          ),
                        ),
                        IgnorePointer(
                          child: Container(
                            width: _viewport, height: _viewport,
                            decoration: BoxDecoration(shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                child: Row(children: [
                  const Icon(Icons.zoom_out, color: Colors.white54, size: 18),
                  Expanded(
                    child: Slider(
                      value: _scale, min: _minScale, max: _minScale * 4,
                      onChanged: _onZoomSlider,
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white54, size: 18),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text('Drag to reposition, pinch or use the slider to zoom',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ]),
    );
  }
}
