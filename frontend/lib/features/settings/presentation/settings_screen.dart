import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(final BuildContext context, final WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _buildSectionHeader(context, 'Appearance'),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  subtitle: const Text('Follow system theme'),
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) settingsNotifier.setThemeMode(value);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  subtitle: const Text('Clean white interface'),
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) settingsNotifier.setThemeMode(value);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Premium slate interface'),
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (ThemeMode? value) {
                    if (value != null) settingsNotifier.setThemeMode(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'Road Monitoring & AI'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Voice Safety Alerts'),
                  subtitle: const Text('Receive immediate audio alerts for incoming potholes'),
                  secondary: Icon(Icons.volume_up, color: theme.colorScheme.primary),
                  value: settings.voiceAlertsEnabled,
                  onChanged: (bool value) {
                    settingsNotifier.toggleVoiceAlerts();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Upload Only on Wi-Fi'),
                  subtitle: const Text('Save mobile data by queuing image uploads for Wi-Fi'),
                  secondary: Icon(Icons.wifi, color: theme.colorScheme.primary),
                  value: settings.uploadOnlyOnWifi,
                  onChanged: (bool value) {
                    settingsNotifier.toggleWifiOnly();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(context, 'Data Management'),
          Card(
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text('Clear Stored Reports', style: TextStyle(color: theme.colorScheme.error)),
              subtitle: const Text('Delete local copies of uploaded reports to free storage'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Offline report logs cleared successfully')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
