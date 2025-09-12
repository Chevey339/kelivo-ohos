import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../scan/pages/qr_scan_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../l10n/app_localizations.dart';

class _ImportResult {
  final String key;
  final ProviderConfig cfg;
  _ImportResult(this.key, this.cfg);
}

List<_ImportResult> _decodeChatBoxJson(BuildContext context, String s) {
  final settings = context.read<SettingsProvider>();
  final Map<String, dynamic> obj = jsonDecode(s) as Map<String, dynamic>;
  final providers = (obj['providers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ?? {};
  final out = <_ImportResult>[];
  String uniqueKey(String prefix, String display) {
    final existing = settings.providerConfigs.keys.toSet();
    String base = '$prefix - $display';
    if (!existing.contains(base)) return base;
    int i = 2;
    while (existing.contains('$base ($i)')) i++;
    return '$base ($i)';
  }
  // OpenAI
  final openai = providers['openai'] as Map?;
  if (openai != null) {
    final apiKey = (openai['apiKey'] ?? '').toString();
    final baseUrl = (openai['baseUrl'] ?? '').toString();
    final providedName = (openai['name'] ?? '').toString();
    if (apiKey.trim().isNotEmpty) {
      final name = providedName.isNotEmpty ? providedName : 'OpenAI-Compat';
      final key = uniqueKey('OpenAI', name);
      final cfg = ProviderConfig(
        id: key,
        enabled: true,
        name: name,
        apiKey: apiKey,
        baseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://api.openai.com/v1',
        providerType: ProviderKind.openai,
        chatPath: '/chat/completions',
        useResponseApi: false,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      out.add(_ImportResult(key, cfg));
    }
  }
  // Claude
  final claude = providers['claude'] as Map?;
  if (claude != null) {
    final apiKey = (claude['apiKey'] ?? '').toString();
    final baseUrl = (claude['baseUrl'] ?? '').toString();
    final providedName = (claude['name'] ?? '').toString();
    if (apiKey.trim().isNotEmpty) {
      final name = providedName.isNotEmpty ? providedName : 'Claude';
      final key = uniqueKey('Claude', name);
      final cfg = ProviderConfig(
        id: key,
        enabled: true,
        name: name,
        apiKey: apiKey,
        baseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://api.anthropic.com/v1',
        providerType: ProviderKind.claude,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      out.add(_ImportResult(key, cfg));
    }
  }
  // Gemini
  final gemini = providers['gemini'] as Map?;
  if (gemini != null) {
    final apiKey = (gemini['apiKey'] ?? '').toString();
    final providedName = (gemini['name'] ?? '').toString();
    if (apiKey.trim().isNotEmpty) {
      final name = providedName.isNotEmpty ? providedName : 'Gemini';
      final key = uniqueKey('Google', name);
      final cfg = ProviderConfig(
        id: key,
        enabled: true,
        name: name,
        apiKey: apiKey,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        providerType: ProviderKind.google,
        vertexAI: false,
        location: '',
        projectId: '',
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      out.add(_ImportResult(key, cfg));
    }
  }
  return out;
}

_ImportResult _decodeSingle(BuildContext context, String s) {
  if (!s.trim().startsWith('ai-provider:v1:')) {
    throw FormatException('Invalid prefix');
  }
  final base64Str = s.trim().substring('ai-provider:v1:'.length);
  final jsonStr = utf8.decode(base64Decode(base64Str));
  final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
  final type = (obj['type'] ?? '').toString();
  final name = (obj['name'] ?? '').toString();
  final apiKey = (obj['apiKey'] ?? '').toString();
  final baseUrl = (obj['baseUrl'] ?? '').toString();

  final settings = context.read<SettingsProvider>();
  String uniqueKey(String prefix, String display) {
    final existing = settings.providerConfigs.keys.toSet();
    String base = '$prefix - $display';
    if (!existing.contains(base)) return base;
    int i = 2;
    while (existing.contains('$base ($i)')) i++;
    return '$base ($i)';
  }

  if (type == 'openai-compat') {
    final key = uniqueKey('OpenAI', name.isEmpty ? 'OpenAI' : name);
    final cfg = ProviderConfig(
      id: key,
      enabled: true,
      name: name.isEmpty ? 'OpenAI' : name,
      apiKey: apiKey,
      baseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://api.openai.com/v1',
      providerType: ProviderKind.openai,
      chatPath: '/chat/completions',
      useResponseApi: false,
      models: const [],
      modelOverrides: const {},
      proxyEnabled: false,
      proxyHost: '',
      proxyPort: '8080',
      proxyUsername: '',
      proxyPassword: '',
    );
    return _ImportResult(key, cfg);
  } else if (type == 'google') {
    final key = uniqueKey('Google', name.isEmpty ? 'Google' : name);
    final cfg = ProviderConfig(
      id: key,
      enabled: true,
      name: name.isEmpty ? 'Google' : name,
      apiKey: apiKey,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      providerType: ProviderKind.google,
      vertexAI: false,
      location: '',
      projectId: '',
      models: const [],
      modelOverrides: const {},
      proxyEnabled: false,
      proxyHost: '',
      proxyPort: '8080',
      proxyUsername: '',
      proxyPassword: '',
    );
    return _ImportResult(key, cfg);
  } else if (type == 'claude') {
    final key = uniqueKey('Claude', name.isEmpty ? 'Claude' : name);
    final cfg = ProviderConfig(
      id: key,
      enabled: true,
      name: name.isEmpty ? 'Claude' : name,
      apiKey: apiKey,
      baseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://api.anthropic.com/v1',
      providerType: ProviderKind.claude,
      models: const [],
      modelOverrides: const {},
      proxyEnabled: false,
      proxyHost: '',
      proxyPort: '8080',
      proxyUsername: '',
      proxyPassword: '',
    );
    return _ImportResult(key, cfg);
  } else {
    throw FormatException('Unknown provider type: $type');
  }
}

Future<void> showImportProviderSheet(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final controller = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: () {
            final mq = MediaQueryData.fromView(View.of(context));
            return EdgeInsets.fromLTRB(
              16,
              10,
              16,
              10 + mq.padding.bottom + mq.viewInsets.bottom,
            );
          }(),
          child: FractionallySizedBox(
            heightFactor: 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text(l10n.importProviderSheetTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                    IconButton(
                      tooltip: l10n.importProviderSheetScanQrTooltip,
                      icon: const Icon(Lucide.Camera),
                      onPressed: () async {
                        final code = await Navigator.of(ctx).push<String>(
                          MaterialPageRoute(builder: (_) => const QrScanPage()),
                        );
                        if (code == null || code.isEmpty) return;
                        try {
                          final settings = ctx.read<SettingsProvider>();
                          final results = <_ImportResult>[];
                          if (code.startsWith('ai-provider:v1:')) {
                            results.add(_decodeSingle(ctx, code));
                          } else if (code.startsWith('{')) {
                            results.addAll(_decodeChatBoxJson(ctx, code));
                          } else {
                            throw const FormatException('Unsupported format');
                          }
                          for (final r in results) {
                            await settings.setProviderConfig(r.key, r.cfg);
                            final order = List<String>.of(settings.providersOrder);
                            order.remove(r.key);
                            order.insert(0, r.key);
                            await settings.setProvidersOrder(order);
                          }
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.importProviderSheetImportSuccessMessage(results.length))));
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l10n.importProviderSheetImportFailedMessage(e.toString()))));
                        }
                      },
                    ),
                    IconButton(
                      tooltip: l10n.importProviderSheetFromGalleryTooltip,
                      icon: const Icon(Lucide.Image),
                      onPressed: () async {
                        try {
                          // pick from gallery and analyze
                          final picker = ImagePicker();
                          final img = await picker.pickImage(source: ImageSource.gallery);
                          if (img == null) return;
                          final scanner = MobileScannerController();
                          final result = await scanner.analyzeImage(img.path);
                          String? code;
                          if (result != null) {
                            try {
                              // dynamic access to barcodes for compatibility
                              final bars = (result as dynamic).barcodes as List?;
                              if (bars != null) {
                                for (final b in bars) {
                                  final v = (b as dynamic).rawValue as String?;
                                  if (v != null && v.isNotEmpty) { code = v; break; }
                                }
                              }
                            } catch (_) {}
                          }
                          if (code == null || code!.isEmpty) throw 'QR not detected';
                          final settings = ctx.read<SettingsProvider>();
                          final results = <_ImportResult>[];
                          if (code!.startsWith('ai-provider:v1:')) {
                            results.add(_decodeSingle(ctx, code!));
                          } else if (code!.startsWith('{')) {
                            results.addAll(_decodeChatBoxJson(ctx, code!));
                          } else {
                            throw 'Unsupported content';
                          }
                          for (final r in results) {
                            await settings.setProviderConfig(r.key, r.cfg);
                            final order = List<String>.of(settings.providersOrder);
                            order.remove(r.key);
                            order.insert(0, r.key);
                            await settings.setProvidersOrder(order);
                          }
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.importProviderSheetImportSuccessMessage(results.length))));
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l10n.importProviderSheetImportFailedMessage(e.toString()))));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.importProviderSheetDescription),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      TextField(
                        controller: controller,
                        maxLines: 10,
                        decoration: InputDecoration(
                          hintText: l10n.importProviderSheetInputHint,
                          filled: true,
                          fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          FocusScope.of(ctx).unfocus();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).maybePop();
                            }
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(l10n.importProviderSheetCancelButton, style: TextStyle(color: cs.primary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Lucide.Import, size: 18),
                        onPressed: () async {
                          final raw = controller.text.trim();
                          if (raw.isEmpty) return;
                          try {
                            final settings = ctx.read<SettingsProvider>();
                            final results = <_ImportResult>[];
                            // Support multi-line input where each non-empty line is a share string or JSON
                            final lines = raw.split(RegExp(r'\r?\n'))
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();
                            if (lines.length > 1) {
                              for (final line in lines) {
                                try {
                                  if (line.startsWith('ai-provider:v1:')) {
                                    results.add(_decodeSingle(ctx, line));
                                  } else if (line.startsWith('{')) {
                                    results.addAll(_decodeChatBoxJson(ctx, line));
                                  }
                                } catch (_) {
                                  // skip invalid line
                                }
                              }
                              if (results.isEmpty) {
                                throw const FormatException('No valid lines');
                              }
                            } else {
                              final text = lines.first;
                              if (text.startsWith('ai-provider:v1:')) {
                                results.add(_decodeSingle(ctx, text));
                              } else if (text.startsWith('{')) {
                                results.addAll(_decodeChatBoxJson(ctx, text));
                              } else {
                                throw const FormatException('Unsupported format');
                              }
                            }
                            for (final r in results) {
                              await settings.setProviderConfig(r.key, r.cfg);
                              // Put to front
                              final order = List<String>.of(settings.providersOrder);
                              order.remove(r.key);
                              order.insert(0, r.key);
                              await settings.setProvidersOrder(order);
                            }
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.importProviderSheetImportSuccessMessage(results.length))),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(l10n.importProviderSheetImportFailedMessage(e.toString()))),
                            );
                          }
                        },
                        label: Text(l10n.importProviderSheetImportButton),
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
