import 'package:flutter/material.dart';

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
    final fill = isDark ? const Color(0xFF131315) : Colors.white;
    final border = isDark ? const Color(0xFF27272D) : const Color(0xFFD4D6DC);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        style: Theme.of(context).textTheme.bodyLarge,
        textInputAction: TextInputAction.go,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
