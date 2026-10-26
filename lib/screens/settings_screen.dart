import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final secondary = context.oneUiSecondary;
    final glassEnabled = provider.glassEffectsEnabled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            OneUi9PageHeader(
              title: t.settings,
              subtitle: t.appearance,
              onBack: () => Navigator.pop(context),
              large: true,
            ),
            const SizedBox(height: 24),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.language, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AppLanguage>(
                    value: provider.appLanguage,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: AppLanguage.values.map((language) => DropdownMenuItem<AppLanguage>(
                      value: language,
                      child: Text(t.labelForLanguage(language)),
                    )).toList(),
                    onChanged: (language) {
                      if (language != null) provider.setLanguage(language);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.appearance,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.glassEffects,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.glassEffectsDescription,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: secondary, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: glassEnabled,
                        activeTrackColor: Theme.of(
                          context,
                        ).colorScheme.primary,
                        onChanged: (value) =>
                            provider.setGlassEffectsEnabled(value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: glassEnabled ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: !glassEnabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GlassSlider(
                            label: t.blurIntensity,
                            value: provider.glassBlurAmount,
                            onChanged: (value) =>
                                provider.setGlassBlurAmount(value),
                          ),
                          const SizedBox(height: 18),
                          _GlassSlider(
                            label: t.transparencyIntensity,
                            value: provider.glassTransparencyAmount,
                            onChanged: (value) =>
                                provider.setGlassTransparencyAmount(value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!glassEnabled) ...[
                    const SizedBox(height: 12),
                    Text(
                      t.glassEffectsDisabledHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: secondary, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OneUi9Glass(
      padding: const EdgeInsets.all(18),
      radius: 30,
      blur: 20,
      strong: true,
      child: child,
    );
  }
}

class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final secondary = context.oneUiSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: secondary),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            inactiveTrackColor: secondary.withOpacity(0.18),
            thumbColor: accent,
            overlayColor: accent.withOpacity(0.15),
            trackHeight: 6,
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
