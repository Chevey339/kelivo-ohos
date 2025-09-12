import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';
import '../../../l10n/app_localizations.dart';

// Shared helpers
String _guessImageMime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

String? _modelDisplayName(BuildContext context, ChatMessage msg) {
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

String _getRoleName(BuildContext context, ChatMessage msg) {
  final l10n = AppLocalizations.of(context)!;
  if (msg.role == 'user') {
    final userProvider = context.read<UserProvider>();
    return userProvider.name;
  } else if (msg.role == 'assistant') {
    // Check if using assistant  
    final assistant = context.read<AssistantProvider>().currentAssistant;
    if (assistant != null && assistant.useAssistantAvatar == true && assistant.name.trim().isNotEmpty) {
      return assistant.name.trim();
    }
    // Otherwise use model display name
    final modelName = _modelDisplayName(context, msg);
    if (modelName != null && modelName.isNotEmpty) {
      return modelName;
    }
    return l10n.messageExportSheetAssistant;
  }
  return msg.role;
}

_Parsed _parseContent(String raw) {
  final imgRe = RegExp(r"\\[image:(.+?)\\]");
  final fileRe = RegExp(r"\\[file:(.+?)\\|(.+?)\\|(.+?)\\]");
  final images = <String>[];
  final docs = <_DocRef>[];
  final buffer = StringBuffer();
  int idx = 0;
  while (idx < raw.length) {
    final m1 = imgRe.matchAsPrefix(raw, idx);
    final m2 = fileRe.matchAsPrefix(raw, idx);
    if (m1 != null) {
      final p = m1.group(1)?.trim();
      if (p != null && p.isNotEmpty) images.add(p);
      idx = m1.end;
      continue;
    }
    if (m2 != null) {
      final path = m2.group(1)?.trim() ?? '';
      final name = m2.group(2)?.trim() ?? 'file';
      final mime = m2.group(3)?.trim() ?? 'text/plain';
      docs.add(_DocRef(path: path, fileName: name, mime: mime));
      idx = m2.end;
      continue;
    }
    buffer.write(raw[idx]);
    idx++;
  }
  return _Parsed(buffer.toString().trim(), images, docs);
}

String _softBreakMd(String input) {
  // Insert zero-width break in very long tokens outside fenced code blocks.
  final lines = input.split('\n');
  final out = StringBuffer();
  bool inFence = false;
  for (final line in lines) {
    String l = line;
    final trimmed = l.trimLeft();
    if (trimmed.startsWith('```')) {
      inFence = !inFence; // toggle on fence lines
      out.writeln(l);
      continue;
    }
    if (!inFence) {
      l = l.replaceAllMapped(RegExp(r'(\S{60,})'), (m) {
        final s = m.group(1)!;
        final buf = StringBuffer();
        for (int i = 0; i < s.length; i++) {
          buf.write(s[i]);
          if ((i + 1) % 20 == 0) buf.write('\u200B');
        }
        return buf.toString();
      });
    }
    out.writeln(l);
  }
  return out.toString();
}

Future<File?> _renderAndSaveMessageImage(BuildContext context, ChatMessage message) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final l10n = AppLocalizations.of(context)!;
  final content = _ExportedMessageCard(
    message: message,
    title: context.read<ChatService>().getConversation(message.conversationId)?.title ?? l10n.messageExportSheetDefaultTitle,
    cs: cs,
    chatFontScale: settings.chatFontScale,
  );
  return _renderWidgetDirectly(context, content);
}

Future<File?> _renderAndSaveChatImage(BuildContext context, Conversation conversation, List<ChatMessage> messages) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final l10n = AppLocalizations.of(context)!;
  final content = _ExportedChatImage(
    conversationTitle: (conversation.title.trim().isNotEmpty) ? conversation.title : l10n.messageExportSheetDefaultTitle,
    cs: cs,
    chatFontScale: settings.chatFontScale,
    messages: messages,
  );
  return _renderWidgetDirectly(context, content);
}

