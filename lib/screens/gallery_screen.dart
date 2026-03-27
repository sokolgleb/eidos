import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import '../models/sighting.dart';
import '../services/sighting_storage.dart';
import 'editor_screen.dart';

// Persists the locked-original mode across navigation
bool _globalLockedOriginal = false;

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<Sighting> _sightings = [];
  bool _loading = true;

  // Smooth pinch-to-zoom: tile size in logical pixels
  double? _tileSize;      // null until first build (initialized from screen width)
  double _baseTileSize = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await SightingStorage.loadAll();
    if (mounted) setState(() { _sightings = list; _loading = false; });
  }

  Future<void> _pickAndEdit(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    if (!mounted) return;
    final result = await Navigator.push<Sighting>(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(imagePath: file.path)),
    );
    if (result != null) _load();
  }

  void _openDetail(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetailScreen(
          sightings: _sightings,
          initialIndex: index,
        ),
      ),
    );
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickAndEdit(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Colors.white),
              title: const Text('Choose from gallery', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _pickAndEdit(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 0) _tileSize ??= screenWidth / 3;
    final effectiveTileSize = (_tileSize != null && _tileSize! > 0)
        ? _tileSize!
        : (screenWidth > 0 ? screenWidth / 3 : 120.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Text(
                    'eidos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showPickerSheet,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withAlpha(60)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ),

            // ── Grid ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white38))
                  : _sightings.isEmpty
                      ? _EmptyState(onAdd: _showPickerSheet)
                      : GestureDetector(
                          onScaleStart: (_) {
                            _baseTileSize = _tileSize!;
                          },
                          onScaleUpdate: (details) {
                            if (details.scale == 1.0) return;
                            final next = (_baseTileSize * details.scale)
                                .clamp(screenWidth / 5, screenWidth);
                            if ((next - _tileSize!).abs() > 0.5) {
                              setState(() => _tileSize = next);
                            }
                          },
                          child: GridView.builder(
                            padding: EdgeInsets.zero,
                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: effectiveTileSize,
                              crossAxisSpacing: 0,
                              mainAxisSpacing: 0,
                              childAspectRatio: 1,
                            ),
                            itemCount: _sightings.length,
                            itemBuilder: (context, i) => _SightingTile(
                              sighting: _sightings[i],
                              onTap: () => _openDetail(i),
                              onDelete: () async {
                                await SightingStorage.delete(_sightings[i].id);
                                _load();
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tile ────────────────────────────────────────────────────────────────────

class _SightingTile extends StatefulWidget {
  final Sighting sighting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SightingTile({
    required this.sighting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SightingTile> createState() => _SightingTileState();
}

class _SightingTileState extends State<_SightingTile> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final path = _showOriginal
        ? widget.sighting.originalPath
        : widget.sighting.annotatedPath;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withAlpha(30), width: 0.5),
      ),
      child: ClipRect(
        child: GestureDetector(
          onLongPressStart: (_) => setState(() => _showOriginal = true),
          onLongPressEnd: (_) => setState(() => _showOriginal = false),
          onLongPressCancel: () => setState(() => _showOriginal = false),
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(path),
                key: ValueKey(path),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
              if (_showOriginal)
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('original',
                        style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Detail screen ────────────────────────────────────────────────────────────
// Buttons live here (fixed overlay). PageView only scrolls images.

class _DetailScreen extends StatefulWidget {
  final List<Sighting> sightings;
  final int initialIndex;

  const _DetailScreen({
    required this.sightings,
    required this.initialIndex,
  });

  @override
  State<_DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<_DetailScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  // Hold-to-reveal state
  bool _pressing = false;
  bool _lockedOriginal = _globalLockedOriginal; // persisted across navigation

  // Per-sighting version counter for cache busting after edit
  final Map<String, int> _versions = {};

  bool get _showingOriginal => _lockedOriginal ? !_pressing : _pressing;

  Sighting get _current => widget.sightings[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() {
      _currentIndex = i;
      _pressing = false;
    });
  }

  Future<void> _openEditor() async {
    final sighting = _current;
    final result = await Navigator.push<Sighting>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          imagePath: sighting.annotatedPath,
          sightingToUpdate: sighting,
        ),
      ),
    );
    if (result != null && mounted) {
      PaintingBinding.instance.imageCache
          .evict(FileImage(File(sighting.annotatedPath)));
      setState(() {
        _versions[sighting.id] = (_versions[sighting.id] ?? 0) + 1;
      });
    }
  }

  Future<void> _saveToGallery() async {
    try {
      await Gal.putImage(_current.annotatedPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.white24,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _share() async {
    await Share.shareXFiles([XFile(_current.annotatedPath)]);
  }

  @override
  Widget build(BuildContext context) {
    final sighting = _current;

    // Button label for hold-to-reveal
    String revealLabel;
    if (_lockedOriginal) {
      revealLabel = _pressing ? 'annotated' : 'original ●';
    } else {
      revealLabel = _pressing ? 'original' : 'hold to reveal';
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── PageView: only images scroll ──
          PageView.builder(
            controller: _pageController,
            itemCount: widget.sightings.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, i) => _DetailPage(
              sighting: widget.sightings[i],
              showOriginal: _lockedOriginal
                  ? (i == _currentIndex ? !_pressing : true)
                  : (i == _currentIndex ? _pressing : false),
              version: _versions[widget.sightings[i].id] ?? 0,
            ),
          ),

          // ── Top gradient ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom gradient ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar (fixed) ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    if (widget.sightings.length > 1)
                      Text(
                        '${_currentIndex + 1} / ${widget.sightings.length}',
                        style: TextStyle(
                          color: Colors.white.withAlpha(150),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom bar (fixed) ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: edit / save / share
                    Row(
                      children: [
                        _IconBtn(icon: Icons.edit_outlined, onTap: _openEditor),
                        const SizedBox(width: 8),
                        _IconBtn(icon: Icons.download_outlined, onTap: _saveToGallery),
                        const SizedBox(width: 8),
                        _IconBtn(icon: Icons.ios_share_outlined, onTap: _share),
                      ],
                    ),

                    // Right: hold-to-reveal / double-tap to lock
                    GestureDetector(
                      onDoubleTap: () => setState(() {
                        _lockedOriginal = !_lockedOriginal;
                        _globalLockedOriginal = _lockedOriginal;
                      }),
                      onTapDown: (_) => setState(() => _pressing = true),
                      onTapUp: (_) => setState(() => _pressing = false),
                      onTapCancel: () {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _pressing = false);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: _lockedOriginal
                              ? Colors.white.withAlpha(50)
                              : Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _lockedOriginal
                                ? Colors.white.withAlpha(140)
                                : Colors.white.withAlpha(80),
                          ),
                        ),
                        child: Text(
                          revealLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single page: only images, no controls ───────────────────────────────────

class _DetailPage extends StatelessWidget {
  final Sighting sighting;
  final bool showOriginal;
  final int version;

  const _DetailPage({
    required this.sighting,
    required this.showOriginal,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            File(sighting.originalPath),
            key: ValueKey('orig-${sighting.id}'),
            fit: BoxFit.contain,
          ),
        ),
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: showOriginal ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Image.file(
              File(sighting.annotatedPath),
              key: ValueKey('ann-${sighting.id}-$version'),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared icon button ───────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing yet',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 18,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Photograph something and\nreveal what you see',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withAlpha(60),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withAlpha(60)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Create first sighting',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
