import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/device_info_service.dart';
import '../services/sighting_storage.dart';

class AccountScreen extends StatefulWidget {
  /// Called after sign-in/sign-out so the shell can react (e.g. reload gallery).
  final VoidCallback? onAuthChanged;

  const AccountScreen({super.key, this.onAuthChanged});

  @override
  AccountScreenState createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  /// Reload info (sighting count, etc.) — called from MainShell.
  void reload() => _loadInfo();

  int _sightingCount = 0;
  bool _loading = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final list = await SightingStorage.loadAll();
    final version = await DeviceInfoService.getAppVersion();
    if (mounted) {
      setState(() {
        _sightingCount = list.length;
        _appVersion = version;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final success = await AuthService.signInWithGoogle();
      if (mounted && success) {
        widget.onAuthChanged?.call();
        _loadInfo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: $e'),
            backgroundColor: Colors.red[900],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _loading = true);
    try {
      await AuthService.signOut();
      if (mounted) {
        widget.onAuthChanged?.call();
        _loadInfo();
        setState(() {}); // rebuild in place
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete account?',
            style: TextStyle(color: cs.onSurface)),
        content: Text(
          'This will clear all local data and sign you out. '
          'Your cloud data may be retained for a period.',
          style: TextStyle(color: cs.onSurface.withAlpha(180)),
        ),
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
    setState(() => _loading = true);
    try {
      await AuthService.deleteAccount();
      if (mounted) {
        widget.onAuthChanged?.call();
        _loadInfo();
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = AuthService.isAnonymous;
    final name = AuthService.displayName;
    final avatar = AuthService.avatarUrl;
    final email = AuthService.currentUser?.email;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Text(
              'Profile',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w200,
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 32),

            // Avatar
            Center(
              child: _Avatar(avatarUrl: avatar, displayName: name, isAnon: isAnon),
            ),

            const SizedBox(height: 16),

            // Display name
            Center(
              child: Text(
                isAnon ? 'Anonymous' : (name ?? 'Signed in'),
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Email
            Center(
              child: Text(
                isAnon ? 'No account' : (email ?? ''),
                style: TextStyle(
                  color: cs.onSurface.withAlpha(100),
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Sighting count
            Center(
              child: Text(
                '$_sightingCount ${_sightingCount == 1 ? 'sighting' : 'sightings'}',
                style: TextStyle(
                  color: cs.onSurface.withAlpha(140),
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),

            const SizedBox(height: 32),

            Divider(color: cs.onSurface.withAlpha(30), height: 1),

            const SizedBox(height: 24),

            if (_loading)
              Center(
                child: CircularProgressIndicator(color: cs.onSurface.withAlpha(97), strokeWidth: 1.5),
              )
            else if (isAnon) ...[
              _AuthButton(
                onTap: _signInWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleLogo(),
                    const SizedBox(width: 12),
                    Text(
                      'Sign in with Google',
                      style: TextStyle(color: cs.onSurface, fontSize: 16),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _AuthButton(
                onTap: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple, color: cs.onSurface.withAlpha(60), size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Sign in with Apple',
                      style: TextStyle(color: cs.onSurface.withAlpha(60), fontSize: 16),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Sign out
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: _signOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.onSurface.withAlpha(40)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                          color: cs.onSurface.withAlpha(180),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
            Divider(color: cs.onSurface.withAlpha(30), height: 1),
            const SizedBox(height: 16),

            // Terms of Service
            _MenuRow(
              label: 'Terms of Service',
              onTap: () {
                // Placeholder
              },
            ),

            // Send feedback
            _MenuRow(
              label: 'Send feedback',
              onTap: () {
                // Placeholder
              },
            ),

            if (!isAnon && !_loading) ...[
              const SizedBox(height: 24),
              // Delete account
              Center(
                child: GestureDetector(
                  onTap: _deleteAccount,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Delete account',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // App version
            Center(
              child: Text(
                _appVersion.isNotEmpty ? 'v$_appVersion' : '',
                style: TextStyle(
                  color: cs.onSurface.withAlpha(60),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Menu row ────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MenuRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(color: cs.onSurface, fontSize: 16)),
            const Spacer(),
            Icon(Icons.chevron_right, color: cs.onSurface.withAlpha(60), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String? displayName;
  final bool isAnon;

  const _Avatar({this.avatarUrl, this.displayName, required this.isAnon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.onSurface.withAlpha(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null
          ? Image.network(avatarUrl!, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _Initial(displayName))
          : _Initial(displayName),
    );
  }
}

class _Initial extends StatelessWidget {
  final String? name;
  const _Initial(this.name);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = (name != null && name!.isNotEmpty)
        ? name![0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          color: cs.onSurface,
          fontSize: 32,
          fontWeight: FontWeight.w200,
        ),
      ),
    );
  }
}

// ─── Auth button ──────────────────────────────────────────────────────────────

class _AuthButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _AuthButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: cs.onSurface.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.onSurface.withAlpha(30)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Google logo ──────────────────────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22, height: 22,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Colors.blue[700],
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