// New direct rendering approach without pagination
Future<File?> _renderWidgetDirectly(
  BuildContext context,
  Widget content, {
  double width = 480, // 宽度*3
  double pixelRatio = 3.0,
}) async {
  final overlay = Overlay.of(context);
  if (overlay == null) return null;
  
  final boundaryKey = GlobalKey();
  final completer = Completer<void>();
  
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (ctx) {
    // Schedule the completion after multiple frames to ensure rendering
    int frameCount = 0;
    void scheduleCompletion() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        frameCount++;
        if (frameCount < 3) {
          // Wait for 3 frames to ensure complete rendering
          scheduleCompletion();
        } else if (!completer.isCompleted) {
          completer.complete();
        }
      });
    }
    scheduleCompletion();
    
    return Positioned(
      left: -10000, // Position far offscreen
      top: -10000,
      child: RepaintBoundary(
        key: boundaryKey,
        child: Container(
          width: width,
          color: Theme.of(ctx).colorScheme.background,
          child: Material(
            type: MaterialType.transparency,
            child: content,
          ),
        ),
      ),
    );
  });
  
  overlay.insert(entry);
  
  try {
    // Wait for the widget to be ready
    await completer.future;
    // Additional delay to ensure everything is painted
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    
    // Try to capture the image with retries
    ui.Image? image;
    for (int retry = 0; retry < 10; retry++) {
      try {
        image = await boundary.toImage(pixelRatio: pixelRatio);
        break;
      } catch (e) {
        if (retry == 9) {
          print('Failed to capture image after 10 retries: $e');
          return null;
        }
        // Wait before retrying
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    
    if (image == null) return null;
    
    // Convert to PNG
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    
    // Save to file
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/chat-export-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    
    return file;
  } finally {
    entry.remove();
  }
}

// Keep the old paginated version for reference but renamed
Future<File?> _renderAndSavePagedOld(
  BuildContext context,
  Widget content, {
  double width = 480, // 宽度*3
  double pageHeight = 1600,
  double pixelRatio = 3.0,
}) async {
  final overlay = Overlay.of(context);
  if (overlay == null) return null;
  final boundaryKey = GlobalKey();
  final contentKey = GlobalKey();
  final controller = ScrollController();
  
  // Create a completer to signal when the widget is ready
  final completer = Completer<void>();
  
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (ctx) {
    // Schedule a callback after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    return Material(
      type: MaterialType.transparency,
      child: IgnorePointer(
        ignoring: true,
        child: Opacity(
          opacity: 0.001,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: width,
                height: pageHeight,
                child: SingleChildScrollView(
                  controller: controller,
                  child: KeyedSubtree(key: contentKey, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  });
  
  overlay.insert(entry);
  
  try {
    // Wait for the initial frame to be ready
    await completer.future;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    
    final contentSize = contentKey.currentContext?.size;
    if (contentSize == null) return null;
    
    final totalHeight = contentSize.height;
    final pages = (totalHeight / pageHeight).ceil().clamp(1, 200);
    final images = <ui.Image>[];
    final drawHeights = <int>[];
    
    for (int i = 0; i < pages; i++) {
      final offset = i * pageHeight;
      controller.jumpTo(offset);
      
      // Wait for the scroll to complete and the new content to render
      await Future<void>.delayed(const Duration(milliseconds: 200));
      
      // Force a frame
      SchedulerBinding.instance.scheduleFrameCallback((_) {});
      await SchedulerBinding.instance.endOfFrame;
      
      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) break;
      
      // Capture with retry logic
      ui.Image? img;
      for (int retry = 0; retry < 5; retry++) {
        try {
          img = await boundary.toImage(pixelRatio: pixelRatio);
          break;
        } catch (e) {
          // Wait and retry
          await Future<void>.delayed(const Duration(milliseconds: 100));
          SchedulerBinding.instance.scheduleFrameCallback((_) {});
          await SchedulerBinding.instance.endOfFrame;
        }
      }
      
      if (img == null) continue;
      
      images.add(img);
      final drawn = drawHeights.fold<int>(0, (a, b) => a + b);
      final remaining = (totalHeight * pixelRatio).round() - drawn;
      final h = remaining <= 0 ? 0 : math.min(img.height, remaining);
      drawHeights.add(h);
    }
    
    if (images.isEmpty) return null;
    
    final composedHeightPx = drawHeights.fold<int>(0, (a, b) => a + b);
    final widthPx = (width * pixelRatio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    double y = 0;
    
    for (int i = 0; i < images.length; i++) {
      final ui.Image page = images[i];
      final int drawH = drawHeights[i];
      if (drawH <= 0) break;
      final src = Rect.fromLTWH(0, 0, page.width.toDouble(), drawH.toDouble());
      final dst = Rect.fromLTWH(0, y, widthPx.toDouble(), drawH.toDouble());
      canvas.drawImageRect(page, src, dst, Paint());
      y += drawH.toDouble();
    }
    
    final pic = recorder.endRecording();
    final img = await pic.toImage(widthPx, composedHeightPx);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/chat-export-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file;
  } finally {
    entry.remove();
  }
}


Future<void> showMessageExportSheet(BuildContext context, ChatMessage message) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: _ExportSheet(message: message),
      );
    },
  );
}

