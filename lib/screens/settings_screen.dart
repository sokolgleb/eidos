import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _defaultShowOriginal = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final theme = await SettingsService.getThemeMode();
    final showOrig = await SettingsService.getDefaultShowOriginal();
    if (mounted) {
      setState(() {
        _themeMode = theme;
        _defaultShowOriginal = showOrig;
      });
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await SettingsService.setThemeMode(mode);
    widget.onThemeChanged?.call();
  }

  Future<void> _setDefaultShowOriginal(bool value) async {
    setState(() => _defaultShowOriginal = value);
    await SettingsService.setDefaultShowOriginal(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Text(
              'Settings',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w200,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 32),

            // Theme
            _SectionHeader(title: 'Appearance'),
            const SizedBox(height: 12),
            _OptionRow(
              label: 'Theme',
              child: _SegmentedPicker<ThemeMode>(
                value: _themeMode,
                options: const [
                  (ThemeMode.system, 'System'),
                  (ThemeMode.light, 'Light'),
                  (ThemeMode.dark, 'Dark'),
                ],
                onChanged: _setThemeMode,
              ),
            ),

            const SizedBox(height: 24),

            // Default view
            _SectionHeader(title: 'Viewing'),
            const SizedBox(height: 12),
            _ToggleRow(
              label: 'Default to original',
              subtitle: 'Show original photo first in detail view',
              value: _defaultShowOriginal,
              onChanged: _setDefaultShowOriginal,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: cs.onSurface.withAlpha(100),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _OptionRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: cs.onSurface, fontSize: 16)),
        child,
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: cs.onSurface, fontSize: 16)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: TextStyle(
                        color: cs.onSurface.withAlpha(80), fontSize: 13)),
              ],
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: cs.onSurface,
        ),
      ],
    );
  }
}

class _SegmentedPicker<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _SegmentedPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final selected = opt.$1 == value;
          return GestureDetector(
            onTap: () => onChanged(opt.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? cs.onSurface.withAlpha(30) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                opt.$2,
                style: TextStyle(
                  color: selected ? cs.onSurface : cs.onSurface.withAlpha(120),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w400 : FontWeight.w300,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
