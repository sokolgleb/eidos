import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sighting.dart';
import '../services/sighting_storage.dart';
import '../services/cloud_service.dart';
import '../utils/route_transitions.dart';
import 'detail_screen.dart';
import 'editor_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  GalleryScreenState createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  List<Sighting> _sightings = [];
  bool _loading = true;
  final bool _syncing = false;

  double? _tileSize;
  double _baseTileSize = 0;

  // Multi-select
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadThenSync();
  }

  /// Public reload method — called from MainShell after auth change or adding a sighting.
  /// Public reload — called from MainShell after auth change or adding a sighting.
  Future<void> reload({VoidCallback? onProgress}) async {
    await _loadThenSync(onProgress: onProgress);
  }

  Future<void> _loadThenSync({VoidCallback? onProgress}) async {
    await _load();
    CloudService.syncProfile();
    final downloaded = await CloudService.downloadFromCloud(
      onProgress: () {
        if (mounted) _load();
        onProgress?.call();
      },
    );
    if (downloaded > 0) await _load();
    await _syncUnsynced();
    _reconcileWithRemote();
  }

  Future<void> _reconcileWithRemote() async {
    final remoteIds = await CloudService.fetchRemoteSightingIds();
    if (remoteIds == null || remoteIds.isEmpty) return;

    final orphaned = _sightings
        .where((s) =>
            s.syncStatus == SyncStatus.synced && !remoteIds.contains(s.id))
        .toList();

    if (orphaned.isEmpty) return;

    for (final s in orphaned) {
      await SightingStorage.delete(s.id);
    }
    if (mounted) await _load();
  }

  Future<void> _load() async {
    final list = await SightingStorage.loadAll();
    if (mounted) setState(() { _sightings = list; _loading = false; });
  }

  Future<void> _refresh() async {
    await CloudService.downloadFromCloud();
    await _load();
    _syncUnsynced();
  }

  Future<void> _syncUnsynced() async {
    await CloudService.ensureSignedIn();
    final unsynced = _sightings
        .where((s) =>
            s.syncStatus == SyncStatus.local ||
            s.syncStatus == SyncStatus.failed)
        .where((s) => s.originalPath.isNotEmpty)
        .toList();
    if (unsynced.isEmpty) return;

    if (mounted) {
      setState(() {
        for (final s in unsynced) {
          final i = _sightings.indexWhere((x) => x.id == s.id);
          if (i >= 0) _sightings[i] = s.copyWith(syncStatus: SyncStatus.uploading);
        }
      });
    }

    Future<void> uploadOne(Sighting sighting) async {
      final synced = await CloudService.uploadSighting(sighting)
          .timeout(const Duration(seconds: 90), onTimeout: () => null);
      if (mounted) {
        setState(() {
          final i = _sightings.indexWhere((s) => s.id == sighting.id);
          if (i >= 0) {
            _sightings[i] = synced ?? sighting.copyWith(syncStatus: SyncStatus.failed);
          }
        });
      }
      if (synced != null) await SightingStorage.save(synced);
    }

    for (int i = 0; i < unsynced.length; i += 2) {
      final batch = unsynced.skip(i).take(2).toList();
      await Future.wait(batch.map(uploadOne));
    }
  }

  /// Pick an image and open the editor. Called from MainShell.
  Future<void> pickAndEdit(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;
    if (!mounted) return;
    final result = await Navigator.push<Sighting>(
      context,
      fadeScaleRoute(EditorScreen(imagePath: file.path)),
    );
    if (result != null) {
      await _load();
      _syncUnsynced();
    }
  }

  void _openDetail(int index) {
    Navigator.push(
      context,
      fadeScaleRoute(DetailScreen(
        sightings: _sightings,
        initialIndex: index,
        onChanged: () => _load(),
      )),
    );
  }

  // ── Multi-select ───────────────────────────────────────────────────────────

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'sighting' : 'sightings'}?',
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
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final id in _selectedIds) {
      await SightingStorage.delete(id);
      CloudService.deleteSighting(id);
    }
    _exitSelectionMode();
    await _load();
  }

  Future<void> _batchShare() async {
    final files = _sightings
        .where((s) => _selectedIds.contains(s.id))
        .map((s) => XFile(s.annotatedPath))
        .toList();
    if (files.isEmpty) return;
    await Share.shareXFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 0) _tileSize ??= screenWidth / 3;
    final effectiveTileSize = (_tileSize != null && _tileSize! > 0)
        ? _tileSize!
        : (screenWidth > 0 ? screenWidth / 3 : 120.0);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _selectionMode
                  ? _SelectionToolbar(
                      count: _selectedIds.length,
                      onClose: _exitSelectionMode,
                      onDelete: _batchDelete,
                      onShare: _batchShare,
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'eidos',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w200,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
            ),
            if (_syncing)
              LinearProgressIndicator(
                color: cs.onSurface.withAlpha(60),
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: cs.onSurface.withAlpha(97)))
                  : _sightings.isEmpty
                      ? const _EmptyState()
                      : GestureDetector(
                          onScaleStart: (_) { _baseTileSize = _tileSize!; },
                          onScaleUpdate: (details) {
                            if (details.scale == 1.0) return;
                            final next = (_baseTileSize * details.scale)
                                .clamp(screenWidth / 5, screenWidth);
                            if ((next - _tileSize!).abs() > 0.5) {
                              setState(() => _tileSize = next);
                            }
                          },
                          child: RefreshIndicator(
                            onRefresh: _refresh,
                            color: cs.onSurface,
                            backgroundColor: cs.surfaceContainerHigh,
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: effectiveTileSize,
                                crossAxisSpacing: 0,
                                mainAxisSpacing: 0,
                                childAspectRatio: 1,
                              ),
                              itemCount: _sightings.length,
                              itemBuilder: (context, i) {
                                final s = _sightings[i];
                                final selected = _selectedIds.contains(s.id);
                                return _SightingTile(
                                  sighting: s,
                                  selected: selected,
                                  selectionMode: _selectionMode,
                                  onTap: () {
                                    if (_selectionMode) {
                                      _toggleSelection(s.id);
                                    } else {
                                      _openDetail(i);
                                    }
                                  },
                                  onLongPress: () {
                                    if (!_selectionMode) {
                                      _enterSelectionMode(s.id);
                                    }
                                  },
                                );
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

// ─── Selection toolbar ───────────────────────────────────────────────────────

class _SelectionToolbar extends StatelessWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  const _SelectionToolbar({
    required this.count,
    required this.onClose,
    required this.onDelete,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        GestureDetector(
          onTap: onClose,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.close, color: cs.onSurface, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$count selected',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w300,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onShare,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.ios_share_outlined, color: cs.onSurface, size: 22),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDelete,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
          ),
        ),
      ],
    );
  }
}

