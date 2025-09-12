import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:syncfusion_flutter_sliders/sliders.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../../../core/providers/settings_provider.dart';
import 'theme_settings_page.dart';
import '../../../theme/palettes.dart';
import '../../../l10n/app_localizations.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    context.watch<SettingsProvider>(); // keep theme reactivity

    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              )),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: l10n.settingsPageBackButton,
        ),
        title: Text(l10n.settingsPageDisplay),
      ),
      body: ListView(
        children: [
          // Theme settings entry card at the very top
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: _ThemeEntryCard(),
          ),
          const SizedBox(height: 4),
          _LanguageTile(),
          _SwitchTile(
            icon: Lucide.User,
            title: l10n.displaySettingsPageShowUserAvatarTitle,
            subtitle: l10n.displaySettingsPageShowUserAvatarSubtitle,
            value: context.watch<SettingsProvider>().showUserAvatar,
            onChanged: (v) => context.read<SettingsProvider>().setShowUserAvatar(v),
          ),
          const SizedBox(height: 6),
          _SwitchTile(
            icon: Lucide.Bot,
            title: l10n.displaySettingsPageChatModelIconTitle,
            subtitle: l10n.displaySettingsPageChatModelIconSubtitle,
            value: context.watch<SettingsProvider>().showModelIcon,
            onChanged: (v) => context.read<SettingsProvider>().setShowModelIcon(v),
          ),
          const SizedBox(height: 6),
          _SwitchTile(
            icon: Lucide.Type,
            title: l10n.displaySettingsPageShowTokenStatsTitle,
            subtitle: l10n.displaySettingsPageShowTokenStatsSubtitle,
            value: context.watch<SettingsProvider>().showTokenStats,
            onChanged: (v) => context.read<SettingsProvider>().setShowTokenStats(v),
          ),
          _SwitchTile(
            icon: Lucide.Brain,
            title: l10n.displaySettingsPageAutoCollapseThinkingTitle,
            subtitle: l10n.displaySettingsPageAutoCollapseThinkingSubtitle,
            value: context.watch<SettingsProvider>().autoCollapseThinking,
            onChanged: (v) => context.read<SettingsProvider>().setAutoCollapseThinking(v),
          ),
          _SwitchTile(
            icon: Lucide.BadgeInfo,
            title: l10n.displaySettingsPageShowUpdatesTitle,
            subtitle: l10n.displaySettingsPageShowUpdatesSubtitle,
            value: context.watch<SettingsProvider>().showAppUpdates,
            onChanged: (v) => context.read<SettingsProvider>().setShowAppUpdates(v),
          ),
          _SwitchTile(
            icon: Lucide.ChevronRight,
            title: l10n.displaySettingsPageMessageNavButtonsTitle,
            subtitle: l10n.displaySettingsPageMessageNavButtonsSubtitle,
            value: context.watch<SettingsProvider>().showMessageNavButtons,
            onChanged: (v) => context.read<SettingsProvider>().setShowMessageNavButtons(v),
          ),
          _SwitchTile(
            icon: Lucide.panelRight,
            title: l10n.displaySettingsPageHapticsOnSidebarTitle,
            subtitle: l10n.displaySettingsPageHapticsOnSidebarSubtitle,
            value: context.watch<SettingsProvider>().hapticsOnDrawer,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsOnDrawer(v),
          ),
          _SwitchTile(
            icon: Lucide.Vibrate,
            title: l10n.displaySettingsPageHapticsOnGenerateTitle,
            subtitle: l10n.displaySettingsPageHapticsOnGenerateSubtitle,
            value: context.watch<SettingsProvider>().hapticsOnGenerate,
            onChanged: (v) => context.read<SettingsProvider>().setHapticsOnGenerate(v),
          ),
          _SwitchTile(
            icon: Lucide.MessageCirclePlus,
            title: l10n.displaySettingsPageNewChatOnLaunchTitle,
            subtitle: l10n.displaySettingsPageNewChatOnLaunchSubtitle,
            value: context.watch<SettingsProvider>().newChatOnLaunch,
            onChanged: (v) => context.read<SettingsProvider>().setNewChatOnLaunch(v),
          ),

          sectionTitle(l10n.displaySettingsPageChatFontSizeTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(builder: (context) {
                      final theme = Theme.of(context);
                      final cs = theme.colorScheme;
                      final isDark = theme.brightness == Brightness.dark;
                      final scale = context.watch<SettingsProvider>().chatFontScale;
                      return Row(
                        children: [
                          Text('80%', style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SfSliderTheme(
                              data: SfSliderThemeData(
                                activeTrackHeight: 8,
                                inactiveTrackHeight: 8,
                                overlayRadius: 14,
                                activeTrackColor: cs.primary,
                                inactiveTrackColor: cs.onSurface.withOpacity(isDark ? 0.25 : 0.20),
                                tooltipBackgroundColor: cs.primary,
                                tooltipTextStyle: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
                                activeTickColor: cs.onSurface.withOpacity(isDark ? 0.45 : 0.35),
                                inactiveTickColor: cs.onSurface.withOpacity(isDark ? 0.30 : 0.25),
                                activeMinorTickColor: cs.onSurface.withOpacity(isDark ? 0.34 : 0.28),
                                inactiveMinorTickColor: cs.onSurface.withOpacity(isDark ? 0.24 : 0.20),
                              ),
                              child: SfSlider(
                                value: scale,
                                min: 0.8,
                                max: 1.50001,
                                stepSize: 0.05,
                                showTicks: true,
                                showLabels: true,
                                interval: 0.1,
                                minorTicksPerInterval: 1,
                                enableTooltip: true,
                                shouldAlwaysShowTooltip: false,
                                tooltipShape: const SfPaddleTooltipShape(),
                                labelFormatterCallback: (value, text) => (value as double).toStringAsFixed(1),
                                thumbIcon: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: isDark ? [] : [
                                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: Offset(0, 2)),
                                    ],
                                  ),
                                ),
                                onChanged: (v) => context.read<SettingsProvider>().setChatFontScale((v as double).clamp(0.8, 1.5)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${(scale * 100).round()}%', style: TextStyle(color: cs.onSurface, fontSize: 12)),
                        ],
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.displaySettingsPageChatFontSampleText,
                        style: TextStyle(fontSize: 16 * context.watch<SettingsProvider>().chatFontScale),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 12),
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                    ],
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeEntryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final palette = ThemePalettes.byId(settings.themePaletteId);
    final subtitleText = Localizations.localeOf(context).languageCode == 'zh' ? palette.displayNameZh : palette.displayNameEn;
    return Material(
      color: cs.surfaceVariant.withOpacity(isDark ? 0.18 : 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 12),
                child: Icon(Lucide.Palette, size: 20, color: cs.primary),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.displaySettingsPageThemeSettingsTitle,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(subtitleText, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                  ],
                ),
              ),
              Icon(Lucide.ChevronRight, size: 18, color: cs.onSurface.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();

    String labelForLocale(Locale l) {
      if (l.languageCode == 'zh') {
        if ((l.scriptCode ?? '').toLowerCase() == 'hant') {
          return l10n.languageDisplayTraditionalChinese;
        }
        return l10n.displaySettingsPageLanguageChineseLabel;
      }
      return l10n.displaySettingsPageLanguageEnglishLabel;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Material(
        color: cs.surfaceVariant.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await _showLanguageSheet(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(right: 12),
                  child: Icon(Lucide.Languages, size: 20, color: cs.primary),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.displaySettingsPageLanguageTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(l10n.displaySettingsPageLanguageSubtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        settings.isFollowingSystemLocale
                            ? l10n.settingsPageSystemMode
                            : labelForLocale(settings.appLocale),
                        style: TextStyle(color: cs.primary, fontSize: 13),
                      ),
                      // const SizedBox(width: 6),
                      // Icon(Lucide.ChevronDown, size: 16, color: cs.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.settingsPageSystemMode),
                onTap: () => Navigator.of(ctx).pop('system'),
              ),
              ListTile(
                title: Text(l10n.displaySettingsPageLanguageChineseLabel),
                onTap: () => Navigator.of(ctx).pop('zh_CN'),
              ),
              ListTile(
                title: Text(l10n.languageDisplayTraditionalChinese),
                onTap: () => Navigator.of(ctx).pop('zh_Hant'),
              ),
              ListTile(
                title: Text(l10n.displaySettingsPageLanguageEnglishLabel),
                onTap: () => Navigator.of(ctx).pop('en_US'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    switch (selected) {
      case 'system':
        await context.read<SettingsProvider>().setAppLocaleFollowSystem();
        break;
      case 'zh_CN':
        await context.read<SettingsProvider>().setAppLocale(const Locale('zh', 'CN'));
        break;
      case 'zh_Hant':
        await context.read<SettingsProvider>().setAppLocale(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
        break;
      case 'en_US':
      default:
        await context.read<SettingsProvider>().setAppLocale(const Locale('en', 'US'));
    }
  }
}
