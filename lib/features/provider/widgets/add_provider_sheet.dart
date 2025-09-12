import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import '../../../l10n/app_localizations.dart';

Future<String?> showAddProviderSheet(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _AddProviderSheet(),
  );
}

class _AddProviderSheet extends StatefulWidget {
  const _AddProviderSheet();
  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  // OpenAI
  bool _openaiEnabled = true;
  late final TextEditingController _openaiName = TextEditingController(text: 'OpenAI');
  late final TextEditingController _openaiKey = TextEditingController();
  late final TextEditingController _openaiBase = TextEditingController(text: 'https://api.openai.com/v1');
  late final TextEditingController _openaiPath = TextEditingController(text: '/chat/completions');
  bool _openaiUseResponse = false;

  // Google
  bool _googleEnabled = true;
  late final TextEditingController _googleName = TextEditingController(text: 'Google');
  late final TextEditingController _googleKey = TextEditingController();
  late final TextEditingController _googleBase = TextEditingController(text: 'https://generativelanguage.googleapis.com/v1beta');
  bool _googleVertex = false;
  late final TextEditingController _googleLocation = TextEditingController(text: 'us-central1');
  late final TextEditingController _googleProject = TextEditingController();
  late final TextEditingController _googleSaJson = TextEditingController();

  // Claude
  bool _claudeEnabled = true;
  late final TextEditingController _claudeName = TextEditingController(text: 'Claude');
  late final TextEditingController _claudeKey = TextEditingController();
  late final TextEditingController _claudeBase = TextEditingController(text: 'https://api.anthropic.com/v1');

  Widget _inputRow({required String label, required TextEditingController controller, String? hint, bool obscure = false, bool enabled = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _switchTile({required String label, required bool value, required ValueChanged<bool> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _openaiForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(label: l10n.addProviderSheetEnabledLabel, value: _openaiEnabled, onChanged: (v) => setState(() => _openaiEnabled = v)),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _openaiName),
        const SizedBox(height: 10),
        _inputRow(label: 'API Key', controller: _openaiKey),
        const SizedBox(height: 10),
        _inputRow(label: 'API Base Url', controller: _openaiBase),
        const SizedBox(height: 10),
        if (!_openaiUseResponse) ...[
          _inputRow(label: l10n.addProviderSheetApiPathLabel, controller: _openaiPath, hint: '/chat/completions'),
          const SizedBox(height: 10),
        ],
        _switchTile(
          label: 'Response API',
          value: _openaiUseResponse,
          onChanged: (v) => setState(() => _openaiUseResponse = v),
        ),
      ],
    );
  }

