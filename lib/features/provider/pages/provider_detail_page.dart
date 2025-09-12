import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../model/widgets/model_detail_sheet.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../widgets/share_provider_sheet.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../../l10n/app_localizations.dart';

class ProviderDetailPage extends StatefulWidget {
  const ProviderDetailPage({super.key, required this.keyName, required this.displayName});
  final String keyName;
  final String displayName;

  @override
  State<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<ProviderDetailPage> {
  final PageController _pc = PageController();
  int _index = 0;
  late ProviderConfig _cfg;
  late ProviderKind _kind;
  final _nameCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  // Google Vertex AI extras
  final _locationCtrl = TextEditingController();
  final _projectCtrl = TextEditingController();
  final _saJsonCtrl = TextEditingController();
  bool _enabled = true;
  bool _useResp = false; // openai
  bool _vertexAI = false; // google
  bool _showApiKey = false; // toggle visibility
  // network proxy (per provider)
  bool _proxyEnabled = false;
  final _proxyHostCtrl = TextEditingController();
  final _proxyPortCtrl = TextEditingController(text: '8080');
  final _proxyUserCtrl = TextEditingController();
  final _proxyPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    _kind = ProviderConfig.classify(widget.keyName, explicitType: _cfg.providerType);
    _enabled = _cfg.enabled;
    _nameCtrl.text = _cfg.name;
    _keyCtrl.text = _cfg.apiKey;
    _baseCtrl.text = _cfg.baseUrl;
    _pathCtrl.text = _cfg.chatPath ?? '/chat/completions';
    _useResp = _cfg.useResponseApi ?? false;
    _vertexAI = _cfg.vertexAI ?? false;
    _locationCtrl.text = _cfg.location ?? '';
    _projectCtrl.text = _cfg.projectId ?? '';
    _saJsonCtrl.text = _cfg.serviceAccountJson ?? '';
    // proxy
    _proxyEnabled = _cfg.proxyEnabled ?? false;
    _proxyHostCtrl.text = _cfg.proxyHost ?? '';
    _proxyPortCtrl.text = _cfg.proxyPort ?? '8080';
    _proxyUserCtrl.text = _cfg.proxyUsername ?? '';
    _proxyPassCtrl.text = _cfg.proxyPassword ?? '';
  }

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _baseCtrl.dispose();
    _pathCtrl.dispose();
    _locationCtrl.dispose();
    _projectCtrl.dispose();
    _saJsonCtrl.dispose();
    _proxyHostCtrl.dispose();
    _proxyPortCtrl.dispose();
    _proxyUserCtrl.dispose();
    _proxyPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    bool _isUserAdded(String key) {
      const fixed = {
        'KelivoIN', 'OpenAI', 'Gemini', 'SiliconFlow', 'OpenRouter',
        'DeepSeek', 'Aliyun', 'Zhipu AI', 'Claude', 'Grok', 'ByteDance',
      };
      return !fixed.contains(key);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            _BrandAvatar(
              name: (_nameCtrl.text.isEmpty ? widget.displayName : _nameCtrl.text),
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _nameCtrl.text.isEmpty ? widget.displayName : _nameCtrl.text,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.providerDetailPageShareTooltip,
            icon: Icon(Lucide.Share2, color: cs.onSurface),
            onPressed: () async {
              await showShareProviderSheet(context, widget.keyName);
            },
          ),
          if (_isUserAdded(widget.keyName))
            IconButton(
              tooltip: l10n.providerDetailPageDeleteProviderTooltip,
              icon: Icon(Lucide.Trash2, color: cs.error),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.providerDetailPageDeleteProviderTitle),
                    content: Text(l10n.providerDetailPageDeleteProviderContent),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.providerDetailPageCancelButton)),
                      TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.providerDetailPageDeleteButton, style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await context.read<SettingsProvider>().removeProviderConfig(widget.keyName);
                  if (!mounted) return;
                  Navigator.of(context).maybePop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.providerDetailPageProviderDeletedSnackbar)),
                  );
                }
              },
            ),
        ],
      ),
      body: PageView(
        controller: _pc,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          _buildConfigTab(context, cs, l10n),
          _buildModelsTab(context, cs, l10n),
          _buildNetworkTab(context, cs, l10n),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        selectedIconTheme: const IconThemeData(size: 20),
        unselectedIconTheme: const IconThemeData(size: 20),
        backgroundColor: cs.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurface.withOpacity(0.7),
        currentIndex: _index,
        onTap: (i) {
          setState(() => _index = i);
          _pc.animateToPage(
            i,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        },
        items: [
          BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(Lucide.Settings2),
            ),
            label: l10n.providerDetailPageConfigTab,
          ),
          BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(Lucide.Boxes),
            ),
            label: l10n.providerDetailPageModelsTab,
          ),
          BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Icon(Lucide.Network),
            ),
            label: l10n.providerDetailPageNetworkTab,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigTab(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (widget.keyName.toLowerCase() == 'kelivoin') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withOpacity(0.35)),
            ),
            child: Text.rich(
              TextSpan(
                text: 'Powered by ',
                style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                children: [
                  TextSpan(
                    text: 'Pollinations AI',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () async {
                        final uri = Uri.parse('https://pollinations.ai');
                        try {
                          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                          if (!ok) {
                            await launchUrl(uri);
                          }
                        } catch (_) {
                          await launchUrl(uri);
                        }
                      },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Provider type selector cards
        if (widget.keyName.toLowerCase() != 'kelivoin') ...[
          _buildProviderTypeSelector(context, cs, l10n),
          const SizedBox(height: 12),
        ],
        _switchRow(
          icon: Icons.check_circle_outline,
          title: l10n.providerDetailPageEnabledTitle,
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 12),
        _inputRow(
          context,
          label: l10n.providerDetailPageNameLabel,
          controller: _nameCtrl,
          hint: widget.displayName,
          enabled: widget.keyName.toLowerCase() != 'kelivoin',
        ),
        const SizedBox(height: 12),
        if (!(_kind == ProviderKind.google && _vertexAI)) ...[
          if (widget.keyName.toLowerCase() != 'kelivoin') ...[
            _inputRow(
              context,
              label: 'API Key',
              controller: _keyCtrl,
              hint: l10n.providerDetailPageApiKeyHint,
              obscure: !_showApiKey,
              suffix: IconButton(
                tooltip: _showApiKey ? l10n.providerDetailPageHideTooltip : l10n.providerDetailPageShowTooltip,
                icon: Icon(_showApiKey ? Lucide.EyeOff : Lucide.Eye, color: cs.onSurface.withOpacity(0.7), size: 18),
                onPressed: () => setState(() => _showApiKey = !_showApiKey),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _inputRow(
            context,
            label: 'API Base URL',
            controller: _baseCtrl,
            hint: ProviderConfig.defaultsFor(widget.keyName, displayName: widget.displayName).baseUrl,
            enabled: widget.keyName.toLowerCase() != 'kelivoin',
          ),
        ],
        if (_kind == ProviderKind.openai && widget.keyName.toLowerCase() != 'kelivoin') ...[
          const SizedBox(height: 12),
          _inputRow(
            context,
            label: l10n.providerDetailPageApiPathLabel,
            controller: _pathCtrl,
            enabled: widget.keyName.toLowerCase() != 'openai',
            hint: '/chat/completions',
          ),
          const SizedBox(height: 4),
          _checkboxRow(context, title: l10n.providerDetailPageResponseApiTitle, value: _useResp, onChanged: (v) => setState(() => _useResp = v)),
        ],
        if (_kind == ProviderKind.google) ...[
          const SizedBox(height: 12),
          _checkboxRow(context, title: l10n.providerDetailPageVertexAiTitle, value: _vertexAI, onChanged: (v) => setState(() => _vertexAI = v)),
          if (_vertexAI) ...[
            const SizedBox(height: 12),
            _inputRow(context, label: l10n.providerDetailPageLocationLabel, controller: _locationCtrl, hint: 'us-central1'),
            const SizedBox(height: 12),
            _inputRow(context, label: l10n.providerDetailPageProjectIdLabel, controller: _projectCtrl, hint: 'my-project-id'),
            const SizedBox(height: 12),
            _multilineRow(
              context,
              label: l10n.providerDetailPageServiceAccountJsonLabel,
              controller: _saJsonCtrl,
              hint: '{\n  "type": "service_account", ...\n}',
              actions: [
                TextButton.icon(
                  onPressed: _importServiceAccountJson,
                  icon: Icon(Lucide.Upload, size: 16),
                  label: Text(l10n.providerDetailPageImportJsonButton),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
              onPressed: _openTestDialog,
              icon: Icon(Lucide.Cable, size: 18, color: cs.primary),
              label: Text(l10n.providerDetailPageTestButton, style: TextStyle(color: cs.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(l10n.providerDetailPageSaveButton),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildModelsTab(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    final cfg = context.watch<SettingsProvider>().providerConfigs[widget.keyName];
    if (cfg == null) {
      // Provider has been removed; avoid recreating it via getProviderConfig.
      return Center(
        child: Text(l10n.providerDetailPageProviderRemovedMessage, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
      );
    }
    final models = cfg.models;
    return Stack(
      children: [
        if (models.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.providerDetailPageNoModelsTitle, style: TextStyle(fontSize: 18, color: cs.onSurface)),
                const SizedBox(height: 6),
                Text(
                  l10n.providerDetailPageNoModelsSubtitle,
                  style: TextStyle(fontSize: 13, color: cs.primary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: models.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex -= 1;
              final id = models[oldIndex];
              final list = List<String>.from(models);
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              setState(() {});
              await context.read<SettingsProvider>().setProviderConfig(
                widget.keyName,
                cfg.copyWith(models: list),
              );
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
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  );
                },
                child: child,
              );
            },
            itemBuilder: (c, i) {
              final id = models[i];
              final cs = Theme.of(context).colorScheme;
              return KeyedSubtree(
                key: ValueKey('reorder-model-$id'),
                child: ReorderableDelayedDragStartListener(
                  index: i,
                  child: Slidable(
                    key: ValueKey('model-$id'),
                    endActionPane: ActionPane(
                      motion: const StretchMotion(),
                      extentRatio: 0.42,
                      children: [
                        CustomSlidableAction(
                          autoClose: true,
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? cs.error.withOpacity(0.22) : cs.error.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.error.withOpacity(0.35)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            alignment: Alignment.center,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Lucide.Trash2, color: cs.error, size: 18),
                                  const SizedBox(width: 6),
                                  Text(l10n.providerDetailPageDeleteModelButton, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                          onPressed: (_) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (dctx) => AlertDialog(
                                backgroundColor: cs.surface,
                                title: Text(l10n.providerDetailPageConfirmDeleteTitle),
                                content: Text(l10n.providerDetailPageConfirmDeleteContent),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text(l10n.providerDetailPageCancelButton)),
                                  TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text(l10n.providerDetailPageDeleteButton)),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            final settings = context.read<SettingsProvider>();
                            final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                            final prevList = List<String>.from(old.models);
                            final prevOverrides = Map<String, dynamic>.from(old.modelOverrides);
                            final removeIndex = prevList.indexOf(id);
                            final newList = prevList.where((e) => e != id).toList();
                            final newOverrides = Map<String, dynamic>.from(prevOverrides)..remove(id);
                            await settings.setProviderConfig(widget.keyName, old.copyWith(models: newList, modelOverrides: newOverrides));
                            if (!mounted) return;
                            final snack = SnackBar(
                              content: Text(l10n.providerDetailPageModelDeletedSnackbar),
                              action: SnackBarAction(
                                label: l10n.providerDetailPageUndoButton,
                                onPressed: () async {
                                  final cfg2 = context.read<SettingsProvider>().getProviderConfig(widget.keyName, defaultName: widget.displayName);
                                  final restoredList = List<String>.from(cfg2.models);
                                  if (!restoredList.contains(id)) {
                                    if (removeIndex >= 0 && removeIndex <= restoredList.length) {
                                      restoredList.insert(removeIndex, id);
                                    } else {
                                      restoredList.add(id);
                                    }
                                  }
                                  final restoredOverrides = Map<String, dynamic>.from(cfg2.modelOverrides);
                                  if (!restoredOverrides.containsKey(id) && prevOverrides.containsKey(id)) {
                                    restoredOverrides[id] = prevOverrides[id];
                                  }
                                  await settings.setProviderConfig(widget.keyName, cfg2.copyWith(models: restoredList, modelOverrides: restoredOverrides));
                                },
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(snack);
                          },
                        ),
                      ],
                    ),
                    child: _ModelCard(providerKey: widget.keyName, modelId: id),
                  ),
                ),
              );
            },
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                // Solid color: dark theme uses an opaque lightened surface; light uses input-like gray
                color: Theme.of(context).brightness == Brightness.dark
                    ? Color.alphaBlend(Colors.white.withOpacity(0.12), cs.surface)
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _showModelPicker(context),
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      padding: const EdgeInsets.all(10),
                      child: Icon(Lucide.Boxes, size: 20, color: cs.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () async {
                      await showCreateModelSheet(context, providerKey: widget.keyName);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Lucide.Plus, size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(l10n.providerDetailPageAddNewModelButton, style: TextStyle(color: cs.primary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkTab(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _switchRow(
                icon: Icons.lan_outlined,
                title: l10n.providerDetailPageEnableProxyTitle,
                value: _proxyEnabled,
                onChanged: (v) => setState(() => _proxyEnabled = v),
              ),
              if (_proxyEnabled) ...[
                const SizedBox(height: 12),
                _inputRow(context, label: l10n.providerDetailPageHostLabel, controller: _proxyHostCtrl, hint: '127.0.0.1'),
                const SizedBox(height: 12),
                _inputRow(context, label: l10n.providerDetailPagePortLabel, controller: _proxyPortCtrl, hint: '8080'),
                const SizedBox(height: 12),
                _inputRow(context, label: l10n.providerDetailPageUsernameOptionalLabel, controller: _proxyUserCtrl),
                const SizedBox(height: 12),
                _inputRow(context, label: l10n.providerDetailPagePasswordOptionalLabel, controller: _proxyPassCtrl, obscure: true),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _saveNetwork,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(l10n.providerDetailPageSaveButton),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _switchRow({required IconData icon, required String title, required bool value, required ValueChanged<bool> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: cs.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 12),
          child: Icon(icon, size: 20, color: cs.primary),
        ),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _inputRow(BuildContext context, {required String label, required TextEditingController controller, String? hint, bool obscure = false, bool enabled = true, Widget? suffix}) {
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }

  Widget _checkboxRow(BuildContext context, {required String title, required bool value, required ValueChanged<bool> onChanged}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Text(title, style: TextStyle(fontSize: 14, color: cs.onSurface)),
        ],
      ),
    );
  }

  

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    String projectId = _projectCtrl.text.trim();
    if ((_kind == ProviderKind.google) && _vertexAI && projectId.isEmpty) {
      try {
        final obj = jsonDecode(_saJsonCtrl.text) as Map<String, dynamic>;
        projectId = (obj['project_id'] as String?)?.trim() ?? '';
      } catch (_) {}
    }
    final updated = old.copyWith(
      enabled: _enabled,
      name: _nameCtrl.text.trim().isEmpty ? widget.displayName : _nameCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      baseUrl: _baseCtrl.text.trim(),
      providerType: _kind,  // Save the selected provider type
      chatPath: _kind == ProviderKind.openai ? _pathCtrl.text.trim() : old.chatPath,
      useResponseApi: _kind == ProviderKind.openai ? _useResp : old.useResponseApi,
      vertexAI: _kind == ProviderKind.google ? _vertexAI : old.vertexAI,
      location: _kind == ProviderKind.google ? _locationCtrl.text.trim() : old.location,
      projectId: _kind == ProviderKind.google ? projectId : old.projectId,
      serviceAccountJson: _kind == ProviderKind.google ? _saJsonCtrl.text.trim() : old.serviceAccountJson,
      // preserve models and modelOverrides and proxy fields implicitly via copyWith
    );
    await settings.setProviderConfig(widget.keyName, updated);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.providerDetailPageSavedSnackbar)));
    setState(() {});
  }

  Widget _multilineRow(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? hint,
    List<Widget>? actions,
  }) {
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
            alignLabelWithHint: true,
            fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
          ),
        ),
      ],
    );
  }

  Future<void> _importServiceAccountJson() async {
    try {
      // Lazy import to avoid hard dependency errors in web
      // ignore: avoid_dynamic_calls
      // ignore: import_of_legacy_library_into_null_safe
      // Using file_picker which is already in pubspec
      // import placed at top-level of this file
      final picker = await _pickJsonFile();
      if (picker == null) return;
      _saJsonCtrl.text = picker;
      // Auto-fill projectId if available
      try {
        final obj = jsonDecode(_saJsonCtrl.text) as Map<String, dynamic>;
        final pid = (obj['project_id'] as String?)?.trim();
        if ((pid ?? '').isNotEmpty && _projectCtrl.text.trim().isEmpty) {
          _projectCtrl.text = pid!;
        }
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _pickJsonFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      final path = file.path;
      if (path == null) return null;
      final text = await File(path).readAsString();
      return text;
    } catch (e) {
      return null;
    }
  }

  Future<void> _openTestDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConnectionTestDialog(providerKey: widget.keyName, providerDisplayName: widget.displayName),
    );
  }

  Future<void> _saveNetwork() async {
    final settings = context.read<SettingsProvider>();
    final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final cfg = old.copyWith(
      proxyEnabled: _proxyEnabled,
      proxyHost: _proxyHostCtrl.text.trim(),
      proxyPort: _proxyPortCtrl.text.trim(),
      proxyUsername: _proxyUserCtrl.text.trim(),
      proxyPassword: _proxyPassCtrl.text.trim(),
    );
    await settings.setProviderConfig(widget.keyName, cfg);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.providerDetailPageSavedSnackbar)));
  }

  Widget _buildProviderTypeSelector(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.openai;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.openai 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.openai 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.openai ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'OpenAI',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.openai ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.openai ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.google;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.google 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.google 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.google ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Gemini',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.google ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.google ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _kind = ProviderKind.claude;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: _kind == ProviderKind.claude 
                    ? cs.primary.withOpacity(0.15) 
                    : Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _kind == ProviderKind.claude 
                      ? cs.primary.withOpacity(0.5) 
                      : cs.outlineVariant.withOpacity(0.2),
                  width: _kind == ProviderKind.claude ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Claude',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _kind == ProviderKind.claude ? FontWeight.w600 : FontWeight.w500,
                      color: _kind == ProviderKind.claude ? cs.primary : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showModelPicker(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
    final controller = TextEditingController();
    List<dynamic> items = const [];
    bool loading = true;
    String error = '';
    // Collapsed state per group in the selector dialog
    final Map<String, bool> collapsed = <String, bool>{};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          final l10n = AppLocalizations.of(ctx)!;
          Future<void> _load() async {
            try {
              final list = await ProviderManager.listModels(cfg);
              setLocal(() {
                items = list;
                loading = false;
              });
            } catch (e) {
              setLocal(() {
                items = const [];
                loading = false;
                error = '$e';
              });
            }
          }

          if (loading) {
            // kick off loading once
            Future.microtask(_load);
          }

          final selected = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName).models.toSet();
          final query = controller.text.trim().toLowerCase();
          final filtered = <ModelInfo>[
            for (final m in items)
              if (m is ModelInfo && (query.isEmpty || m.id.toLowerCase().contains(query) || m.displayName.toLowerCase().contains(query))) m
          ];

          String _groupFor(ModelInfo m) {
            final id = m.id.toLowerCase();
            // Embeddings first
            if (m.type == ModelType.embedding || id.contains('embedding') || id.contains('embed')) {
              return l10n.providerDetailPageEmbeddingsGroupTitle;
            }
            // OpenAI families
            // if (RegExp(r'gpt-4o|gpt-4\.1|gpt-4|gpt4').hasMatch(id)) return 'GPT-4';
            if (id.contains('gpt') || RegExp(r'(^|[^a-z])o[134]').hasMatch(id)) return 'GPT';
            // if (RegExp(r'(^|[^a-z])o[134]').hasMatch(id)) return zhLocal ? 'o 系列' : 'o Series';
            // if (id.contains('gpt-5')) return 'GPT-5';
            // Google Gemini
            if (id.contains('gemini-2.0')) return 'Gemini 2.0';
            if (id.contains('gemini-2.5')) return 'Gemini 2.5';
            if (id.contains('gemini-1.5')) return 'Gemini 1.5';
            if (id.contains('gemini')) return 'Gemini';
            // Anthropic Claude
            if (id.contains('claude-3.5')) return 'Claude 3.5';
            if (id.contains('claude-3')) return 'Claude 3';
            if (id.contains('claude-4')) return 'Claude 4';
            if (id.contains('claude-sonnet')) return 'Claude Sonnet';
            if (id.contains('claude-opus')) return 'Claude Opus';
            // Others by vendor keyword
            if (id.contains('deepseek')) return 'DeepSeek';
            if (RegExp(r'qwen|qwq|qvq|dashscope').hasMatch(id)) return 'Qwen';
            if (RegExp(r'doubao|ark|volc').hasMatch(id)) return 'Doubao';
            if (id.contains('glm') || id.contains('zhipu')) return 'GLM';
            if (id.contains('mistral')) return 'Mistral';
            if (id.contains('grok') || id.contains('xai')) return 'Grok';
            return l10n.providerDetailPageOtherModelsGroupTitle;
          }

          final Map<String, List<ModelInfo>> grouped = {};
          for (final m in filtered) {
            final g = _groupFor(m);
            (grouped[g] ??= []).add(m);
          }
          final groupKeys = grouped.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          return SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                maxChildSize: 0.95,
                minChildSize: 0.4,
                builder: (c, scrollController) {
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
                      const SizedBox(height: 8),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                          : error.isNotEmpty
                              ? Center(child: Text(error, style: TextStyle(color: cs.error)))
                              : ListView(
                                  controller: scrollController,
                                  children: [
                                    for (final g in groupKeys) ...[
                                      // Group header with actions
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                        child: Material(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white10
                                              : const Color(0xFFF2F3F5),
                                          borderRadius: BorderRadius.circular(12),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () => setLocal(() {
                                              collapsed[g] = !(collapsed[g] == true);
                                            }),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 28,
                                                    child: Center(
                                                      child: Icon(
                                                        (collapsed[g] == true) ? Lucide.ChevronRight : Lucide.ChevronDown,
                                                        size: 20,
                                                        color: cs.onSurface.withOpacity(0.7),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Text(
                                                      g,
                                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Builder(builder: (ctx2) {
                                                    final allAdded = grouped[g]!.every((m) => selected.contains(m.id));
                                                    return IconButton(
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                                                      tooltip: allAdded ? l10n.providerDetailPageRemoveGroupTooltip : l10n.providerDetailPageAddGroupTooltip,
                                                      icon: Icon(allAdded ? Lucide.Minus : Lucide.Plus, size: 24, color: allAdded ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.7)),
                                                      onPressed: () async {
                                                        final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                                                        if (allAdded) {
                                                          final toRemove = grouped[g]!.map((m) => m.id).toSet();
                                                          final list = old.models.where((id) => !toRemove.contains(id)).toList();
                                                          await settings.setProviderConfig(widget.keyName, old.copyWith(models: list));
                                                        } else {
                                                          final toAdd = grouped[g]!.where((m) => !selected.contains(m.id)).map((m) => m.id).toList();
                                                          if (toAdd.isEmpty) return;
                                                          final set = old.models.toSet()..addAll(toAdd);
                                                          await settings.setProviderConfig(widget.keyName, old.copyWith(models: set.toList()));
                                                        }
                                                        setLocal(() {});
                                                      },
                                                    );
                                                  }),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (!(collapsed[g] == true))
                                        for (final m in grouped[g]!)
                                          Builder(builder: (c2) {
                                            final added = selected.contains(m.id);
                                            return Padding(
                                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                                              child: Material(
                                                // color: Theme.of(context).brightness == Brightness.dark
                                                //     ? Colors.white10
                                                //     : const Color(0xFFF2F3F5),
                                                borderRadius: BorderRadius.circular(12),
                                                child: InkWell(
                                                  borderRadius: BorderRadius.circular(12),
                                                  onTap: () {},
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                    child: Row(
                                                      children: [
                    SizedBox(
                      width: 28,
                      child: Center(child: _BrandAvatar(name: m.id, size: 28)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.displayName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          _modelTagWrap(context, m),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                      onPressed: () async {
                        final old = settings.getProviderConfig(widget.keyName, defaultName: widget.displayName);
                        final list = old.models.toList();
                        if (added) {
                          list.removeWhere((e) => e == m.id);
                        } else {
                          list.add(m.id);
                        }
                        await settings.setProviderConfig(widget.keyName, old.copyWith(models: list));
                        setLocal(() {});
                      },
                      icon: Icon(added ? Lucide.Minus : Lucide.Plus, size: 24, color: added ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.7)),
                    ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                    ],
                                  ],
                                ),
                    ),
                      Padding(
                        padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(ctx).padding.bottom + 12),
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => setLocal(() {}),
                          decoration: InputDecoration(
                            hintText: l10n.providerDetailPageFilterHint,
                            filled: true,
                            fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        });
      },
    );
  }

  Widget _capPill(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.primary)),
      ]),
    );
  }
}

Widget _buildDismissBg(BuildContext context, {required bool alignStart}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  return Container(
    decoration: BoxDecoration(
      color: cs.error.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
    child: Row(
      mainAxisAlignment: alignStart ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        Icon(Lucide.Trash2, color: cs.error, size: 20),
        const SizedBox(width: 6),
        Text(
          l10n.providerDetailPageDeleteText,
          style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.providerKey, required this.modelId});
  final String providerKey;
  final String modelId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _BrandAvatar(name: modelId, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName(context), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _modelTagWrap(context, _effective(context)),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.providerDetailPageEditTooltip,
                icon: Icon(Lucide.Settings2, size: 18, color: cs.onSurface.withOpacity(0.7)),
                onPressed: () async {
                  await showModelDetailSheet(context, providerKey: providerKey, modelId: modelId);
                  // Force refresh by getting provider and doing nothing; outer ListView watches provider changes
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ModelInfo _infer(String id) {
    // build a minimal ModelInfo and let registry infer
    return ModelRegistry.infer(ModelInfo(id: id, displayName: id));
  }

  ModelInfo _effective(BuildContext context) {
    final base = _infer(modelId);
    final cfg = context.watch<SettingsProvider>().getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov == null) return base;
    ModelType? type;
    final t = (ov['type'] as String?) ?? '';
    if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
    List<Modality>? input;
    if (ov['input'] is List) {
      input = [
        for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
      ];
    }
    List<Modality>? output;
    if (ov['output'] is List) {
      output = [
        for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
      ];
    }
    List<ModelAbility>? abilities;
    if (ov['abilities'] is List) {
      abilities = [
        for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)
      ];
    }
    return base.copyWith(
      displayName: (ov['name'] as String?)?.isNotEmpty == true ? ov['name'] as String : base.displayName,
      type: type ?? base.type,
      input: input ?? base.input,
      output: output ?? base.output,
      abilities: abilities ?? base.abilities,
    );
  }

  String _displayName(BuildContext context) {
    final cfg = context.watch<SettingsProvider>().getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null) {
      final n = (ov['name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return modelId;
  }

  Widget _pill(BuildContext context, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cs.primary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.primary)),
      ]),
    );
  }
}

class _ConnectionTestDialog extends StatefulWidget {
  const _ConnectionTestDialog({required this.providerKey, required this.providerDisplayName});
  final String providerKey;
  final String providerDisplayName;

  @override
  State<_ConnectionTestDialog> createState() => _ConnectionTestDialogState();
}

enum _TestState { idle, loading, success, error }

class _ConnectionTestDialogState extends State<_ConnectionTestDialog> {
  String? _selectedModelId;
  _TestState _state = _TestState.idle;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.providerDetailPageTestConnectionTitle;
    final canTest = _selectedModelId != null && _state != _TestState.loading;
    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              const SizedBox(height: 16),
              _buildBody(context, cs, l10n),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.providerDetailPageCancelButton)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: canTest ? _doTest : null,
                    style: TextButton.styleFrom(foregroundColor: canTest ? cs.primary : cs.onSurface.withOpacity(0.4)),
                    child: Text(l10n.providerDetailPageTestButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  

  Widget _buildBody(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    switch (_state) {
      case _TestState.idle:
        return _buildIdle(context, cs, l10n);
      case _TestState.loading:
        return _buildLoading(context, cs, l10n);
      case _TestState.success:
        return _buildResult(context, cs, l10n, success: true, message: l10n.providerDetailPageTestSuccessMessage);
      case _TestState.error:
        return _buildResult(context, cs, l10n, success: false, message: _errorMessage);
    }
  }

  Widget _buildIdle(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId == null)
          TextButton(
            onPressed: _pickModel,
            child: Text(l10n.providerDetailPageSelectModelButton),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: _pickModel, child: Text(l10n.providerDetailPageChangeButton)),
            ],
          ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BrandAvatar(name: _selectedModelId!, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _selectedModelId!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(minHeight: 4),
        const SizedBox(height: 12),
        Text(l10n.providerDetailPageTestingMessage, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
      ],
    );
  }

  Widget _buildResult(BuildContext context, ColorScheme cs, AppLocalizations l10n, {required bool success, required String message}) {
    final color = success ? Colors.green : cs.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedModelId != null)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pickModel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  _BrandAvatar(name: _selectedModelId!, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedModelId!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Lucide.ChevronDown, size: 16, color: cs.onSurface.withOpacity(0.7)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(message, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Future<void> _pickModel() async {
    final selected = await showModelPickerForTest(context, widget.providerKey, widget.providerDisplayName);
    if (selected != null) {
      setState(() {
        _selectedModelId = selected;
        _state = _TestState.idle;
        _errorMessage = '';
      });
    }
  }

  Future<void> _doTest() async {
    if (_selectedModelId == null) return;
    setState(() {
      _state = _TestState.loading;
      _errorMessage = '';
    });
    try {
      final cfg = context.read<SettingsProvider>().getProviderConfig(widget.providerKey, defaultName: widget.providerDisplayName);
      await ProviderManager.testConnection(cfg, _selectedModelId!);
      if (!mounted) return;
      setState(() => _state = _TestState.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _TestState.error;
        _errorMessage = e.toString();
      });
    }
  }
}

Future<String?> showModelPickerForTest(BuildContext context, String providerKey, String providerDisplayName) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final cfg = settings.getProviderConfig(providerKey, defaultName: providerDisplayName);
  final sel = await showModelSelector(context, limitProviderKey: providerKey);
  return sel?.modelId;
}

ModelInfo _effectiveFor(BuildContext context, String providerKey, String providerDisplayName, ModelInfo base) {
  final cfg = context.read<SettingsProvider>().getProviderConfig(providerKey, defaultName: providerDisplayName);
  final ov = cfg.modelOverrides[base.id] as Map?;
  if (ov == null) return base;
  ModelType? type;
  final t = (ov['type'] as String?) ?? '';
  if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
  List<Modality>? input;
  if (ov['input'] is List) {
    input = [
      for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
    ];
  }
  List<Modality>? output;
  if (ov['output'] is List) {
    output = [
      for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)
    ];
  }
  List<ModelAbility>? abilities;
  if (ov['abilities'] is List) {
    abilities = [
      for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)
    ];
  }
  return base.copyWith(
    type: type ?? base.type,
    input: input ?? base.input,
    output: output ?? base.output,
    abilities: abilities ?? base.abilities,
  );
}


// Using flutter_slidable for reliable swipe actions with confirm + undo.

Widget _modelTagWrap(BuildContext context, ModelInfo m) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  List<Widget> chips = [];
  // type tag
  chips.add(Container(
    decoration: BoxDecoration(
      color: isDark ? cs.primary.withOpacity(0.25) : cs.primary.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.primary.withOpacity(0.2), width: 0.5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Text(m.type == ModelType.chat ? l10n.modelSelectSheetChatType : l10n.modelSelectSheetEmbeddingType, style: TextStyle(fontSize: 11, color: isDark ? cs.primary : cs.primary.withOpacity(0.9), fontWeight: FontWeight.w500)),
  ));
  // modality tag capsule
  chips.add(Container(
    decoration: BoxDecoration(
      color: isDark ? cs.tertiary.withOpacity(0.25) : cs.tertiary.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.tertiary.withOpacity(0.2), width: 0.5),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      for (final mod in m.input)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(mod == Modality.text ? Lucide.Type : Lucide.Image, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
        ),
      Icon(Lucide.ChevronRight, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
      for (final mod in m.output)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Icon(mod == Modality.text ? Lucide.Type : Lucide.Image, size: 12, color: isDark ? cs.tertiary : cs.tertiary.withOpacity(0.9)),
        ),
    ]),
  ));
  // abilities capsules (icon-only)
  for (final ab in m.abilities) {
    if (ab == ModelAbility.tool) {
      chips.add(Container(
        decoration: BoxDecoration(
          color: isDark ? cs.primary.withOpacity(0.25) : cs.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withOpacity(0.2), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Icon(Lucide.Hammer, size: 12, color: isDark ? cs.primary : cs.primary.withOpacity(0.9)),
      ));
    } else if (ab == ModelAbility.reasoning) {
      chips.add(Container(
        decoration: BoxDecoration(
          color: isDark ? cs.secondary.withOpacity(0.3) : cs.secondary.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.secondary.withOpacity(0.25), width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: SvgPicture.asset('assets/icons/deepthink.svg', width: 12, height: 12, colorFilter: ColorFilter.mode(isDark ? cs.secondary : cs.secondary.withOpacity(0.9), BlendMode.srcIn)),
      ));
    }
  }
  return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: chips);
}


// Legacy page-based implementations removed in favor of swipeable PageView tabs.


class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20});
  final String name;
  final double size;

  String? _assetForName(String n) {
    final lower = n.toLowerCase();
    final mapping = <RegExp, String>{
      RegExp(r'openai|gpt|o\d'): 'openai.svg',
      RegExp(r'gemini'): 'gemini-color.svg',
      RegExp(r'google'): 'google-color.svg',
      RegExp(r'claude'): 'claude-color.svg',
      RegExp(r'anthropic'): 'anthropic.svg',
      RegExp(r'deepseek'): 'deepseek-color.svg',
      RegExp(r'grok'): 'grok.svg',
      RegExp(r'qwen|qwq|qvq'): 'qwen-color.svg',
      RegExp(r'doubao'): 'doubao-color.svg',
      RegExp(r'openrouter'): 'openrouter.svg',
      RegExp(r'zhipu|智谱|glm'): 'zhipu-color.svg',
      RegExp(r'mistral'): 'mistral-color.svg',
      RegExp(r'(?<!o)llama|meta'): 'meta-color.svg',
      RegExp(r'hunyuan|tencent'): 'hunyuan-color.svg',
      RegExp(r'gemma'): 'gemma-color.svg',
      RegExp(r'perplexity'): 'perplexity-color.svg',
      RegExp(r'aliyun|阿里云|百炼'): 'alibabacloud-color.svg',
      RegExp(r'bytedance|火山'): 'bytedance-color.svg',
      RegExp(r'silicon|硅基'): 'siliconflow-color.svg',
      RegExp(r'aihubmix'): 'aihubmix-color.svg',
      RegExp(r'ollama'): 'ollama.svg',
      RegExp(r'github'): 'github.svg',
      RegExp(r'cloudflare'): 'cloudflare-color.svg',
      RegExp(r'minimax'): 'minimax-color.svg',
      RegExp(r'xai'): 'xai.svg',
      RegExp(r'juhenext'): 'juhenext.png',
      RegExp(r'kimi'): 'kimi-color.svg',
      RegExp(r'302'): '302ai-color.svg',
      RegExp(r'step|阶跃'): 'stepfun-color.svg',
      RegExp(r'intern|书生'): 'internlm-color.svg',
      RegExp(r'cohere|command-.+'): 'cohere-color.svg',
      RegExp(r'kelivo'): 'kelivo.png',
    };
    for (final e in mapping.entries) {
      if (e.key.hasMatch(lower)) return 'assets/icons/${e.value}';
    }
    return null;
  }

  bool _preferMonochromeWhite(String n) {
    final k = n.toLowerCase();
    if (RegExp(r'openai|gpt|o\d').hasMatch(k)) return true;
    if (RegExp(r'grok|xai').hasMatch(k)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _assetForName(name);
    final lower = name.toLowerCase();
    final bool _mono = isDark && (RegExp(r'openai|gpt|o\\d').hasMatch(lower) || RegExp(r'grok|xai').hasMatch(lower) || RegExp(r'openrouter').hasMatch(lower));
    final bool _purple = RegExp(r'silicon|硅基').hasMatch(lower);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
      child: asset == null
          ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: cs.primary, fontSize: size * 0.5, fontWeight: FontWeight.w700))
          : (asset.endsWith('.svg')
              ? SvgPicture.asset(
                  asset,
                  width: size * 0.7,
                  height: size * 0.7,
                  colorFilter: _mono
                      ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
                      : (_purple ? const ColorFilter.mode(Color(0xFF7C4DFF), BlendMode.srcIn) : null),
                )
              : Image.asset(
                  asset,
                  width: size * 0.7,
                  height: size * 0.7,
                  fit: BoxFit.contain,
                  color: _mono ? Colors.white : (_purple ? const Color(0xFF7C4DFF) : null),
                  colorBlendMode: (_mono || _purple) ? BlendMode.srcIn : null,
                )),
    );
  }
}
