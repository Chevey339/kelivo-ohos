import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../icons/lucide_adapter.dart';
import 'provider_detail_page.dart';
import '../widgets/import_provider_sheet.dart';
import '../widgets/add_provider_sheet.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  List<_Provider>? _items;
  final Set<String> _settleKeys = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Base, fixed providers (recompute each build so dynamic additions reflect immediately)
    final base = _providers(l10n: l10n);

    // Dynamic providers from settings
    final settings = context.watch<SettingsProvider>();
    final cfgs = settings.providerConfigs;
    final baseKeys = {for (final p in base) p.keyName};
    final dynamicItems = <_Provider>[];
    cfgs.forEach((key, cfg) {
      if (!baseKeys.contains(key)) {
        dynamicItems.add(_Provider(
          name: (cfg.name.isNotEmpty ? cfg.name : key),
          keyName: key,
          enabled: cfg.enabled,
          modelCount: cfg.models.length,
        ));
      }
    });

    // Merge base + dynamic, then apply saved order
    final merged = <_Provider>[...base, ...dynamicItems];
    final order = settings.providersOrder;
    final map = {for (final p in merged) p.keyName: p};
    final tmp = <_Provider>[];
    for (final k in order) {
      final p = map.remove(k);
      if (p != null) tmp.add(p);
    }
    // Append any remaining providers not recorded in order
    tmp.addAll(map.values);
    final items = tmp;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.providersPageTitle),
        actions: [
          IconButton(
            tooltip: l10n.providersPageImportTooltip,
            icon: Icon(Lucide.Import, color: cs.onSurface),
            onPressed: () async {
              await showImportProviderSheet(context);
              if (!mounted) return;
              setState(() {});
            },
          ),
          IconButton(
            tooltip: l10n.providersPageAddTooltip,
            icon: Icon(Lucide.Plus, color: cs.onSurface),
            onPressed: () async {
              final createdKey = await showAddProviderSheet(context);
              if (!mounted) return;
              if (createdKey != null && createdKey.isNotEmpty) {
                setState(() {});
                final msg = l10n.providersPageProviderAddedSnackbar;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tileHeight = 148.0;
            const spacing = 10.0;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            final ratio = tileWidth / tileHeight;
            return ReorderableGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: ratio,
              dragStartDelay: const Duration(milliseconds: 380),
              onReorder: (oldIndex, newIndex) async {
                final moved = items[oldIndex];
                final mut = List<_Provider>.of(items);
                final item = mut.removeAt(oldIndex);
                mut.insert(newIndex, item);
                setState(() => _settleKeys.add(moved.keyName));
                await context.read<SettingsProvider>().setProvidersOrder([
                  for (final p in mut) p.keyName
                ]);
                Future.delayed(const Duration(milliseconds: 220), () {
                  if (!mounted) return;
                  setState(() => _settleKeys.remove(moved.keyName));
                });
              },
              dragWidgetBuilder: (index, child) => Opacity(
                opacity: 0.95,
                child: Transform.scale(scale: 0.94, child: child),
              ),
              children: [
                for (int i = 0; i < items.length; i++)
                  KeyedSubtree(
                    key: ValueKey(items[i].keyName),
                    child: _SettleAnim(
                      active: _settleKeys.contains(items[i].keyName),
                      child: _ProviderCard(provider: items[i], compact: true),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_Provider> _providers({required AppLocalizations l10n}) => [
        _p('KelivoIN', 'KelivoIN', enabled: true, models: 0),
        _p('OpenAI', 'OpenAI', enabled: true, models: 0),
        _p('Gemini', 'Gemini', enabled: true, models: 0),
        _p(l10n.providersPageSiliconFlowName, 'SiliconFlow', enabled: true, models: 0),
        _p('OpenRouter', 'OpenRouter', enabled: true, models: 0),
        _p('DeepSeek', 'DeepSeek', enabled: false, models: 0),
        _p(l10n.providersPageAliyunName, 'Aliyun', enabled: false, models: 0),
        _p(l10n.providersPageZhipuName, 'Zhipu AI', enabled: false, models: 0),
        _p('Claude', 'Claude', enabled: false, models: 0),
        // _p(zh ? '腾讯混元' : 'Hunyuan', 'Hunyuan', enabled: false, models: 0),
        // _p('InternLM', 'InternLM', enabled: true, models: 0),
        // _p('Kimi', 'Kimi', enabled: false, models: 0),
        _p('Grok', 'Grok', enabled: false, models: 0),
        // _p('302.AI', '302.AI', enabled: false, models: 0),
        // _p(zh ? '阶跃星辰' : 'StepFun', 'StepFun', enabled: false, models: 0),
        // _p('MiniMax', 'MiniMax', enabled: true, models: 0),
        _p(l10n.providersPageByteDanceName, 'ByteDance', enabled: false, models: 0),
        // _p(zh ? '豆包' : 'Doubao', 'Doubao', enabled: true, models: 0),
        // _p(zh ? '阿里云' : 'Alibaba Cloud', 'Alibaba Cloud', enabled: true, models: 0),
        // _p('Meta', 'Meta', enabled: false, models: 0),
        // _p('Mistral', 'Mistral', enabled: true, models: 0),
        // _p('Perplexity', 'Perplexity', enabled: true, models: 0),
        // _p('Cohere', 'Cohere', enabled: true, models: 0),
        // _p('Gemma', 'Gemma', enabled: true, models: 0),
        // _p('Cloudflare', 'Cloudflare', enabled: true, models: 0),
        //  _p('AIHubMix', 'AIHubMix', enabled: false, models: 0),
        // _p('Ollama', 'Ollama', enabled: true, models: 0),
        // _p('GitHub', 'GitHub', enabled: false, models: 0),
      ];

  _Provider _p(String name, String key, {required bool enabled, required int models}) =>
      _Provider(name: name, keyName: key, enabled: enabled, modelCount: models);
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, this.compact = false});
  final _Provider provider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(provider.keyName, defaultName: provider.name);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final enabled = cfg.enabled;
    final bg = enabled
        ? (isDark ? Colors.white12 : const Color(0xFFF7F7F9))
        : (isDark ? cs.errorContainer.withOpacity(0.30) : cs.errorContainer.withOpacity(0.25));

    final statusBg = enabled ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.15);
    final statusFg = enabled ? Colors.green.shade700 : Colors.orange.shade700;
    final modelsBg = cs.primary.withOpacity(0.12);
    final modelsFg = cs.primary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderDetailPage(
                keyName: provider.keyName,
                displayName: provider.name,
              ),
            ),
          );
        },
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(10, compact ? 10 : 12, 10, compact ? 8 : 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _BrandAvatar(
                    name: (cfg.name.isNotEmpty ? cfg.name : provider.keyName),
                    size: compact ? 40 : 44,
                  ),
                  Text(
                    (cfg.name.isNotEmpty ? cfg.name : provider.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _Pill(
                            text: enabled ? l10n.providersPageEnabledStatus : l10n.providersPageDisabledStatus,
                            bg: statusBg,
                            fg: statusFg,
                          ),
                        ),
                      ),
                      _Pill(
                        text: '${cfg.models.length}${l10n.providersPageModelsCountSingleSuffix}',
                        bg: modelsBg,
                        fg: modelsFg,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // No explicit drag handle; whole card can be long-pressed to drag.
          ],
        ),
      ),
    );
  }
}

