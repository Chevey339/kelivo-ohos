import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/chat_message.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../pages/select_copy_page.dart';
import '../../../l10n/app_localizations.dart';

enum MessageMoreAction { edit, fork, delete, share }

Future<MessageMoreAction?> showMessageMoreSheet(BuildContext context, ChatMessage message) async {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<MessageMoreAction?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _MessageMoreSheet(message: message),
  );
}

class _MessageMoreSheet extends StatefulWidget {
  const _MessageMoreSheet({required this.message});
  final ChatMessage message;

  @override
  State<_MessageMoreSheet> createState() => _MessageMoreSheetState();
}

class _MessageMoreSheetState extends State<_MessageMoreSheet> {
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();
  static const double _initialSize = 0.7;
  static const double _maxSize = 0.7;

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  String _formatTime(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context);
    final fmt = locale.languageCode == 'zh' ? DateFormat('yyyy年M月d日 HH:mm:ss') : DateFormat('yyyy-MM-dd HH:mm:ss');
    return fmt.format(time);
  }

  String? _modelDisplayName(BuildContext context) {
    final msg = widget.message;
    if (msg.role != 'assistant') return null;
    if (msg.providerId == null || msg.modelId == null) return null;
    final settings = context.read<SettingsProvider>();
    try {
      final cfg = settings.getProviderConfig(msg.providerId!);
      final ov = cfg.modelOverrides[msg.modelId!] as Map?;
      if (ov != null) {
        final name = (ov['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
      return msg.modelId!;
    } catch (_) {
      return msg.modelId!;
    }
  }

  Widget _actionItem({
    required IconData icon,
    required String label,
    Color? iconColor,
    bool danger = false,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = danger
        ? (isDark ? Colors.red.withOpacity(0.12) : Colors.red.withOpacity(0.08))
        : cs.surface;
    final borderColor = danger ? Colors.transparent : cs.outlineVariant.withOpacity(0.3);
    final fg = danger ? Colors.red.shade600 : cs.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () => Navigator.of(context).maybePop(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: iconColor ?? fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: fg),
                  ),
                ),
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

    final timeStr = _formatTime(context, widget.message.timestamp);
    final modelName = _modelDisplayName(context);

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        controller: _sheetCtrl,
        expand: false,
        initialChildSize: _initialSize,
        maxChildSize: _maxSize,
        minChildSize: 0.3,
        builder: (c, controller) {
          return Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  l10n.messageMoreSheetTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  children: [
                    _actionItem(
                      icon: Lucide.TextSelect,
                      label: l10n.messageMoreSheetSelectCopy,
                      onTap: () async {
                        Navigator.of(context).pop();
                        // Push the select copy page
                        await Future.delayed(const Duration(milliseconds: 50));
                        if (!mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SelectCopyPage(message: widget.message)),
                        );
                      },
                    ),
                    _actionItem(
                      icon: Lucide.BookOpenText,
                      label: l10n.messageMoreSheetRenderWebView,
                      onTap: () {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.messageMoreSheetNotImplemented),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                    _actionItem(
                      icon: Lucide.Pencil,
                      label: l10n.messageMoreSheetEdit,
                      onTap: () {
                        Navigator.of(context).pop(MessageMoreAction.edit);
                      },
                    ),
                    _actionItem(
                      icon: Lucide.Share,
                      label: l10n.messageMoreSheetShare,
                      onTap: () {
                        Navigator.of(context).pop(MessageMoreAction.share);
                      },
                    ),
                    _actionItem(
                      icon: Lucide.GitFork,
                      label: l10n.messageMoreSheetCreateBranch,
                      onTap: () {
                        Navigator.of(context).pop(MessageMoreAction.fork);
                      },
                    ),
                    _actionItem(
                      icon: Lucide.Trash2,
                      label: l10n.messageMoreSheetDelete,
                      danger: true,
                      onTap: () {
                        Navigator.of(context).pop(MessageMoreAction.delete);
                      },
                    ),

                    const SizedBox(height: 16),

                    // Bottom info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Lucide.History, size: 16, color: cs.onSurface.withOpacity(0.7)),
                              const SizedBox(width: 8),
                              Text(timeStr, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
                            ],
                          ),
                          if (modelName != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Lucide.Bot, size: 16, color: cs.onSurface.withOpacity(0.7)),
                                const SizedBox(width: 8),
                                Text(modelName, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
