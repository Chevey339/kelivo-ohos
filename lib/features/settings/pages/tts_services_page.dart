import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../l10n/app_localizations.dart';

class TtsServicesPage extends StatelessWidget {
  const TtsServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: l10n.ttsServicesPageBackButton,
        ),
        title: Text(l10n.ttsServicesPageTitle),
        actions: [
          IconButton(
            tooltip: l10n.ttsServicesPageAddTooltip,
            icon: Icon(Lucide.Plus, color: cs.onSurface),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.ttsServicesPageAddNotImplemented)),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Consumer<TtsProvider>(builder: (context, tts, _) {
            final available = tts.isAvailable && (tts.error == null);
            final titleText = l10n.ttsServicesPageSystemTtsTitle;
            final avatarText = titleText.trim().isEmpty
                ? '?'
                : titleText.trim().substring(0, 1).toUpperCase();
            return _TtsServiceCard(
              avatarText: avatarText,
              title: titleText,
              subtitle: available
                  ? l10n.ttsServicesPageSystemTtsAvailableSubtitle
                  : l10n.ttsServicesPageSystemTtsUnavailableSubtitle(tts.error ?? l10n.ttsServicesPageSystemTtsUnavailableNotInitialized),
              selected: true,
              speaking: tts.isSpeaking,
              onTest: available
                  ? () async {
                      if (!tts.isSpeaking) {
                        final demo = l10n.ttsServicesPageTestSpeechText;
                        await tts.speak(demo);
                      } else {
                        await tts.stop();
                      }
                    }
                  : null,
              onDelete: null,
              onConfig: available ? () => _showSystemTtsConfig(context) : null,
            );
          }),
        ],
      ),
    );
  }
}

class _TtsServiceCard extends StatelessWidget {
  const _TtsServiceCard({
    required this.avatarText,
    required this.title,
    required this.subtitle,
    this.selected = false,
    this.speaking = false,
    this.onConfig,
    this.onTest,
    this.onDelete,
  });

  final String avatarText;
  final String title;
  final String subtitle;
  final bool selected;
  final bool speaking;
  final VoidCallback? onConfig;
  final VoidCallback? onTest;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? (isDark ? Colors.white10 : cs.primary.withOpacity(0.08))
        : cs.surface;
    final borderColor = selected
        ? cs.primary.withOpacity(0.35)
        : cs.outlineVariant.withOpacity(0.4);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + titles + settings on the far right
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CircleAvatar(text: avatarText),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: l10n.ttsServicesPageConfigureTooltip,
                  onPressed: onConfig,
                  icon: Icon(Lucide.Settings, size: 20, color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Bottom row: actions on the right
            Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: speaking ? l10n.ttsServicesPageStopTooltip : l10n.ttsServicesPageTestVoiceTooltip,
                  onPressed: onTest,
                  icon: Icon(speaking ? Lucide.CircleStop : Lucide.Volume2, size: 20, color: cs.onSurface),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n.ttsServicesPageDeleteTooltip,
                  onPressed: onDelete,
                  icon: Icon(
                    Lucide.Trash2,
                    size: 20,
                    color: (onDelete == null)
                        ? cs.onSurface.withOpacity(0.35)
                        : cs.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAvatar extends StatelessWidget {
  const _CircleAvatar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}

// Removed selected tag; background highlight indicates selection

Future<void> _showSystemTtsConfig(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final tts = context.read<TtsProvider>();
  double rate = tts.speechRate;
  double pitch = tts.pitch;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.Settings, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(l10n.ttsServicesPageSystemTtsSettingsTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              // Engine selector
              FutureBuilder<List<String>>(
                future: tts.listEngines(),
                builder: (context, snap) {
                  final engines = snap.data ?? const <String>[];
                  final cur = tts.engineId ?? (engines.isNotEmpty ? engines.first : '');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.ttsServicesPageEngineLabel, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                    subtitle: Text(cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur, style: const TextStyle(fontSize: 13)),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: engines.isEmpty ? null : () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: cs.surface,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        builder: (ctx2) {
                          return SafeArea(
                            child: ListView(
                              shrinkWrap: true,
                              children: engines.map((e) => ListTile(
                                title: Text(e),
                                onTap: () => Navigator.of(ctx2).pop(e),
                              )).toList(),
                            ),
                          );
                        },
                      );
                      if (picked != null && picked.isNotEmpty) {
                        await tts.setEngineId(picked);
                        (ctx as Element).markNeedsBuild();
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              // Language selector
              FutureBuilder<List<String>>(
                future: tts.listLanguages(),
                builder: (context, snap) {
                  final langs = snap.data ?? const <String>[];
                  final cur = tts.languageTag ?? (langs.contains('zh-CN') ? 'zh-CN' : (langs.contains('en-US') ? 'en-US' : (langs.isNotEmpty ? langs.first : '')));
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.ttsServicesPageLanguageLabel, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                    subtitle: Text(cur.isEmpty ? l10n.ttsServicesPageAutoLabel : cur, style: const TextStyle(fontSize: 13)),
                    trailing: const Icon(Icons.keyboard_arrow_right),
                    onTap: langs.isEmpty ? null : () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: cs.surface,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        builder: (ctx2) {
                          return SafeArea(
                            child: ListView(
                              shrinkWrap: true,
                              children: langs.map((e) => ListTile(
                                title: Text(e),
                                onTap: () => Navigator.of(ctx2).pop(e),
                              )).toList(),
                            ),
                          );
                        },
                      );
                      if (picked != null && picked.isNotEmpty) {
                        await tts.setLanguageTag(picked);
                        (ctx as Element).markNeedsBuild();
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(l10n.ttsServicesPageSpeechRateLabel, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
              Slider(
                value: rate,
                min: 0.1,
                max: 1.0,
                onChanged: (v) {
                  rate = v;
                  // Rebuild this bottom sheet
                  (ctx as Element).markNeedsBuild();
                },
                onChangeEnd: (v) async {
                  await tts.setSpeechRate(v);
                },
              ),
              const SizedBox(height: 4),
              Text(l10n.ttsServicesPagePitchLabel, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
              Slider(
                value: pitch,
                min: 0.5,
                max: 2.0,
                onChanged: (v) {
                  pitch = v;
                  (ctx as Element).markNeedsBuild();
                },
                onChangeEnd: (v) async {
                  await tts.setPitch(v);
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final demo = l10n.ttsServicesPageSettingsSavedMessage;
                    Navigator.of(ctx).maybePop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(demo)));
                  },
                  icon: Icon(Lucide.Check, size: 16),
                  label: Text(l10n.ttsServicesPageDoneButton),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
