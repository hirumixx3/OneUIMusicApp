import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared One UI 9 inspired visual language used by the whole application.
///
/// The palette intentionally stays independent from playback and data code so
/// every route can share the same liquid-glass treatment without changing any
/// of the app's music features.
abstract final class OneUi9 {
  static const Color accent = Color(0xFF5B8CFF);
  static const Color accentSoft = Color(0xFFAFC6FF);
  static const Color violet = Color(0xFFB89CFF);
  static const Color cyan = Color(0xFF8DE1FF);
  static const Color pink = Color(0xFFFFA8D8);

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: dark ? const Color(0xFF9DB7FF) : const Color(0xFF315FC8),
      secondary: dark ? const Color(0xFFC9B7FF) : const Color(0xFF7054B8),
      surface: dark ? const Color(0xFF111827) : const Color(0xFFF8FAFF),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: dark ? const Color(0xFF0A0F1B) : const Color(0xFFF3F6FF),
      fontFamily: 'Roboto',
    );
    final foreground = dark ? const Color(0xFFF4F6FF) : const Color(0xFF161B28);
    final secondary = dark ? const Color(0xFFB7BED0) : const Color(0xFF5F6677);
    final outline = dark ? Colors.white.withOpacity(0.13) : Colors.white.withOpacity(0.88);
    final fieldFill = dark ? Colors.white.withOpacity(0.075) : Colors.white.withOpacity(0.56);

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: foreground),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: foreground),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: secondary),
      ),
      appBarTheme: AppBarThemeData(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: foreground,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
      iconTheme: IconThemeData(color: foreground),
      dividerTheme: DividerThemeData(color: dark ? Colors.white10 : Colors.black12, space: 1),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: fieldFill,
        hintStyle: TextStyle(color: secondary.withOpacity(0.82), fontWeight: FontWeight.w500),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.78), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colorScheme.error.withOpacity(0.78)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? const Color(0xFF9DB7FF) : const Color(0xFF315FC8),
          foregroundColor: dark ? const Color(0xFF0C1B3A) : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          side: BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: foreground,
          highlightColor: colorScheme.primary.withOpacity(0.14),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: fieldFill,
        selectedColor: colorScheme.primary.withOpacity(dark ? 0.25 : 0.16),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        secondaryLabelStyle: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w800),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondary,
        textColor: foreground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        color: dark ? const Color(0xEB171D2B) : const Color(0xEBF7F9FF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: dark ? const Color(0xEB111827) : const Color(0xEBF8FAFF),
        modalBackgroundColor: dark ? const Color(0xEB111827) : const Color(0xEBF8FAFF),
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: secondary.withOpacity(0.45),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: dark ? const Color(0xF0182030) : const Color(0xF5F8FAFF),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: outline),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: dark ? const Color(0xEE20283A) : const Color(0xF2FFFFFF),
        contentTextStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: outline),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primary.withOpacity(0.14),
        circularTrackColor: colorScheme.primary.withOpacity(0.12),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelColor: foreground,
        unselectedLabelColor: secondary,
        overlayColor: WidgetStatePropertyAll(colorScheme.primary.withOpacity(0.08)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension OneUi9Context on BuildContext {
  bool get oneUiDark => Theme.of(this).brightness == Brightness.dark;

  Color get oneUiForeground => oneUiDark ? const Color(0xFFF4F6FF) : const Color(0xFF161B28);

  Color get oneUiSecondary => oneUiDark ? const Color(0xFFB7BED0) : const Color(0xFF5F6677);

  Color get oneUiGlass => oneUiDark ? Colors.white.withOpacity(0.075) : Colors.white.withOpacity(0.54);

  Color get oneUiGlassStrong => oneUiDark ? const Color(0xB3182130) : const Color(0xC7F8FAFF);

  Color get oneUiOutline => oneUiDark ? Colors.white.withOpacity(0.13) : Colors.white.withOpacity(0.88);

  Color get oneUiShadow => oneUiDark ? Colors.black.withOpacity(0.34) : const Color(0xFF778AB8).withOpacity(0.18);
}

/// Atmospheric wallpaper rendered once behind the app's transparent routes.
class OneUi9Backdrop extends StatelessWidget {
  const OneUi9Backdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.oneUiDark;
    return ColoredBox(
      color: dark ? const Color(0xFF070B13) : const Color(0xFFF5F7FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0xFF070B13), Color(0xFF0D1728), Color(0xFF171225), Color(0xFF080C15)]
                    : const [Color(0xFFF9FBFF), Color(0xFFEAF1FF), Color(0xFFF4ECFF), Color(0xFFF8FAFF)],
                stops: const [0, 0.38, 0.72, 1],
              ),
            ),
          ),
          const Positioned(
            top: -150,
            right: -120,
            child: _LiquidOrb(size: 340, color: OneUi9.violet),
          ),
          const Positioned(
            top: 230,
            left: -150,
            child: _LiquidOrb(size: 310, color: OneUi9.cyan),
          ),
          const Positioned(
            bottom: -170,
            right: -100,
            child: _LiquidOrb(size: 360, color: OneUi9.pink),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? [Colors.black.withOpacity(0.05), Colors.black.withOpacity(0.22)]
                    : [Colors.white.withOpacity(0.03), Colors.white.withOpacity(0.20)],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _LiquidOrb extends StatelessWidget {
  const _LiquidOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(context.oneUiDark ? 0.26 : 0.40),
              color.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable frosted surface for cards, bars, controls and sheet content.
class OneUi9Glass extends StatelessWidget {
  const OneUi9Glass({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 28,
    this.blur = 18,
    this.strong = false,
    this.tint,
    this.borderColor,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final bool strong;
  final Color? tint;
  final Color? borderColor;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final surface = tint ?? (strong ? context.oneUiGlassStrong : context.oneUiGlass);
    final glass = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor ?? context.oneUiOutline),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(context.oneUiDark ? 0.12 : 0.46),
                surface,
                OneUi9.accent.withOpacity(context.oneUiDark ? 0.035 : 0.025),
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      ),
    );

    return Container(
      margin: margin,
      decoration: showShadow
          ? BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: context.oneUiShadow,
                  blurRadius: strong ? 30 : 22,
                  offset: const Offset(0, 10),
                ),
              ],
            )
          : null,
      child: glass,
    );
  }
}

