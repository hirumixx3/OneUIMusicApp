import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/music_player_provider.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF050608) : const Color(0xFFF3F5FB);
    final card = isDark ? const Color(0xFF141416) : Colors.white;
    final border = isDark ? const Color(0xFF1F2026) : const Color(0xFFE3E6F0);
    final secondary = isDark ? Colors.white70 : Colors.black54;

    final presetOrder = <EqualizerPreset>[
      EqualizerPreset.balanced,
      EqualizerPreset.bassBoost,
      EqualizerPreset.soft,
      EqualizerPreset.dynamic,
      EqualizerPreset.crisp,
      EqualizerPreset.trebleBoost,
      EqualizerPreset.custom,
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Text(
          t.equalizer,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: provider.equalizerEnabled ? t.equalizerStatusActive : t.equalizerStatusOff,
            onPressed: provider.equalizerSupported ? () => provider.setEqualizerEnabled(!provider.equalizerEnabled) : null,
            icon: Icon(
              provider.equalizerEnabled ? Icons.equalizer_rounded : Icons.equalizer_outlined,
            ),
          ),
          IconButton(
            tooltip: t.equalizerReset,
            onPressed: provider.equalizerBands.isEmpty ? null : () => provider.resetEqualizer(),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        provider.equalizerEnabled ? t.equalizerStatusActive : t.equalizerStatusOff,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: provider.equalizerEnabled ? const Color(0xFFC9D9FF) : secondary,
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
                  enabled: provider.equalizerEnabled && provider.equalizerSupported,
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
          else if (provider.equalizerBands.isEmpty)
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
            provider.equalizerSupported && provider.equalizerBands.isNotEmpty
                ? t.descriptionForEqualizerPreset(provider.equalizerPreset)
                : t.equalizerOnlyAppAudio,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: secondary, height: 1.35),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? const Color(0xFF1B1C22) : const Color(0xFFE8ECF6);
    final inactive = isDark ? Colors.white38 : Colors.black26;
    final active = const Color(0xFFC8D8EE);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF2A2A33) : const Color(0xFFD8DDEC);
    return SizedBox(
      width: width,
      child: Material(
        color: selected ? const Color(0xFFC8D8EE) : (isDark ? const Color(0xFF1C1D24) : Colors.white),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Container(
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: selected ? const Color(0xFFDCE9FF) : border),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? const Color(0xFF172033) : null,
                    fontSize: 20,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
