import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sighting.dart';
import '../services/sighting_storage.dart';
import '../services/cloud_service.dart';
import '../services/settings_service.dart';
import '../utils/app_theme.dart';
import '../utils/route_transitions.dart';
import 'editor_screen.dart';

// Persists the locked-original mode across navigation
bool _globalLockedOriginal = false;

class DetailScreen extends StatefulWidget {
  final List<Sighting> sightings;
  final int initialIndex;
  /// Called when a sighting is deleted or modified, so the caller can reload.
  final VoidCallback? onChanged;

  const DetailScreen({
    super.key,
    required this.sightings,
    required this.initialIndex,
    this.onChanged,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<Sighting> _sightings;

  bool _pressing = false;
  bool _lockedOriginal = _globalLockedOriginal;

  final Map<String, int> _versions = {};

  Sighting get _current => _sightings[_currentIndex];

  @override
  void initState() {
    super.initState();
    _sightings = List.of(widget.sightings);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadDefaultViewMode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precache(_currentIndex));
  }

  Future<void> _loadDefaultViewMode() async {
    final showOriginal = await SettingsService.getDefaultShowOriginal();
    if (mounted && showOriginal != _lockedOriginal) {
      setState(() {
        _lockedOriginal = showOriginal;
        _globalLockedOriginal = showOriginal;
      });
    }
  }

  void _precache(int center) {
    for (int offset = -2; offset <= 2; offset++) {
      final i = center + offset;
      if (i >= 0 && i < _sightings.length && mounted) {
        final s = _sightings[i];
        if (s.originalPath.isNotEmpty && File(s.originalPath).existsSync()) {
          precacheImage(FileImage(File(s.originalPath)), context);
        }
      }
    }
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
    _precache(i);
  }

  Future<void> _toggleFavorite() async {
    final s = _current;
    final updated = s.copyWith(isFavorite: !s.isFavorite);
    setState(() => _sightings[_currentIndex] = updated);
    await SightingStorage.save(updated);
    CloudService.updateSightingFields(s.id, isFavorite: updated.isFavorite);
    widget.onChanged?.call();
  }

  Future<void> _togglePublic() async {
    final s = _current;
    final updated = s.copyWith(isPublic: !s.isPublic);
    setState(() => _sightings[_currentIndex] = updated);
    await SightingStorage.save(updated);
    CloudService.updateSightingFields(s.id, isPublic: updated.isPublic);
    widget.onChanged?.call();
  }

  Future<void> _openEditor() async {
    final sighting = _current;
    final result = await Navigator.push<Sighting>(
      context,
      fadeScaleRoute(EditorScreen(
        imagePath: sighting.annotatedPath,
        sightingToUpdate: sighting,
      )),
    );
    if (result != null && mounted) {
      PaintingBinding.instance.imageCache
          .evict(FileImage(File(sighting.annotatedPath)));
      setState(() {
        _versions[sighting.id] = (_versions[sighting.id] ?? 0) + 1;
      });
      widget.onChanged?.call();
    }
  }

  Future<void> _share() async {
    await Share.shareXFiles([XFile(_current.annotatedPath)]);
  }

  Future<void> _deleteSighting() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text('Delete sighting?',
              style: TextStyle(color: cs.onSurface)),
          content: Text('This cannot be undone.',
              style: TextStyle(color: cs.onSurface.withAlpha(180))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: TextStyle(color: cs.onSurface.withAlpha(140))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final sighting = _current;
    await SightingStorage.delete(sighting.id);
    CloudService.deleteSighting(sighting.id);
    widget.onChanged?.call();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = _current;
    final isOwn = s.originalPath.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 500) {
            Navigator.pop(context);
          }
        },
        child: Stack(
          children: [
            // Images + tap gestures
            GestureDetector(
              onLongPressStart:  (_) => setState(() => _pressing = true),
              onLongPressEnd:    (_) => setState(() => _pressing = false),
              onLongPressCancel: ()  => setState(() => _pressing = false),
              onDoubleTap: () => setState(() {
                _lockedOriginal = !_lockedOriginal;
                _globalLockedOriginal = _lockedOriginal;
              }),
              child: PageView.builder(
                controller: _pageController,
                itemCount: _sightings.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, i) => _DetailPage(
                  key: ValueKey(_sightings[i].id),
                  sighting: _sightings[i],
                  showOriginal: _lockedOriginal
                      ? (i == _currentIndex ? !_pressing : true)
                      : (i == _currentIndex ? _pressing : false),
                  version: _versions[_sightings[i].id] ?? 0,
                ),
              ),
            ),

            // Top gradient
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

            // Bottom gradient
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

            // Top bar: back button
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FlatIconButton(
                      icon: Icons.arrow_back,
                      color: Colors.white,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom bar: flat icon buttons
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FlatIconButton(
                        icon: s.isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: s.isFavorite ? Colors.redAccent : Colors.white,
                        onTap: _toggleFavorite,
                      ),
                      FlatIconButton(
                        icon: s.isPublic ? Icons.public : Icons.public_off,
                        color: s.isPublic ? Colors.white : Colors.white54,
                        onTap: _togglePublic,
                      ),
                      FlatIconButton(
                        icon: Icons.ios_share_outlined,
                        color: Colors.white,
                        onTap: _share,
                      ),
                      if (isOwn) ...[
                        FlatIconButton(
                          icon: Icons.edit_outlined,
                          color: Colors.white,
                          onTap: _openEditor,
                        ),
                        FlatIconButton(
                          icon: Icons.delete_outline,
                          color: Colors.white54,
                          onTap: _deleteSighting,
                        ),
                      ],
                    ],
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

// Single page: both images stacked with crossfade
class _DetailPage extends StatelessWidget {
  final Sighting sighting;
  final bool showOriginal;
  final int version;

  const _DetailPage({
    required super.key,
    required this.sighting,
    required this.showOriginal,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildImage(sighting.originalProvider, 'orig-${sighting.id}'),
        ),
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: showOriginal ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _buildImage(
              sighting.annotatedProvider,
              'ann-${sighting.id}-$version',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(ImageProvider provider, String keyStr) {
    return Image(
      key: ValueKey(keyStr),
      image: provider,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
