import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../providers/music_player_provider.dart';
import 'equalizer_screen.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const String _phoneNumber = '+5511954792230';

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF090A0E) : const Color(0xFFF5F6FB);
    final card = isDark ? const Color(0xFF14161D) : Colors.white;
    final border = isDark ? const Color(0xFF252632) : const Color(0xFFE4E6EC);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(t.aboutApp),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _SectionCard(
            color: card,
            border: border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.aboutApp,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                _SelectableInfoTile(
                  icon: Icons.code_rounded,
                  title: t.developedBy,
                  value: 'Higor',
                ),
                const SizedBox(height: 10),
                _SelectableInfoTile(
                  icon: Icons.equalizer_rounded,
                  title: t.equalizer,
                  value: t.equalizerOnlyAppAudio,
                  helper: t.tapToOpen,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EqualizerScreen())),
                ),
                const SizedBox(height: 10),
                _SelectableInfoTile(
                  icon: Icons.chat_rounded,
                  title: t.whatsapp,
                  value: _phoneNumber,
                  helper: t.tapToOpen,
                  onTap: () => _openWhatsApp(context),
                ),
                const SizedBox(height: 10),
                _SelectableInfoTile(
                  icon: Icons.send_rounded,
                  title: t.telegram,
                  value: _phoneNumber,
                  helper: t.tapToOpen,
                  onTap: () => _openTelegram(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            color: card,
            border: border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.language,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final language in AppLanguage.values)
                      ChoiceChip(
                        label: Text(t.labelForLanguage(language)),
                        selected: provider.appLanguage == language,
                        onSelected: (_) => context.read<MusicPlayerProvider>().setLanguage(language),
                        showCheckmark: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Future<void> _openWhatsApp(BuildContext context) async {
    final phoneDigits = _phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uris = [
      Uri.parse('whatsapp://send?phone=$phoneDigits'),
      Uri.parse('https://wa.me/$phoneDigits'),
    ];
    await _launchFirstAvailable(context, uris);
  }

  Future<void> _openTelegram(BuildContext context) async {
    final phoneDigits = _phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uris = [
      Uri.parse('tg://resolve?phone=$phoneDigits'),
      Uri.parse('https://t.me/+${phoneDigits}'),
    ];
    await _launchFirstAvailable(context, uris);
  }

  Future<void> _launchFirstAvailable(BuildContext context, List<Uri> uris) async {
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return;
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    final t = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.couldNotOpenLink)),
    );
  }

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    final t = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.copied(label))),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    required this.color,
    required this.border,
  });

  final Widget child;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

class _SelectableInfoTile extends StatelessWidget {
  const _SelectableInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.helper,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? helper;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: secondary.withOpacity(0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if ((helper ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      helper!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondary),
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
