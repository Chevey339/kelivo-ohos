import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark-reasonable.dart';
import 'package:markdown/markdown.dart' as md;
import '../../icons/lucide_adapter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:convert';
import '../../utils/sandbox_path_resolver.dart';
import '../../features/chat/pages/image_viewer_page.dart';

/// flutter_markdown with custom code block highlight and inline code styling.
class MarkdownWithCodeHighlight extends StatelessWidget {
  const MarkdownWithCodeHighlight({
    super.key,
    required this.text,
    this.onCitationTap,
  });

  final String text;
  final void Function(String id)? onCitationTap;

  @override
  Widget build(BuildContext context) {
    try {
      final normalized = _preprocessFences(text);
      
      return MarkdownBody(
        data: normalized,
        selectable: true,
        styleSheet: _buildStyleSheet(context),
        extensionSet: md.ExtensionSet.gitHubFlavored,
        onTapLink: (text, href, title) => _handleLinkTap(context, href ?? '', text),
        imageBuilder: (uri, title, alt) => _buildImageWidget(context, uri.toString()),
        // 移除所有自定义builders，使用默认渲染
      );
    } catch (e) {
      // 如果渲染失败，显示纯文本
      return SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 15.5,
          height: 1.55,
        ),
      );
    }
  }

  Widget _buildImageWidget(BuildContext context, String url) {
    try {
        final provider = _imageProviderFor(url);
        return GestureDetector(
          onTap: () {
          Navigator.of(context).push(PageRouteBuilder(
            pageBuilder: (_, __, ___) => ImageViewerPage(images: [url], initialIndex: 0),
            transitionDuration: const Duration(milliseconds: 300),
            ));
          },
        child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Icon(Icons.broken_image),
                ),
        ),
      );
    } catch (e) {
      return const Icon(Icons.broken_image);
    }
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    try {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final cs = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      
      final baseTextStyle = textTheme.bodyMedium?.copyWith(
        fontSize: 15.5,
        height: 1.55,
        letterSpacing: _isZh(context) ? 0.0 : 0.05,
        color: cs.onSurface,
      );

      return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: baseTextStyle,
        h1: baseTextStyle?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
        h2: baseTextStyle?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        h3: baseTextStyle?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        h4: baseTextStyle?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
        h5: baseTextStyle?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
        h6: baseTextStyle?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
        code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.4,
          backgroundColor: isDark ? Colors.white12 : const Color(0xFFF1F3F5),
          color: cs.onSurface,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: baseTextStyle?.copyWith(
          fontStyle: FontStyle.italic,
          color: cs.onSurface.withOpacity(0.8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: cs.primary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.all(12),
        a: TextStyle(color: cs.primary),
        em: const TextStyle(fontStyle: FontStyle.italic),
        strong: const TextStyle(fontWeight: FontWeight.bold),
      );
    } catch (e) {
      // 如果样式构建失败，返回基础样式
      return MarkdownStyleSheet.fromTheme(Theme.of(context));
    }
  }

  static bool _isZh(BuildContext context) {
    try {
      return Localizations.localeOf(context).languageCode == 'zh';
    } catch (e) {
      return false;
    }
  }

  static String _preprocessFences(String input) {
    // Normalize newlines to simplify regex handling
    var out = input.replaceAll('\r\n', '\n');

    // 1) Move fenced code from list lines to the next line: "* ```lang" -> "*\n```lang"
    final bulletFence = RegExp(r"^(\s*(?:[*+-]|\d+\.)\s+)```([^\s`]*)\s*$", multiLine: true);
    out = out.replaceAllMapped(bulletFence, (m) => "${m[1]}\n```${m[2]}" );

    // 2) Dedent opening fences: leading spaces before ```lang
    final dedentOpen = RegExp(r"^[ \t]+```([^\n`]*)\s*$", multiLine: true);
    out = out.replaceAllMapped(dedentOpen, (m) => "```${m[1]}" );

    // 3) Dedent closing fences: leading spaces before ```
    final dedentClose = RegExp(r"^[ \t]+```\s*$", multiLine: true);
    out = out.replaceAllMapped(dedentClose, (m) => "```" );

    // 4) Ensure closing fences are on their own line: transform "} ```" or "}```" into "}\n```"
    final inlineClosing = RegExp(r"([^\r\n`])```(?=\s*(?:\r?\n|$))");
    out = out.replaceAllMapped(inlineClosing, (m) => "${m[1]}\n```");

    // 5) Disambiguate Setext vs HR after label-value lines:
    // If a line of only dashes follows a bold label line (e.g., "**作者:** 张三"),
    // insert a blank line so it's treated as an HR, not a Setext heading underline.
    final labelThenDash = RegExp(r"^(\*\*[^\n*]+\*\*.*)\n(\s*-{3,}\s*$)", multiLine: true);
    out = out.replaceAllMapped(labelThenDash, (m) => "${m[1]}\n\n${m[2]}");

    // 6) Allow ATX headings starting with enumerations like "## 1.引言" or "## 1. 引言"
    // Insert a zero-width non-joiner after the dot to prevent list parsing without changing visual text.
    final atxEnum = RegExp(r"^(\s{0,3}#{1,6}\s+\d+)\.(\s*)(\S)", multiLine: true);
    out = out.replaceAllMapped(atxEnum, (m) => "${m[1]}.\u200C${m[2]}${m[3]}");

    // 7) Auto-close an unmatched opening code fence at EOF
    final fenceAtBol = RegExp(r"^\s*```", multiLine: true);
    final count = fenceAtBol.allMatches(out).length;
    if (count % 2 == 1) {
      if (!out.endsWith('\n')) out += '\n';
      out += '```';
    }

    return out;
  }

  static String _softBreakInline(String input) {
    // Insert zero-width break for inline code segments with long tokens.
    if (input.length < 60) return input;
    final buf = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      buf.write(input[i]);
      if ((i + 1) % 24 == 0) buf.write('\u200B');
    }
    return buf.toString();
  }

  Future<void> _handleLinkTap(BuildContext context, String url, String linkText) async {
    // Special handling for citation links: [citation](index:id)
    if (linkText.toLowerCase() == 'citation') {
      final parts = url.split(':');
      if (parts.length == 2) {
        final id = parts[1].trim();
        if (onCitationTap != null && id.isNotEmpty) {
          onCitationTap!(id);
          return;
        }
      }
    }
    
    Uri uri;
    try {
      uri = _normalizeUrl(url);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isZh(context) ? '无效链接' : 'Invalid link')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isZh(context) ? '无法打开链接' : 'Cannot open link')),
      );
    }
  }

  Uri _normalizeUrl(String url) {
    var u = url.trim();
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(u)) {
      u = 'https://'+u;
    }
    return Uri.parse(u);
  }

  static List<String> _extractImageUrls(String md) {
    final re = RegExp(r"!\[[^\]]*\]\(([^)\s]+)\)");
    return re
        .allMatches(md)
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static ImageProvider _imageProviderFor(String src) {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return NetworkImage(src);
    }
    if (src.startsWith('data:')) {
      try {
        final base64Marker = 'base64,';
        final idx = src.indexOf(base64Marker);
        if (idx != -1) {
          final b64 = src.substring(idx + base64Marker.length);
          return MemoryImage(base64Decode(b64));
        }
      } catch (_) {}
    }
    final fixed = SandboxPathResolver.fix(src);
    return FileImage(File(fixed));
  }
}

// 移除了自定义builders以避免兼容性问题，使用默认的markdown渲染

