import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/design_tokens.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/assistant.dart';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:characters/characters.dart';
import 'assistant_settings_edit_page.dart';

class AssistantSettingsPage extends StatelessWidget {
  const AssistantSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final assistants = context.watch<AssistantProvider>().assistants;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.assistantSettingsPageTitle),
        actions: [
          IconButton(
            icon: Icon(Lucide.Plus, size: 22, color: cs.onSurface),
            onPressed: () async {
              final name = await _showAddAssistantSheet(context);
              if (name == null) return;
              final id = await context.read<AssistantProvider>().addAssistant(name: name.trim(), context: context);
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AssistantSettingsEditPage(assistantId: id)),
              );
            },
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: assistants.length,
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > oldIndex) newIndex -= 1;
          // Immediately update UI for smooth experience
          final assistantProvider = context.read<AssistantProvider>();
          await assistantProvider.reorderAssistants(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOutBack.transform(animation.value);
              return Transform.scale(
                scale: 0.98 + 0.02 * t,
                child: Material(
                  elevation: 8 * t,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: child,
                ),
              );
            },
          );
        },
        itemBuilder: (context, index) {
          final item = assistants[index];
          return KeyedSubtree(
            key: ValueKey('reorder-assistant-${item.id}'),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssistantCard(item: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.item});
  final Assistant item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AssistantSettingsEditPage(assistantId: item.id)),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.25)),
            boxShadow: isDark ? [] : AppShadows.soft,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AssistantAvatar(item: item, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (!item.deletable)
                                _TagPill(text: l10n.assistantSettingsDefaultTag, color: cs.primary),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.systemPrompt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7), height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: item.deletable
                          ? () async {
                              final ok = await _confirmDelete(context, l10n);
                              if (ok == true) {
                                await context.read<AssistantProvider>().deleteAssistant(item.id);
                              }
                            }
                          : null,
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      icon: Icon(Lucide.Trash2, size: 16),
                      label: Text(l10n.assistantSettingsDeleteButton),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AssistantSettingsEditPage(assistantId: item.id)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Lucide.Pencil, size: 16),
                      label: Text(l10n.assistantSettingsEditButton),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final first = String.fromCharCode(trimmed.runes.first);
    return first.toUpperCase();
  }
}

Future<String?> _showAddAssistantSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  String? result;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final viewInsets = MediaQuery.of(ctx).viewInsets;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.assistantSettingsAddSheetTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: l10n.assistantSettingsAddSheetHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.transparent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.primary.withOpacity(0.45)),
                    ),
                  ),
                  onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.assistantSettingsAddSheetCancel),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(l10n.assistantSettingsAddSheetSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).then((val) => result = val as String?);
  final trimmed = (result ?? '').trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Future<bool?> _confirmDelete(BuildContext context, AppLocalizations l10n) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(l10n.assistantSettingsDeleteDialogTitle),
        content: Text(l10n.assistantSettingsDeleteDialogContent),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.assistantSettingsDeleteDialogCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.assistantSettingsDeleteDialogConfirm, style: TextStyle(color: cs.error)),
          ),
        ],
      );
    },
  );
}

class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar({required this.item, this.size = 40});
  final Assistant item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final av = (item.avatar ?? '').trim();
    if (av.isNotEmpty) {
      if (av.startsWith('http')) {
        return ClipOval(
          child: Image.network(
            av,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => _initial(cs),
          ),
        );
      } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
        return ClipOval(
          child: Image(
            image: FileImage(File(av)),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } else {
        return _emoji(cs, av);
      }
    }
    return _initial(cs);
  }

  Widget _initial(ColorScheme cs) {
    final letter = item.name.isNotEmpty ? item.name.characters.first : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }

  Widget _emoji(ColorScheme cs, String emoji) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(emoji.characters.take(1).toString(), style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