// Drag handle removed per design; dragging is triggered by long-pressing the card.

// Replaced custom reorder grid with reorderable_grid_view for
// smoother, battle-tested drag animations and reordering.

class _SettleAnim extends StatelessWidget {
  const _SettleAnim({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tween = Tween<double>(begin: active ? 0.94 : 1.0, end: 1.0);
    return TweenAnimationBuilder<double>(
      tween: tween,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, scale, _) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: 1.0,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11)),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 40});
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
    if (RegExp(r'openrouter').hasMatch(k)) return true;
    return false;
  }

  bool _tintPurpleSilicon(String n) {
    final k = n.toLowerCase();
    return RegExp(r'silicon|硅基').hasMatch(k);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = _assetForName(name);
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: asset == null
          ? Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.42))
          : _IconAsset(
              asset: asset,
              size: size * 0.62,
              monochromeWhite: isDark && _preferMonochromeWhite(name),
              tintColor: _tintPurpleSilicon(name) ? const Color(0xFF7C4DFF) : null,
            ),
    );
    return circle;
  }
}

class _IconAsset extends StatelessWidget {
  const _IconAsset({required this.asset, required this.size, this.monochromeWhite = false, this.tintColor});
  final String asset;
  final double size;
  final bool monochromeWhite;
  final Color? tintColor;
  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: monochromeWhite
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : (tintColor != null ? ColorFilter.mode(tintColor!, BlendMode.srcIn) : null),
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: monochromeWhite ? Colors.white : tintColor,
      colorBlendMode: (monochromeWhite || tintColor != null) ? BlendMode.srcIn : null,
    );
  }
}

class _Provider {
  final String name;
  final String keyName;
  final bool enabled;
  final int modelCount;
  _Provider({required this.name, required this.keyName, required this.enabled, required this.modelCount});
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDragStarted, required this.onDragEnd, required this.feedback, required this.data});
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final Widget feedback;
  final int data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LongPressDraggable<int>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: (_) => onDragEnd(),
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Opacity(opacity: 0.95, child: feedback),
        ),
      ),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(Lucide.GripHorizontal, size: 24, color: cs.onSurface.withOpacity(0.7)),
      ),
      childWhenDragging: const SizedBox(width: 40, height: 40),
    );
  }
}
