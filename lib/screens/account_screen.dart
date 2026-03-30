import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/sighting_storage.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  int _sightingCount = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final list = await SightingStorage.loadAll();
    if (mounted) setState(() => _sightingCount = list.length);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final success = await AuthService.signInWithGoogle();
      if (mounted && success) Navigator.pop(context);
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
      if (mounted) Navigator.pop(context);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Avatar
            Center(
              child: _Avatar(avatarUrl: avatar, displayName: name, isAnon: isAnon),
            ),

            const SizedBox(height: 16),

            // Display name
            Center(
              child: Text(
                isAnon ? 'Anonymous' : (name ?? 'Signed in'),
                style: const TextStyle(
                  color: Colors.white,
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
                  color: Colors.white.withAlpha(100),
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
                  color: Colors.white.withAlpha(140),
                  fontSize: 15,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),

            const SizedBox(height: 32),

            Divider(color: Colors.white.withAlpha(30), height: 1),

            const SizedBox(height: 24),

            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5),
              )
            else if (isAnon) ...[
              // Sign in with Google
              _AuthButton(
                onTap: _signInWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleLogo(),
                    const SizedBox(width: 12),
                    const Text(
                      'Sign in with Google',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Sign in with Apple (disabled — requires paid Apple Developer account)
              _AuthButton(
                onTap: null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.apple, color: Colors.white.withAlpha(60), size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Sign in with Apple',
                      style: TextStyle(color: Colors.white.withAlpha(60), fontSize: 16),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Sign out
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: _signOut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withAlpha(40)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                          color: Colors.white.withAlpha(180),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(20),
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
    final letter = (name != null && name!.isNotEmpty)
        ? name![0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─── Google logo (simple G) ───────────────────────────────────────────────────

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22, height: 22,
      decoration: BoxDecoration(
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