class OneUi9IconButton extends StatelessWidget {
  const OneUi9IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 46,
    this.iconSize = 23,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OneUi9Glass(
      radius: size / 2,
      blur: 14,
      showShadow: false,
      tint: active ? Theme.of(context).colorScheme.primary.withOpacity(context.oneUiDark ? 0.28 : 0.16) : null,
      child: SizedBox.square(
        dimension: size,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          iconSize: iconSize,
          icon: Icon(
            icon,
            color: active ? Theme.of(context).colorScheme.primary : context.oneUiForeground,
          ),
        ),
      ),
    );
  }
}

/// Compact route header with One UI's generous title and one-handed spacing.
class OneUi9PageHeader extends StatelessWidget {
  const OneUi9PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.large = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              OneUi9IconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: large ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: large
                    ? Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 38, height: 1.02)
                    : Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 10),
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                actions[index],
              ],
            ],
          ],
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.oneUiSecondary,
                  height: 1.35,
                ),
          ),
        ],
      ],
    );
  }
}

class OneUi9EmptyState extends StatelessWidget {
  const OneUi9EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.music_note_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: OneUi9Glass(
          radius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          showShadow: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [OneUi9.accentSoft, OneUi9.violet],
                  ),
                  boxShadow: [
                    BoxShadow(color: OneUi9.accent.withOpacity(0.24), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: Icon(icon, color: const Color(0xFF10234A), size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OneUi9SheetHandle extends StatelessWidget {
  const OneUi9SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: context.oneUiSecondary.withOpacity(0.38),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
