import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// The user's chosen palette and light/dark preference, persisted locally.
///
/// This deliberately does *not* live in `profiles`. It is a device
/// preference, not an account fact: the same person on a phone at night and a
/// tablet in a lecture wants different answers, and putting it in the
/// database would mean a network round-trip before the first frame could be
/// painted.
class ThemeChoice {
  const ThemeChoice({this.paletteId = 'terminal', this.mode = ThemeMode.dark});

  final String paletteId;
  final ThemeMode mode;

  AppPalette get palette => paletteById(paletteId);

  ThemeChoice copyWith({String? paletteId, ThemeMode? mode}) => ThemeChoice(
        paletteId: paletteId ?? this.paletteId,
        mode: mode ?? this.mode,
      );
}

class ThemeController extends StateNotifier<ThemeChoice> {
  ThemeController() : super(const ThemeChoice()) {
    _restore();
  }

  static const _paletteKey = 'theme.palette';
  static const _modeKey = 'theme.mode';

  /// Reads the saved choice after the first frame. Starting from the default
  /// and correcting a moment later avoids blocking startup on disk I/O; the
  /// swap is a single rebuild.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final palette = prefs.getString(_paletteKey);
      final mode = prefs.getString(_modeKey);
      if (!mounted) return;

      state = ThemeChoice(
        paletteId: palette ?? state.paletteId,
        mode: switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => state.mode,
        },
      );
    } catch (_) {
      // A preferences failure is not worth blocking the app over — the
      // default theme is perfectly usable.
    }
  }

  Future<void> setPalette(String id) async {
    state = state.copyWith(paletteId: id);
    await _save(_paletteKey, id);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _save(_modeKey, mode.name);
  }

  Future<void> _save(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // Ditto: the choice still applies for this run.
    }
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeChoice>(
  (_) => ThemeController(),
);
