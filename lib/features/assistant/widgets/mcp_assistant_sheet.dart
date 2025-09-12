import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../theme/design_tokens.dart';

Future<void> showAssistantMcpSheet(BuildContext context, {required String assistantId}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AssistantMcpSheet(assistantId: assistantId),
  );
}

class _AssistantMcpSheet extends StatelessWidget {
  const _AssistantMcpSheet({required this.assistantId});
  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final mcp = context.watch<McpProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.getById(assistantId)!;

    final selected = a.mcpServerIds.toSet();
    final servers = mcp.servers.where((s) => mcp.statusFor(s.id) == McpStatus.connected).toList();

    Widget tag(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withOpacity(0.35)),
          ),
          child: Text(text, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
        );

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.45,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mcpAssistantSheetTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.mcpAssistantSheetSubtitle,
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                  if (servers.isNotEmpty) ...[
                    TextButton.icon(
                      onPressed: () async {
                        final ids = servers.map((e) => e.id).toList(growable: false);
                        final next = a.copyWith(mcpServerIds: ids);
                        await context.read<AssistantProvider>().updateAssistant(next);
                      },
                      icon: Icon(Lucide.Check, size: 16, color: cs.primary),
                      label: Text(l10n.mcpAssistantSheetSelectAll),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () async {
                        final next = a.copyWith(mcpServerIds: const <String>[]);
                        await context.read<AssistantProvider>().updateAssistant(next);
                      },
                      icon: Icon(Lucide.X, size: 16, color: cs.primary),
                      label: Text(l10n.mcpAssistantSheetClearAll),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: servers.isEmpty
                    ? Center(
                        child: Text(
                          l10n.assistantEditMcpNoServersMessage,
                          style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemBuilder: (context, index) {
                          final s = servers[index];
                          final tools = s.tools;
                          final enabledTools = tools.where((t) => t.enabled).length;
                          final isSelected = selected.contains(s.id);
                          final bg = isSelected
                              ? cs.primary.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.10)
                              : (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : cs.surface);
                          final borderColor = isSelected ? cs.primary.withOpacity(0.45) : cs.outlineVariant.withOpacity(0.25);

                          return Material(
                            color: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              onTap: () async {
                                final set = a.mcpServerIds.toSet();
                                if (isSelected) set.remove(s.id); else set.add(s.id);
                                await context.read<AssistantProvider>().updateAssistant(a.copyWith(mcpServerIds: set.toList()));
                              },
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                  boxShadow: Theme.of(context).brightness == Brightness.dark ? [] : AppShadows.soft,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(Lucide.Terminal, size: 20, color: cs.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    s.name,
                                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                tag(l10n.assistantEditMcpConnectedTag),
                                                tag(l10n.assistantEditMcpToolsCountTag(enabledTools.toString(), tools.length.toString())),
                                                tag(s.transport == McpTransportType.sse ? 'SSE' : 'HTTP'),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Switch(
                                        value: isSelected,
                                        onChanged: (v) async {
                                          final set = a.mcpServerIds.toSet();
                                          if (v) set.add(s.id); else set.remove(s.id);
                                          await context.read<AssistantProvider>().updateAssistant(a.copyWith(mcpServerIds: set.toList()));
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: servers.length,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
