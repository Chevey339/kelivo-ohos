import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showReasoningBudgetSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _ReasoningBudgetSheet(),
  );
}

class _ReasoningBudgetSheet extends StatefulWidget {
  const _ReasoningBudgetSheet();
  @override
  State<_ReasoningBudgetSheet> createState() => _ReasoningBudgetSheetState();
}

class _ReasoningBudgetSheetState extends State<_ReasoningBudgetSheet> {
  late int? _selected;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selected = s.thinkingBudget ?? -1;
    _controller = TextEditingController(text: (_selected ?? -1).toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int value) {
    setState(() {
      _selected = value;
      _controller.text = value.toString();
    });
    context.read<SettingsProvider>().setThinkingBudget(value);
  }

  int _bucket(int? n) {
    if (n == null) return -1; // treat as auto in UI bucketting
    if (n == -1) return -1;
    if (n < 1024) return 0;
    if (n < 16000) return 1024;
    if (n < 32000) return 16000;
    return 32000;
  }

  String _bucketName(BuildContext context, int? n) {
    final l10n = AppLocalizations.of(context)!;
    final b = _bucket(n);
    switch (b) {
      case 0:
        return l10n.reasoningBudgetSheetOff;
      case -1:
        return l10n.reasoningBudgetSheetAuto;
      case 1024:
        return l10n.reasoningBudgetSheetLight;
      case 16000:
        return l10n.reasoningBudgetSheetMedium;
      default:
        return l10n.reasoningBudgetSheetHeavy;
    }
  }

  Widget _tile(IconData icon, String title, int value, {String? subtitle, bool deepthink = false}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = _bucket(_selected) == value;
    final bg = active
        ? (isDark ? cs.primary.withOpacity(0.12) : cs.primary.withOpacity(0.08))
        : cs.surface;
    final Color iconColor = active ? cs.primary : cs.onSurface.withOpacity(0.7);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _select(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                deepthink
                    ? SvgPicture.asset(
                        'assets/icons/deepthink.svg',
                        width: 18,
                        height: 18,
                        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                      )
                    : Icon(icon, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                      ]
                    ],
                  ),
                ),
                if (active) Icon(Lucide.Check, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.6,
          minChildSize: 0.4,
          builder: (c, controller) {
            return Column(
              children: [
                // drag indicator
                const SizedBox(height: 8),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Text(
                          l10n.reasoningBudgetSheetTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Builder(builder: (context) {
                          final cur = int.tryParse(_controller.text.trim());
                          final eff = cur ?? _selected ?? -1;
                          return Text(
                            l10n.reasoningBudgetSheetCurrentLevel(_bucketName(context, eff)),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }),
                      ),
                      _tile(Lucide.X, l10n.reasoningBudgetSheetOff, 0, subtitle: l10n.reasoningBudgetSheetOffSubtitle),
                      _tile(Lucide.Settings2, l10n.reasoningBudgetSheetAuto, -1, subtitle: l10n.reasoningBudgetSheetAutoSubtitle),
                      _tile(Lucide.Brain, l10n.reasoningBudgetSheetLight, 1024, subtitle: l10n.reasoningBudgetSheetLightSubtitle, deepthink: true),
                      _tile(Lucide.Brain, l10n.reasoningBudgetSheetMedium, 16000, subtitle: l10n.reasoningBudgetSheetMediumSubtitle, deepthink: true),
                      _tile(Lucide.Brain, l10n.reasoningBudgetSheetHeavy, 32000, subtitle: l10n.reasoningBudgetSheetHeavySubtitle, deepthink: true),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.reasoningBudgetSheetCustomLabel, style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 8),
                            Builder(builder: (context) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              final cs2 = Theme.of(context).colorScheme;
                              return TextField(
                                controller: _controller,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: l10n.reasoningBudgetSheetCustomHint,
                                  filled: true,
                                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.transparent),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.transparent),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: cs2.primary.withOpacity(0.4)),
                                  ),
                                ),
                                onChanged: (v) {
                                  final n = int.tryParse(v.trim());
                                  if (n != null) {
                                    // Real-time save and update highlighting
                                    _select(n);
                                  } else {
                                    setState(() {}); // Only refresh "Current Level"
                                  }
                                },
                                onSubmitted: (v) {
                                  final n = int.tryParse(v.trim());
                                  if (n != null) {
                                    _select(n);
                                  }
                                  Navigator.of(context).maybePop();
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
