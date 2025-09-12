import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../l10n/app_localizations.dart';

import 'dart:io';
import '../../../core/models/chat_input_data.dart';

class ChatInputBarController {
  _ChatInputBarState? _state;
  void _bind(_ChatInputBarState s) => _state = s;
  void _unbind(_ChatInputBarState s) { if (identical(_state, s)) _state = null; }

  void addImages(List<String> paths) => _state?._addImages(paths);
  void clearImages() => _state?._clearImages();
  void addFiles(List<DocumentAttachment> docs) => _state?._addFiles(docs);
  void clearFiles() => _state?._clearFiles();
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    this.onSend,
    this.onStop,
    this.onSelectModel,
    this.onOpenMcp,
    this.onToggleSearch,
    this.onOpenSearch,
    this.onMore,
    this.onConfigureReasoning,
    this.moreOpen = false,
    this.focusNode,
    this.modelIcon,
    this.controller,
    this.mediaController,
    this.loading = false,
    this.reasoningActive = false,
    this.supportsReasoning = true,
    this.showMcpButton = false,
    this.mcpActive = false,
    this.searchEnabled = false,
  });

  final ValueChanged<ChatInputData>? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onSelectModel;
  final VoidCallback? onOpenMcp;
  final ValueChanged<bool>? onToggleSearch;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onMore;
  final VoidCallback? onConfigureReasoning;
  final bool moreOpen;
  final FocusNode? focusNode;
  final Widget? modelIcon;
  final TextEditingController? controller;
  final ChatInputBarController? mediaController;
  final bool loading;
  final bool reasoningActive;
  final bool supportsReasoning;
  final bool showMcpButton;
  final bool mcpActive;
  final bool searchEnabled;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late TextEditingController _controller;
  bool _searchEnabled = false;
  final List<String> _images = <String>[]; // local file paths
  final List<DocumentAttachment> _docs = <DocumentAttachment>[]; // files to upload

  void _addImages(List<String> paths) {
    if (paths.isEmpty) return;
    setState(() => _images.addAll(paths));
  }

  void _clearImages() {
    setState(() => _images.clear());
  }

  void _addFiles(List<DocumentAttachment> docs) {
    if (docs.isEmpty) return;
    setState(() => _docs.addAll(docs));
  }

  void _clearFiles() {
    setState(() => _docs.clear());
  }

  void _removeImageAt(int index) async {
    final path = _images[index];
    setState(() => _images.removeAt(index));
    // best-effort delete
    try { final f = File(path); if (await f.exists()) { await f.delete(); } } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    widget.mediaController?._bind(this);
    _searchEnabled = widget.searchEnabled;
  }

  @override
  void dispose() {
    widget.mediaController?._unbind(this);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchEnabled != widget.searchEnabled) {
      _searchEnabled = widget.searchEnabled;
    }
  }

  String _hint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.chatInputBarHint;
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty && _docs.isEmpty) return;
    widget.onSend?.call(ChatInputData(text: text, imagePaths: List.of(_images), documents: List.of(_docs)));
    _controller.clear();
    _images.clear();
    _docs.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasText = _controller.text.trim().isNotEmpty;
    final hasImages = _images.isNotEmpty;
    final hasDocs = _docs.isNotEmpty;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File attachments (if any)
            if (hasDocs) ...[
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final d = _docs[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: isDark ? [] : AppShadows.soft,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 18),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              d.fileName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() => _docs.removeAt(idx));
                              // best-effort delete persisted attachment
                              try { final f = File(d.path); if (f.existsSync()) { f.deleteSync(); } } catch (_) {}
                            },
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            // Image previews (if any)
            if (hasImages) ...[
              SizedBox(
                height: 64,
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final path = _images[idx];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(path),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 64,
                              height: 64,
                              color: Colors.black12,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -6,
                          top: -6,
                          child: GestureDetector(
                            onTap: () => _removeImageAt(idx),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            // Top: large rounded input capsule
            DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.capsule),
                boxShadow: isDark
                    ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
                    : AppShadows.soft,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
                child: TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  onChanged: (_) => setState(() {}),
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: _hint(context),
                    hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.55)),
                    border: InputBorder.none,
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  cursorColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Bottom: circular buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _CircleIconButton(
                      tooltip: AppLocalizations.of(context)!.chatInputBarSelectModelTooltip,
                      icon: Lucide.Boxes,
                      child: widget.modelIcon,
                      padding: widget.modelIcon != null ? 1 : 10,
                      onTap: widget.onSelectModel,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _CircleIconButton(
                      tooltip: AppLocalizations.of(context)!.chatInputBarOnlineSearchTooltip,
                      icon: Lucide.Globe,
                      active: _searchEnabled,
                      onTap: widget.onOpenSearch,
                    ),
                    if (widget.supportsReasoning) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _CircleIconButton(
                        tooltip: AppLocalizations.of(context)!.chatInputBarReasoningStrengthTooltip,
                        icon: Lucide.Brain,
                        active: widget.reasoningActive,
                        onTap: widget.onConfigureReasoning,
                        child: SvgPicture.asset(
                          'assets/icons/deepthink.svg',
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(
                            widget.reasoningActive
                                ? theme.colorScheme.primary
                                : (isDark ? Colors.white : Colors.black87),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
                    if (widget.showMcpButton) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _CircleIconButton(
                        tooltip: AppLocalizations.of(context)!.chatInputBarMcpServersTooltip,
                        icon: Lucide.Terminal,
                        active: widget.mcpActive,
                        onTap: widget.onOpenMcp,
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    _CircleIconButton(
                      tooltip: AppLocalizations.of(context)!.chatInputBarMoreTooltip,
                      icon: Lucide.Plus,
                      active: widget.moreOpen,
                      onTap: widget.onMore,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => RotationTransition(
                          turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          widget.moreOpen ? Lucide.X : Lucide.Plus,
                          key: ValueKey(widget.moreOpen ? 'close' : 'add'),
                          size: 22,
                          color: widget.moreOpen
                              ? theme.colorScheme.primary
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SendButton(
                      enabled: (hasText || hasImages || hasDocs) && !widget.loading,
                      loading: widget.loading,
                      onSend: _handleSend,
                      onStop: widget.loading ? widget.onStop : null,
                      color: theme.colorScheme.primary,
                      icon: Lucide.ArrowUp,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
    this.active = false,
    this.child,
    this.padding,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;
  final Widget? child;
  final double? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = active ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent;
    final fgColor = active ? theme.colorScheme.primary : (isDark ? Colors.white : Colors.black87);

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: const ShapeDecoration(shape: CircleBorder()),
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(padding ?? 10),
            child: child ?? Icon(icon, size: 22, color: fgColor),
          ),
        ),
      ),
    );

    // Avoid Material Tooltip's ticker conflicts on some platforms; use semantics-only tooltip
    return tooltip == null ? button : Semantics(tooltip: tooltip!, child: button);
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.onSend,
    required this.color,
    required this.icon,
    this.loading = false,
    this.onStop,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (enabled || loading) ? color : (isDark ? Colors.white12 : Colors.grey.shade300);
    final fg = (enabled || loading) ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white70 : Colors.grey.shade600);

    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? onStop : (enabled ? onSend : null),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: loading
                ? SvgPicture.asset(
                    key: const ValueKey('stop'),
                    'assets/icons/stop.svg',
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  )
                : Icon(icon, key: const ValueKey('send'), size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}