Future<void> showChatExportSheet(
  BuildContext context, {
  required Conversation conversation,
  required List<ChatMessage> selectedMessages,
}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: _BatchExportSheet(conversation: conversation, messages: selectedMessages),
      );
    },
  );
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.message});
  final ChatMessage message;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _BatchExportSheet extends StatefulWidget {
  const _BatchExportSheet({required this.conversation, required this.messages});
  final Conversation conversation;
  final List<ChatMessage> messages;

  @override
  State<_BatchExportSheet> createState() => _BatchExportSheetState();
}

class _BatchExportSheetState extends State<_BatchExportSheet> {
  final DraggableScrollableController _ctrl = DraggableScrollableController();
  bool _exporting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTime(BuildContext context, DateTime time) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = DateFormat(l10n.messageExportSheetDateTimeWithSecondsPattern);
    return fmt.format(time);
  }

  Future<void> _onExportMarkdown() async {
    if (_exporting) return;
    
    // Dismiss dialog immediately
    if (mounted) Navigator.of(context).maybePop();
    
    setState(() => _exporting = true);
    try {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExporting)),
        );
      }
      final ctx = context;
      final conv = widget.conversation;
      final l10n = AppLocalizations.of(ctx)!;
      final title = (conv.title.trim().isNotEmpty) ? conv.title : l10n.messageExportSheetDefaultTitle;
      final buf = StringBuffer();
      buf.writeln('# $title');
      buf.writeln('');
      for (final msg in widget.messages) {
        final time = _formatTime(ctx, msg.timestamp);
        buf.writeln('> $time · ${_getRoleName(ctx, msg)}');
        buf.writeln('');
        final parsed = _parseContent(msg.content);
        if (parsed.text.isNotEmpty) {
          buf.writeln(parsed.text);
          buf.writeln('');
        }
        for (final p in parsed.images) {
          final fixed = SandboxPathResolver.fix(p);
          try {
            final f = File(fixed);
            if (await f.exists()) {
              final bytes = await f.readAsBytes();
              final b64 = base64Encode(bytes);
              final mime = _guessImageMime(fixed);
              buf.writeln('![](data:$mime;base64,$b64)');
            } else {
              buf.writeln('![image]($fixed)');
            }
          } catch (_) {
            buf.writeln('![image]($fixed)');
          }
          buf.writeln('');
        }
        for (final d in parsed.docs) {
          buf.writeln('- ${d.fileName}  `(${d.mime})`');
        }
        buf.writeln('\n---\n');
      }

      final tmp = await getTemporaryDirectory();
      final filename = 'chat-export-${DateTime.now().millisecondsSinceEpoch}.md';
      final file = File('${tmp.path}/$filename');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/markdown', name: filename)], text: title);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExportFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _onExportImage() async {
    if (_exporting) return;
    
    // Dismiss dialog immediately
    if (mounted) Navigator.of(context).maybePop();
    
    setState(() => _exporting = true);
    try {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExporting)),
        );
      }
      final file = await _renderAndSaveChatImage(context, widget.conversation, widget.messages);
      if (file == null) throw 'render error';
      final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'chat.png';
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png', name: filename)]);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExportFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      controller: _ctrl,
      expand: false,
      initialChildSize: 0.42,
      maxChildSize: 0.42,
      minChildSize: 0.3,
      builder: (c, sc) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
            ),
            const SizedBox(height: 10),
            Text(l10n.messageExportSheetFormatTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                controller: sc,
                children: [
                  _ExportOptionTile(
                    icon: Lucide.BookOpenText,
                    title: l10n.messageExportSheetMarkdown,
                    subtitle: l10n.messageExportSheetBatchMarkdownSubtitle,
                    onTap: _exporting ? null : () {
                      _onExportMarkdown();
                    },
                  ),
                  _ExportOptionTile(
                    icon: Lucide.Image,
                    title: l10n.messageExportSheetExportImage,
                    subtitle: l10n.messageExportSheetBatchExportImageSubtitle,
                    onTap: _exporting ? null : () {
                      _onExportImage();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSheetState extends State<_ExportSheet> {
  final DraggableScrollableController _ctrl = DraggableScrollableController();
  bool _exporting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTime(BuildContext context, DateTime time) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = DateFormat(l10n.messageExportSheetDateTimeWithSecondsPattern);
    return fmt.format(time);
  }

  Future<void> _onExportMarkdown() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final ctx = context;
      final msg = widget.message;
      final service = ctx.read<ChatService>();
      final convo = service.getConversation(msg.conversationId);
      final l10n = AppLocalizations.of(ctx)!;
      final title = ((convo?.title ?? '').trim().isNotEmpty) ? (convo?.title ?? '') : l10n.messageExportSheetDefaultTitle;
      final time = _formatTime(ctx, msg.timestamp);

      final parsed = _parseContent(msg.content);

      final buf = StringBuffer();
      buf.writeln('# $title');
      buf.writeln('');
      buf.writeln('> $time · ${_getRoleName(ctx, msg)}');
      buf.writeln('');
      if (parsed.text.isNotEmpty) {
        buf.writeln(parsed.text);
        buf.writeln('');
      }
      // Inline images as data URLs where possible
      for (final p in parsed.images) {
        final fixed = SandboxPathResolver.fix(p);
        try {
          final f = File(fixed);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            final b64 = base64Encode(bytes);
            final mime = _guessImageMime(fixed);
            buf.writeln('![](data:$mime;base64,$b64)');
          } else {
            buf.writeln('![image]($fixed)');
          }
        } catch (_) {
          buf.writeln('![image]($fixed)');
        }
        buf.writeln('');
      }
      // List file attachments as links (path only)
      for (final d in parsed.docs) {
        buf.writeln('- ${d.fileName}  `(${d.mime})`');
      }

      final tmp = await getTemporaryDirectory();
      final filename = 'chat-export-${DateTime.now().millisecondsSinceEpoch}.md';
      final file = File('${tmp.path}/$filename');
      await file.writeAsString(buf.toString());

      await Share.shareXFiles([XFile(file.path, mimeType: 'text/markdown', name: filename)], text: title);

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExportedAs(filename))),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExportFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _onExportImage() async {
    if (_exporting) return;
    
    // Dismiss dialog immediately
    if (mounted) Navigator.of(context).maybePop();
    
    setState(() => _exporting = true);
    try {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExporting)),
        );
      }
      final file = await _renderAndSaveMessageImage(context, widget.message);
      if (file == null) throw 'render error';
      final filename = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'chat.png';
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png', name: filename)]);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.messageExportSheetExportFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      controller: _ctrl,
      expand: false,
      initialChildSize: 0.42,
      maxChildSize: 0.42,
      minChildSize: 0.3,
      builder: (c, sc) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
            ),
            const SizedBox(height: 10),
            Text(l10n.messageExportSheetFormatTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                controller: sc,
                children: [
                  _ExportOptionTile(
                    icon: Lucide.BookOpenText,
                    title: l10n.messageExportSheetMarkdown,
                    subtitle: l10n.messageExportSheetSingleMarkdownSubtitle,
                    onTap: _exporting ? null : () {
                      _onExportMarkdown();
                    },
                  ),
                  _ExportOptionTile(
                    icon: Lucide.Image,
                    title: l10n.messageExportSheetExportImage,
                    subtitle: l10n.messageExportSheetSingleExportImageSubtitle,
                    onTap: _exporting ? null : () {
                      _onExportImage();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // shared widgets and helpers moved to top-level
}

class _ExportedMessageCard extends StatelessWidget {
  const _ExportedMessageCard({
    required this.message,
    required this.title,
    required this.cs,
    required this.chatFontScale,
  });
  final ChatMessage message;
  final String title;
  final ColorScheme cs;
  final double chatFontScale;

  @override
  Widget build(BuildContext context) {
    final isAssistant = message.role == 'assistant';
    final headerFg = cs.onSurface;
    final headerBg = cs.surface;
    final bubbleBg = isAssistant ? cs.surfaceVariant.withOpacity(0.6) : cs.primary.withOpacity(0.08);
    final bubbleFg = cs.onSurface;
    final time = DateFormat('yyyy-MM-dd HH:mm').format(message.timestamp);

    final parsed = _parseContent(message.content);
    final mdText = StringBuffer();
    if (parsed.text.isNotEmpty) mdText.writeln(_softBreakMd(parsed.text));
    for (final p in parsed.images) {
      mdText.writeln('\n![](${SandboxPathResolver.fix(p)})\n');
    }
    for (final d in parsed.docs) {
      mdText.writeln('\n- ${d.fileName}  `(${d.mime})`');
    }

    final Widget contentWidget = (mdText.toString().trim().isNotEmpty)
        ? MarkdownWithCodeHighlight(text: mdText.toString())
        : Text('—', style: TextStyle(color: bubbleFg.withOpacity(0.5)));

    return MediaQuery(
      // Respect chat font scale for export rendering
      data: MediaQuery.of(context).copyWith(
        textScaleFactor: MediaQuery.of(context).textScaleFactor * chatFontScale,
      ),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.background,
          borderRadius: BorderRadius.circular(16),
          // removed outer border per UX
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Lucide.MessageSquare, size: 18, color: headerFg.withOpacity(0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: headerFg.withOpacity(0.95)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(time, style: TextStyle(fontSize: 12, color: headerFg.withOpacity(0.6))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getRoleName(context, message),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: bubbleFg.withOpacity(0.8)),
                          ),
                          const SizedBox(width: 8),
                          Text(time, style: TextStyle(fontSize: 12, color: bubbleFg.withOpacity(0.6))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      contentWidget,
                    ],
                  ),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  _Parsed _parseContent(String raw) {
    final imgRe = RegExp(r"\[image:(.+?)\]");
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    final images = <String>[];
    final docs = <_DocRef>[];
    final buffer = StringBuffer();
    int idx = 0;
    while (idx < raw.length) {
      final m1 = imgRe.matchAsPrefix(raw, idx);
      final m2 = fileRe.matchAsPrefix(raw, idx);
      if (m1 != null) {
        final p = m1.group(1)?.trim();
        if (p != null && p.isNotEmpty) images.add(p);
        idx = m1.end;
        continue;
      }
      if (m2 != null) {
        final path = m2.group(1)?.trim() ?? '';
        final name = m2.group(2)?.trim() ?? 'file';
        final mime = m2.group(3)?.trim() ?? 'text/plain';
        docs.add(_DocRef(path: path, fileName: name, mime: mime));
        idx = m2.end;
        continue;
      }
      buffer.write(raw[idx]);
      idx++;
    }
    return _Parsed(buffer.toString().trim(), images, docs);
  }
}

class _ExportedChatImage extends StatelessWidget {
  const _ExportedChatImage({
    required this.conversationTitle,
    required this.cs,
    required this.chatFontScale,
    required this.messages,
  });
  final String conversationTitle;
  final ColorScheme cs;
  final double chatFontScale;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaleFactor: MediaQuery.of(context).textScaleFactor * chatFontScale,
      ),
      child: ClipRect(
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: BorderRadius.circular(16),
            // removed outer border per UX
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Lucide.MessageSquare, size: 18, color: cs.onSurface.withOpacity(0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conversationTitle,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.95)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final m in messages) ...[
              _ExportedBubble(message: m, cs: cs),
              const SizedBox(height: 8),
            ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportedBubble extends StatelessWidget {
  const _ExportedBubble({required this.message, required this.cs});
  final ChatMessage message;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final isAssistant = message.role == 'assistant';
    final bubbleBg = isAssistant ? cs.surfaceVariant.withOpacity(0.6) : cs.primary.withOpacity(0.08);
    final bubbleFg = cs.onSurface;
    final time = DateFormat('yyyy-MM-dd HH:mm').format(message.timestamp);
    final parsed = _parseContent(message.content);
    final mdText = StringBuffer();
    if (parsed.text.isNotEmpty) mdText.writeln(_softBreakMd(parsed.text));
    for (final p in parsed.images) {
      mdText.writeln('\n![](${SandboxPathResolver.fix(p)})\n');
    }
    for (final d in parsed.docs) {
      mdText.writeln('\n- ${d.fileName}  `(${d.mime})`');
    }
    final Widget contentWidget = (mdText.toString().trim().isNotEmpty)
        ? MarkdownWithCodeHighlight(text: mdText.toString())
        : Text('—', style: TextStyle(color: bubbleFg.withOpacity(0.5)));

    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getRoleName(context, message),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: bubbleFg.withOpacity(0.8)),
                    ),
                    const SizedBox(width: 8),
                    Text(time, style: TextStyle(fontSize: 12, color: bubbleFg.withOpacity(0.6))),
                  ],
                ),
                const SizedBox(height: 8),
                contentWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Parsed {
  final String text;
  final List<String> images;
  final List<_DocRef> docs;
  _Parsed(this.text, this.images, this.docs);
}

class _DocRef {
  final String path;
  final String fileName;
  final String mime;
  _DocRef({required this.path, required this.fileName, required this.mime});
}

class _ExportOptionTile extends StatelessWidget {
  const _ExportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: isDark ? cs.primary.withOpacity(0.10) : cs.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.75))),
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
}
