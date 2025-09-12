import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/learning_mode_store.dart';
import '../../../l10n/app_localizations.dart';

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({super.key, this.onCamera, this.onPhotos, this.onUpload, this.onClear, this.clearLabel});

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;

    Widget roundedAction({required IconData icon, required String label, VoidCallback? onTap}) {
      return Expanded(
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              overlayColor: MaterialStateProperty.resolveWith(
                (states) => primary.withOpacity(states.contains(MaterialState.pressed) ? 0.14 : 0.08),
              ),
              splashColor: primary.withOpacity(0.18),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap?.call();
              },
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: primary),
                    const SizedBox(height: 6),
                    Text(label, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -6)),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Row(
            children: [
              roundedAction(
                icon: Lucide.Camera,
                label: l10n.bottomToolsSheetCamera,
                onTap: onCamera,
              ),
              const SizedBox(width: 12),
              roundedAction(
                icon: Lucide.Image,
                label: l10n.bottomToolsSheetPhotos,
                onTap: onPhotos,
              ),
              const SizedBox(width: 12),
              roundedAction(
                icon: Lucide.Upload,
                label: l10n.bottomToolsSheetUpload,
                onTap: onUpload,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LearningModeTile(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                overlayColor: MaterialStateProperty.resolveWith(
                  (states) => primary.withOpacity(states.contains(MaterialState.pressed) ? 0.14 : 0.08),
                ),
                splashColor: primary.withOpacity(0.18),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onClear?.call();
                },
                child: Center(
                  child: Text(clearLabel ?? l10n.bottomToolsSheetClearContext, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _LearningModeTile extends StatefulWidget {
  @override
  State<_LearningModeTile> createState() => _LearningModeTileState();
}

class _LearningModeTileState extends State<_LearningModeTile> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await LearningModeStore.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = v;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            child: Icon(Lucide.BookOpenText, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bottomToolsSheetLearningMode,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.bottomToolsSheetLearningModeDescription,
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.bottomToolsSheetConfigurePrompt,
            onPressed: () => _showLearningPromptSheet(context),
            icon: Icon(Lucide.Settings, size: 20, color: cs.primary),
          ),
          IgnorePointer(
            ignoring: _loading,
            child: Opacity(
              opacity: _loading ? 0.5 : 1,
              child: Switch(
                value: _enabled,
                onChanged: (v) async {
                  await LearningModeStore.setEnabled(v);
                  if (!mounted) return;
                  setState(() => _enabled = v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLearningPromptSheet(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final prompt = await LearningModeStore.getPrompt();
    final controller = TextEditingController(text: prompt);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.bottomToolsSheetPrompt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: l10n.bottomToolsSheetPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        await LearningModeStore.resetPrompt();
                        controller.text = await LearningModeStore.getPrompt();
                      },
                      child: Text(l10n.bottomToolsSheetResetDefault),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await LearningModeStore.setPrompt(controller.text.trim());
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.bottomToolsSheetSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
