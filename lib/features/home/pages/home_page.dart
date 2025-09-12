import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';

import '../widgets/chat_input_bar.dart';
import '../../../core/models/chat_input_data.dart';
import '../../chat/widgets/bottom_tools_sheet.dart';
import '../widgets/side_drawer.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../main.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/prompt_transformer.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../settings/widgets/language_select_sheet.dart';
import '../../chat/widgets/message_more_sheet.dart';
import '../../chat/pages/message_edit_page.dart';
import '../../chat/widgets/message_export_sheet.dart';
import '../../assistant/widgets/mcp_assistant_sheet.dart';
import '../../chat/widgets/reasoning_budget_sheet.dart';
import '../../search/widgets/search_settings_sheet.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../utils/markdown_media_sanitizer.dart';
import '../../../core/services/learning_mode_store.dart';
import '../../../shared/animations/widgets.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin, RouteAware {
  bool _toolsOpen = false;
  static const double _sheetHeight = 256; // height of tools area
  // Animation tuning
  static const Duration _scrollAnimateDuration = Duration(milliseconds: 300);
  static const Duration _postSwitchScrollDelay = Duration(milliseconds: 220);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ZoomDrawerController _drawerController = ZoomDrawerController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _inputController = TextEditingController();
  final ChatInputBarController _mediaController = ChatInputBarController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _inputBarKey = GlobalKey();
  late final AnimationController _convoFadeController;
  late final Animation<double> _convoFade;
  double _inputBarHeight = 72;

  late ChatService _chatService;
  Conversation? _currentConversation;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  StreamSubscription? _messageStreamSubscription;
  final Map<String, _ReasoningData> _reasoning = <String, _ReasoningData>{};
  final Map<String, _TranslationData> _translations = <String, _TranslationData>{};
  final Map<String, List<ToolUIPart>> _toolParts = <String, List<ToolUIPart>>{}; // assistantMessageId -> parts
  final Map<String, List<_ReasoningSegmentData>> _reasoningSegments = <String, List<_ReasoningSegmentData>>{}; // assistantMessageId -> reasoning segments
  McpProvider? _mcpProvider;
  Set<String> _connectedMcpIds = <String>{};
  bool _showJumpToBottom = false;
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;

  // Drawer haptics for swipe-open
  DrawerState? _lastDrawerState;
  bool _suppressNextOpenHaptic = false; // set when we already vibrated on programmatic open
  ValueNotifier<DrawerState>? _drawerStateNotifier;

  // Deduplicate tool UI parts by id or by name+args when id is empty
  List<ToolUIPart> _dedupeToolPartsList(List<ToolUIPart> parts) {
    final seen = <String>{};
    final out = <ToolUIPart>[];
    for (final p in parts) {
      final id = (p.id).trim();
      final key = id.isNotEmpty ? 'id:$id' : 'name:${p.toolName}|args:${jsonEncode(p.arguments)}';
      if (seen.add(key)) out.add(p);
    }
    return out;
  }

  // Deduplicate raw persisted tool events using same criteria
  List<Map<String, dynamic>> _dedupeToolEvents(List<Map<String, dynamic>> events) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final e in events) {
      final id = (e['id']?.toString() ?? '').trim();
      final name = (e['name']?.toString() ?? '');
      final args = ((e['arguments'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
      final key = id.isNotEmpty ? 'id:$id' : 'name:$name|args:${jsonEncode(args)}';
      if (seen.add(key)) out.add(e.map((k, v) => MapEntry(k.toString(), v)));
    }
    return out;
  }

  // Selection mode state for export/share
  bool _selecting = false;
  final Set<String> _selectedItems = <String>{}; // selected message ids (collapsed view)

  // Helper methods to serialize/deserialize reasoning segments
  String _serializeReasoningSegments(List<_ReasoningSegmentData> segments) {
    final list = segments.map((s) => {
      'text': s.text,
      'startAt': s.startAt?.toIso8601String(),
      'finishedAt': s.finishedAt?.toIso8601String(),
      'expanded': s.expanded,
      'toolStartIndex': s.toolStartIndex,
    }).toList();
    return jsonEncode(list);
  }

  List<_ReasoningSegmentData> _deserializeReasoningSegments(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((item) {
        final s = _ReasoningSegmentData();
        s.text = item['text'] ?? '';
        s.startAt = item['startAt'] != null ? DateTime.parse(item['startAt']) : null;
        s.finishedAt = item['finishedAt'] != null ? DateTime.parse(item['finishedAt']) : null;
        s.expanded = item['expanded'] ?? false;
        s.toolStartIndex = (item['toolStartIndex'] as int?) ?? 0;
        return s;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  bool _isReasoningModel(String providerKey, String modelId) {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null) {
      final abilities = (ov['abilities'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (abilities.map((e) => e.toLowerCase()).contains('reasoning')) return true;
    }
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    return inferred.abilities.contains(ModelAbility.reasoning);
  }

  Future<void> _cancelStreaming() async {
    // Cancel active stream subscription, if any
    final sub = _messageStreamSubscription;
    _messageStreamSubscription = null;
    await sub?.cancel();

    // Find the latest assistant streaming message and mark it finished
    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) {
        streaming = m;
        break;
      }
    }
    if (streaming != null) {
      // Persist whatever content we have so far and mark finished
      await _chatService.updateMessage(
        streaming.id,
        content: streaming.content,
        isStreaming: false,
        totalTokens: streaming.totalTokens,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == streaming!.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
          _isLoading = false;
        });
      }
      final r = _reasoning[streaming.id];
      if (r != null) {
        if (r.finishedAt == null) {
          r.finishedAt = DateTime.now();
          await _chatService.updateMessage(
            streaming.id,
            reasoningText: r.text,
            reasoningFinishedAt: r.finishedAt,
          );
        }
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          r.expanded = false;
        }
        _reasoning[streaming.id] = r;
        if (mounted) setState(() {});
      }

      // Also finalize any unfinished reasoning segment blocks and persist them
      final segs = _reasoningSegments[streaming.id];
      if (segs != null && segs.isNotEmpty && segs.last.finishedAt == null) {
        segs.last.finishedAt = DateTime.now();
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          segs.last.expanded = false;
        }
        _reasoningSegments[streaming.id] = segs;
        await _chatService.updateMessage(
          streaming.id,
          reasoningSegmentsJson: _serializeReasoningSegments(segs),
        );
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isReasoningEnabled(int? budget) {
    if (budget == null) return true; // treat null as default/auto -> enabled
    if (budget == -1) return true; // auto
    return budget >= 1024;
  }

  String _titleForLocale(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.titleForLocale;
  }

  // Version selections (groupId -> selected version index)
  Map<String, int> _versionSelections = <String, int>{};

  void _loadVersionSelections() {
    final cid = _currentConversation?.id;
    if (cid == null) {
      _versionSelections = <String, int>{};
      return;
    }
    try {
      _versionSelections = _chatService.getVersionSelections(cid);
    } catch (_) {
      _versionSelections = <String, int>{};
    }
  }

  // Restore per-message UI states (reasoning/segments/tool parts/translation) after switching conversations
  void _restoreMessageUiState() {
    // Clear first to avoid stale entries
    _reasoning.clear();
    _reasoningSegments.clear();
    _toolParts.clear();
    _translations.clear();

    for (final m in _messages) {
      if (m.role == 'assistant') {
        // Restore reasoning state
        final txt = m.reasoningText ?? '';
        if (txt.isNotEmpty || m.reasoningStartAt != null || m.reasoningFinishedAt != null) {
          final rd = _ReasoningData();
          rd.text = txt;
          rd.startAt = m.reasoningStartAt;
          rd.finishedAt = m.reasoningFinishedAt;
          rd.expanded = false;
          _reasoning[m.id] = rd;
        }

        // Restore tool events persisted for this assistant message
        try {
          final events = _dedupeToolEvents(_chatService.getToolEvents(m.id));
          if (events.isNotEmpty) {
            _toolParts[m.id] = events
                .map((e) => ToolUIPart(
                      id: (e['id'] ?? '').toString(),
                      toolName: (e['name'] ?? '').toString(),
                      arguments: (e['arguments'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
                      content: (e['content']?.toString().isNotEmpty == true) ? e['content'].toString() : null,
                      loading: !(e['content']?.toString().isNotEmpty == true),
                    ))
                .toList();
          }
        } catch (_) {}

        // Restore reasoning segments
        final segments = _deserializeReasoningSegments(m.reasoningSegmentsJson);
        if (segments.isNotEmpty) {
          _reasoningSegments[m.id] = segments;
        }
      }

      // Restore translation UI state: default collapsed
      if (m.translation != null && m.translation!.isNotEmpty) {
        final td = _TranslationData();
        td.expanded = false;
        _translations[m.id] = td;
      }
    }
  }

  List<ChatMessage> _collapseVersions(List<ChatMessage> items) {
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    final List<String> order = <String>[];
    for (final m in items) {
      final gid = (m.groupId ?? m.id);
      final list = byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <ChatMessage>[];
      });
      list.add(m);
    }
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }
    final out = <ChatMessage>[];
    for (final gid in order) {
      final vers = byGroup[gid]!;
      final sel = _versionSelections[gid];
      final idx = (sel != null && sel >= 0 && sel < vers.length) ? sel : (vers.length - 1);
      out.add(vers[idx]);
    }
    return out;
  }

  String _clearContextLabel() {
    final l10n = AppLocalizations.of(context)!;
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final configured = assistant?.contextMessageSize ?? 0;
    final t = _currentConversation?.truncateIndex ?? -1;
    int remaining = 0;
    for (int i = 0; i < _messages.length; i++) {
      if (i >= (t < 0 ? 0 : t)) {
        if (_messages[i].content.trim().isNotEmpty) remaining++;
      }
    }
    if (configured > 0) {
      final actual = remaining > configured ? configured : remaining;
      return l10n.homePageClearContextWithCount(actual.toString(), configured.toString());
    }
    return l10n.homePageClearContext;
  }

  Future<void> _onClearContext() async {
    final convo = _currentConversation;
    if (convo == null) return;
    final updated = await _chatService.toggleTruncateAtTail(convo.id, defaultTitle: _titleForLocale(context));
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _currentConversation = updated;
      });
    }
    if (_toolsOpen) _toggleTools();
  }

  void _toggleTools() {
    setState(() {
      final opening = !_toolsOpen;
      _toolsOpen = !_toolsOpen;
      if (opening) _dismissKeyboard();
    });
  }

  bool _isToolModel(String providerKey, String modelId) {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null) {
      final abilities = (ov['abilities'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      if (abilities.map((e) => e.toLowerCase()).contains('tool')) return true;
    }
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    return inferred.abilities.contains(ModelAbility.tool);
  }

  // More page entry is temporarily removed.
  // void _openMorePage() {
  //   _dismissKeyboard();
  //   Navigator.of(context).push(
  //     MaterialPageRoute(builder: (_) => const MorePage()),
  //   );
  // }

  void _dismissKeyboard() {
    _inputFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void initState() {
    super.initState();
    _convoFadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _convoFade = CurvedAnimation(parent: _convoFadeController, curve: Curves.easeOutCubic);
    _convoFadeController.value = 1.0;
    // Use the provided ChatService instance
    _chatService = context.read<ChatService>();
    _initChat();
    _scrollController.addListener(_onScrollControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());

    // Attach MCP provider listener to auto-join new connected servers
    try {
      _mcpProvider = context.read<McpProvider>();
      _connectedMcpIds = _mcpProvider!.connectedServers.map((s) => s.id).toSet();
      _mcpProvider!.addListener(_onMcpChanged);
    } catch (_) {}

    // 监听键盘弹出
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        // 延迟一下等待键盘完全弹出
        Future.delayed(const Duration(milliseconds: 300), () {
          _scrollToBottom();
        });
      }
    });

    // Attach ZoomDrawer state listener after first frame to catch swipe-open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachDrawerStateListener();
    });
  }

  void _attachDrawerStateListener() {
    // Avoid duplicate listeners
    final notifier = _drawerController.stateNotifier;
    if (notifier == null) return;
    if (!identical(_drawerStateNotifier, notifier)) {
      // Remove old
      _drawerStateNotifier?.removeListener(_onDrawerStateChanged);
      _drawerStateNotifier = notifier;
      _drawerStateNotifier!.addListener(_onDrawerStateChanged);
    }
  }

  void _onDrawerStateChanged() {
    final s = _drawerController.stateNotifier?.value;
    if (s == null) return;
    // Fire once when transitioning from closed/closing to opening (covers swipe-open)
    final wasClosedLike = _lastDrawerState == null ||
        _lastDrawerState == DrawerState.closed ||
        _lastDrawerState == DrawerState.closing;
    if (wasClosedLike && s == DrawerState.opening) {
      if (_suppressNextOpenHaptic) {
        // Skip duplicate when we already vibrated on programmatic open
        _suppressNextOpenHaptic = false;
      } else {
        try {
          if (context.read<SettingsProvider>().hapticsOnDrawer) {
            HapticFeedback.mediumImpact();
          }
        } catch (_) {}
      }
    }
    _lastDrawerState = s;
  }

  void _onScrollControllerChanged() {
    try {
      if (!_scrollController.hasClients) return;
      
      // Detect user scrolling
      if (_scrollController.position.userScrollDirection != ScrollDirection.idle) {
        _isUserScrolling = true;
        
        // Cancel previous timer and set a new one
        _userScrollTimer?.cancel();
        _userScrollTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() {
              _isUserScrolling = false;
            });
          }
        });
      }
      
      // Only show when not near bottom
      final pos = _scrollController.position;
      final atBottom = pos.pixels >= (pos.maxScrollExtent - 24);
      final shouldShow = !atBottom;
      if (_showJumpToBottom != shouldShow) {
        setState(() => _showJumpToBottom = shouldShow);
      }
    } catch (_) {}
  }

  Future<void> _initChat() async {
    await _chatService.init();
    // Respect user preference: create new chat on launch
    final prefs = context.read<SettingsProvider>();
    if (prefs.newChatOnLaunch) {
      await _createNewConversation();
    } else {
      // When disabled, jump to the most recent conversation if exists
      final conversations = _chatService.getAllConversations();
      if (conversations.isNotEmpty) {
        final recent = conversations.first; // already sorted by updatedAt desc
        _chatService.setCurrentConversation(recent.id);
        final msgs = _chatService.getMessages(recent.id);
        setState(() {
          _currentConversation = recent;
          _messages = List.of(msgs);
          _loadVersionSelections();
          _restoreMessageUiState();
        });
        _scrollToBottomSoon();
      }
    }
  }

  // _onMcpChanged defined below; remove listener in the main dispose at bottom

  Future<void> _onMcpChanged() async {
    if (!mounted) return;
    final prov = _mcpProvider;
    if (prov == null) return;
    final now = prov.connectedServers.map((s) => s.id).toSet();
    final added = now.difference(_connectedMcpIds);
    _connectedMcpIds = now;
    // Assistant-level MCP selection is managed in Assistant settings; no per-conversation merge.
  }

  Future<List<String>> _copyPickedFiles(List<XFile> files) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory("${docs.path}/upload");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final out = <String>[];
    for (final f in files) {
      try {
        final name = f.name.isNotEmpty ? f.name : DateTime.now().millisecondsSinceEpoch.toString();
        final dest = File("${dir.path}/$name");
        await dest.writeAsBytes(await f.readAsBytes());
        out.add(dest.path);
      } catch (_) {}
    }
    return out;
  }

  Future<void> _onPickPhotos() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files == null || files.isEmpty) return;
      final paths = await _copyPickedFiles(files);
      if (paths.isNotEmpty) {
        _mediaController.addImages(paths);
        _scrollToBottomSoon();
      }
    } catch (_) {} finally {
      if (mounted && _toolsOpen) _toggleTools();
    }
  }

  Future<void> _onPickCamera() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file == null) return;
      final paths = await _copyPickedFiles([file]);
      if (paths.isNotEmpty) {
        _mediaController.addImages(paths);
        _scrollToBottomSoon();
      }
    } catch (_) {} finally {
      if (mounted && _toolsOpen) _toggleTools();
    }
  }

  String _inferMimeByExtension(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
    return 'text/plain';
  }

  Future<void> _onPickFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.custom,
        allowedExtensions: const [
          'txt','md','json','js','pdf','docx'
        ],
      );
      if (res == null || res.files.isEmpty) return;
      final docs = <DocumentAttachment>[];
      final toCopy = <XFile>[];
      for (final f in res.files) {
        if (f.path != null && f.path!.isNotEmpty) {
          toCopy.add(XFile(f.path!));
        }
      }
      final saved = await _copyPickedFiles(toCopy);
      for (int i = 0; i < saved.length; i++) {
        final orig = res.files[i];
        final savedPath = saved[i];
        final name = orig.name;
        final mime = _inferMimeByExtension(name);
        docs.add(DocumentAttachment(path: savedPath, fileName: name, mime: mime));
      }
      if (docs.isNotEmpty) {
        _mediaController.addFiles(docs);
        _scrollToBottomSoon();
      }
    } catch (_) {} finally {
      if (mounted && _toolsOpen) _toggleTools();
    }
  }

  Future<void> _createNewConversation() async {
    final ap = context.read<AssistantProvider>();
    final settings = context.read<SettingsProvider>();
    final assistantId = ap.currentAssistantId;
    // If assistant has a default chat model, seed the global current model for this new conversation
    final a = ap.currentAssistant;
    if (a?.chatModelProvider != null && a?.chatModelId != null) {
      await settings.setCurrentModel(a!.chatModelProvider!, a.chatModelId!);
    }
    final conversation = await _chatService.createDraftConversation(title: _titleForLocale(context), assistantId: assistantId);
    // Default-enable MCP: select all connected servers for this conversation
    // MCP defaults are now managed per assistant; no per-conversation enabling here
    setState(() {
      _currentConversation = conversation;
      _messages = [];
      _versionSelections.clear();
      _reasoning.clear();
      _translations.clear();
      _toolParts.clear();
      _reasoningSegments.clear();
    });
    _scrollToBottomSoon();
  }

  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_currentConversation == null) await _createNewConversation();

    final settings = context.read<SettingsProvider>();
    // Use the user's currently selected model (seeded on new chat by assistant default if set)
    final providerKey = settings.currentModelProvider;
    final modelId = settings.currentModelId;
    final assistant = context.read<AssistantProvider>().currentAssistant;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.homePagePleaseSelectModel)),
      );
      return;
    }

    // Add user message
    // Persist user message; append image and document markers for display
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents.map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]').join();
    final userMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'user',
      content: content + imageMarkers + docMarkers,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    // 延迟滚动确保UI更新完成
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    // Create assistant message placeholder
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    // Haptics on generate (if enabled)
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    // Reset tool parts for this new assistant message
    _toolParts.remove(assistantMessage.id);

    // Initialize reasoning state only when enabled and model supports it
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && _isReasoningEnabled((assistant?.thinkingBudget) ?? settings.thinkingBudget);
    if (enableReasoning) {
      final rd = _ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(
        assistantMessage.id,
        reasoningStartAt: DateTime.now(),
      );
    }

    // 添加助手消息后也滚动到底部
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    // Prepare messages for API
    // Apply truncateIndex and collapse versions first, then transform the last user message to include document content
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= _messages.length)
        ? _messages.sublist(tIndex)
        : List.of(_messages);
    final List<ChatMessage> source = _collapseVersions(sourceAll);
    final apiMessages = source
        .where((m) => m.content.isNotEmpty)
        .map((m) => {
              'role': m.role == 'assistant' ? 'assistant' : 'user',
              'content': m.content,
            })
        .toList();

    // Build document prompts and clean markers in last user message
    if (apiMessages.isNotEmpty) {
      // Find last user message index in apiMessages
      int lastUserIdx = -1;
      for (int i = apiMessages.length - 1; i >= 0; i--) {
        if (apiMessages[i]['role'] == 'user') { lastUserIdx = i; break; }
      }
      if (lastUserIdx != -1) {
        final raw = (apiMessages[lastUserIdx]['content'] ?? '').toString();
        final cleaned = raw
            .replaceAll(RegExp(r"\[image:.*?\]"), '')
            .replaceAll(RegExp(r"\[file:.*?\]"), '')
            .trim();
        // Build document prompts
        final filePrompts = StringBuffer();
        for (final d in input.documents) {
          try {
            final text = await DocumentTextExtractor.extract(path: d.path, mime: d.mime);
            filePrompts.writeln('## user sent a file: ${d.fileName}');
            filePrompts.writeln('<content>');
            filePrompts.writeln('```');
            filePrompts.writeln(text);
            filePrompts.writeln('```');
            filePrompts.writeln('</content>');
            filePrompts.writeln();
          } catch (_) {}
        }
        final merged = (filePrompts.toString() + cleaned).trim();
        final userText = merged.isEmpty ? cleaned : merged;
        // Apply message template if set
        final templ = (assistant?.messageTemplate ?? '{{ message }}').trim().isEmpty
            ? '{{ message }}'
            : (assistant!.messageTemplate);
        final templated = PromptTransformer.applyMessageTemplate(
          templ,
          role: 'user',
          message: userText,
          now: DateTime.now(),
        );
        apiMessages[lastUserIdx]['content'] = templated;
      }
    }

    // Inject system prompt (assistant.systemPrompt with placeholders)
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }

    // Determine tool support and built-in Gemini search status
    final supportsTools = _isToolModel(providerKey, modelId);
    bool _hasBuiltInGeminiSearch() {
      try {
        final cfg = settings.getProviderConfig(providerKey);
        // Only official Gemini API supports built-in search
        if (cfg.providerType != ProviderKind.google || (cfg.vertexAI == true)) return false;
        final ov = cfg.modelOverrides[modelId] as Map?;
        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
        return list.map((e) => e.toString().toLowerCase()).contains('search');
      } catch (_) {
        return false;
      }
    }
    final hasBuiltInSearch = _hasBuiltInGeminiSearch();

    // Optionally inject search tool usage guide (when search is enabled and not using Gemini built-in search)
    if (settings.searchEnabled && !hasBuiltInSearch) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject learning mode prompt when enabled (global)
    try {
      final lmEnabled = await LearningModeStore.isEnabled();
      if (lmEnabled) {
        final lp = await LearningModeStore.getPrompt();
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + lp;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': lp});
        }
      }
    } catch (_) {}

    // Limit context length according to assistant settings
    if ((assistant?.contextMessageSize ?? 0) > 0) {
      final keep = assistant!.contextMessageSize.clamp(1, 512).toInt();
      // Always keep the first message if it's system
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages
          ..removeRange(startIdx, apiMessages.length)
          ..addAll(trimmed);
      }
    }

    // Convert any local Markdown image links to inline base64 for model context
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] = await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }

    // Get provider config
    final config = settings.getProviderConfig(providerKey);

    // Stream response
    String fullContent = '';
    int totalTokens = 0;
    TokenUsage? usage;
    // Respect assistant streaming toggle: if off, buffer updates until done
    final bool streamOutput = assistant?.streamOutput ?? true;
    String _bufferedReasoning = '';
    DateTime? _reasoningStartAt;

    try {
      // Prepare tools (Search tool + MCP tools)
      final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
      Future<String> Function(String, Map<String, dynamic>)? onToolCall;

      // Search tool (skip when Gemini built-in search is active)
      if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }

      // MCP tools
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      if (supportsTools && tools.isNotEmpty) {
        toolDefs.addAll(tools.map((t) {
          final props = <String, dynamic>{
            for (final p in t.params) p.name: {'type': 'string'},
          };
          final required = [for (final p in t.params.where((e) => e.required)) p.name];
          return {
            'type': 'function',
            'function': {
              'name': t.name,
              if ((t.description ?? '').isNotEmpty) 'description': t.description,
              'parameters': {
                'type': 'object',
                'properties': props,
                'required': required,
              },
            }
          };
        }));
      }

      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          // Fallback to MCP tools
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }

      // Build assistant-level custom request overrides
      Map<String, String>? aHeaders;
      Map<String, dynamic>? aBody;
      if ((assistant?.customHeaders.isNotEmpty ?? false)) {
        aHeaders = {
          for (final e in assistant!.customHeaders)
            if ((e['name'] ?? '').trim().isNotEmpty) (e['name']!.trim()): (e['value'] ?? '')
        };
        if (aHeaders.isEmpty) aHeaders = null;
      }
      if ((assistant?.customBody.isNotEmpty ?? false)) {
        aBody = {
          for (final e in assistant!.customBody)
            if ((e['key'] ?? '').trim().isNotEmpty)
              (e['key']!.trim()): (e['value'] ?? '')
        };
        if (aBody.isEmpty) aBody = null;
      }

    final stream = ChatApiService.sendMessageStream(
      config: config,
      modelId: modelId,
      messages: apiMessages,
      userImagePaths: input.imagePaths,
      thinkingBudget: assistant?.thinkingBudget ?? settings.thinkingBudget,
      temperature: assistant?.temperature,
      topP: assistant?.topP,
      maxTokens: assistant?.maxTokens,
      tools: toolDefs.isEmpty ? null : toolDefs,
        onToolCall: onToolCall,
        extraHeaders: aHeaders,
        extraBody: aBody,
      );

      Future<void> finish({bool generateTitle = true}) async {
        // Replace extremely long inline base64 images with local files to avoid jank
        final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(fullContent);
        await _chatService.updateMessage(
          assistantMessage.id,
          content: processedContent,
          totalTokens: totalTokens,
          isStreaming: false,
        );
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              content: processedContent,
              totalTokens: totalTokens,
              isStreaming: false,
            );
          }
          _isLoading = false;
        });
        final r = _reasoning[assistantMessage.id];
        if (r != null) {
          if (r.finishedAt == null) {
            r.finishedAt = DateTime.now();
          }
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            r.expanded = false; // auto close after finish
          }
          _reasoning[assistantMessage.id] = r;
          if (mounted) setState(() {});
        }

        // Also finish any unfinished reasoning segments
        final segments = _reasoningSegments[assistantMessage.id];
        if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
          segments.last.finishedAt = DateTime.now();
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            segments.last.expanded = false;
          }
          _reasoningSegments[assistantMessage.id] = segments;
          if (mounted) setState(() {});
        }

        // Save reasoning segments to database
        if (segments != null && segments.isNotEmpty) {
          await _chatService.updateMessage(
            assistantMessage.id,
            reasoningSegmentsJson: _serializeReasoningSegments(segments),
          );
        }
        if (generateTitle) {
          _maybeGenerateTitle();
        }
      }

      _messageStreamSubscription?.cancel();
      _messageStreamSubscription = stream.listen(
            (chunk) async {
          // Capture reasoning deltas only when reasoning is enabled
          if ((chunk.reasoning ?? '').isNotEmpty && supportsReasoning && _isReasoningEnabled((assistant?.thinkingBudget) ?? settings.thinkingBudget)) {
            if (streamOutput) {
              final r = _reasoning[assistantMessage.id] ?? _ReasoningData();
              r.text += chunk.reasoning!;
              r.startAt ??= DateTime.now();
              r.finishedAt = null;
              r.expanded = true; // auto expand while generating
              _reasoning[assistantMessage.id] = r;

              // Add to reasoning segments for mixed display
              final segments = _reasoningSegments[assistantMessage.id] ?? <_ReasoningSegmentData>[];

              if (segments.isEmpty) {
                // First reasoning segment
                final newSegment = _ReasoningSegmentData();
                newSegment.text = chunk.reasoning!;
                newSegment.startAt = DateTime.now();
                newSegment.expanded = true;
                newSegment.toolStartIndex = (_toolParts[assistantMessage.id]?.length ?? 0);
                segments.add(newSegment);
              } else {
                // Check if we should start a new segment (after tool calls)
                final hasToolsAfterLastSegment = (_toolParts[assistantMessage.id]?.isNotEmpty ?? false);
                final lastSegment = segments.last;

                if (hasToolsAfterLastSegment && lastSegment.finishedAt != null) {
                  // Start a new segment after tools
                  final newSegment = _ReasoningSegmentData();
                  newSegment.text = chunk.reasoning!;
                  newSegment.startAt = DateTime.now();
                  newSegment.expanded = true;
                  newSegment.toolStartIndex = (_toolParts[assistantMessage.id]?.length ?? 0);
                  segments.add(newSegment);
                } else {
                  // Continue current segment
                  lastSegment.text += chunk.reasoning!;
                  lastSegment.startAt ??= DateTime.now();
                }
              }
              _reasoningSegments[assistantMessage.id] = segments;

              // Save segments to database periodically
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningSegmentsJson: _serializeReasoningSegments(segments),
              );

              if (mounted) setState(() {});
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningText: r.text,
                reasoningStartAt: r.startAt,
              );
            } else {
              // Buffer reasoning only; commit on finish
              _reasoningStartAt ??= DateTime.now();
              _bufferedReasoning += chunk.reasoning!;
            }
          }

          // MCP tool call placeholders
          if ((chunk.toolCalls ?? const []).isNotEmpty) {
            // Finish current reasoning segment if exists, and auto-collapse per settings
            final segments = _reasoningSegments[assistantMessage.id] ?? <_ReasoningSegmentData>[];
            if (segments.isNotEmpty && segments.last.finishedAt == null) {
              segments.last.finishedAt = DateTime.now();
              final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
              if (autoCollapse) {
                segments.last.expanded = false;
                final rd = _reasoning[assistantMessage.id];
                if (rd != null) rd.expanded = false;
              }
              _reasoningSegments[assistantMessage.id] = segments;
              // Persist closed segment state
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningSegmentsJson: _serializeReasoningSegments(segments),
              );
            }

            // Simply append new tool calls instead of merging by ID/name
            // This allows multiple calls to the same tool
            final existing = List<ToolUIPart>.of(_toolParts[assistantMessage.id] ?? const []);
            for (final c in chunk.toolCalls!) {
              existing.add(ToolUIPart(id: c.id, toolName: c.name, arguments: c.arguments, loading: true));
            }
            setState(() {
              _toolParts[assistantMessage.id] = _dedupeToolPartsList(existing);
            });

            // Persist placeholders - append new events
            try {
              final prev = _chatService.getToolEvents(assistantMessage.id);
              final newEvents = <Map<String, dynamic>>[
                ...prev,
                for (final c in chunk.toolCalls!)
                  {
                    'id': c.id,
                    'name': c.name,
                    'arguments': c.arguments,
                    'content': null,
                  },
              ];
              await _chatService.setToolEvents(assistantMessage.id, _dedupeToolEvents(newEvents));
            } catch (_) {}
          }

          // MCP tool results -> hydrate placeholders in-place (avoid extra tool message cards)
          if ((chunk.toolResults ?? const []).isNotEmpty) {
            final parts = List<ToolUIPart>.of(_toolParts[assistantMessage.id] ?? const []);
            for (final r in chunk.toolResults!) {
              // Find the first loading tool with matching ID or name
              // This ensures we update the correct placeholder even with multiple same-name tools
              int idx = -1;
              for (int i = 0; i < parts.length; i++) {
                if (parts[i].loading && (parts[i].id == r.id || (parts[i].id.isEmpty && parts[i].toolName == r.name))) {
                  idx = i;
                  break;
                }
              }

              if (idx >= 0) {
                parts[idx] = ToolUIPart(
                  id: parts[idx].id,
                  toolName: parts[idx].toolName,
                  arguments: parts[idx].arguments,
                  content: r.content,
                  loading: false,
                );
              } else {
                // If we didn't see the placeholder (edge case), append a finished part
                parts.add(ToolUIPart(
                  id: r.id,
                  toolName: r.name,
                  arguments: r.arguments,
                  content: r.content,
                  loading: false,
                ));
              }
              // Persist each event update
              try {
                await _chatService.upsertToolEvent(
                  assistantMessage.id,
                  id: r.id,
                  name: r.name,
                  arguments: r.arguments,
                  content: r.content,
                );
              } catch (_) {}
            }
            setState(() {
              _toolParts[assistantMessage.id] = _dedupeToolPartsList(parts);
            });
            _scrollToBottomSoon();
          }

          if (chunk.isDone) {
            // Guard: if we have any loading tool-call placeholders, a follow-up round is coming.
            final hasLoadingTool = (_toolParts[assistantMessage.id]?.any((p) => p.loading) ?? false);
            if (hasLoadingTool) {
              // Skip finishing now; wait for follow-up round.
              return;
            }
            // Capture final usage/tokens if only provided at end
            if (chunk.totalTokens > 0) {
              totalTokens = chunk.totalTokens;
            }
            if (chunk.usage != null) {
              usage = (usage ?? const TokenUsage()).merge(chunk.usage!);
              totalTokens = usage!.totalTokens;
            }
            await finish();
            // If non-streaming, persist buffered reasoning once at the end
            if (!streamOutput && _bufferedReasoning.isNotEmpty) {
              final now = DateTime.now();
              final startAt = _reasoningStartAt ?? now;
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningText: _bufferedReasoning,
                reasoningStartAt: startAt,
                reasoningFinishedAt: now,
              );
              final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
              _reasoning[assistantMessage.id] = _ReasoningData()
                ..text = _bufferedReasoning
                ..startAt = startAt
                ..finishedAt = now
                ..expanded = !autoCollapse;
              if (mounted) setState(() {});
            }
            await _messageStreamSubscription?.cancel();
            _messageStreamSubscription = null;
            final r = _reasoning[assistantMessage.id];
            if (r != null && r.finishedAt == null) {
              r.finishedAt = DateTime.now();
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningText: r.text,
                reasoningFinishedAt: r.finishedAt,
              );
            }
          } else {
            fullContent += chunk.content;
            if (chunk.totalTokens > 0) {
              totalTokens = chunk.totalTokens;
            }
            if (chunk.usage != null) {
              usage = (usage ?? const TokenUsage()).merge(chunk.usage!);
              totalTokens = usage!.totalTokens;
            }

            if (streamOutput) {
              // If content has started, consider reasoning finished and collapse
              if ((chunk.content).isNotEmpty) {
                final r = _reasoning[assistantMessage.id];
                if (r != null && r.startAt != null && r.finishedAt == null) {
                  r.finishedAt = DateTime.now();
                  final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
                  if (autoCollapse) {
                    r.expanded = false; // auto collapse once main content starts
                  }
                  _reasoning[assistantMessage.id] = r;
                  await _chatService.updateMessage(
                    assistantMessage.id,
                    reasoningText: r.text,
                    reasoningFinishedAt: r.finishedAt,
                  );
                  if (mounted) setState(() {});
                }

                // Also finish the current reasoning segment
                final segments = _reasoningSegments[assistantMessage.id];
                if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
                  segments.last.finishedAt = DateTime.now();
                  final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
                  if (autoCollapse) {
                    segments.last.expanded = false;
                  }
                  _reasoningSegments[assistantMessage.id] = segments;
                  if (mounted) setState(() {});
                  // Persist closed segment state
                  await _chatService.updateMessage(
                    assistantMessage.id,
                    reasoningSegmentsJson: _serializeReasoningSegments(segments),
                  );
                }
              }
            }

            if (streamOutput) {
              // Update UI with streaming content
              if (mounted) {
                setState(() {
                  final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
                  if (index != -1) {
                    _messages[index] = _messages[index].copyWith(
                      content: fullContent,
                      totalTokens: totalTokens,
                    );
                  }
                });
              }

              // Persist partial content so it's saved even if interrupted
              await _chatService.updateMessage(
                assistantMessage.id,
                content: fullContent,
                totalTokens: totalTokens,
              );

              // 滚动到底部显示新内容
              Future.delayed(const Duration(milliseconds: 50), () {
                _scrollToBottom();
              });
            }
          }
        },
        onError: (e) async {
          // Preserve partial content; just finalize state and notify user
          await _chatService.updateMessage(
            assistantMessage.id,
            content: fullContent,
            totalTokens: totalTokens,
            isStreaming: false,
          );

          if (!mounted) return;
          setState(() {
            final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                content: fullContent.isNotEmpty ? fullContent : _messages[index].content,
                isStreaming: false,
                totalTokens: totalTokens,
              );
            }
            _isLoading = false;
          });

          // End reasoning on error
          final r = _reasoning[assistantMessage.id];
          if (r != null) {
            if (r.finishedAt == null) {
              r.finishedAt = DateTime.now();
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningText: r.text,
                reasoningFinishedAt: r.finishedAt,
              );
            }
            final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
            if (autoCollapse) {
              r.expanded = false;
            }
            _reasoning[assistantMessage.id] = r;
          }

          // Also finish any unfinished reasoning segments on error
          final segments = _reasoningSegments[assistantMessage.id];
          if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
            segments.last.finishedAt = DateTime.now();
            final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
            if (autoCollapse) {
              segments.last.expanded = false;
            }
            _reasoningSegments[assistantMessage.id] = segments;
            // Persist closed segment state
            try {
              await _chatService.updateMessage(
                assistantMessage.id,
                reasoningSegmentsJson: _serializeReasoningSegments(segments),
              );
            } catch (_) {}
          }

          _messageStreamSubscription = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('生成已中断: $e')),
          );
        },
        onDone: () async {
          // If stream closed without explicit isDone chunk, finalize
          if (_isLoading) {
            await finish(generateTitle: true);
          }
          _messageStreamSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      // Preserve partial content on outer error as well
      await _chatService.updateMessage(
        assistantMessage.id,
        content: fullContent,
        totalTokens: totalTokens,
        isStreaming: false,
      );

      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: fullContent.isNotEmpty ? fullContent : _messages[index].content,
            isStreaming: false,
            totalTokens: totalTokens,
          );
        }
        _isLoading = false;
      });

      // End reasoning on error
      final r = _reasoning[assistantMessage.id];
      if (r != null) {
        r.finishedAt = DateTime.now();
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          r.expanded = false;
        }
        _reasoning[assistantMessage.id] = r;
        await _chatService.updateMessage(
          assistantMessage.id,
          reasoningText: r.text,
          reasoningFinishedAt: r.finishedAt,
        );
      }

      // Also finish any unfinished reasoning segments on error
      final segments = _reasoningSegments[assistantMessage.id];
      if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
        segments.last.finishedAt = DateTime.now();
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) {
          segments.last.expanded = false;
        }
        _reasoningSegments[assistantMessage.id] = segments;
        // Persist closed segment state
        try {
          await _chatService.updateMessage(
            assistantMessage.id,
            reasoningSegmentsJson: _serializeReasoningSegments(segments),
          );
        } catch (_) {}
      }

      _messageStreamSubscription = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成已中断: $e')),
      );
    }
  }

  Future<void> _regenerateAtMessage(ChatMessage message) async {
    if (_currentConversation == null) return;
    // Cancel any ongoing stream
    await _cancelStreaming();

    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    // Compute versioning target (groupId + nextVersion) and where to cut
    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;
    if (message.role == 'assistant') {
      // Keep the existing assistant message as old version
      lastKeep = idx; // remove after this
      targetGroupId = message.groupId ?? message.id;
      int maxVer = -1;
      for (final m in _messages) {
        final gid = (m.groupId ?? m.id);
        if (gid == targetGroupId) {
          if (m.version > maxVer) maxVer = m.version;
        }
      }
      nextVersion = maxVer + 1;
    } else {
      // User message: find the first assistant reply after it to branch from
      int aid = -1;
      for (int i = idx + 1; i < _messages.length; i++) {
        if (_messages[i].role == 'assistant') { aid = i; break; }
      }
      if (aid >= 0) {
        lastKeep = aid; // keep that assistant message as old version
        targetGroupId = _messages[aid].groupId ?? _messages[aid].id;
        int maxVer = -1;
        for (final m in _messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        // No assistant reply yet; keep up to the user message and start new group
        lastKeep = idx;
        targetGroupId = null; // will be set to new id automatically
        nextVersion = 0;
      }
    }

    // Remove messages after lastKeep (persistently), but preserve other versions of the target group
    if (lastKeep < _messages.length - 1) {
      final trailing = _messages.sublist(lastKeep + 1);
      final removeIds = <String>[];
      for (final m in trailing) {
        final gid = (m.groupId ?? m.id);
        final shouldKeep = (targetGroupId != null && gid == targetGroupId);
        if (!shouldKeep) removeIds.add(m.id);
      }
      for (final id in removeIds) {
        try { await _chatService.deleteMessage(id); } catch (_) {}
        _reasoning.remove(id);
        _translations.remove(id);
        _toolParts.remove(id);
        _reasoningSegments.remove(id);
      }
      if (removeIds.isNotEmpty) {
        setState(() {
          _messages.removeWhere((m) => removeIds.contains(m.id));
        });
      }
    }

    // Start a new assistant generation from current context
    final settings = context.read<SettingsProvider>();
    final providerKey = settings.currentModelProvider;
    final modelId = settings.currentModelId;
    final assistant = context.read<AssistantProvider>().currentAssistant;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.homePagePleaseSelectModel)));
      return;
    }

    // Create assistant message placeholder (new version in target group)
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: targetGroupId,
      version: nextVersion,
    );

    // Persist selection to the latest version of this group
    final gid = assistantMessage.groupId ?? assistantMessage.id;
    _versionSelections[gid] = assistantMessage.version;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, assistantMessage.version);

    setState(() {
      _messages.add(assistantMessage);
      _isLoading = true;
    });

    // Haptics on regenerate
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}

    // Initialize reasoning state only when enabled and model supports it
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && _isReasoningEnabled((assistant?.thinkingBudget) ?? settings.thinkingBudget);
    if (enableReasoning) {
      final rd = _ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(assistantMessage.id, reasoningStartAt: DateTime.now());
    }

    // Build API messages from current context (apply truncate + collapse versions)
    final tIndex = _currentConversation?.truncateIndex ?? -1;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= _messages.length)
        ? _messages.sublist(tIndex)
        : List.of(_messages);
    final List<ChatMessage> source = _collapseVersions(sourceAll);
    final apiMessages = source
        .where((m) => m.content.isNotEmpty)
        .map((m) => {'role': m.role == 'assistant' ? 'assistant' : 'user', 'content': m.content})
        .toList();

    // Inject system prompt
    if ((assistant?.systemPrompt.trim().isNotEmpty ?? false)) {
      final vars = PromptTransformer.buildPlaceholders(
        context: context,
        assistant: assistant!,
        modelId: modelId,
        modelName: modelId,
        userNickname: context.read<UserProvider>().name,
      );
      final sys = PromptTransformer.replacePlaceholders(assistant.systemPrompt, vars);
      apiMessages.insert(0, {'role': 'system', 'content': sys});
    }
    // Inject search tool usage guide when enabled
    if (settings.searchEnabled) {
      final prompt = SearchToolService.getSystemPrompt();
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + prompt;
      } else {
        apiMessages.insert(0, {'role': 'system', 'content': prompt});
      }
    }
    // Inject learning mode prompt when enabled (global)
    try {
      final lmEnabled = await LearningModeStore.isEnabled();
      if (lmEnabled) {
        final lp = await LearningModeStore.getPrompt();
        if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
          apiMessages[0]['content'] = ((apiMessages[0]['content'] ?? '') as String) + '\n\n' + lp;
        } else {
          apiMessages.insert(0, {'role': 'system', 'content': lp});
        }
      }
    } catch (_) {}

    // Limit context length
    if ((assistant?.contextMessageSize ?? 0) > 0) {
      final keep = assistant!.contextMessageSize.clamp(1, 512).toInt();
      int startIdx = 0;
      if (apiMessages.isNotEmpty && apiMessages.first['role'] == 'system') {
        startIdx = 1;
      }
      final tail = apiMessages.sublist(startIdx);
      if (tail.length > keep) {
        final trimmed = tail.sublist(tail.length - keep);
        apiMessages..removeRange(startIdx, apiMessages.length)..addAll(trimmed);
      }
    }

    // Convert any local Markdown image links to inline base64 for model context
    for (int i = 0; i < apiMessages.length; i++) {
      final s = (apiMessages[i]['content'] ?? '').toString();
      if (s.isNotEmpty) {
        apiMessages[i]['content'] = await MarkdownMediaSanitizer.inlineLocalImagesToBase64(s);
      }
    }

    // Prepare tools (Search + MCP)
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    Future<String> Function(String, Map<String, dynamic>)? onToolCall;
    try {
      if (settings.searchEnabled) {
        toolDefs.add(SearchToolService.getToolDefinition());
      }
      final mcp = context.read<McpProvider>();
      final toolSvc = context.read<McpToolService>();
      final tools = toolSvc.listAvailableToolsForAssistant(mcp, context.read<AssistantProvider>(), assistant?.id);
      final supportsTools = _isToolModel(providerKey, modelId);
      if (supportsTools && tools.isNotEmpty) {
        toolDefs.addAll(tools.map((t) {
          final props = <String, dynamic>{for (final p in t.params) p.name: {'type': 'string'}};
          final required = [for (final p in t.params.where((e) => e.required)) p.name];
          return {
            'type': 'function',
            'function': {
              'name': t.name,
              if ((t.description ?? '').isNotEmpty) 'description': t.description,
              'parameters': {'type': 'object', 'properties': props, 'required': required},
            }
          };
        }));
      }
      if (toolDefs.isNotEmpty) {
        onToolCall = (name, args) async {
          if (name == SearchToolService.toolName && settings.searchEnabled) {
            final q = (args['query'] ?? '').toString();
            return await SearchToolService.executeSearch(q, settings);
          }
          final text = await toolSvc.callToolTextForAssistant(
            mcp,
            context.read<AssistantProvider>(),
            assistantId: assistant?.id,
            toolName: name,
            arguments: args,
          );
          return text;
        };
      }
    } catch (_) {}

    // Build assistant-level custom request overrides
    Map<String, String>? aHeaders;
    Map<String, dynamic>? aBody;
    if ((assistant?.customHeaders.isNotEmpty ?? false)) {
      aHeaders = {
        for (final e in assistant!.customHeaders)
          if ((e['name'] ?? '').trim().isNotEmpty) (e['name']!.trim()): (e['value'] ?? '')
      };
      if (aHeaders.isEmpty) aHeaders = null;
    }
    if ((assistant?.customBody.isNotEmpty ?? false)) {
      aBody = {
        for (final e in assistant!.customBody)
          if ((e['key'] ?? '').trim().isNotEmpty)
            (e['key']!.trim()): (e['value'] ?? '')
      };
      if (aBody.isEmpty) aBody = null;
    }

    final stream = ChatApiService.sendMessageStream(
      config: settings.getProviderConfig(providerKey),
      modelId: modelId,
      messages: apiMessages,
      thinkingBudget: assistant?.thinkingBudget ?? settings.thinkingBudget,
      temperature: assistant?.temperature,
      topP: assistant?.topP,
      maxTokens: assistant?.maxTokens,
      tools: toolDefs.isEmpty ? null : toolDefs,
      onToolCall: onToolCall,
      extraHeaders: aHeaders,
      extraBody: aBody,
    );

    String fullContent = '';
    int totalTokens = 0;
    TokenUsage? usage;

    // Respect assistant streaming toggle: if off, buffer updates until done
    final bool streamOutput = assistant?.streamOutput ?? true;
    String _bufferedReasoning2 = '';
    DateTime? _reasoningStartAt2;

    Future<void> finish({bool generateTitle = false}) async {
      final processedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(fullContent);
      await _chatService.updateMessage(assistantMessage.id, content: processedContent, totalTokens: totalTokens, isStreaming: false);
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == assistantMessage.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(content: processedContent, totalTokens: totalTokens, isStreaming: false);
        }
        _isLoading = false;
      });
      final r = _reasoning[assistantMessage.id];
      if (r != null && r.finishedAt == null) {
        r.finishedAt = DateTime.now();
        await _chatService.updateMessage(assistantMessage.id, reasoningText: r.text, reasoningFinishedAt: r.finishedAt);
      }
      final segments = _reasoningSegments[assistantMessage.id];
      if (segments != null && segments.isNotEmpty && segments.last.finishedAt == null) {
        segments.last.finishedAt = DateTime.now();
        final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
        if (autoCollapse) segments.last.expanded = false;
        _reasoningSegments[assistantMessage.id] = segments;
        if (mounted) setState(() {});
        await _chatService.updateMessage(assistantMessage.id, reasoningSegmentsJson: _serializeReasoningSegments(segments));
      }
    }

    _messageStreamSubscription?.cancel();
    _messageStreamSubscription = stream.listen((chunk) async {
      if ((chunk.reasoning ?? '').isNotEmpty && enableReasoning) {
        if (streamOutput) {
          final r = _reasoning[assistantMessage.id] ?? _ReasoningData();
          r.text += chunk.reasoning!;
          r.startAt ??= DateTime.now();
          r.finishedAt = null;
          r.expanded = true;
          _reasoning[assistantMessage.id] = r;
          final segments = _reasoningSegments[assistantMessage.id] ?? <_ReasoningSegmentData>[];
          if (segments.isEmpty) {
            final seg = _ReasoningSegmentData();
            seg.text = chunk.reasoning!;
            seg.startAt = DateTime.now();
            seg.expanded = true;
            seg.toolStartIndex = (_toolParts[assistantMessage.id]?.length ?? 0);
            segments.add(seg);
          } else {
            final last = segments.last;
            if ((_toolParts[assistantMessage.id]?.isNotEmpty ?? false) && last.finishedAt != null) {
              final seg = _ReasoningSegmentData();
              seg.text = chunk.reasoning!;
              seg.startAt = DateTime.now();
              seg.expanded = true;
              seg.toolStartIndex = (_toolParts[assistantMessage.id]?.length ?? 0);
              segments.add(seg);
            } else {
              last.text += chunk.reasoning!;
              last.startAt ??= DateTime.now();
            }
          }
          _reasoningSegments[assistantMessage.id] = segments;
          if (mounted) setState(() {});
          await _chatService.updateMessage(assistantMessage.id, reasoningText: r.text, reasoningStartAt: r.startAt, reasoningSegmentsJson: _serializeReasoningSegments(segments));
        } else {
          _reasoningStartAt2 ??= DateTime.now();
          _bufferedReasoning2 += chunk.reasoning!;
        }
      }

      if ((chunk.toolCalls ?? const []).isNotEmpty) {
        // Finish current reasoning segment if one is open, so follow-up reasoning becomes a new card
        final segments = _reasoningSegments[assistantMessage.id] ?? <_ReasoningSegmentData>[];
        if (segments.isNotEmpty && segments.last.finishedAt == null) {
          segments.last.finishedAt = DateTime.now();
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          if (autoCollapse) {
            segments.last.expanded = false;
            final rd = _reasoning[assistantMessage.id];
            if (rd != null) rd.expanded = false;
          }
          _reasoningSegments[assistantMessage.id] = segments;
          try {
            await _chatService.updateMessage(
              assistantMessage.id,
              reasoningSegmentsJson: _serializeReasoningSegments(segments),
            );
          } catch (_) {}
        }

        final existing = List<ToolUIPart>.of(_toolParts[assistantMessage.id] ?? const []);
        for (final c in chunk.toolCalls!) {
          existing.add(ToolUIPart(id: c.id, toolName: c.name, arguments: c.arguments, loading: true));
        }
        setState(() => _toolParts[assistantMessage.id] = _dedupeToolPartsList(existing));
        try {
          final prev = _chatService.getToolEvents(assistantMessage.id);
          final newEvents = <Map<String, dynamic>>[
            ...prev,
            for (final c in chunk.toolCalls!) {'id': c.id, 'name': c.name, 'arguments': c.arguments, 'content': null},
          ];
          await _chatService.setToolEvents(assistantMessage.id, _dedupeToolEvents(newEvents));
        } catch (_) {}
      }

      if ((chunk.toolResults ?? const []).isNotEmpty) {
        final parts = List<ToolUIPart>.of(_toolParts[assistantMessage.id] ?? const []);
        for (final r in chunk.toolResults!) {
          int idx = -1;
          for (int i = 0; i < parts.length; i++) {
            if (parts[i].loading && (parts[i].id == r.id || (parts[i].id.isEmpty && parts[i].toolName == r.name))) {
              idx = i; break;
            }
          }
          if (idx >= 0) {
            parts[idx] = ToolUIPart(id: parts[idx].id, toolName: parts[idx].toolName, arguments: parts[idx].arguments, content: r.content, loading: false);
          } else {
            parts.add(ToolUIPart(id: r.id, toolName: r.name, arguments: r.arguments, content: r.content, loading: false));
          }
          try { await _chatService.upsertToolEvent(assistantMessage.id, id: r.id, name: r.name, arguments: r.arguments, content: r.content); } catch (_) {}
        }
        setState(() => _toolParts[assistantMessage.id] = _dedupeToolPartsList(parts));
        _scrollToBottomSoon();
      }

      if (chunk.content.isNotEmpty) {
        fullContent += chunk.content;
        if (streamOutput) {
          setState(() {
            final i = _messages.indexWhere((m) => m.id == assistantMessage.id);
            if (i != -1) _messages[i] = _messages[i].copyWith(content: fullContent);
          });
        }
      }

      if (chunk.usage != null) {
        usage = (usage ?? const TokenUsage()).merge(chunk.usage!);
        totalTokens = usage!.totalTokens;
      }

      if (chunk.isDone) {
        if (chunk.totalTokens > 0) totalTokens = chunk.totalTokens;
        await finish();
        // If non-streaming, write buffered reasoning once
        if (!streamOutput && _bufferedReasoning2.isNotEmpty) {
          final now = DateTime.now();
          final startAt = _reasoningStartAt2 ?? now;
          await _chatService.updateMessage(
            assistantMessage.id,
            reasoningText: _bufferedReasoning2,
            reasoningStartAt: startAt,
            reasoningFinishedAt: now,
          );
          final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
          _reasoning[assistantMessage.id] = _ReasoningData()
            ..text = _bufferedReasoning2
            ..startAt = startAt
            ..finishedAt = now
            ..expanded = !autoCollapse;
          if (mounted) setState(() {});
        }
        await _messageStreamSubscription?.cancel();
        _messageStreamSubscription = null;
      }
    });
  }

  ChatInputData _parseInputFromRaw(String raw) {
    final imgRe = RegExp(r"\[image:(.+?)\]");
    final fileRe = RegExp(r"\[file:(.+?)\|(.+?)\|(.+?)\]");
    final images = <String>[];
    final docs = <DocumentAttachment>[];
    final buffer = StringBuffer();
    int idx = 0;
    while (idx < raw.length) {
      final imgMatch = imgRe.matchAsPrefix(raw, idx);
      final fileMatch = fileRe.matchAsPrefix(raw, idx);
      if (imgMatch != null) {
        final p = imgMatch.group(1)?.trim();
        if (p != null && p.isNotEmpty) images.add(p);
        idx = imgMatch.end;
        continue;
      }
      if (fileMatch != null) {
        final path = fileMatch.group(1)?.trim() ?? '';
        final name = fileMatch.group(2)?.trim() ?? 'file';
        final mime = fileMatch.group(3)?.trim() ?? 'text/plain';
        docs.add(DocumentAttachment(path: path, fileName: name, mime: mime));
        idx = fileMatch.end;
        continue;
      }
      buffer.write(raw[idx]);
      idx++;
    }
    return ChatInputData(text: buffer.toString().trim(), imagePaths: images, documents: docs);
  }

  Future<void> _maybeGenerateTitle({bool force = false}) async {
    final convo = _currentConversation;
    if (convo == null) return;
    if (!force && convo.title.isNotEmpty && convo.title != _titleForLocale(context)) return;

    final settings = context.read<SettingsProvider>();
    // Decide model: prefer title model, else fall back to current chat model
    final provKey = settings.titleModelProvider ?? settings.currentModelProvider;
    final mdlId = settings.titleModelId ?? settings.currentModelId;
    if (provKey == null || mdlId == null) return;
    final cfg = settings.getProviderConfig(provKey);

    // Build content from messages (truncate to reasonable length)
    final msgs = _chatService.getMessages(convo.id);
    final tIndex = convo.truncateIndex;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= msgs.length) ? msgs.sublist(tIndex) : msgs;
    final List<ChatMessage> source = _collapseVersions(sourceAll);
    final joined = source
        .where((m) => m.content.isNotEmpty)
        .map((m) => '${m.role == 'assistant' ? 'Assistant' : 'User'}: ${m.content}')
        .join('\n\n');
    final content = joined.length > 3000 ? joined.substring(0, 3000) : joined;
    final locale = Localizations.localeOf(context).toLanguageTag();

    String prompt = settings.titlePrompt
        .replaceAll('{locale}', locale)
        .replaceAll('{content}', content);

    try {
      final title = (await ChatApiService.generateText(config: cfg, modelId: mdlId, prompt: prompt)).trim();
      if (title.isNotEmpty) {
        await _chatService.renameConversation(convo.id, title);
        setState(() {
          _currentConversation = _chatService.getConversation(convo.id);
        });
      }
    } catch (_) {
      // Ignore title generation failure silently
    }
  }

  void _scrollToBottom() {
    try {
      if (!_scrollController.hasClients) return;
      
      // Don't auto-scroll if user is actively scrolling
      if (_isUserScrolling) return;
      
      // Prevent using controller while it is still attached to old/new list simultaneously
      if (_scrollController.positions.length != 1) {
        // Try again after microtask when the previous list detaches
        Future.microtask(_scrollToBottom);
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(max);
      if (_showJumpToBottom) {
        setState(() => _showJumpToBottom = false);
      }
    } catch (_) {
      // Ignore transient attachment errors
    }
  }

  void _forceScrollToBottom() {
    // Force scroll to bottom when user explicitly clicks the button
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    _scrollToBottom();
  }

  // Force scroll after rebuilds when switching topics/conversations
  void _forceScrollToBottomSoon() {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    Future.delayed(_postSwitchScrollDelay, _scrollToBottom);
  }

  void _measureInputBar() {
    try {
      final ctx = _inputBarKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final h = box.size.height;
      if ((_inputBarHeight - h).abs() > 1.0) {
        setState(() => _inputBarHeight = h);
      }
    } catch (_) {}
  }

  // Ensure scroll reaches bottom even after widget tree transitions
  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);
  }

  // Translate message functionality
  Future<void> _translateMessage(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    // Show language selector
    final language = await showLanguageSelector(context);
    if (language == null) return;

    // Check if clear translation is selected
    if (language.code == '__clear__') {
      // Clear the translation (use empty string so UI hides immediately)
      final updatedMessage = message.copyWith(translation: '');
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = updatedMessage;
        }
        // Remove translation state
        _translations.remove(message.id);
      });
      await _chatService.updateMessage(message.id, translation: '');
      return;
    }

    final settings = context.read<SettingsProvider>();

    // Check if translation model is set
    final translateProvider = settings.translateModelProvider ?? settings.currentModelProvider;
    final translateModelId = settings.translateModelId ?? settings.currentModelId;

    if (translateProvider == null || translateModelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.homePagePleaseSetupTranslateModel)),
      );
      return;
    }

    // Extract text content from message (removing reasoning text if present)
    String textToTranslate = message.content;

    // Set loading state and initialize translation data
    final loadingMessage = message.copyWith(translation: l10n.homePageTranslating);
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        _messages[index] = loadingMessage;
      }
      // Initialize translation state with expanded
      _translations[message.id] = _TranslationData();
    });

    try {
      // Get translation prompt with placeholders replaced
      String prompt = settings.translatePrompt
          .replaceAll('{source_text}', textToTranslate)
          .replaceAll('{target_lang}', language.displayName);

      // Create translation request
      final provider = settings.getProviderConfig(translateProvider);

      final translationStream = ChatApiService.sendMessageStream(
        config: provider,
        modelId: translateModelId,
        messages: [
          {'role': 'user', 'content': prompt}
        ],
      );

      final buffer = StringBuffer();

      await for (final chunk in translationStream) {
        buffer.write(chunk.content);

        // Update translation in real-time
        final updatingMessage = message.copyWith(translation: buffer.toString());
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = updatingMessage;
          }
        });
      }

      // Save final translation
      await _chatService.updateMessage(message.id, translation: buffer.toString());

    } catch (e) {
      // Clear translation on error (empty to hide immediately)
      final errorMessage = message.copyWith(translation: '');
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          _messages[index] = errorMessage;
        }
        // Remove translation state on error
        _translations.remove(message.id);
      });

      await _chatService.updateMessage(message.id, translation: '');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.homePageTranslateFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = ((_currentConversation?.title ?? '').trim().isNotEmpty)
        ? _currentConversation!.title
        : _titleForLocale(context);
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final providerKey = settings.currentModelProvider;
    final modelId = settings.currentModelId;
    String? providerName;
    String? modelDisplay;
    if (providerKey != null && modelId != null) {
      final cfg = settings.getProviderConfig(providerKey);
      providerName = cfg.name.isNotEmpty ? cfg.name : providerKey;
      final ov = cfg.modelOverrides[modelId] as Map?;
      modelDisplay = (ov != null && (ov['name'] as String?)?.isNotEmpty == true) ? (ov['name'] as String) : modelId;
    }

    // Chats are seeded via ChatProvider in main.dart

    return ZoomDrawer(
      controller: _drawerController,
      style: DrawerStyle.defaultStyle,
      mainScreenTapClose: true,
      borderRadius: 0.0,
      showShadow: false,
      angle: 0.0,
      mainScreenScale: 0.0,
      menuScreenWidth: MediaQuery.sizeOf(context).width * 0.75,
      menuBackgroundColor: Theme.of(context).colorScheme.surface,
      drawerShadowsBackgroundColor: Colors.grey[300] ?? Colors.grey,
       mainScreenOverlayColor: cs.onSurface.withValues(alpha: 0.1),
      // mainScreenOverlayColor: Colors.transparent,
      // drawerShadowsBackgroundColor: Colors.grey[300] ?? Colors.grey,
      slideWidth: MediaQuery.of(context).size.width * 0.75,
      menuScreen: SideDrawer(
        userName: context.watch<UserProvider>().name,
        assistantName: (() {
          final l10n = AppLocalizations.of(context)!;
          final a = context.watch<AssistantProvider>().currentAssistant;
          final n = a?.name.trim();
          return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
        })(),
        onSelectConversation: (id) {
          // Update current selection for highlight in drawer
          _chatService.setCurrentConversation(id);
          final convo = _chatService.getConversation(id);
          if (convo != null) {
            final msgs = _chatService.getMessages(id);
            setState(() {
              _currentConversation = convo;
              _messages = List.of(msgs);
              _loadVersionSelections();
              _restoreMessageUiState();
            });
            _forceScrollToBottomSoon();
          }
          // Haptic feedback when closing the sidebar
          try {
            if (context.read<SettingsProvider>().hapticsOnDrawer) {
              HapticFeedback.mediumImpact();
            }
          } catch (_) {}
          _drawerController.close?.call();
        },
        onNewConversation: () async {
          await _createNewConversation();
          if (mounted) {
            _forceScrollToBottomSoon();
          }
          // Haptic feedback when closing the sidebar
          try {
            if (context.read<SettingsProvider>().hapticsOnDrawer) {
              HapticFeedback.mediumImpact();
            }
          } catch (_) {}
          _drawerController.close?.call();
        },
      ),
      mainScreen: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: true,
        extendBodyBehindAppBar: true,
      appBar: AppBar(
        // centerTitle: true,
        systemOverlayStyle: (Theme.of(context).brightness == Brightness.dark)
            ? const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light, // Android icons
          statusBarBrightness: Brightness.dark, // iOS text
        )
            : const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () {
            // Haptic feedback on opening/closing the sidebar
            try {
              if (context.read<SettingsProvider>().hapticsOnDrawer) {
                HapticFeedback.mediumImpact();
              }
            } catch (_) {}
            // If the drawer is currently closed, toggling will open -> suppress listener haptic
            final isOpen = _drawerController.isOpen?.call() == true;
            if (!isOpen) _suppressNextOpenHaptic = true;
            _drawerController.toggle?.call();
          },
          icon: SvgPicture.asset(
            'assets/icons/list.svg',
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(
              Theme.of(context).iconTheme.color ?? Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
        ),
        titleSpacing: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          // crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedTextSwap(
              text: title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
            ),
            if (providerName != null && modelDisplay != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: Text(
                    '$modelDisplay ($providerName)',
                    key: ValueKey<String>('${settings.currentModelKey ?? ''}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w500),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          // Temporarily hidden: More menu button
          // IconButton(
          //   onPressed: () {
          //     Navigator.of(context).push(
          //       MaterialPageRoute(builder: (_) => const MorePage()),
          //     );
          //   },
          //   icon: const Icon(Lucide.Menu, size: 22),
          // ),
          IconButton(
            onPressed: () async {
              await _createNewConversation();
              if (mounted) {
                // Close drawer if open and scroll to bottom (fresh convo)
                _forceScrollToBottomSoon();
              }
            },
            icon: const Icon(Lucide.MessageCirclePlus, size: 22),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Assistant-specific chat background + gradient overlay to improve readability
          Builder(builder: (context) {
            final bg = context.watch<AssistantProvider>().currentAssistant?.background;
            if (bg == null || bg.trim().isEmpty) return const SizedBox.shrink();
            final cs = Theme.of(context).colorScheme;
            ImageProvider provider;
            if (bg.startsWith('http')) {
              provider = NetworkImage(bg);
            } else {
              provider = FileImage(File(bg));
            }
            return Positioned.fill(
              child: Stack(
                children: [
                  // Background image
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: provider,
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.srcATop),
                        ),
                      ),
                    ),
                  ),
                  // Vertical gradient overlay (top ~20% -> bottom ~50%) using theme background color
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              cs.background.withOpacity(0.20),
                              cs.background.withOpacity(0.50),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Main column content
          Padding(
            padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.of(context).padding.top),
            child: Column(
            children: [
              // Chat messages list (animate when switching topic)
              Expanded(
                child: FadeTransition(
                  opacity: _convoFade,
                  child: KeyedSubtree(
                    key: ValueKey<String>(_currentConversation?.id ?? 'none'),
                    child: (() {
                      // Stable snapshot for this build (collapse versions)
                      final messages = _collapseVersions(_messages);
                      final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
                      for (final m in _messages) {
                        final gid = (m.groupId ?? m.id);
                        byGroup.putIfAbsent(gid, () => <ChatMessage>[]).add(m);
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16, top: 8),
                        itemCount: messages.length,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemBuilder: (context, index) {
                          if (index < 0 || index >= messages.length) {
                            return const SizedBox.shrink();
                          }
                          final message = messages[index];
                          final r = _reasoning[message.id];
                          final t = _translations[message.id];
                          final chatScale = context.watch<SettingsProvider>().chatFontScale;
                          final assistant = context.watch<AssistantProvider>().currentAssistant;
                          final useAssist = assistant?.useAssistantAvatar == true;
                          final trunc = _currentConversation?.truncateIndex ?? -1;
                          final l10n = AppLocalizations.of(context)!;
                          final showDivider = trunc > 0 && index == trunc - 1;
                          final cs = Theme.of(context).colorScheme;
                          final label = l10n.homePageClearContext;
                          final divider = Row(
                            children: [
                              Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                              ),
                              Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
                            ],
                          );
                          final gid = (message.groupId ?? message.id);
                          final vers = (byGroup[gid] ?? const <ChatMessage>[]).toList()..sort((a,b)=>a.version.compareTo(b.version));
                          final selectedIdx = _versionSelections[gid] ?? (vers.isNotEmpty ? vers.length - 1 : 0);
                          final total = vers.length;
                          final showMsgNav = context.watch<SettingsProvider>().showMessageNavButtons;
                          final effectiveTotal = showMsgNav ? total : 1;
                          final effectiveIndex = showMsgNav ? selectedIdx : 0;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selecting && (message.role == 'user' || message.role == 'assistant'))
                                    Padding(
                                      padding: const EdgeInsets.only(left: 10, right: 6),
                                      child: Checkbox(
                                        value: _selectedItems.contains(message.id),
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedItems.add(message.id);
                                            } else {
                                              _selectedItems.remove(message.id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  Expanded(
                                    child: MediaQuery(
                                      data: MediaQuery.of(context).copyWith(
                                        textScaleFactor: MediaQuery.of(context).textScaleFactor * chatScale,
                                      ),
                                      child: ChatMessageWidget(
                                  message: message,
                                  versionIndex: effectiveIndex,
                                  versionCount: effectiveTotal,
                                  onPrevVersion: (showMsgNav && selectedIdx > 0) ? () async {
                                    final next = selectedIdx - 1;
                                    _versionSelections[gid] = next;
                                    await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
                                    if (mounted) setState(() {});
                                  } : null,
                                  onNextVersion: (showMsgNav && selectedIdx < total - 1) ? () async {
                                    final next = selectedIdx + 1;
                                    _versionSelections[gid] = next;
                                    await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
                                    if (mounted) setState(() {});
                                  } : null,
                                  modelIcon: (!useAssist && message.role == 'assistant' && message.providerId != null && message.modelId != null)
                                      ? _CurrentModelIcon(providerKey: message.providerId, modelId: message.modelId)
                                      : null,
                                  showModelIcon: useAssist ? false : context.watch<SettingsProvider>().showModelIcon,
                                  useAssistantAvatar: useAssist && message.role == 'assistant',
                                  assistantName: useAssist ? (assistant?.name ?? 'Assistant') : null,
                                  assistantAvatar: useAssist ? (assistant?.avatar ?? '') : null,
                                  showUserAvatar: context.watch<SettingsProvider>().showUserAvatar,
                                  showTokenStats: context.watch<SettingsProvider>().showTokenStats,
                                  reasoningText: (message.role == 'assistant') ? (r?.text ?? '') : null,
                                  reasoningExpanded: (message.role == 'assistant') ? (r?.expanded ?? false) : false,
                                  reasoningLoading: (message.role == 'assistant') ? (r?.finishedAt == null && (r?.text.isNotEmpty == true)) : false,
                                  reasoningStartAt: (message.role == 'assistant') ? r?.startAt : null,
                                  reasoningFinishedAt: (message.role == 'assistant') ? r?.finishedAt : null,
                                  onToggleReasoning: (message.role == 'assistant' && r != null)
                                      ? () {
                                          setState(() {
                                            r.expanded = !r.expanded;
                                          });
                                        }
                                      : null,
                                  translationExpanded: t?.expanded ?? true,
                                  onToggleTranslation: (message.translation != null && message.translation!.isNotEmpty && t != null)
                                      ? () {
                                          setState(() {
                                            t.expanded = !t.expanded;
                                          });
                                        }
                                      : null,
                                  onRegenerate: message.role == 'assistant' ? () { _regenerateAtMessage(message); } : null,
                                  onResend: message.role == 'user' ? () { _regenerateAtMessage(message); } : null,
                                  onTranslate: message.role == 'assistant'
                                      ? () {
                                          _translateMessage(message);
                                        }
                                      : null,
                                  onSpeak: message.role == 'assistant'
                                      ? () async {
                                          final tts = context.read<TtsProvider>();
                                          if (!tts.isSpeaking) {
                                            await tts.speak(message.content);
                                          } else {
                                            await tts.stop();
                                          }
                                        }
                                      : null,
                              onMore: () async {
                                final action = await showMessageMoreSheet(context, message);
                                if (!mounted) return;
                                if (action == MessageMoreAction.delete) {
                                  final l10n = AppLocalizations.of(context)!;
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(l10n.homePageDeleteMessage),
                                      content: Text(l10n.homePageDeleteMessageConfirm),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: Text(l10n.homePageCancel),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: Text(l10n.homePageDelete, style: const TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    final id = message.id;
                                    setState(() {
                                      _messages.removeWhere((m) => m.id == id);
                                      _reasoning.remove(id);
                                      _translations.remove(id);
                                      _toolParts.remove(id);
                                      _reasoningSegments.remove(id);
                                    });
                                    await _chatService.deleteMessage(id);
                                  }
                                } else if (action == MessageMoreAction.edit) {
                                  final edited = await Navigator.of(context).push<String>(
                                    MaterialPageRoute(builder: (_) => MessageEditPage(message: message)),
                                  );
                                  if (edited != null) {
                                    final newMsg = await _chatService.appendMessageVersion(messageId: message.id, content: edited);
                                    if (!mounted) return;
                                    setState(() {
                                      if (newMsg != null) {
                                        _messages.add(newMsg);
                                        final gid = (newMsg.groupId ?? newMsg.id);
                                        _versionSelections[gid] = newMsg.version;
                                      }
                                    });
                                  }
                                } else if (action == MessageMoreAction.fork) {
                                  // Determine included groups up to the message's group (inclusive)
                                  final Map<String, int> groupFirstIndex = <String, int>{};
                                  final List<String> groupOrder = <String>[];
                                  for (int i = 0; i < _messages.length; i++) {
                                    final gid0 = (_messages[i].groupId ?? _messages[i].id);
                                    if (!groupFirstIndex.containsKey(gid0)) {
                                      groupFirstIndex[gid0] = i;
                                      groupOrder.add(gid0);
                                    }
                                  }
                                  final targetGroup = (message.groupId ?? message.id);
                                  final targetOrderIndex = groupOrder.indexOf(targetGroup);
                                  if (targetOrderIndex >= 0) {
                                    final includeGroups = groupOrder.take(targetOrderIndex + 1).toSet();
                                    final selected = [
                                      for (final m in _messages)
                                        if (includeGroups.contains(m.groupId ?? m.id)) m
                                    ];
                                    // Filter version selections to included groups
                                    final sel = <String, int>{};
                                    for (final gid in includeGroups) {
                                      final v = _versionSelections[gid];
                                      if (v != null) sel[gid] = v;
                                    }
                                    final newConvo = await _chatService.forkConversation(
                                      title: _titleForLocale(context),
                                      assistantId: _currentConversation?.assistantId,
                                      sourceMessages: selected,
                                      versionSelections: sel,
                                    );
                                    // Switch to the new conversation
                                    _chatService.setCurrentConversation(newConvo.id);
                                    final msgs = _chatService.getMessages(newConvo.id);
                                    if (!mounted) return;
                                    setState(() {
                                      _currentConversation = newConvo;
                                      _messages = List.of(msgs);
                                      _loadVersionSelections();
                                      _restoreMessageUiState();
                                    });
                                    _triggerConversationFade();
                                    _scrollToBottomSoon();
                                  }
                                } else if (action == MessageMoreAction.share) {
                                  // Enter selection mode and preselect up to this message (inclusive)
                                  setState(() {
                                    _selecting = true;
                                    _selectedItems.clear();
                                    for (int i = 0; i <= index && i < messages.length; i++) {
                                      final m = messages[i];
                                      final enabled0 = (m.role == 'user' || m.role == 'assistant');
                                      if (enabled0) _selectedItems.add(m.id);
                                    }
                                  });
                                }
                              },
                                  toolParts: message.role == 'assistant' ? _toolParts[message.id] : null,
                                  reasoningSegments: message.role == 'assistant'
                                      ? (() {
                                          final segments = _reasoningSegments[message.id];
                                          if (segments == null || segments.isEmpty) return null;
                                          return segments
                                              .map((s) => ReasoningSegment(
                                                    text: s.text,
                                                    expanded: s.expanded,
                                                    loading: s.finishedAt == null && s.text.isNotEmpty,
                                                    startAt: s.startAt,
                                                    finishedAt: s.finishedAt,
                                                    onToggle: () {
                                                      setState(() {
                                                        s.expanded = !s.expanded;
                                                      });
                                                    },
                                                    toolStartIndex: s.toolStartIndex,
                                                  ))
                                              .toList();
                                        })()
                                      : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (showDivider)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: AppSpacing.md),
                                  child: divider,
                                ),
                            ],
                          );
                        },
                      );
                    })(),
                  ),
                ),
              ),
              // Input bar; lifts when tools open
              AnimatedPadding(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: _toolsOpen ? _sheetHeight : 0),
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (n) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
                    return false;
                  },
                  child: SizeChangedLayoutNotifier(
                  child: Builder(builder: (context) {
                    // Enforce model capabilities: disable MCP selection if model doesn't support tools
                    final settings = context.watch<SettingsProvider>();
                    final pk = settings.currentModelProvider;
                    final mid = settings.currentModelId;
                    if (pk != null && mid != null) {
                      final ap = context.read<AssistantProvider>();
                      final a = ap.currentAssistant;
                      // Enforce tool ability: clear MCP bindings when unsupported
                      final supportsTools = _isToolModel(pk, mid);
                      if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final aa = ap.currentAssistant;
                          if (aa != null && aa.mcpServerIds.isNotEmpty) {
                            ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
                          }
                        });
                      }
                      // Enforce reasoning ability: set thinkingBudget OFF when unsupported
                      final supportsReasoning = _isReasoningModel(pk, mid);
                      if (!supportsReasoning && a != null) {
                        final enabledNow = _isReasoningEnabled(a.thinkingBudget ?? settings.thinkingBudget);
                        if (enabledNow) {
                          WidgetsBinding.instance.addPostFrameCallback((_) async {
                            final aa = ap.currentAssistant;
                            if (aa != null) {
                              await ap.updateAssistant(aa.copyWith(thinkingBudget: 0));
                            }
                          });
                        }
                      }
                    }
                    // Compute whether built-in Gemini search is active to highlight the search button
                    final cfg = (settings.currentModelProvider != null)
                        ? settings.getProviderConfig(settings.currentModelProvider!)
                        : null;
                    bool builtinSearchActive = false;
                    if (cfg != null && cfg.providerType == ProviderKind.google && (cfg.vertexAI != true)) {
                      final mid = settings.currentModelId;
                      if ((mid ?? '').isNotEmpty) {
                        final ov = cfg.modelOverrides[mid] as Map?;
                        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
                        builtinSearchActive = list.map((e) => e.toString().toLowerCase()).contains('search');
                      }
                    }

                    return ChatInputBar(
                  key: _inputBarKey,
                  onMore: _toggleTools,
                  moreOpen: _toolsOpen,
                  // Highlight when app-level search enabled OR model built-in search enabled
                  searchEnabled: context.watch<SettingsProvider>().searchEnabled || builtinSearchActive,
                  onToggleSearch: (enabled) {
                    context.read<SettingsProvider>().setSearchEnabled(enabled);
                  },
                  onSelectModel: () => showModelSelectSheet(context),
                  onOpenMcp: () {
                    final a = context.read<AssistantProvider>().currentAssistant;
                    if (a != null) {
                      showAssistantMcpSheet(context, assistantId: a.id);
                    }
                  },
                  onStop: _cancelStreaming,
                  modelIcon: (settings.showModelIcon && settings.currentModelProvider != null && settings.currentModelId != null)
                      ? _CurrentModelIcon(
                    providerKey: settings.currentModelProvider,
                    modelId: settings.currentModelId,
                    size: 40,
                  )
                      : null,
                  focusNode: _inputFocus,
                  controller: _inputController,
                  mediaController: _mediaController,
                  onConfigureReasoning: () async {
                    final assistant = context.read<AssistantProvider>().currentAssistant;
                    if (assistant != null) {
                      if (assistant.thinkingBudget != null) {
                        context.read<SettingsProvider>().setThinkingBudget(assistant.thinkingBudget);
                      }
                      await showReasoningBudgetSheet(context);
                      final chosen = context.read<SettingsProvider>().thinkingBudget;
                      await context.read<AssistantProvider>().updateAssistant(
                        assistant.copyWith(thinkingBudget: chosen),
                      );
                    }
                  },
                  reasoningActive: _isReasoningEnabled((context.watch<AssistantProvider>().currentAssistant?.thinkingBudget) ?? settings.thinkingBudget),
                  supportsReasoning: (settings.currentModelProvider != null && settings.currentModelId != null)
                      ? _isReasoningModel(settings.currentModelProvider!, settings.currentModelId!)
                      : false,
                  onOpenSearch: () => showSearchSettingsSheet(context),
                  onSend: (text) {
                    _sendMessage(text);
                    _inputController.clear();
                    // Dismiss keyboard after sending
                    _dismissKeyboard();
                  },
                  loading: _isLoading,
                  showMcpButton: (() {
                    final pk = settings.currentModelProvider;
                    final mid = settings.currentModelId;
                    if (pk == null || mid == null) return false;
                    return _isToolModel(pk, mid) && context.watch<McpProvider>().servers.isNotEmpty;
                  })(),
                  mcpActive: (() {
                    final a = context.watch<AssistantProvider>().currentAssistant;
                    final connected = context.watch<McpProvider>().connectedServers;
                    final selected = a?.mcpServerIds ?? const <String>[];
                    if (selected.isEmpty || connected.isEmpty) return false;
                    return connected.any((s) => selected.contains(s.id));
                  })(),
                );
                    }),
                  ),
                ),
              ),
            ],
            ),
          ),

          // // iOS-style blur/fade effect above input area
          // Positioned(
          //   left: 0,
          //   right: 0,
          //   bottom: _inputBarHeight,
          //   child: IgnorePointer(
          //     child: Container(
          //       height: 20,
          //       decoration: BoxDecoration(
          //         gradient: LinearGradient(
          //           begin: Alignment.topCenter,
          //           end: Alignment.bottomCenter,
          //           colors: [
          //             Theme.of(context).colorScheme.background.withOpacity(0.0),
          //             Theme.of(context).colorScheme.background.withOpacity(0.8),
          //             Theme.of(context).colorScheme.background.withOpacity(1.0),
          //           ],
          //           stops: const [0.0, 0.6, 1.0],
          //         ),
          //       ),
          //     ),
          //   ),
          // ),

          // Backdrop to close sheet on tap
          IgnorePointer(
            ignoring: !_toolsOpen,
            child: AnimatedOpacity(
              opacity: _toolsOpen ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _toggleTools,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Tools sheet overlayed at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: AnimatedSlide(
                offset: _toolsOpen ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _toolsOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: SizedBox(
                    height: _sheetHeight,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      child: BottomToolsSheet(
                        onPhotos: _onPickPhotos,
                        onCamera: _onPickCamera,
                        onUpload: _onPickFiles,
                        onClear: _onClearContext,
                        clearLabel: _clearContextLabel(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Selection toolbar overlay (above input bar)
          if (_selecting)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: _toolsOpen ? (_sheetHeight + 72) : 72),
                  child: _SelectionToolbar(
                    onCancel: () {
                      setState(() {
                        _selecting = false;
                        _selectedItems.clear();
                      });
                    },
                    onConfirm: () async {
                      final convo = _currentConversation;
                      if (convo == null) return;
                      final collapsed = _collapseVersions(_messages);
                      final selected = <ChatMessage>[];
                      for (final m in collapsed) {
                        if (_selectedItems.contains(m.id)) selected.add(m);
                      }
                      if (selected.isEmpty) {
                        final l10n = AppLocalizations.of(context)!;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.homePageSelectMessagesToShare)),
                        );
                        return;
                      }
                      setState(() { _selecting = false; });
                      await showChatExportSheet(context, conversation: convo, selectedMessages: selected);
                      if (mounted) setState(() { _selectedItems.clear(); });
                    },
                  ),
                ),
              ),
            ),

          // Scroll-to-bottom button (bottom-right, above input bar)
          Builder(builder: (context) {
            final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
            // Hide nav button in brand-new chats with no messages
            if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
            final cs = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final bottomOffset = (_toolsOpen ? _sheetHeight : 0) + _inputBarHeight + 12;
            return Align(
              alignment: Alignment.bottomRight,
              child: SafeArea(
                top: false,
                bottom: false, // avoid double bottom inset so button hugs input bar
                child: IgnorePointer(
                  ignoring: !_showJumpToBottom,
                  child: AnimatedScale(
                    scale: _showJumpToBottom ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      opacity: _showJumpToBottom ? 1 : 0,
                      child: Padding(
                        padding: EdgeInsets.only(right: 16, bottom: bottomOffset),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                          boxShadow: isDark ? [] : [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _forceScrollToBottom,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(Lucide.ChevronDown, size: 16, color: isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _convoFadeController.dispose();
    _mcpProvider?.removeListener(_onMcpChanged);
    _drawerStateNotifier?.removeListener(_onDrawerStateChanged);
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.removeListener(_onScrollControllerChanged);
    _scrollController.dispose();
    _messageStreamSubscription?.cancel();
    _userScrollTimer?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  void _triggerConversationFade() {
    try {
      _convoFadeController.stop();
      _convoFadeController.value = 0;
      _convoFadeController.forward();
    } catch (_) {}
  }

  @override
  void didPushNext() {
    // Navigating away: drop focus so it won't be restored.
    _dismissKeyboard();
  }

  @override
  void didPopNext() {
    // Returning to this page: ensure keyboard stays closed unless user taps.
    WidgetsBinding.instance.addPostFrameCallback((_) => _dismissKeyboard());
  }
}

class _ReasoningData {
  String text = '';
  DateTime? startAt;
  DateTime? finishedAt;
  bool expanded = false;
}

class _ReasoningSegmentData {
  String text = '';
  DateTime? startAt;
  DateTime? finishedAt;
  bool expanded = true;
  int toolStartIndex = 0;
}

class _TranslationData {
  bool expanded = true; // default to expanded when translation is added
}

class _CurrentModelIcon extends StatelessWidget {
  const _CurrentModelIcon({required this.providerKey, required this.modelId, this.size = 28});
  final String? providerKey;
  final String? modelId;
  final double size; // outer diameter

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
    if (providerKey == null || modelId == null) return const SizedBox.shrink();
    String? asset = _assetForName(modelId!);
    asset ??= _assetForName(providerKey!);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (Theme.of(context).brightness == Brightness.dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset, width: size * 0.5, height: size * 0.5, fit: BoxFit.contain);
      }
    } else {
      inner = Text(
        modelId!.isNotEmpty ? modelId!.characters.first.toUpperCase() : '?',
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.43),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: isDark ? Colors.white10 : cs.primary.withOpacity(0.1), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.64,
        height: size * 0.64,
        child: Center(child: inner is SvgPicture || inner is Image ? inner : FittedBox(child: inner)),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.onCancel, required this.onConfirm});
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Lucide.X, size: 16),
            onPressed: onCancel,
            label: Text(l10n.homePageCancel),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            icon: const Icon(Lucide.Check, size: 16),
            onPressed: onConfirm,
            label: Text(l10n.homePageDone),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}
