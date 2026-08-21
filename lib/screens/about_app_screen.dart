import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../providers/music_player_provider.dart';
import '../ui/one_ui_9.dart';
import 'equalizer_screen.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const String _phoneNumber = '+5511954792230';

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final provider = context.watch<MusicPlayerProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            OneUi9PageHeader(
              title: t.aboutApp,
              subtitle: 'Music • One UI 9 Liquid Glass',
              onBack: () => Navigator.pop(context),
              large: true,
            ),
            const SizedBox(height: 24),
          _SectionCard(
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
  });

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
      borderRadius: BorderRadius.circular(21),
      onTap: onTap,
      child: OneUi9Glass(
        padding: const EdgeInsets.all(14),
        radius: 21,
        blur: 10,
        showShadow: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(context.oneUiDark ? 0.24 : 0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
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
