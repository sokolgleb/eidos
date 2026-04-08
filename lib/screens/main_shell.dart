import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'feed_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';

class MainShell extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  const MainShell({super.key, this.onThemeChanged});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 1; // default to My Photos

  final _galleryKey = GlobalKey<GalleryScreenState>();
  final _accountKey = GlobalKey<AccountScreenState>();

  void _onTabTapped(int index) {
    if (index == 2) {
      // Center button: show picker sheet, not a tab
      _showPickerSheet();
      return;
    }
    setState(() => _currentIndex = index);
    if (index == 4) {
      _accountKey.currentState?.reload();
    }
  }

  void _showPickerSheet() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
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
                color: cs.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: cs.onSurface),
              title: Text('Take a photo', style: TextStyle(color: cs.onSurface)),
              onTap: () async {
                Navigator.pop(context);
                await _galleryKey.currentState?.pickAndEdit(ImageSource.camera);
                _accountKey.currentState?.reload();
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_outlined, color: cs.onSurface),
              title: Text('Choose from gallery', style: TextStyle(color: cs.onSurface)),
              onTap: () async {
                Navigator.pop(context);
                await _galleryKey.currentState?.pickAndEdit(ImageSource.gallery);
                _accountKey.currentState?.reload();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _onAuthChanged() async {
    _accountKey.currentState?.reload();
    // Gallery reload runs in background; refresh account count on each progress step
    await _galleryKey.currentState?.reload(
      onProgress: () => _accountKey.currentState?.reload(),
    );
    _accountKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex > 2 ? _currentIndex - 1 : _currentIndex,
        children: [
          const FeedScreen(),
          GalleryScreen(key: _galleryKey),
          SettingsScreen(onThemeChanged: widget.onThemeChanged),
          AccountScreen(key: _accountKey, onAuthChanged: _onAuthChanged),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}

// ─── Bottom nav ──────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore,
                index: 0,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.grid_view_outlined,
                activeIcon: Icons.grid_view,
                index: 1,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _AddButton(onTap: () => onTap(2)),
              _NavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                index: 3,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                index: 4,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          active ? activeIcon : icon,
          color: active ? cs.onSurface : cs.onSurface.withAlpha(100),
          size: 26,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: cs.onSurface.withAlpha(25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.add, color: cs.onSurface, size: 26),
      ),
    );
  }
}
