import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final secondary = context.oneUiSecondary;

    final presetOrder = <EqualizerPreset>[
      EqualizerPreset.balanced,
      EqualizerPreset.bassBoost,
      EqualizerPreset.soft,
      EqualizerPreset.dynamic,
      EqualizerPreset.crisp,
      EqualizerPreset.trebleBoost,
      EqualizerPreset.custom,
    ];
    final equalizerReady = provider.equalizerSupported && provider.equalizerAttached && provider.equalizerBands.isNotEmpty;
    final equalizerActive = equalizerReady && provider.equalizerEnabled;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            OneUi9PageHeader(
              title: t.equalizer,
              subtitle: t.equalizerOnlyAppAudio,
              onBack: () => Navigator.pop(context),
              large: true,
              actions: [
                OneUi9IconButton(
                  tooltip: equalizerActive ? t.equalizerStatusActive : t.equalizerStatusOff,
                  onPressed: provider.equalizerSupported ? () => provider.setEqualizerEnabled(!provider.equalizerEnabled) : null,
                  icon: equalizerActive ? Icons.equalizer_rounded : Icons.equalizer_outlined,
                  active: equalizerActive,
                ),
                OneUi9IconButton(
                  tooltip: t.equalizerReset,
                  onPressed: provider.equalizerBands.isEmpty ? null : () => provider.resetEqualizer(),
                  icon: Icons.restart_alt_rounded,
                ),
              ],
            ),
            const SizedBox(height: 24),
          OneUi9Glass(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            radius: 32,
            blur: 20,
            strong: true,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        equalizerReady
                            ? (provider.equalizerEnabled ? t.equalizerStatusActive : t.equalizerStatusOff)
                            : t.equalizerNeedsPlayback,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: equalizerActive ? const Color(0xFFC9D9FF) : secondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (provider.equalizerAudioSessionId != null)
                      Text(
                        '#${provider.equalizerAudioSessionId}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: secondary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _EqualizerChart(
                  bands: provider.equalizerBands,
                  enabled: equalizerActive,
                  onChanged: provider.setEqualizerBandLevel,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!provider.equalizerSupported)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                t.equalizerUnsupported,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: secondary, height: 1.35),
              ),
            )
          else if (!equalizerReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                t.equalizerNeedsPlayback,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: secondary, height: 1.35),
              ),
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (var i = 0; i < presetOrder.length; i++)
                  _PresetButton(
                    widthFactor: i == presetOrder.length - 1 ? 0.44 : 0.44,
                    title: t.labelForEqualizerPreset(presetOrder[i]),
                    selected: provider.equalizerPreset == presetOrder[i],
                    onTap: () => provider.applyEqualizerPreset(presetOrder[i]),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          Text(
            equalizerReady
                ? t.descriptionForEqualizerPreset(provider.equalizerPreset)
                : t.equalizerOnlyAppAudio,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: secondary, height: 1.35),
          ),
          ],
        ),
      ),
    );
  }
}

class _EqualizerChart extends StatelessWidget {
  const _EqualizerChart({
    required this.bands,
    required this.enabled,
    required this.onChanged,
  });

  final List<EqualizerBandSetting> bands;
  final bool enabled;
  final Future<void> Function(int bandIndex, int level) onChanged;

  @override
  Widget build(BuildContext context) {
    final lineColor = context.oneUiOutline.withOpacity(0.52);
    final inactive = context.oneUiSecondary.withOpacity(0.34);
    final active = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = 430.0;
        final bandsToShow = bands;
        return SizedBox(
          height: chartHeight,
          child: Stack(
            children: [
              Positioned.fill(
                top: 34,
                bottom: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    6,
                    (_) => Divider(height: 1, thickness: 1, color: lineColor),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final band in bandsToShow)
                    Expanded(
                      child: _VerticalBandSlider(
                        band: band,
                        activeColor: active,
                        inactiveColor: inactive,
                        enabled: enabled,
                        onChanged: (value) => onChanged(band.index, value),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VerticalBandSlider extends StatelessWidget {
  const _VerticalBandSlider({
    required this.band,
    required this.activeColor,
    required this.inactiveColor,
    required this.enabled,
    required this.onChanged,
  });

  final EqualizerBandSetting band;
  final Color activeColor;
  final Color inactiveColor;
  final bool enabled;
  final ValueChanged<int> onChanged;

  String _topValue(int milliBel) {
    final db = milliBel / 100.0;
    if (db.abs() < 0.05) return '0';
    final rounded = db.round();
    return rounded > 0 ? '+$rounded' : '$rounded';
  }

  String _shortLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('khz')) {
      return label.replaceAll(' kHz', 'k');
    }
    return label.replaceAll(' Hz', '');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = enabled ? (isDark ? Colors.white70 : Colors.black54) : (isDark ? Colors.white38 : Colors.black26);
    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 4,
      activeTrackColor: activeColor,
      inactiveTrackColor: inactiveColor,
      overlayShape: SliderComponentShape.noOverlay,
      thumbColor: activeColor,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      trackShape: const RoundedRectSliderTrackShape(),
    );

    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              _topValue(band.level),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: sliderTheme,
              child: Slider(
                value: band.level.toDouble().clamp(band.minLevel.toDouble(), band.maxLevel.toDouble()),
                min: band.minLevel.toDouble(),
                max: band.maxLevel.toDouble(),
                onChanged: enabled ? (value) => onChanged(value.round()) : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: Center(
            child: Text(
              _shortLabel(band.label),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.widthFactor,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final double widthFactor;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final width = (screenWidth - 54) * widthFactor;
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      child: OneUi9Glass(
        radius: 28,
        blur: 14,
        showShadow: false,
        tint: selected ? accent.withOpacity(context.oneUiDark ? 0.25 : 0.14) : null,
        borderColor: selected ? accent.withOpacity(0.48) : context.oneUiOutline,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: SizedBox(
              height: 92,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? accent : null,
                          fontSize: 20,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
