import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final ThemeMode themeMode;
  final bool voiceAlertsEnabled;
  final bool uploadOnlyOnWifi;

  SettingsState({
    this.themeMode = ThemeMode.system,
    this.voiceAlertsEnabled = true,
    this.uploadOnlyOnWifi = true,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? voiceAlertsEnabled,
    bool? uploadOnlyOnWifi,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      voiceAlertsEnabled: voiceAlertsEnabled ?? this.voiceAlertsEnabled,
      uploadOnlyOnWifi: uploadOnlyOnWifi ?? this.uploadOnlyOnWifi,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState());

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
  }

  void toggleVoiceAlerts() {
    state = state.copyWith(voiceAlertsEnabled: !state.voiceAlertsEnabled);
  }

  void toggleWifiOnly() {
    state = state.copyWith(uploadOnlyOnWifi: !state.uploadOnlyOnWifi);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
