import 'package:flutter/material.dart';

import '../ui/one_ui_9.dart';

class MusicSearchField extends StatelessWidget {
  const MusicSearchField({
    super.key,
    required this.controller,
    required this.isDark,
    this.onSubmitted,
    this.hintText = 'Buscar músicas...',
  });

  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String>? onSubmitted;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return OneUi9Glass(
      radius: 26,
      blur: 18,
      showShadow: false,
      child: TextField(
        controller: controller,
        style: Theme.of(context).textTheme.bodyLarge,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: Icon(Icons.search_rounded, color: context.oneUiSecondary),
          hintText: hintText,
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.oneUiSecondary,
                fontWeight: FontWeight.w500,
              ),
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }
}
