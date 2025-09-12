import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'model_detail_sheet.dart';
import '../../provider/pages/provider_detail_page.dart';
import '../../../l10n/app_localizations.dart';

class ModelSelection {
  final String providerKey;
  final String modelId;
  ModelSelection(this.providerKey, this.modelId);
}

Future<ModelSelection?> showModelSelector(BuildContext context, {String? limitProviderKey}) async {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<ModelSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ModelSelectSheet(limitProviderKey: limitProviderKey),
  );
}

Future<void> showModelSelectSheet(BuildContext context) async {
  final sel = await showModelSelector(context);
  if (sel != null) {
    // persist as current model
    final settings = context.read<SettingsProvider>();
    await settings.setCurrentModel(sel.providerKey, sel.modelId);
  }
}

class _ModelSelectSheet extends StatefulWidget {
  const _ModelSelectSheet({this.limitProviderKey});
  final String? limitProviderKey;
  @override
  State<_ModelSelectSheet> createState() => _ModelSelectSheetState();
}

class _ModelSelectSheetState extends State<_ModelSelectSheet> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _headers = {};
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();
  static const double _initialSize = 0.7;
  static const double _maxSize = 0.85;
  ScrollController? _listCtrl; // controller from DraggableScrollableSheet
  final Map<String, double> _headerOffsets = {}; // Store computed offsets for providers

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final pinned = settings.pinnedModels;
    final providers = widget.limitProviderKey == null
        ? settings.providerConfigs
        : {
      if (settings.providerConfigs.containsKey(widget.limitProviderKey))
        widget.limitProviderKey!: settings.providerConfigs[widget.limitProviderKey]!,
    };
    final currentKey = settings.currentModelKey;
    final l10n = AppLocalizations.of(context)!;

    // Build data map: providerKey -> (displayName, models)
    final Map<String, _ProviderGroup> groups = {};
    providers.forEach((key, cfg) {
      // Skip disabled providers entirely so they can't be selected
      if (!(cfg.enabled)) return;
      if (cfg.models.isEmpty) return;
      final list = <_ModelItem>[
        for (final id in cfg.models)
          _ModelItem(
            providerKey: key,
            providerName: cfg.name.isNotEmpty ? cfg.name : key,
            id: id,
            info: ModelRegistry.infer(ModelInfo(id: id, displayName: id)),
            pinned: pinned.contains('$key::$id'),
            selected: currentKey == '$key::$id',
          )
      ];
      groups[key] = _ProviderGroup(name: cfg.name.isNotEmpty ? cfg.name : key, items: list);
    });

    // Build favorites group (duplicate items)
    final favItems = <_ModelItem>[];
    for (final k in pinned) {
      final parts = k.split('::');
      if (parts.length < 2) continue;
      final pk = parts[0];
      final mid = parts.sublist(1).join('::');
      final g = groups[pk];
      if (g == null) continue;
      final found = g.items.firstWhere((e) => e.id == mid, orElse: () => _ModelItem(providerKey: pk, providerName: g.name, id: mid, info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)), pinned: true, selected: currentKey == '$pk::$mid'));
      favItems.add(found.copyWith(pinned: true));
    }

    final query = _search.text.trim().toLowerCase();
    List<Widget> slivers = [];
    _headerOffsets.clear(); // Clear previous offsets
    double currentOffset = 0;

    // Header drag indicator
    final dragIndicator = Column(children: [
      const SizedBox(height: 8),
      Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999))),
      const SizedBox(height: 8),
    ]);
    slivers.add(dragIndicator);
    currentOffset += 20; // Approximate height of drag indicator

    // Search field
    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: l10n.modelSelectSheetSearchHint,
          prefixIcon: Icon(Lucide.Search, size: 18, color: cs.onSurface.withOpacity(0.6)),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.transparent)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.4))),
        ),
      ),
    );
    slivers.add(searchField);
    currentOffset += 64; // Approximate height of search field

    // Favorites section (only when not limited)
    if (favItems.isNotEmpty && widget.limitProviderKey == null) {
      final items = favItems.where((e) => query.isEmpty || e.id.toLowerCase().contains(query)).toList();
      if (items.isNotEmpty) {
        final key = GlobalKey();
        _headers['__fav__'] = key;
        _headerOffsets['__fav__'] = currentOffset;
        slivers.add(_sectionHeader(context, l10n.modelSelectSheetFavoritesSection, key));
        currentOffset += 44; // Approximate height of section header
        slivers.addAll(items.map((m) {
          final tile = _modelTile(context, m);
          currentOffset += 68; // Approximate height of model tile
          return tile;
        }));
      }
    }

    // Provider sections ordered by ProvidersPage order
    final order = settings.providersOrder;
    final orderedKeys = <String>[];
    for (final k in order) {
      if (groups.containsKey(k)) orderedKeys.add(k);
    }
    for (final k in groups.keys) {
      if (!orderedKeys.contains(k)) orderedKeys.add(k);
    }
    for (final pk in orderedKeys) {
      final g = groups[pk]!;
      final items = g.items.where((e) => query.isEmpty || e.id.toLowerCase().contains(query)).toList();
      if (items.isEmpty) continue;
      final key = GlobalKey();
      _headers[pk] = key;
      _headerOffsets[pk] = currentOffset;
      slivers.add(_sectionHeader(context, g.name, key));
      currentOffset += 44; // Approximate height of section header
      slivers.addAll(items.map((m) {
        final tile = _modelTile(context, m);
        currentOffset += 68; // Approximate height of model tile
        return tile;
      }));
    }

    // Bottom provider tabs (ordered per ProvidersPage order)
    final List<Widget> providerTabs = <Widget>[];
    if (widget.limitProviderKey == null) {
      final order = settings.providersOrder;
      // Build ordered keys: first by saved order, then append remaining in insertion order
      final keysInOrder = <String>[];
      for (final k in order) {
        if (groups.containsKey(k)) keysInOrder.add(k);
      }
      for (final k in groups.keys) {
        if (!keysInOrder.contains(k)) keysInOrder.add(k);
      }
      for (final k in keysInOrder) {
        final g = groups[k]!;
        providerTabs.add(_providerTab(context, k, g.name));
      }
    }

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          controller: _sheetCtrl,
          expand: false,
          initialChildSize: _initialSize,
          maxChildSize: _maxSize,
          minChildSize: 0.4,
          builder: (c, controller) {
            _listCtrl = controller;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: slivers,
                  ),
                ),
                if (providerTabs.isNotEmpty)
                  if (providerTabs.isNotEmpty)
                    Padding(
                      // SafeArea already applies bottom inset; avoid doubling it here.
                      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 10), // bottom: MediaQuery.of(context).padding.bottom
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: providerTabs),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, Key key) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: key,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withOpacity(0.6))),
    );
  }

  Widget _modelTile(BuildContext context, _ModelItem m) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = m.selected ? (isDark ? cs.primary.withOpacity(0.12) : cs.primary.withOpacity(0.08)) : cs.surface;
    final effective = _effectiveInfo(context, m);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(ModelSelection(m.providerKey, m.id)),
          onLongPress: () async {
            // Edit model overrides in-place; refresh list after closing
            await showModelDetailSheet(context, providerKey: m.providerKey, modelId: m.id);
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _BrandAvatar(name: m.id, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName(context, m), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      _modelTagWrap(context, effective),
                    ],
                  ),
                ),
                Builder(builder: (context) {
                  final pinnedNow = context.select<SettingsProvider, bool>((s) => s.isModelPinned(m.providerKey, m.id));
                  final icon = pinnedNow ? Icons.favorite : Icons.favorite_border;
                  return IconButton(
                    onPressed: () => settings.togglePinModel(m.providerKey, m.id),
                    icon: Icon(icon, size: 20, color: cs.primary),
                    tooltip: l10n.modelSelectSheetFavoriteTooltip,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerTab(BuildContext context, String key, String name) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton.icon(
        onPressed: () async { await _jumpToProvider(key); },
        onLongPress: () async {
          // Open provider detail page for quick edits
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderDetailPage(keyName: key, displayName: name),
            ),
          );
          if (mounted) setState(() {});
        },
        icon: _BrandAvatar(name: name, size: 16),
        label: Text(name, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
          backgroundColor: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
    );
  }

  Future<void> _jumpToProvider(String pk) async {
    // Expand sheet first if needed
    if (_sheetCtrl.size < _maxSize) {
      await _sheetCtrl.animateTo(
        _maxSize,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      // Wait a bit for the animation to complete
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Clear search if needed to ensure provider is visible
    if (_search.text.isNotEmpty) {
      setState(() => _search.clear());
      // Wait for the widget tree to rebuild
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Use pre-calculated offset
    final targetOffset = _headerOffsets[pk];
    if (targetOffset != null && _listCtrl?.hasClients == true) {
      // Calculate the actual scroll position
      // Subtract a small offset to show the header at the top with some padding
      final scrollTo = (targetOffset - 10).clamp(0.0, _listCtrl!.position.maxScrollExtent);
      
      await _listCtrl!.animateTo(
        scrollTo,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _displayName(BuildContext context, _ModelItem m) {
    final cfg = context.read<SettingsProvider>().getProviderConfig(m.providerKey, defaultName: m.providerName);
    final ov = cfg.modelOverrides[m.id] as Map?;
    if (ov != null) {
      final n = (ov['name'] as String?)?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return m.info.displayName;
  }

  ModelInfo _effectiveInfo(BuildContext context, _ModelItem m) {
    final cfg = context.read<SettingsProvider>().getProviderConfig(m.providerKey, defaultName: m.providerName);
    final ov = cfg.modelOverrides[m.id] as Map?;
    if (ov == null) return m.info;
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
    return m.info.copyWith(
      type: type ?? m.info.type,
      input: input ?? m.info.input,
      output: output ?? m.info.output,
      abilities: abilities ?? m.info.abilities,
    );
  }
}

class _ProviderGroup {
  final String name;
  final List<_ModelItem> items;
  _ProviderGroup({required this.name, required this.items});
}

class _ModelItem {
  final String providerKey;
  final String providerName;
  final String id;
  final ModelInfo info;
  final bool pinned;
  final bool selected;
  _ModelItem({required this.providerKey, required this.providerName, required this.id, required this.info, this.pinned = false, this.selected = false});
  _ModelItem copyWith({bool? pinned, bool? selected}) => _ModelItem(providerKey: providerKey, providerName: providerName, id: id, info: info, pinned: pinned ?? this.pinned, selected: selected ?? this.selected);
}

// Reuse badges and avatars similar to provider detail
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
      RegExp(r'qwen|qwq|qvq|aliyun|dashscope'): 'qwen-color.svg',
      RegExp(r'doubao|ark|volc'): 'doubao-color.svg',
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
      RegExp(r'xai|grok'): 'xai.svg',
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _assetForName(name);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.62,
          height: size * 0.62,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset, width: size * 0.62, height: size * 0.62, fit: BoxFit.contain);
      }
    } else {
      inner = Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

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
  // modality tag capsule with icons (keep consistent with provider detail page)
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
  // abilities capsules
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
