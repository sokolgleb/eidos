import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:uuid/uuid.dart';
import '../models/sighting.dart';
import '../models/stroke.dart';
import '../services/sighting_storage.dart';
import '../services/cloud_service.dart';
import '../widgets/drawing_canvas.dart';

class EditorScreen extends StatefulWidget {
  final String imagePath;
  /// If set, we're editing an existing sighting — overwrites its annotated file.
  final Sighting? sightingToUpdate;

  const EditorScreen({
    super.key,
    required this.imagePath,
    this.sightingToUpdate,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  List<Stroke> _strokes = [];
  Stroke? _currentStroke;
  bool _saving = false;

  // Zoom & mode
  final _transformController = TransformationController();
  bool _isDrawMode = true;
  Matrix4? _scaleStartMatrix; // captured when pinch starts
  double _scaleAtPinchStart = 1.0; // d.scale value when we detected 2 fingers

  // Brush
  Color _brushColor = Colors.white;
  double _brushSize = 8.0;
  bool _showBrushSettings = false;

  final _repaintKey = GlobalKey();

  // Image size for draw-boundary clamping
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
    }
  }

  // Returns the image rect (in scene/canvas coords) using BoxFit.contain logic.
  Rect? _imageRect() {
    if (_imageSize == null) return null;
    final ctx = _repaintKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final container = box.size;

    final imgAspect = _imageSize!.width / _imageSize!.height;
    final ctnAspect = container.width / container.height;
    double w, h, x, y;
    if (imgAspect > ctnAspect) {
      w = container.width;
      h = container.width / imgAspect;
      x = 0;
      y = (container.height - h) / 2;
    } else {
      h = container.height;
      w = container.height * imgAspect;
      x = (container.width - w) / 2;
      y = 0;
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────
  // onScale* handles both drawing (1 finger) and pinch-to-zoom (2 fingers).
  // In navigate mode, InteractiveViewer takes over (no GestureDetector overlay).

  Offset? _clampToImage(Offset scenePt) {
    final rect = _imageRect();
    if (rect == null) return scenePt;
    if (!rect.contains(scenePt)) return null;
    return scenePt;
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount == 1) {
      final pt = _clampToImage(_transformController.toScene(d.localFocalPoint));
      if (pt == null) return;
      setState(() {
        _currentStroke = Stroke(
          points: [pt],
          color: _brushColor,
          size: _brushSize,
          thinning: 1.0,
          smoothing: 1.0,
        );
      });
    } else {
      // Started directly with 2 fingers
      _scaleStartMatrix = _transformController.value.clone();
      _scaleAtPinchStart = 1.0;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      // Discard any in-progress stroke — don't commit it
      if (_currentStroke != null) {
        setState(() => _currentStroke = null);
      }
      // Lazily init pinch baseline when transitioning from 1→2 fingers
      if (_scaleStartMatrix == null) {
        _scaleStartMatrix = _transformController.value.clone();
        _scaleAtPinchStart = d.scale;
        return;
      }
      // Zoom around focal point; d.scale is cumulative from gesture start,
      // so use it relative to _scaleAtPinchStart.
      final relativeScale = d.scale / _scaleAtPinchStart;
      final focal = d.localFocalPoint;
      final baseScale = _scaleStartMatrix!.getMaxScaleOnAxis();
      final newScale = (baseScale * relativeScale).clamp(0.8, 6.0);
      final s = newScale / baseScale;
      final m = Matrix4.identity()
        ..translate(focal.dx, focal.dy)
        ..scale(s)
        ..translate(-focal.dx, -focal.dy)
        ..multiply(_scaleStartMatrix!);
      setState(() => _transformController.value = m);
    } else if (d.pointerCount == 1 && _currentStroke != null) {
      final raw = _transformController.toScene(d.localFocalPoint);
      final rect = _imageRect();
      final pt = rect != null
          ? Offset(raw.dx.clamp(rect.left, rect.right),
                   raw.dy.clamp(rect.top, rect.bottom))
          : raw;
      setState(() {
        _currentStroke = _currentStroke!.copyWith(
          points: [..._currentStroke!.points, pt],
        );
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // Only commit the stroke if it ended as a 1-finger gesture.
    // 2-finger gestures already cleared _currentStroke in onScaleUpdate.
    if (_currentStroke != null) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
      });
    }
    _scaleStartMatrix = null;
    _scaleAtPinchStart = 1.0;
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes = _strokes.sublist(0, _strokes.length - 1));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    // Reset zoom before capture
    _transformController.value = Matrix4.identity();
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      if (widget.sightingToUpdate != null) {
        // ── Edit mode: overwrite annotated file, no new DB entry ──
        final annotatedFile = File(widget.sightingToUpdate!.annotatedPath);
        await annotatedFile.writeAsBytes(pngBytes);
        // Evict from Flutter image cache so the updated file loads from disk
        PaintingBinding.instance.imageCache.evict(FileImage(annotatedFile));
        if (mounted) Navigator.pop(context, widget.sightingToUpdate);
      } else {
        // ── Create mode: new sighting ──
        final id = const Uuid().v4();
        final dir = await SightingStorage.sightingDir(id);

        final originalPath = '$dir/original.jpg';
        await File(widget.imagePath).copy(originalPath);

        final annotatedPath = '$dir/annotated.png';
        await File(annotatedPath).writeAsBytes(pngBytes);

        final sighting = Sighting(
          id: id,
          createdAt: DateTime.now().toUtc(),
          originalPath: originalPath,
          annotatedPath: annotatedPath,
          syncStatus: SyncStatus.local,
        );
        await SightingStorage.save(sighting);
        if (mounted) Navigator.pop(context, sighting);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Photo + canvas inside InteractiveViewer ──
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformController,
              panEnabled: !_isDrawMode,
              scaleEnabled: !_isDrawMode, // in draw mode we handle scale manually
              minScale: 0.8,
              maxScale: 6.0,
              boundaryMargin: const EdgeInsets.all(80),
              child: RepaintBoundary(
                key: _repaintKey,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image(
                        image: _imageProvider(),
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned.fill(
                      child: DrawingCanvas(
                        strokes: _strokes,
                        currentStroke: _currentStroke,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Drawing + zoom gesture (draw mode only) ──
          // 1 finger = draw, 2 fingers = pinch-to-zoom (manual matrix update).
          // Taps on UI buttons go to the buttons, not here (translucent).
          if (_isDrawMode)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
              ),
            ),

          // ── Top bar ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _IconBtn(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    _IconBtn(
                      icon: _isDrawMode ? Icons.edit_outlined : Icons.pan_tool_outlined,
                      active: true,
                      tooltip: _isDrawMode ? 'Draw mode' : 'Navigate mode',
                      onTap: () => setState(() => _isDrawMode = !_isDrawMode),
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.undo,
                      onTap: _strokes.isEmpty ? null : _undo,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Brush settings panel ──
          if (_showBrushSettings)
            Positioned(
              bottom: 80, left: 16, right: 16,
              child: _BrushSettingsPanel(
                color: _brushColor,
                size: _brushSize,
                onColorChanged: (c) => setState(() => _brushColor = c),
                onSizeChanged: (v) => setState(() => _brushSize = v),
              ),
            ),

          // ── Bottom bar ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: _showBrushSettings
                    // ── Brush settings open: single OK button centred ──
                    ? Center(
                        child: GestureDetector(
                          onTap: () => setState(() => _showBrushSettings = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(25),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )
                    // ── Normal: brush button + save/spinner ──
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _IconBtn(
                            icon: Icons.brush,
                            active: _showBrushSettings,
                            iconColor: _brushColor,
                            onTap: () => setState(
                                () => _showBrushSettings = !_showBrushSettings),
                          ),
                          _saving
                              ? const SizedBox(
                                  width: 44, height: 44,
                                  child: Center(
                                    child: SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    ),
                                  ),
                                )
                              : _IconBtn(icon: Icons.check, onTap: _save),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider _imageProvider() {
    if (widget.imagePath.startsWith('http')) return NetworkImage(widget.imagePath);
    return FileImage(File(widget.imagePath));
  }
}

// ─── Palette ────────────────────────────────────────────────────────────────

List<Color> _buildPalette() {
  final colors = <Color>[
    Colors.white,
    const Color(0xFFDDDDDD),
    const Color(0xFF999999),
    const Color(0xFF555555),
    Colors.black,
  ];

  // 12 hues × 5 shades = 60 colors
  // Ordered as [pale, light, vivid, dark, very_dark] per hue
  // → GridView crossAxisCount=5 shows each hue in one column
  const hues = [0.0, 20.0, 40.0, 60.0, 100.0, 150.0, 180.0, 200.0, 240.0, 270.0, 300.0, 330.0];
  for (final h in hues) {
    colors.add(HSVColor.fromAHSV(1, h, 0.25, 1.00).toColor());
    colors.add(HSVColor.fromAHSV(1, h, 0.55, 1.00).toColor());
    colors.add(HSVColor.fromAHSV(1, h, 1.00, 1.00).toColor());
    colors.add(HSVColor.fromAHSV(1, h, 1.00, 0.65).toColor());
    colors.add(HSVColor.fromAHSV(1, h, 1.00, 0.35).toColor());
  }

  return colors;
}

// ─── Brush settings panel ───────────────────────────────────────────────────

class _BrushSettingsPanel extends StatelessWidget {
  final Color color;
  final double size;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onSizeChanged;

  const _BrushSettingsPanel({
    required this.color,
    required this.size,
    required this.onColorChanged,
    required this.onSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _buildPalette();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(210),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color row: single horizontal scrollable row
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: palette.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = palette[i];
                final selected = c.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => onColorChanged(c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(color: Colors.white12, width: 0.5),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),
          _Slider(label: 'Size', value: size, min: 1.0, max: 25.0,
              onChanged: onSizeChanged),
        ],
      ),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final String? tooltip;
  final Color? iconColor;

  const _IconBtn({required this.icon, this.onTap, this.active = false, this.tooltip, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withAlpha(60)
              : Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: onTap == null
              ? Colors.white.withAlpha(60)
              : (iconColor ?? Colors.white),
          size: 22,
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.label, required this.value,
    required this.min, required this.max, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min, max: max,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