// ─── Tile ─────────────────────────────────────────────────────────────────────

class _SightingTile extends StatefulWidget {
  final Sighting sighting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;

  const _SightingTile({
    required this.sighting,
    required this.onTap,
    required this.onLongPress,
    required this.selected,
    required this.selectionMode,
  });

  @override
  State<_SightingTile> createState() => _SightingTileState();
}

class _SightingTileState extends State<_SightingTile> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.onSurface.withAlpha(30), width: 0.5),
      ),
      child: ClipRect(
        child: GestureDetector(
          onLongPress: widget.selectionMode ? null : widget.onLongPress,
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: widget.sighting.thumbnailProvider,
                key: ValueKey(widget.sighting.id),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return Container(
                    color: cs.onSurface.withAlpha(10),
                    child: Center(
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: cs.onSurface.withAlpha(60),
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  color: cs.onSurface.withAlpha(10),
                  child: Icon(Icons.broken_image_outlined,
                      color: cs.onSurface.withAlpha(40), size: 24),
                ),
              ),
              // Sync status badge (stays hardcoded — overlaid on photo)
              if (widget.sighting.syncStatus != SyncStatus.synced)
                Positioned(
                  bottom: 6, right: 6,
                  child: widget.sighting.syncStatus == SyncStatus.uploading
                      ? const SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white70,
                          ),
                        )
                      : Icon(
                          widget.sighting.syncStatus == SyncStatus.failed
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_upload_outlined,
                          color: Colors.white.withAlpha(160),
                          size: 14,
                        ),
                ),
              // Selection indicator (stays hardcoded — overlaid on photo)
              if (widget.selectionMode)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected
                          ? Colors.white
                          : Colors.black.withAlpha(100),
                      border: Border.all(
                        color: Colors.white.withAlpha(widget.selected ? 255 : 120),
                        width: 2,
                      ),
                    ),
                    child: widget.selected
                        ? const Icon(Icons.check, color: Colors.black, size: 16)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing yet',
            style: TextStyle(
              color: cs.onSurface.withAlpha(100),
              fontSize: 18,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Photograph something and\nreveal what you see',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface.withAlpha(60),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
