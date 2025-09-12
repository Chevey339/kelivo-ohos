import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../../providers/mcp_provider.dart';
import '../chat/chat_service.dart';
import '../../providers/assistant_provider.dart';

class McpToolService extends ChangeNotifier {
  McpToolService();

  List<McpToolConfig> listAvailableToolsForConversation(
    McpProvider mcpProvider,
    ChatService chat,
    String conversationId,
  ) {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  List<McpToolConfig> listAvailableToolsForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants,
    String? assistantId,
  ) {
    final a = (assistantId != null) ? assistants.getById(assistantId) : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  Future<mcp.CallToolResult?> callToolForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
      required String conversationId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
  }) async {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    if (selected.isEmpty) return null;

    // Find a server that has this tool enabled
    for (final s in mcpProvider.connectedServers.where((s) => selected.contains(s.id))) {
      final has = s.tools.any((t) => t.enabled && t.name == toolName);
      if (has) {
        return await mcpProvider.callTool(s.id, toolName, arguments);
      }
    }
    return null;
  }

  // Convenience: call tool and flatten result contents to plain text
  Future<String> callToolTextForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
      required String conversationId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
  }) async {
    final res = await callToolForConversation(
      mcpProvider,
      chat,
      conversationId: conversationId,
      toolName: toolName,
      arguments: arguments,
    );
    if (res == null) return '';
    final buf = StringBuffer();
    // Be liberal in what we accept: many servers return different content variants.
    for (final c in res.content) {
      try {
        // Known types from mcp_client
        if (c is mcp.TextContent) {
          if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
          continue;
        }
        if (c is mcp.ResourceContent) {
          final t = (c.text ?? '').toString();
          if (t.trim().isNotEmpty) {
            buf.writeln(t);
          } else {
            final uri = (c.uri).toString();
            if (uri.isNotEmpty) buf.writeln('resource: $uri');
          }
          continue;
        }
        if (c is mcp.ImageContent) {
          final url = (c.url ?? '').toString();
          final mime = (c.mimeType ?? '').toString();
          buf.writeln('[image:${url.isNotEmpty ? url : mime}]');
          continue;
        }
        // Try dynamic accessors that some adapters may expose
        final dyn = c as dynamic;
        try {
          final txt = (dyn.text as String?);
          if (txt != null && txt.trim().isNotEmpty) {
            buf.writeln(txt);
            continue;
          }
        } catch (_) {}
        try {
          final uri = (dyn.uri as String?);
          if (uri != null && uri.isNotEmpty) {
            buf.writeln('resource: $uri');
            continue;
          }
        } catch (_) {}
        // As a last resort, serialize to JSON if available
        try {
          final json = (dyn.toJson as dynamic).call();
          buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
          continue;
        } catch (_) {}
        // Fallback to a readable string (avoid Instance of ... when possible)
        final s = c.toString();
        if (!s.startsWith('Instance of')) buf.writeln(s);
      } catch (_) {
        // ignore single content parse errors and continue
      }
    }
    return buf.toString().trim();
  }

  Future<String> callToolTextForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
      required String? assistantId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
  }) async {
    // try servers selected for the assistant
    final a = (assistantId != null) ? assistants.getById(assistantId) : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    if (selected.isEmpty) return '';
    for (final s in mcpProvider.connectedServers.where((s) => selected.contains(s.id))) {
      final has = s.tools.any((t) => t.enabled && t.name == toolName);
      if (has) {
        final res = await mcpProvider.callTool(s.id, toolName, arguments);
        if (res == null) continue;
        final buf = StringBuffer();
        for (final c in res.content) {
          try {
            if (c is mcp.TextContent) {
              if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
              continue;
            }
            if (c is mcp.ResourceContent) {
              final t = (c.text ?? '').toString();
              if (t.trim().isNotEmpty) {
                buf.writeln(t);
              } else {
                final uri = (c.uri).toString();
                if (uri.isNotEmpty) buf.writeln('resource: $uri');
              }
              continue;
            }
            if (c is mcp.ImageContent) {
              final url = (c.url ?? '').toString();
              final mime = (c.mimeType ?? '').toString();
              buf.writeln('[image:${url.isNotEmpty ? url : mime}]');
              continue;
            }
            final dyn = c as dynamic;
            try {
              final txt = (dyn.text as String?);
              if (txt != null && txt.trim().isNotEmpty) {
                buf.writeln(txt);
                continue;
              }
            } catch (_) {}
            try {
              final uri = (dyn.uri as String?);
              if (uri != null && uri.isNotEmpty) {
                buf.writeln('resource: $uri');
                continue;
              }
            } catch (_) {}
            try {
              final json = (dyn.toJson as dynamic).call();
              buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
              continue;
            } catch (_) {}
            final s = c.toString();
            if (!s.startsWith('Instance of')) buf.writeln(s);
          } catch (_) {}
        }
        return buf.toString().trim();
      }
    }
    return '';
  }
}
