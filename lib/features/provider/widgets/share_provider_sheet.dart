import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import '../../../l10n/app_localizations.dart';

String encodeProviderConfig(ProviderConfig cfg) {
  String type;
  final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
  switch (kind) {
    case ProviderKind.google:
      type = 'google';
      break;
    case ProviderKind.claude:
      type = 'claude';
      break;
    case ProviderKind.openai:
    default:
      type = 'openai-compat';
  }
  final map = <String, dynamic>{
    'type': type,
    'name': cfg.name,
    'apiKey': cfg.apiKey,
  };
  if (kind != ProviderKind.google) {
    map['baseUrl'] = cfg.baseUrl;
  }
  final jsonStr = jsonEncode(map);
  final b64 = base64Encode(utf8.encode(jsonStr));
  return 'ai-provider:v1:$b64';
}

Future<void> showShareProviderSheet(BuildContext context, String providerKey) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final cfg = settings.providerConfigs[providerKey] ?? settings.getProviderConfig(providerKey);
  final code = encodeProviderConfig(cfg);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      final controller = TextEditingController(text: code);
      return SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.6,
          minChildSize: 0.4,
          builder: (c, sc) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
                ),
                const SizedBox(height: 12),
                Text(l10n.shareProviderSheetTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(l10n.shareProviderSheetDescription),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    controller: sc,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            // Always use white background to ensure visibility in dark mode
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                          ),
                          child: PrettyQr(
                            data: code,
                            size: 180,
                            roundEdges: true,
                            errorCorrectLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Show non-selectable text; use the copy button to copy
                      Text(
                        code,
                        style: const TextStyle(fontSize: 13.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Lucide.Copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: controller.text));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.shareProviderSheetCopiedMessage)));
                        },
                        label: Text(l10n.shareProviderSheetCopyButton),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Lucide.Share2, size: 18),
                        onPressed: () async {
                          await Share.share(code, subject: 'AI Provider');
                        },
                        label: Text(l10n.shareProviderSheetShareButton),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