  Widget _googleForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(label: l10n.addProviderSheetEnabledLabel, value: _googleEnabled, onChanged: (v) => setState(() => _googleEnabled = v)),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _googleName),
        const SizedBox(height: 10),
        if (!_googleVertex) ...[
          _inputRow(label: 'API Key', controller: _googleKey),
          const SizedBox(height: 10),
          _inputRow(label: 'API Base Url', controller: _googleBase),
          const SizedBox(height: 10),
        ],
        _switchTile(
          label: 'Vertex AI',
          value: _googleVertex,
          onChanged: (v) => setState(() => _googleVertex = v),
        ),
        const SizedBox(height: 10),
        if (_googleVertex) ...[
          _inputRow(label: l10n.addProviderSheetVertexAiLocationLabel, controller: _googleLocation, hint: 'us-central1'),
          const SizedBox(height: 10),
          _inputRow(label: l10n.addProviderSheetVertexAiProjectIdLabel, controller: _googleProject),
          const SizedBox(height: 10),
          _multilineRow(
            label: l10n.addProviderSheetVertexAiServiceAccountJsonLabel,
            controller: _googleSaJson,
            hint: '{\n  "type": "service_account", ...\n}',
            actions: [
              TextButton.icon(
                onPressed: _importGoogleServiceAccount,
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.addProviderSheetImportJsonButton),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _claudeForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchTile(label: l10n.addProviderSheetEnabledLabel, value: _claudeEnabled, onChanged: (v) => setState(() => _claudeEnabled = v)),
        const SizedBox(height: 10),
        _inputRow(label: l10n.addProviderSheetNameLabel, controller: _claudeName),
        const SizedBox(height: 10),
        _inputRow(label: 'API Key', controller: _claudeKey),
        const SizedBox(height: 10),
        _inputRow(label: 'API Base Url', controller: _claudeBase),
      ],
    );
  }

  Future<void> _onAdd() async {
    final settings = context.read<SettingsProvider>();
    String uniqueKey(String prefix, String display) {
      final existing = context.read<SettingsProvider>().providerConfigs.keys.toSet();
      String base = (display.toLowerCase() == prefix.toLowerCase()) ? '$prefix - 1' : '$prefix - $display';
      if (!existing.contains(base)) return base;
      int i = 2;
      while (existing.contains('$base ($i)') || existing.contains('$prefix - $display ($i)')) {
        i++;
      }
      // Prefer appending numeric suffix for clarity
      final candidate = (display.toLowerCase() == prefix.toLowerCase()) ? '$prefix - $i' : '$prefix - $display ($i)';
      return candidate;
    }
    final idx = _tab.index;
    String createdKey = '';
    if (idx == 0) {
      final rawName = _openaiName.text.trim();
      final display = rawName.isEmpty ? 'OpenAI' : rawName;
      final keyName = uniqueKey('OpenAI', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _openaiEnabled,
        name: display,
        apiKey: _openaiKey.text.trim(),
        baseUrl: _openaiBase.text.trim().isEmpty ? 'https://api.openai.com/v1' : _openaiBase.text.trim(),
        providerType: ProviderKind.openai,  // Explicitly set as OpenAI type
        chatPath: _openaiUseResponse ? null : (_openaiPath.text.trim().isEmpty ? '/chat/completions' : _openaiPath.text.trim()),
        useResponseApi: _openaiUseResponse,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    } else if (idx == 1) {
      final rawName = _googleName.text.trim();
      final display = rawName.isEmpty ? 'Google' : rawName;
      final keyName = uniqueKey('Google', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _googleEnabled,
        name: display,
        apiKey: _googleVertex ? '' : _googleKey.text.trim(),
        baseUrl: _googleVertex ? 'https://aiplatform.googleapis.com' : (_googleBase.text.trim().isEmpty ? 'https://generativelanguage.googleapis.com/v1beta' : _googleBase.text.trim()),
        providerType: ProviderKind.google,  // Explicitly set as Google type
        vertexAI: _googleVertex,
        location: _googleVertex ? (_googleLocation.text.trim().isEmpty ? 'us-central1' : _googleLocation.text.trim()) : '',
        projectId: _googleVertex ? _googleProject.text.trim() : '',
        serviceAccountJson: _googleVertex ? _googleSaJson.text.trim() : null,
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    } else {
      final rawName = _claudeName.text.trim();
      final display = rawName.isEmpty ? 'Claude' : rawName;
      final keyName = uniqueKey('Claude', display);
      final cfg = ProviderConfig(
        id: keyName,
        enabled: _claudeEnabled,
        name: display,
        apiKey: _claudeKey.text.trim(),
        baseUrl: _claudeBase.text.trim().isEmpty ? 'https://api.anthropic.com/v1' : _claudeBase.text.trim(),
        providerType: ProviderKind.claude,  // Explicitly set as Claude type
        models: const [],
        modelOverrides: const {},
        proxyEnabled: false,
        proxyHost: '',
        proxyPort: '8080',
        proxyUsername: '',
        proxyPassword: '',
      );
      await settings.setProviderConfig(keyName, cfg);
      createdKey = keyName;
    }

    // Ensure providers appear in order list at least once
    final order = List<String>.of(context.read<SettingsProvider>().providersOrder);
    // Put the newly created provider at the front
    order.remove(createdKey);
    order.insert(0, createdKey);
    await context.read<SettingsProvider>().setProvidersOrder(order);

    if (mounted) Navigator.of(context).pop(createdKey);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.8,
          minChildSize: 0.5,
          builder: (c, controller) => Column(
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.addProviderSheetTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F7F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: TabBar(
                    controller: _tab,
                    indicatorColor: cs.primary,
                    labelColor: cs.primary,
                    unselectedLabelColor: cs.onSurface.withOpacity(0.7),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: const [
                      Tab(text: 'OpenAI'),
                      Tab(text: 'Google'),
                      Tab(text: 'Claude'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView(
                    controller: controller,
                    children: [
                      AnimatedBuilder(
                        animation: _tab,
                        builder: (_, __) {
                          final idx = _tab.index;
                          return Column(
                            children: [
                              if (idx == 0) _openaiForm(l10n),
                              if (idx == 1) _googleForm(l10n),
                              if (idx == 2) _claudeForm(l10n),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cs.primary.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(l10n.addProviderSheetCancelButton, style: TextStyle(color: cs.primary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Lucide.Plus, size: 18),
                        onPressed: _onAdd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        label: Text(l10n.addProviderSheetAddButton),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multilineRow({required String label, required TextEditingController controller, String? hint, List<Widget>? actions}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)))),
            if (actions != null) ...actions,
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: 8,
          minLines: 4,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.transparent)),
            enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _importGoogleServiceAccount() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      if (path == null) return;
      final text = await File(path).readAsString();
      _googleSaJson.text = text;
      try {
        final obj = jsonDecode(text) as Map<String, dynamic>;
        final pid = (obj['project_id'] as String?)?.trim();
        if ((pid ?? '').isNotEmpty && _googleProject.text.trim().isEmpty) {
          _googleProject.text = pid!;
        }
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (_) {}
  }
}
