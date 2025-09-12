import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../providers/settings_provider.dart';
import '../../providers/model_provider.dart';
import '../../models/token_usage.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'google_service_account_auth.dart';

class ChatApiService {
  // Read built-in tools configured per model (e.g., ['search', 'url_context']).
  // Stored under ProviderConfig.modelOverrides[modelId].builtInTools.
  static Set<String> _builtInTools(ProviderConfig cfg, String modelId) {
    try {
      final ov = cfg.modelOverrides[modelId];
      if (ov is Map<String, dynamic>) {
        final raw = ov['builtInTools'];
        if (raw is List) {
          return raw.map((e) => e.toString().trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
        }
      }
    } catch (_) {}
    return const <String>{};
  }
  // Helpers to read per-model overrides (headers/body) from ProviderConfig
  static Map<String, dynamic> _modelOverride(ProviderConfig cfg, String modelId) {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) return ov;
    return const <String, dynamic>{};
  }

  static Map<String, String> _customHeaders(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['headers'] as List?) ?? const <dynamic>[];
    final out = <String, String>{};
    for (final e in list) {
      if (e is Map) {
        final name = (e['name'] ?? e['key'] ?? '').toString().trim();
        final value = (e['value'] ?? '').toString();
        if (name.isNotEmpty) out[name] = value;
      }
    }
    return out;
  }

  static dynamic _parseOverrideValue(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null') return null;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null) return d;
    if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
      try {
        return jsonDecode(s);
      } catch (_) {}
    }
    return v;
  }

  static Map<String, dynamic> _customBody(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['body'] as List?) ?? const <dynamic>[];
    final out = <String, dynamic>{};
    for (final e in list) {
      if (e is Map) {
        final key = (e['key'] ?? e['name'] ?? '').toString().trim();
        final val = (e['value'] ?? '').toString();
        if (key.isNotEmpty) out[key] = _parseOverrideValue(val);
      }
    }
    return out;
  }

  // Resolve effective model info by respecting per-model overrides; fallback to inference
  static ModelInfo _effectiveModelInfo(ProviderConfig cfg, String modelId) {
    final base = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    final ov = _modelOverride(cfg, modelId);
    ModelType? type;
    final t = (ov['type'] as String?) ?? '';
    if (t == 'embedding') type = ModelType.embedding; else if (t == 'chat') type = ModelType.chat;
    List<Modality>? input;
    if (ov['input'] is List) {
      input = [for (final e in (ov['input'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)];
    }
    List<Modality>? output;
    if (ov['output'] is List) {
      output = [for (final e in (ov['output'] as List)) (e.toString() == 'image' ? Modality.image : Modality.text)];
    }
    List<ModelAbility>? abilities;
    if (ov['abilities'] is List) {
      abilities = [for (final e in (ov['abilities'] as List)) (e.toString() == 'reasoning' ? ModelAbility.reasoning : ModelAbility.tool)];
    }
    return base.copyWith(
      type: type ?? base.type,
      input: input ?? base.input,
      output: output ?? base.output,
      abilities: abilities ?? base.abilities,
    );
  }
  static String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  static String _mimeFromDataUrl(String dataUrl) {
    try {
      final start = dataUrl.indexOf(':');
      final semi = dataUrl.indexOf(';');
      if (start >= 0 && semi > start) {
        return dataUrl.substring(start + 1, semi);
      }
    } catch (_) {}
    return 'image/png';
  }

  // Simple container for parsed text + image refs
  static _ParsedTextAndImages _parseTextAndImages(String raw) {
    if (raw.isEmpty) return const _ParsedTextAndImages('', <_ImageRef>[]);
    final mdImg = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
    final customImg = RegExp(r"\\[image:(.+?)\\]");
    final images = <_ImageRef>[];
    final buf = StringBuffer();
    int i = 0;
    while (i < raw.length) {
      final m1 = mdImg.matchAsPrefix(raw, i);
      final m2 = customImg.matchAsPrefix(raw, i);
      if (m1 != null) {
        final url = (m1.group(1) ?? '').trim();
        if (url.isNotEmpty) {
          if (url.startsWith('data:')) {
            images.add(_ImageRef('data', url));
          } else if (url.startsWith('http://') || url.startsWith('https://')) {
            images.add(_ImageRef('url', url));
          } else {
            images.add(_ImageRef('path', url));
          }
        }
        i = m1.end;
        continue;
      }
      if (m2 != null) {
        final p = (m2.group(1) ?? '').trim();
        if (p.isNotEmpty) images.add(_ImageRef('path', p));
        i = m2.end;
        continue;
      }
      buf.write(raw[i]);
      i++;
    }
    return _ParsedTextAndImages(buf.toString().trim(), images);
  }

  static Future<String> _encodeBase64File(String path, {bool withPrefix = false}) async {
    final fixed = SandboxPathResolver.fix(path);
    final file = File(fixed);
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    if (withPrefix) {
      final mime = _mimeFromPath(fixed);
      return 'data:$mime;base64,$b64';
    }
    return b64;
  }
  static http.Client _clientFor(ProviderConfig cfg) {
    final enabled = cfg.proxyEnabled == true;
    final host = (cfg.proxyHost ?? '').trim();
    final portStr = (cfg.proxyPort ?? '').trim();
    final user = (cfg.proxyUsername ?? '').trim();
    final pass = (cfg.proxyPassword ?? '').trim();
    if (enabled && host.isNotEmpty && portStr.isNotEmpty) {
      final port = int.tryParse(portStr) ?? 8080;
      final io = HttpClient();
      io.findProxy = (uri) => 'PROXY $host:$port';
      if (user.isNotEmpty) {
        io.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, pass));
      }
      return IOClient(io);
    }
    return http.Client();
  }

  static Stream<ChatStreamChunk> sendMessageStream({
    required ProviderConfig config,
    required String modelId,
    required List<Map<String, dynamic>> messages,
    List<String>? userImagePaths,
    int? thinkingBudget,
    double? temperature,
    double? topP,
    int? maxTokens,
    List<Map<String, dynamic>>? tools,
    Future<String> Function(String name, Map<String, dynamic> args)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async* {
    final kind = ProviderConfig.classify(config.id, explicitType: config.providerType);
    final client = _clientFor(config);

    try {
      if (kind == ProviderKind.openai) {
        yield* _sendOpenAIStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      } else if (kind == ProviderKind.claude) {
        yield* _sendClaudeStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      } else if (kind == ProviderKind.google) {
        yield* _sendGoogleStream(
          client,
          config,
          modelId,
          messages,
          userImagePaths: userImagePaths,
          thinkingBudget: thinkingBudget,
          temperature: temperature,
          topP: topP,
          maxTokens: maxTokens,
          tools: tools,
          onToolCall: onToolCall,
          extraHeaders: extraHeaders,
          extraBody: extraBody,
        );
      }
    } finally {
      client.close();
    }
  }

  // Non-streaming text generation for utilities like title summarization
  static Future<String> generateText({
    required ProviderConfig config,
    required String modelId,
    required String prompt,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
  }) async {
    final kind = ProviderConfig.classify(config.id, explicitType: config.providerType);
    final client = _clientFor(config);
    try {
      if (kind == ProviderKind.openai) {
        final base = config.baseUrl.endsWith('/')
            ? config.baseUrl.substring(0, config.baseUrl.length - 1)
            : config.baseUrl;
        final path = (config.useResponseApi == true) ? '/responses' : (config.chatPath ?? '/chat/completions');
        final url = Uri.parse('$base$path');
        final body = (config.useResponseApi == true)
            ? {
                'model': modelId,
                'input': [
                  {'role': 'user', 'content': prompt}
                ],
              }
            : {
                'model': modelId,
                'messages': [
                  {'role': 'user', 'content': prompt}
                ],
                'temperature': 0.3,
              };
        final headers = <String, String>{
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        };
        headers.addAll(_customHeaders(config, modelId));
        if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
        final extra = _customBody(config, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        if (extraBody != null && extraBody.isNotEmpty) {
          (extraBody).forEach((k, v) {
            (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
          });
        }
        final resp = await client.post(url, headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        if (config.useResponseApi == true) {
          final output = data['output'];
          return (output?['content'] ?? '').toString();
        } else {
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final msg = choices.first['message'];
            return (msg?['content'] ?? '').toString();
          }
          return '';
        }
      } else if (kind == ProviderKind.claude) {
        final base = config.baseUrl.endsWith('/')
            ? config.baseUrl.substring(0, config.baseUrl.length - 1)
            : config.baseUrl;
        final url = Uri.parse('$base/messages');
        final body = {
          'model': modelId,
          'max_tokens': 512,
          'temperature': 0.3,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        };
        final headers = <String, String>{
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        };
        headers.addAll(_customHeaders(config, modelId));
        if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
        final extra = _customBody(config, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        if (extraBody != null && extraBody.isNotEmpty) {
          (extraBody).forEach((k, v) {
            (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
          });
        }
        final resp = await client.post(url, headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        final content = data['content'] as List?;
        if (content != null && content.isNotEmpty) {
          final text = content.first['text'];
          return (text ?? '').toString();
        }
        return '';
      } else {
        // Google
        String url;
        if (config.vertexAI == true && (config.location?.isNotEmpty == true) && (config.projectId?.isNotEmpty == true)) {
          final loc = config.location!;
          final proj = config.projectId!;
          url = 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$modelId:generateContent';
        } else {
          final base = config.baseUrl.endsWith('/')
              ? config.baseUrl.substring(0, config.baseUrl.length - 1)
              : config.baseUrl;
          url = '$base/models/$modelId:generateContent?key=${Uri.encodeComponent(config.apiKey)}';
        }
        final body = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {'temperature': 0.3},
        };

        // Inject Gemini built-in tools (only for official Gemini API; Vertex may not support these)
        final builtIns = _builtInTools(config, modelId);
        final isOfficialGemini = config.vertexAI != true; // heuristic per requirement
        if (isOfficialGemini && builtIns.isNotEmpty) {
          final toolsArr = <Map<String, dynamic>>[];
          if (builtIns.contains('search')) {
            toolsArr.add({'google_search': {}});
          }
          if (builtIns.contains('url_context')) {
            toolsArr.add({'url_context': {}});
          }
          if (toolsArr.isNotEmpty) {
            (body as Map<String, dynamic>)['tools'] = toolsArr;
          }
        }
    final headers = <String, String>{'Content-Type': 'application/json'};
    // Add Bearer for Vertex via service account JSON
    if (config.vertexAI == true) {
      final token = await _maybeVertexAccessToken(config);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final proj = (config.projectId ?? '').trim();
      if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
    }
    headers.addAll(_customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    final extra = _customBody(config, modelId);
    if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
    if (extraBody != null && extraBody.isNotEmpty) {
      (extraBody).forEach((k, v) {
        (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
      });
    }
        final resp = await client.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw HttpException('HTTP ${resp.statusCode}: ${resp.body}');
        }
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates.first['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            return (parts.first['text'] ?? '').toString();
          }
        }
        return '';
      }
    } finally {
      client.close();
    }
  }

  static bool _isOff(int? budget) => (budget != null && budget != -1 && budget < 1024);
  static String _effortForBudget(int? budget) {
    if (budget == null || budget == -1) return 'auto';
    if (_isOff(budget)) return 'off';
    if (budget <= 2000) return 'low';
    if (budget <= 20000) return 'medium';
    return 'high';
  }

  static Stream<ChatStreamChunk> _sendOpenAIStream(
    http.Client client,
    ProviderConfig config,
    String modelId,
    List<Map<String, dynamic>> messages,
    {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, List<Map<String, dynamic>>? tools, Future<String> Function(String, Map<String, dynamic>)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
  ) async* {
    final base = config.baseUrl.endsWith('/') 
        ? config.baseUrl.substring(0, config.baseUrl.length - 1) 
        : config.baseUrl;
    final path = (config.useResponseApi == true) 
        ? '/responses' 
        : (config.chatPath ?? '/chat/completions');
    final url = Uri.parse('$base$path');

    final effectiveInfo = _effectiveModelInfo(config, modelId);
    final isReasoning = effectiveInfo.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effectiveInfo.output.contains(Modality.image);

    final effort = _effortForBudget(thinkingBudget);
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
        Map<String, dynamic> body;
    if (config.useResponseApi == true) {
      final input = <Map<String, dynamic>>[];
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        final isLast = i == messages.length - 1;
        final raw = (m['content'] ?? '').toString();
        
        // Only parse images if there are images to process
        final hasMarkdownImages = raw.contains('![') && raw.contains('](');
        final hasCustomImages = raw.contains('[image:');
        final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');
        
        if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
          final parsed = _parseTextAndImages(raw);
          final parts = <Map<String, dynamic>>[];
          if (parsed.text.isNotEmpty) {
            parts.add({'type': 'input_text', 'text': parsed.text});
          }
          // Images extracted from this message's text
          for (final ref in parsed.images) {
            String url;
            if (ref.kind == 'data') {
              url = ref.src;
            } else if (ref.kind == 'path') {
              url = await _encodeBase64File(ref.src, withPrefix: true);
            } else {
              url = ref.src; // http(s)
            }
            parts.add({'type': 'input_image', 'image_url': url});
          }
          // Additional images explicitly attached to the last user message
          if (hasAttachedImages) {
            for (final p in userImagePaths!) {
              final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await _encodeBase64File(p, withPrefix: true);
              parts.add({'type': 'input_image', 'image_url': dataUrl});
            }
          }
          input.add({'role': m['role'] ?? 'user', 'content': parts});
        } else {
          // No images, use simple string content
          input.add({'role': m['role'] ?? 'user', 'content': raw});
        }
      }
      body = {
        'model': modelId,
        'input': input,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null) 'max_output_tokens': maxTokens,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
        if (isReasoning && effort != 'off')
          'reasoning': {
            'summary': 'auto',
            if (effort != 'auto') 'effort': effort,
          },
      };
    } else {
      final mm = <Map<String, dynamic>>[];
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        final isLast = i == messages.length - 1;
        final raw = (m['content'] ?? '').toString();
        
        // Only parse images if there are images to process
        final hasMarkdownImages = raw.contains('![') && raw.contains('](');
        final hasCustomImages = raw.contains('[image:');
        final hasAttachedImages = isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user');
        
        if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
          final parsed = _parseTextAndImages(raw);
          final parts = <Map<String, dynamic>>[];
          if (parsed.text.isNotEmpty) {
            parts.add({'type': 'text', 'text': parsed.text});
          }
          for (final ref in parsed.images) {
            String url;
            if (ref.kind == 'data') {
              url = ref.src;
            } else if (ref.kind == 'path') {
              url = await _encodeBase64File(ref.src, withPrefix: true);
            } else {
              url = ref.src;
            }
            parts.add({'type': 'image_url', 'image_url': {'url': url}});
          }
          if (hasAttachedImages) {
            for (final p in userImagePaths!) {
              final dataUrl = (p.startsWith('http') || p.startsWith('data:')) ? p : await _encodeBase64File(p, withPrefix: true);
              parts.add({'type': 'image_url', 'image_url': {'url': dataUrl}});
            }
          }
          mm.add({'role': m['role'] ?? 'user', 'content': parts});
        } else {
          // No images, use simple string content
          mm.add({'role': m['role'] ?? 'user', 'content': raw});
        }
      }
      body = {
        'model': modelId,
        'messages': mm,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'top_p': topP,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
      };
    }

    // Vendor-specific reasoning knobs for chat-completions compatible hosts
    if (config.useResponseApi != true) {
      final off = _isOff(thinkingBudget);
      if (host.contains('openrouter.ai')) {
        if (isReasoning) {
          // OpenRouter uses `reasoning.enabled/max_tokens`
          if (off) {
            (body as Map<String, dynamic>)['reasoning'] = {'enabled': false};
          } else {
            final obj = <String, dynamic>{'enabled': true};
            if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
            (body as Map<String, dynamic>)['reasoning'] = obj;
          }
          (body as Map<String, dynamic>).remove('reasoning_effort');
        } else {
          (body as Map<String, dynamic>).remove('reasoning');
          (body as Map<String, dynamic>).remove('reasoning_effort');
        }
      } else if (host.contains('dashscope') || host.contains('aliyun')) {
        // Aliyun DashScope: enable_thinking + thinking_budget
        if (isReasoning) {
          (body as Map<String, dynamic>)['enable_thinking'] = !off;
          if (!off && thinkingBudget != null && thinkingBudget > 0) {
            (body as Map<String, dynamic>)['thinking_budget'] = thinkingBudget;
          } else {
            (body as Map<String, dynamic>).remove('thinking_budget');
          }
        } else {
          (body as Map<String, dynamic>).remove('enable_thinking');
          (body as Map<String, dynamic>).remove('thinking_budget');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
        // Volc Ark: thinking: { type: enabled|disabled }
        if (isReasoning) {
          (body as Map<String, dynamic>)['thinking'] = {'type': off ? 'disabled' : 'enabled'};
        } else {
          (body as Map<String, dynamic>).remove('thinking');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
        // InternLM (InternAI): thinking_mode boolean switch
        if (isReasoning) {
          (body as Map<String, dynamic>)['thinking_mode'] = !off;
        } else {
          (body as Map<String, dynamic>).remove('thinking_mode');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('siliconflow')) {
        // SiliconFlow: OFF -> enable_thinking: false; otherwise omit
        if (isReasoning) {
          if (off) {
            (body as Map<String, dynamic>)['enable_thinking'] = false;
          } else {
            (body as Map<String, dynamic>).remove('enable_thinking');
          }
        } else {
          (body as Map<String, dynamic>).remove('enable_thinking');
        }
        (body as Map<String, dynamic>).remove('reasoning_effort');
      } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
        if (isReasoning) {
          if (off) {
            (body as Map<String, dynamic>)['reasoning_content'] = false;
            (body as Map<String, dynamic>).remove('reasoning_budget');
          } else {
            (body as Map<String, dynamic>)['reasoning_content'] = true;
            if (thinkingBudget != null && thinkingBudget > 0) {
              (body as Map<String, dynamic>)['reasoning_budget'] = thinkingBudget;
            } else {
              (body as Map<String, dynamic>).remove('reasoning_budget');
            }
          }
        } else {
          (body as Map<String, dynamic>).remove('reasoning_content');
          (body as Map<String, dynamic>).remove('reasoning_budget');
        }
      }
    }

    final request = http.Request('POST', url);
    final headers = <String, String>{
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    // Merge custom headers (override takes precedence)
    headers.addAll(_customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    request.headers.addAll(headers);
    // Ask for usage in streaming for chat-completions compatible hosts (when supported)
    if (config.useResponseApi != true) {
      final h = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
      if (!h.contains('mistral.ai')) {
        (body as Map<String, dynamic>)['stream_options'] = {'include_usage': true};
      }
    }
    // Merge custom body keys (override takes precedence)
    final extraBodyCfg = _customBody(config, modelId);
    if (extraBodyCfg.isNotEmpty) {
      (body as Map<String, dynamic>).addAll(extraBodyCfg);
    }
    if (extraBody != null && extraBody.isNotEmpty) {
      extraBody.forEach((k, v) {
        (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
      });
    }
    request.body = jsonEncode(body);

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $errorBody');
    }

    final stream = response.stream.transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;
    // Fallback approx token calculation when provider doesn't include usage
    int _approxTokensFromChars(int chars) => (chars / 4).round();
    final int approxPromptChars = messages.fold<int>(0, (acc, m) => acc + ((m['content'] ?? '').toString().length));
    final int approxPromptTokens = _approxTokensFromChars(approxPromptChars);
    int approxCompletionChars = 0;

    // Track potential tool calls (OpenAI Chat Completions)
    final Map<int, Map<String, String>> toolAcc = <int, Map<String, String>>{}; // index -> {id,name,args}
    // Track potential tool calls (OpenAI Responses API)
    final Map<String, Map<String, String>> toolAccResp = <String, Map<String, String>>{}; // id/name -> {name,args}
    String? finishReason;

    await for (final chunk in stream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data: ')) continue;

        final data = line.substring(6);
        if (data == '[DONE]') {
          // If model streamed tool_calls but didn't include finish_reason on prior chunks,
          // execute tool flow now and start follow-up request.
          if (onToolCall != null && toolAcc.isNotEmpty) {
            final calls = <Map<String, dynamic>>[];
            final callInfos = <ToolCallInfo>[];
            final toolMsgs = <Map<String, dynamic>>[];
            toolAcc.forEach((idx, m) {
              final id = (m['id'] ?? 'call_$idx');
              final name = (m['name'] ?? '');
              Map<String, dynamic> args;
              try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
              calls.add({
                'id': id,
                'type': 'function',
                'function': {
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              });
              toolMsgs.add({'__name': name, '__id': id, '__args': args});
            });

            if (callInfos.isNotEmpty) {
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
            }

            // Execute tools and emit results
            final results = <Map<String, dynamic>>[];
            final resultsInfo = <ToolResultInfo>[];
            for (final m in toolMsgs) {
              final name = m['__name'] as String;
              final id = m['__id'] as String;
              final args = (m['__args'] as Map<String, dynamic>);
              final res = await onToolCall(name, args) ?? '';
              results.add({'tool_call_id': id, 'content': res});
              resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
            }
            if (resultsInfo.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
            }

            // Build follow-up messages
            final mm2 = <Map<String, dynamic>>[];
            for (final m in messages) {
              mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
            }
            mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
            for (final r in results) {
              final id = r['tool_call_id'];
              final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
              mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
            }

            // Follow-up request(s) with multi-round tool calls
            var currentMessages = mm2;
            while (true) {
              final body2 = {
                'model': modelId,
                'messages': currentMessages,
                'stream': true,
                if (temperature != null) 'temperature': temperature,
                if (topP != null) 'top_p': topP,
                if (maxTokens != null) 'max_tokens': maxTokens,
                if (isReasoning && effort != 'off' && effort != 'auto') 'reasoning_effort': effort,
                if (tools != null && tools.isNotEmpty) 'tools': tools,
                if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
              };
              
              // Apply the same vendor-specific reasoning settings as the original request
              final off = _isOff(thinkingBudget);
              if (host.contains('openrouter.ai')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning'] = {'enabled': false};
                  } else {
                    final obj = <String, dynamic>{'enabled': true};
                    if (thinkingBudget != null && thinkingBudget > 0) obj['max_tokens'] = thinkingBudget;
                    body2['reasoning'] = obj;
                  }
                  body2.remove('reasoning_effort');
                } else {
                  body2.remove('reasoning');
                  body2.remove('reasoning_effort');
                }
              } else if (host.contains('dashscope') || host.contains('aliyun')) {
                if (isReasoning) {
                  body2['enable_thinking'] = !off;
                  if (!off && thinkingBudget != null && thinkingBudget > 0) {
                    body2['thinking_budget'] = thinkingBudget;
                  } else {
                    body2.remove('thinking_budget');
                  }
                } else {
                  body2.remove('enable_thinking');
                  body2.remove('thinking_budget');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('ark.cn-beijing.volces.com') || host.contains('volc') || host.contains('ark')) {
                if (isReasoning) {
                  body2['thinking'] = {'type': off ? 'disabled' : 'enabled'};
                } else {
                  body2.remove('thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('intern-ai') || host.contains('intern') || host.contains('chat.intern-ai.org.cn')) {
                if (isReasoning) {
                  body2['thinking_mode'] = !off;
                } else {
                  body2.remove('thinking_mode');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('siliconflow')) {
                if (isReasoning) {
                  if (off) {
                    body2['enable_thinking'] = false;
                  } else {
                    body2.remove('enable_thinking');
                  }
                } else {
                  body2.remove('enable_thinking');
                }
                body2.remove('reasoning_effort');
              } else if (host.contains('deepseek') || modelId.toLowerCase().contains('deepseek')) {
                if (isReasoning) {
                  if (off) {
                    body2['reasoning_content'] = false;
                    body2.remove('reasoning_budget');
                  } else {
                    body2['reasoning_content'] = true;
                    if (thinkingBudget != null && thinkingBudget > 0) {
                      body2['reasoning_budget'] = thinkingBudget;
                    } else {
                      body2.remove('reasoning_budget');
                    }
                  }
                } else {
                  body2.remove('reasoning_content');
                  body2.remove('reasoning_budget');
                }
              }
              
              // Ask for usage in streaming (when supported)
              if (!host.contains('mistral.ai')) {
                body2['stream_options'] = {'include_usage': true};
              }
              
              // Apply custom body overrides
              if (extraBody != null && extraBody.isNotEmpty) {
                extraBody.forEach((k, v) {
                  body2[k] = (v is String) ? _parseOverrideValue(v) : v;
                });
              }
              
              final req2 = http.Request('POST', url);
              final headers2 = <String, String>{
                'Authorization': 'Bearer ${config.apiKey}',
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
              };
              // Apply custom headers
              headers2.addAll(_customHeaders(config, modelId));
              if (extraHeaders != null && extraHeaders.isNotEmpty) headers2.addAll(extraHeaders);
              req2.headers.addAll(headers2);
              req2.body = jsonEncode(body2);
              final resp2 = await client.send(req2);
              if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
                final errorBody = await resp2.stream.bytesToString();
                throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
              }
              final s2 = resp2.stream.transform(utf8.decoder);
              String buf2 = '';
              // Track potential subsequent tool calls
              final Map<int, Map<String, String>> toolAcc2 = <int, Map<String, String>>{};
              String? finishReason2;
              String contentAccum = ''; // Accumulate content for this round
              await for (final ch in s2) {
                buf2 += ch;
                final lines2 = buf2.split('\n');
                buf2 = lines2.last;
                for (int j = 0; j < lines2.length - 1; j++) {
                  final l = lines2[j].trim();
                  if (l.isEmpty || !l.startsWith('data: ')) continue;
                  final d = l.substring(6);
                  if (d == '[DONE]') {
                    // This round finished; handle below
                    continue;
                  }
                  try {
                    final o = jsonDecode(d);
                    if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                      final c0 = (o['choices'] as List).first;
                      finishReason2 = c0['finish_reason'] as String?;
                      final delta = c0['delta'] as Map?;
                      final txt = delta?['content'];
                      final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                      final u = o['usage'];
                      if (u != null) {
                        final prompt = (u['prompt_tokens'] ?? 0) as int;
                        final completion = (u['completion_tokens'] ?? 0) as int;
                        final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
                        usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
                        totalTokens = usage!.totalTokens;
                      }
                      if (rc is String && rc.isNotEmpty) {
                        yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                      }
                      if (txt is String && txt.isNotEmpty) {
                        contentAccum += txt; // Accumulate content
                        yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                      }
                      // Handle image outputs from OpenRouter-style deltas
                      // Possible shapes:
                      // - delta['images']: [ { type: 'image_url', image_url: { url: 'data:...' }, index: 0 }, ... ]
                      // - delta['content']: [ { type: 'image_url', image_url: { url: '...' } }, { type: 'text', text: '...' } ]
                      // - delta['image_url'] directly (less common)
                      if (wantsImageOutput) {
                        final List<dynamic> imageItems = <dynamic>[];
                        final imgs = delta?['images'];
                        if (imgs is List) imageItems.addAll(imgs);
                        final contentArr = (txt is List) ? txt : (delta?['content'] as List?);
                        if (contentArr is List) {
                          for (final it in contentArr) {
                            if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) {
                              imageItems.add(it);
                            }
                          }
                        }
                        final singleImage = delta?['image_url'];
                        if (singleImage is Map || singleImage is String) {
                          imageItems.add({'type': 'image_url', 'image_url': singleImage});
                        }
                        if (imageItems.isNotEmpty) {
                          final buf = StringBuffer();
                          for (final it in imageItems) {
                            if (it is! Map) continue;
                            dynamic iu = it['image_url'];
                            String? url;
                            if (iu is String) {
                              url = iu;
                            } else if (iu is Map) {
                              final u2 = iu['url'];
                              if (u2 is String) url = u2;
                            }
                            if (url != null && url.isNotEmpty) {
                              final md = '\n\n![image](' + url + ')';
                              buf.write(md);
                              contentAccum += md;
                            }
                          }
                          final out = buf.toString();
                          if (out.isNotEmpty) {
                            yield ChatStreamChunk(content: out, isDone: false, totalTokens: 0, usage: usage);
                          }
                        }
                      }
                      final tcs = delta?['tool_calls'] as List?;
                      if (tcs != null) {
                        for (final t in tcs) {
                          final idx = (t['index'] as int?) ?? 0;
                          final id = t['id'] as String?;
                          final func = t['function'] as Map<String, dynamic>?;
                          final name = func?['name'] as String?;
                          final argsDelta = func?['arguments'] as String?;
                          final entry = toolAcc2.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                          if (id != null) entry['id'] = id;
                          if (name != null && name.isNotEmpty) entry['name'] = name;
                          if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                        }
                      }
                    }
                  } catch (_) {}
                }
              }

              // After this follow-up round finishes: if tool calls again, execute and loop
              if ((finishReason2 == 'tool_calls' || toolAcc2.isNotEmpty) && onToolCall != null) {
                final calls2 = <Map<String, dynamic>>[];
                final callInfos2 = <ToolCallInfo>[];
                final toolMsgs2 = <Map<String, dynamic>>[];
                toolAcc2.forEach((idx, m) {
                  final id = (m['id'] ?? 'call_$idx');
                  final name = (m['name'] ?? '');
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  callInfos2.add(ToolCallInfo(id: id, name: name, arguments: args));
                  calls2.add({'id': id, 'type': 'function', 'function': {'name': name, 'arguments': jsonEncode(args)}});
                  toolMsgs2.add({'__name': name, '__id': id, '__args': args});
                });
                if (callInfos2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos2);
                }
                final results2 = <Map<String, dynamic>>[];
                final resultsInfo2 = <ToolResultInfo>[];
                for (final m in toolMsgs2) {
                  final name = m['__name'] as String;
                  final id = m['__id'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(name, args) ?? '';
                  results2.add({'tool_call_id': id, 'content': res});
                  resultsInfo2.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
                }
                if (resultsInfo2.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo2);
                }
                // Append for next loop - including any content accumulated in this round
                currentMessages = [
                  ...currentMessages,
                  if (contentAccum.isNotEmpty) {'role': 'assistant', 'content': contentAccum},
                  {'role': 'assistant', 'content': '', 'tool_calls': calls2},
                  for (final r in results2)
                    {
                      'role': 'tool',
                      'tool_call_id': r['tool_call_id'],
                      'name': calls2.firstWhere((c) => c['id'] == r['tool_call_id'], orElse: () => const {'function': {'name': ''}})['function']['name'],
                      'content': r['content'],
                    },
                ];
                // Continue loop
                continue;
              } else {
                // No further tool calls; finish
                final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage);
                return;
              }
            }
            // Should not reach here
            return;
          }

          final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
          yield ChatStreamChunk(
            content: '',
            isDone: true,
            totalTokens: usage?.totalTokens ?? approxTotal,
            usage: usage,
          );
          return;
        }

        try {
          final json = jsonDecode(data);
          String content = '';
          String? reasoning;

          if (config.useResponseApi == true) {
            // OpenAI /responses SSE types
            final type = json['type'];
            if (type == 'response.output_text.delta') {
              final delta = json['delta'];
              if (delta is String) {
                content = delta;
                approxCompletionChars += content.length;
              }
            } else if (type == 'response.reasoning_summary_text.delta') {
              final delta = json['delta'];
              if (delta is String) reasoning = delta;
            } else if (type is String && type.contains('function_call')) {
              // Accumulate function call args for Responses API
              final id = (json['id'] ?? json['call_id'] ?? '').toString();
              final name = (json['name'] ?? json['function']?['name'] ?? '').toString();
              final argsDelta = (json['arguments'] ?? json['arguments_delta'] ?? json['delta'] ?? '').toString();
              if (id.isNotEmpty || name.isNotEmpty) {
                final key = id.isNotEmpty ? id : name;
                final entry = toolAccResp.putIfAbsent(key, () => {'name': name, 'args': ''});
                if (name.isNotEmpty) entry['name'] = name;
                if (argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
              }
            } else if (type == 'response.completed') {
              final u = json['response']?['usage'];
              if (u != null) {
                final inTok = (u['input_tokens'] ?? 0) as int;
                final outTok = (u['output_tokens'] ?? 0) as int;
                usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                totalTokens = usage!.totalTokens;
              }
              // Responses: emit any collected tool calls from previous deltas
              if (onToolCall != null && toolAccResp.isNotEmpty) {
                final callInfos = <ToolCallInfo>[];
                final msgs = <Map<String, dynamic>>[];
                int idx = 0;
                toolAccResp.forEach((key, m) {
                  Map<String, dynamic> args;
                  try { args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
                  final id2 = key.isNotEmpty ? key : 'call_$idx';
                  callInfos.add(ToolCallInfo(id: id2, name: (m['name'] ?? ''), arguments: args));
                  msgs.add({'__id': id2, '__name': (m['name'] ?? ''), '__args': args});
                  idx += 1;
                });
                if (callInfos.isNotEmpty) {
                  final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? approxTotal, usage: usage, toolCalls: callInfos);
                }
                final resultsInfo = <ToolResultInfo>[];
                for (final m in msgs) {
                  final nm = m['__name'] as String;
                  final id2 = m['__id'] as String;
                  final args = (m['__args'] as Map<String, dynamic>);
                  final res = await onToolCall(nm, args) ?? '';
                  resultsInfo.add(ToolResultInfo(id: id2, name: nm, arguments: args, content: res));
                }
                if (resultsInfo.isNotEmpty) {
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
                }
              }
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(
                content: '',
                reasoning: null,
                isDone: true,
                totalTokens: usage?.totalTokens ?? approxTotal,
                usage: usage,
              );
              return;
            } else {
              // Fallback for providers that inline output
              final output = json['output'];
              if (output != null) {
                content = (output['content'] ?? '').toString();
                approxCompletionChars += content.length;
                final u = json['usage'];
                if (u != null) {
                  final inTok = (u['input_tokens'] ?? 0) as int;
                  final outTok = (u['output_tokens'] ?? 0) as int;
                  usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
                  totalTokens = usage!.totalTokens;
                }
              }
            }
          } else {
            // Handle standard OpenAI Chat Completions format
            final choices = json['choices'];
            if (choices != null && choices.isNotEmpty) {
              final c0 = choices[0];
              finishReason = c0['finish_reason'] as String?;
              final delta = c0['delta'];
              if (delta != null) {
                // content may be string or list of parts
                final dc = delta['content'];
                if (dc is String) {
                  content = dc;
                } else if (dc is List) {
                  // collect text pieces
                  final sb = StringBuffer();
                  for (final it in dc) {
                    if (it is Map) {
                      final t = (it['text'] ?? it['delta'] ?? '') as String? ?? '';
                      if (t.isNotEmpty && (it['type'] == null || it['type'] == 'text')) sb.write(t);
                    }
                  }
                  content = sb.toString();
                } else {
                  content = (dc ?? '') as String;
                }
                if (content.isNotEmpty) {
                  approxCompletionChars += content.length;
                }
                final rc = (delta['reasoning_content'] ?? delta['reasoning']) as String?;
                if (rc != null && rc.isNotEmpty) reasoning = rc;

                // Parse possible image outputs in delta, gated by model output capability
                if (wantsImageOutput) {
                  final List<dynamic> imageItems = <dynamic>[];
                  final imgs = delta['images'];
                  if (imgs is List) imageItems.addAll(imgs);
                  if (dc is List) {
                    for (final it in dc) {
                      if (it is Map && (it['type'] == 'image_url' || it['type'] == 'image')) imageItems.add(it);
                    }
                  }
                  final singleImage = delta['image_url'];
                  if (singleImage is Map || singleImage is String) {
                    imageItems.add({'type': 'image_url', 'image_url': singleImage});
                  }
                  if (imageItems.isNotEmpty) {
                    final buf = StringBuffer();
                    for (final it in imageItems) {
                      if (it is! Map) continue;
                      dynamic iu = it['image_url'];
                      String? url;
                      if (iu is String) {
                        url = iu;
                      } else if (iu is Map) {
                        final u2 = iu['url'];
                        if (u2 is String) url = u2;
                      }
                      if (url != null && url.isNotEmpty) buf.write('\n\n![image](' + url + ')');
                    }
                    if (buf.isNotEmpty) content = content + buf.toString();
                  }
                }

                // Accumulate tool_calls deltas if present
                final tcs = delta['tool_calls'] as List?;
                if (tcs != null) {
                  for (final t in tcs) {
                    final idx = (t['index'] as int?) ?? 0;
                    final id = t['id'] as String?;
                    final func = t['function'] as Map<String, dynamic>?;
                    final name = func?['name'] as String?;
                    final argsDelta = func?['arguments'] as String?;
                    final entry = toolAcc.putIfAbsent(idx, () => {'id': '', 'name': '', 'args': ''});
                    if (id != null) entry['id'] = id;
                    if (name != null && name.isNotEmpty) entry['name'] = name;
                    if (argsDelta != null && argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                  }
                }
              }
            }
            final u = json['usage'];
            if (u != null) {
              final prompt = (u['prompt_tokens'] ?? 0) as int;
              final completion = (u['completion_tokens'] ?? 0) as int;
              final cached = (u['prompt_tokens_details']?['cached_tokens'] ?? 0) as int? ?? 0;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached));
              totalTokens = usage!.totalTokens;
            }
          }

          if (content.isNotEmpty || (reasoning != null && reasoning!.isNotEmpty)) {
            final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
            yield ChatStreamChunk(
              content: content,
              reasoning: reasoning,
              isDone: false,
              totalTokens: totalTokens > 0 ? totalTokens : approxTotal,
              usage: usage,
            );
          }

          // Some providers (e.g., OpenRouter) may omit the [DONE] sentinel
          // and only send finish_reason on the last delta. If we see a
          // definitive finish that's not tool_calls, end the stream now so
          // the UI can persist the message.
          if (config.useResponseApi != true && finishReason != null && finishReason != 'tool_calls') {
            final bool hasPendingToolCalls = toolAcc.isNotEmpty || toolAccResp.isNotEmpty;
            if (hasPendingToolCalls) {
              // print('[ChatApi/OpenAI] suppress early finish due to pending tool_calls (acc.size=' + toolAcc.length.toString() + ')');
            } else if (host.contains('openrouter.ai')) {
              // print('[ChatApi/OpenAI] suppress early finish due to OpenRouter host; wait for [DONE]');
            } else {
              final approxTotal = approxPromptTokens + _approxTokensFromChars(approxCompletionChars);
              yield ChatStreamChunk(
                content: '',
                reasoning: null,
                isDone: true,
                totalTokens: usage?.totalTokens ?? approxTotal,
                usage: usage,
              );
              return;
            }
          }

          // If model finished with tool_calls, execute them and follow-up
          if (false && config.useResponseApi != true && finishReason == 'tool_calls' && onToolCall != null) {
            // Build messages for follow-up
            final calls = <Map<String, dynamic>>[];
            // Emit UI tool call placeholders
            final callInfos = <ToolCallInfo>[];
            final toolMsgs = <Map<String, dynamic>>[];
            toolAcc.forEach((idx, m) {
              final id = (m['id'] ?? 'call_$idx');
              final name = (m['name'] ?? '');
              Map<String, dynamic> args;
              try {
                args = (jsonDecode(m['args'] ?? '{}') as Map).cast<String, dynamic>();
              } catch (_) {
                args = <String, dynamic>{};
              }
              callInfos.add(ToolCallInfo(id: id, name: name, arguments: args));
              calls.add({
                'id': id,
                'type': 'function',
                'function': {
                  'name': name,
                  'arguments': jsonEncode(args),
                },
              });
              toolMsgs.add({'__name': name, '__id': id, '__args': args});
            });

            if (callInfos.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolCalls: callInfos);
            }

            // Execute tools
            final results = <Map<String, dynamic>>[];
            final resultsInfo = <ToolResultInfo>[];
            for (final m in toolMsgs) {
              final name = m['__name'] as String;
              final id = m['__id'] as String;
              final args = (m['__args'] as Map<String, dynamic>);
              final res = await onToolCall(name, args) ?? '';
              results.add({'tool_call_id': id, 'content': res});
              resultsInfo.add(ToolResultInfo(id: id, name: name, arguments: args, content: res));
            }

            if (resultsInfo.isNotEmpty) {
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: usage?.totalTokens ?? 0, usage: usage, toolResults: resultsInfo);
            }

            // Follow-up request with assistant tool_calls + tool messages
            final mm2 = <Map<String, dynamic>>[];
            for (final m in messages) {
              mm2.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
            }
            mm2.add({'role': 'assistant', 'content': '', 'tool_calls': calls});
            for (final r in results) {
              final id = r['tool_call_id'];
              final name = calls.firstWhere((c) => c['id'] == id, orElse: () => const {'function': {'name': ''}})['function']['name'];
              mm2.add({'role': 'tool', 'tool_call_id': id, 'name': name, 'content': r['content']});
            }

            final body2 = {
              'model': modelId,
              'messages': mm2,
              'stream': true,
              if (tools != null && tools.isNotEmpty) 'tools': tools,
              if (tools != null && tools.isNotEmpty) 'tool_choice': 'auto',
            };

            final request2 = http.Request('POST', url);
            request2.headers.addAll({
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
            });
            request2.body = jsonEncode(body2);
            final resp2 = await client.send(request2);
            if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
              final errorBody = await resp2.stream.bytesToString();
              throw HttpException('HTTP ${resp2.statusCode}: $errorBody');
            }
            final s2 = resp2.stream.transform(utf8.decoder);
            String buf2 = '';
            await for (final ch in s2) {
              buf2 += ch;
              final lines2 = buf2.split('\n');
              buf2 = lines2.last;
              for (int j = 0; j < lines2.length - 1; j++) {
                final l = lines2[j].trim();
                if (l.isEmpty || !l.startsWith('data: ')) continue;
                final d = l.substring(6);
                if (d == '[DONE]') {
                  yield ChatStreamChunk(content: '', isDone: true, totalTokens: usage?.totalTokens ?? 0, usage: usage);
                  return;
                }
                try {
                  final o = jsonDecode(d);
                  if (o is Map && o['choices'] is List && (o['choices'] as List).isNotEmpty) {
                    final delta = (o['choices'] as List).first['delta'] as Map?;
                    final txt = delta?['content'];
                    final rc = delta?['reasoning_content'] ?? delta?['reasoning'];
                    if (rc is String && rc.isNotEmpty) {
                      yield ChatStreamChunk(content: '', reasoning: rc, isDone: false, totalTokens: 0, usage: usage);
                    }
                    if (txt is String && txt.isNotEmpty) {
                      yield ChatStreamChunk(content: txt, isDone: false, totalTokens: 0, usage: usage);
                    }
                  }
                } catch (_) {}
              }
            }
            return;
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  static Stream<ChatStreamChunk> _sendClaudeStream(
    http.Client client,
    ProviderConfig config,
    String modelId,
    List<Map<String, dynamic>> messages,
    {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, List<Map<String, dynamic>>? tools, Future<String> Function(String, Map<String, dynamic>)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
  ) async* {
    final base = config.baseUrl.endsWith('/') 
        ? config.baseUrl.substring(0, config.baseUrl.length - 1) 
        : config.baseUrl;
    final url = Uri.parse('$base/messages');

    final isReasoning = _effectiveModelInfo(config, modelId)
        .abilities
        .contains(ModelAbility.reasoning);

    // Transform last user message to include images per Anthropic schema
    final transformed = <Map<String, dynamic>>[];
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isLast = i == messages.length - 1;
      if (isLast && (userImagePaths?.isNotEmpty == true) && (m['role'] == 'user')) {
        final parts = <Map<String, dynamic>>[];
        final text = (m['content'] ?? '').toString();
        if (text.isNotEmpty) parts.add({'type': 'text', 'text': text});
        for (final p in userImagePaths!) {
          if (p.startsWith('http') || p.startsWith('data:')) {
            // Fallback: include link as text
            parts.add({'type': 'text', 'text': p});
          } else {
            final mime = _mimeFromPath(p);
            final b64 = await _encodeBase64File(p, withPrefix: false);
            parts.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mime,
                'data': b64,
              }
            });
          }
        }
        transformed.add({'role': 'user', 'content': parts});
      } else {
        transformed.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
      }
    }

    // Map OpenAI-style tools to Anthropic tools if provided
    List<Map<String, dynamic>>? anthropicTools;
    if (tools != null && tools.isNotEmpty) {
      anthropicTools = [];
      for (final t in tools) {
        final fn = (t['function'] as Map<String, dynamic>?);
        if (fn == null) continue;
        final name = (fn['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final desc = (fn['description'] ?? '').toString();
        final params = (fn['parameters'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{'type': 'object'};
        anthropicTools.add({
          'name': name,
          if (desc.isNotEmpty) 'description': desc,
          'input_schema': params,
        });
      }
    }

    final body = <String, dynamic>{
      'model': modelId,
      'max_tokens': maxTokens ?? 4096,
      'messages': transformed,
      'stream': true,
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (anthropicTools != null && anthropicTools.isNotEmpty) 'tools': anthropicTools,
      if (anthropicTools != null && anthropicTools.isNotEmpty) 'tool_choice': {'type': 'auto'},
      if (isReasoning)
        'thinking': {
          'type': (thinkingBudget == 0) ? 'disabled' : 'enabled',
          if (thinkingBudget != null && thinkingBudget > 0)
            'budget_tokens': thinkingBudget,
        },
    };

    final request = http.Request('POST', url);
    final headers = <String, String>{
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    headers.addAll(_customHeaders(config, modelId));
    if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
    request.headers.addAll(headers);
    final extraClaude = _customBody(config, modelId);
    if (extraClaude.isNotEmpty) (body as Map<String, dynamic>).addAll(extraClaude);
    if (extraBody != null && extraBody.isNotEmpty) {
      extraBody.forEach((k, v) {
        (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
      });
    }
    request.body = jsonEncode(body);

    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $errorBody');
    }

    final stream = response.stream.transform(utf8.decoder);
    String buffer = '';
    int totalTokens = 0;
    TokenUsage? usage;

    // Accumulate tool_use inputs by id
    final Map<String, Map<String, dynamic>> _anthToolUse = <String, Map<String, dynamic>>{}; // id -> {name, argsStr}

    await for (final chunk in stream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();
        if (line.isEmpty || !line.startsWith('data: ')) continue;

        final data = line.substring(6);
        try {
          final json = jsonDecode(data);
          final type = json['type'];
          
          if (type == 'content_block_delta') {
            final delta = json['delta'];
            if (delta != null) {
              if (delta['type'] == 'text_delta') {
                final content = delta['text'] ?? '';
                if (content is String && content.isNotEmpty) {
                  yield ChatStreamChunk(
                    content: content,
                    isDone: false,
                    totalTokens: totalTokens,
                  );
                }
              } else if (delta['type'] == 'thinking_delta') {
                final thinking = (delta['thinking'] ?? delta['text'] ?? '') as String;
                if (thinking.isNotEmpty) {
                  yield ChatStreamChunk(
                    content: '',
                    reasoning: thinking,
                    isDone: false,
                    totalTokens: totalTokens,
                  );
                }
              } else if (delta['type'] == 'tool_use_delta') {
                final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
                if (id.isNotEmpty) {
                  final entry = _anthToolUse.putIfAbsent(id, () => {'name': (json['content_block']?['name'] ?? '').toString(), 'args': ''});
                  final argsDelta = (delta['partial_json'] ?? delta['input'] ?? delta['text'] ?? '').toString();
                  if (argsDelta.isNotEmpty) entry['args'] = (entry['args'] ?? '') + argsDelta;
                }
              }
            }
          } else if (type == 'content_block_start') {
            // Start of tool_use block: we can pre-register name/id
            final cb = json['content_block'];
            if (cb is Map && (cb['type'] == 'tool_use')) {
              final id = (cb['id'] ?? '').toString();
              final name = (cb['name'] ?? '').toString();
              if (id.isNotEmpty) {
                _anthToolUse.putIfAbsent(id, () => {'name': name, 'args': ''});
              }
            }
          } else if (type == 'content_block_stop') {
            // Finalize tool_use and emit tool call + result
            final id = (json['content_block']?['id'] ?? json['id'] ?? '').toString();
            if (id.isNotEmpty && _anthToolUse.containsKey(id)) {
              final name = (_anthToolUse[id]!['name'] ?? '').toString();
              Map<String, dynamic> args;
              try { args = (jsonDecode((_anthToolUse[id]!['args'] ?? '{}') as String) as Map).cast<String, dynamic>(); } catch (_) { args = <String, dynamic>{}; }
              // Emit placeholder
              final calls = [ToolCallInfo(id: id, name: name, arguments: args)];
              yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolCalls: calls, usage: usage);
              // Execute tool and emit result
              if (onToolCall != null) {
                final res = await onToolCall(name, args) ?? '';
                final results = [ToolResultInfo(id: id, name: name, arguments: args, content: res)];
                yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, toolResults: results, usage: usage);
              }
            }
          } else if (type == 'message_stop') {
            yield ChatStreamChunk(
              content: '',
              isDone: true,
              totalTokens: totalTokens,
              usage: usage,
            );
            return;
          } else if (type == 'message_delta') {
            final u = json['usage'] ?? json['message']?['usage'];
            if (u != null) {
              final inTok = (u['input_tokens'] ?? 0) as int;
              final outTok = (u['output_tokens'] ?? 0) as int;
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(promptTokens: inTok, completionTokens: outTok));
              totalTokens = usage!.totalTokens;
            }
          }
        } catch (e) {
          // Skip malformed JSON
        }
      }
    }
  }

  static Stream<ChatStreamChunk> _sendGoogleStream(
    http.Client client,
    ProviderConfig config,
    String modelId,
    List<Map<String, dynamic>> messages,
    {List<String>? userImagePaths, int? thinkingBudget, double? temperature, double? topP, int? maxTokens, List<Map<String, dynamic>>? tools, Future<String> Function(String, Map<String, dynamic>)? onToolCall, Map<String, String>? extraHeaders, Map<String, dynamic>? extraBody}
  ) async* {
    // Implement SSE streaming via :streamGenerateContent with alt=sse
    // Build endpoint per Vertex vs Gemini
    String baseUrl;
    if (config.vertexAI == true && (config.location?.isNotEmpty == true) && (config.projectId?.isNotEmpty == true)) {
      final loc = config.location!.trim();
      final proj = config.projectId!.trim();
      baseUrl = 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$modelId:streamGenerateContent';
    } else {
      final base = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      baseUrl = '$base/models/$modelId:streamGenerateContent';
    }

    // Build query with key (for non-Vertex) and alt=sse
    final uriBase = Uri.parse(baseUrl);
    final qp = Map<String, String>.from(uriBase.queryParameters);
    if (!(config.vertexAI == true)) {
      if (config.apiKey.isNotEmpty) qp['key'] = config.apiKey;
    }
    qp['alt'] = 'sse';
    final uri = uriBase.replace(queryParameters: qp);

    // Convert messages to Google contents format
    final contents = <Map<String, dynamic>>[];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final role = msg['role'] == 'assistant' ? 'model' : 'user';
      final isLast = i == messages.length - 1;
      final parts = <Map<String, dynamic>>[];
      final raw = (msg['content'] ?? '').toString();
      
      // Only parse images if there are images to process
      final hasMarkdownImages = raw.contains('![') && raw.contains('](');
      final hasCustomImages = raw.contains('[image:');
      final hasAttachedImages = isLast && role == 'user' && (userImagePaths?.isNotEmpty == true);
      
      if (hasMarkdownImages || hasCustomImages || hasAttachedImages) {
        final parsed = _parseTextAndImages(raw);
        if (parsed.text.isNotEmpty) parts.add({'text': parsed.text});
        // Images extracted from this message's text
        for (final ref in parsed.images) {
          if (ref.kind == 'data') {
            final mime = _mimeFromDataUrl(ref.src);
            final idx = ref.src.indexOf('base64,');
            if (idx > 0) {
              final b64 = ref.src.substring(idx + 7);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              // If malformed data URL, include as plain text fallback
              parts.add({'text': ref.src});
            }
          } else if (ref.kind == 'path') {
            final mime = _mimeFromPath(ref.src);
            final b64 = await _encodeBase64File(ref.src, withPrefix: false);
            parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
          } else {
            // Remote URL: Gemini official API doesn't fetch http(s) here; keep short reference
            parts.add({'text': '(image) ${ref.src}'});
          }
        }
        if (hasAttachedImages) {
          for (final p in userImagePaths!) {
            if (p.startsWith('data:')) {
              final mime = _mimeFromDataUrl(p);
              final idx = p.indexOf('base64,');
              if (idx > 0) {
                final b64 = p.substring(idx + 7);
                parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
              }
            } else if (!(p.startsWith('http://') || p.startsWith('https://'))) {
              final mime = _mimeFromPath(p);
              final b64 = await _encodeBase64File(p, withPrefix: false);
              parts.add({'inline_data': {'mime_type': mime, 'data': b64}});
            } else {
              // http url fallback reference text
              parts.add({'text': '(image) ${p}'});
            }
          }
        }
      } else {
        // No images, use simple text content
        if (raw.isNotEmpty) parts.add({'text': raw});
      }
      contents.add({'role': role, 'parts': parts});
    }

    // Effective model features (includes user overrides)
    final effective = _effectiveModelInfo(config, modelId);
    final isReasoning = effective.abilities.contains(ModelAbility.reasoning);
    final wantsImageOutput = effective.output.contains(Modality.image);
    bool _expectImage = wantsImageOutput;
    bool _receivedImage = false;
    final off = _isOff(thinkingBudget);
    // Built-in Gemini tools (only for official Gemini API)
    final builtIns = _builtInTools(config, modelId);
    final isOfficialGemini = config.vertexAI != true; // requirement: only Gemini official API
    final builtInToolEntries = <Map<String, dynamic>>[];
    if (isOfficialGemini && builtIns.isNotEmpty) {
      if (builtIns.contains('search')) {
        builtInToolEntries.add({'google_search': {}});
      }
      if (builtIns.contains('url_context')) {
        builtInToolEntries.add({'url_context': {}});
      }
    }

    // Map OpenAI-style tools to Gemini functionDeclarations (skip if built-in tools are enabled, as they are not compatible)
    List<Map<String, dynamic>>? geminiTools;
    if (builtInToolEntries.isEmpty && tools != null && tools.isNotEmpty) {
      final decls = <Map<String, dynamic>>[];
      for (final t in tools) {
        final fn = (t['function'] as Map<String, dynamic>?);
        if (fn == null) continue;
        final name = (fn['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final desc = (fn['description'] ?? '').toString();
        final params = (fn['parameters'] as Map?)?.cast<String, dynamic>();
        final d = <String, dynamic>{'name': name, if (desc.isNotEmpty) 'description': desc};
        if (params != null) d['parameters'] = params;
        decls.add(d);
      }
      if (decls.isNotEmpty) geminiTools = [{'function_declarations': decls}];
    }

    // Maintain a rolling conversation for multi-round tool calls
    List<Map<String, dynamic>> convo = List<Map<String, dynamic>>.from(contents);
    TokenUsage? usage;
    int totalTokens = 0;

    // Accumulate built-in search citations across stream rounds
    final List<Map<String, dynamic>> _builtinCitations = <Map<String, dynamic>>[];

    List<Map<String, dynamic>> _parseCitations(dynamic gm) {
      final out = <Map<String, dynamic>>[];
      if (gm is! Map) return out;
      final chunks = gm['groundingChunks'] as List? ?? const <dynamic>[];
      int idx = 1;
      final seen = <String>{};
      for (final ch in chunks) {
        if (ch is! Map) continue;
        final web = ch['web'] as Map? ?? ch['webSite'] as Map? ?? ch['webPage'] as Map?;
        if (web is! Map) continue;
        final uri = (web['uri'] ?? web['url'] ?? '').toString();
        if (uri.isEmpty) continue;
        // Deduplicate by uri
        if (seen.contains(uri)) continue;
        seen.add(uri);
        final title = (web['title'] ?? web['name'] ?? uri).toString();
        final id = 'c${idx.toString().padLeft(2, '0')}';
        out.add({'id': id, 'index': idx, 'title': title, 'url': uri});
        idx++;
      }
      return out;
    }

    while (true) {
      final gen = <String, dynamic>{
        if (temperature != null) 'temperature': temperature,
        if (topP != null) 'topP': topP,
        if (maxTokens != null) 'maxOutputTokens': maxTokens,
        // Enable IMAGE+TEXT output modalities when model is configured to output images
        if (wantsImageOutput) 'responseModalities': ['TEXT', 'IMAGE'],
        if (isReasoning)
          'thinkingConfig': {
            'includeThoughts': off ? false : true,
            if (!off && thinkingBudget != null && thinkingBudget >= 0)
              'thinkingBudget': thinkingBudget,
          },
      };
      final body = <String, dynamic>{
        'contents': convo,
        if (gen.isNotEmpty) 'generationConfig': gen,
        // Prefer built-in tools when configured; otherwise map function tools
        if (builtInToolEntries.isNotEmpty) 'tools': builtInToolEntries,
        if (builtInToolEntries.isEmpty && geminiTools != null && geminiTools.isNotEmpty) 'tools': geminiTools,
      };

      final request = http.Request('POST', uri);
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      };
      if (config.vertexAI == true) {
        final token = await _maybeVertexAccessToken(config);
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
        final proj = (config.projectId ?? '').trim();
        if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
      }
      headers.addAll(_customHeaders(config, modelId));
      if (extraHeaders != null && extraHeaders.isNotEmpty) headers.addAll(extraHeaders);
      request.headers.addAll(headers);
      final extra = _customBody(config, modelId);
      if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
      if (extraBody != null && extraBody.isNotEmpty) {
        extraBody.forEach((k, v) {
          (body as Map<String, dynamic>)[k] = (v is String) ? _parseOverrideValue(v) : v;
        });
      }
      request.body = jsonEncode(body);

      final resp = await client.send(request);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final errorBody = await resp.stream.bytesToString();
        throw HttpException('HTTP ${resp.statusCode}: $errorBody');
      }

      final stream = resp.stream.transform(utf8.decoder);
      String buffer = '';
      // Collect any function calls in this round
      final List<Map<String, dynamic>> calls = <Map<String, dynamic>>[]; // {id,name,args,res}

      // Track a streaming inline image (append base64 progressively)
      bool _imageOpen = false; // true after we emit the data URL prefix
      String _imageMime = 'image/png';

      await for (final chunk in stream) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.last; // keep incomplete line

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim(); // after 'data:'
          if (data.isEmpty) continue;
          try {
            final obj = jsonDecode(data) as Map<String, dynamic>;
            final um = obj['usageMetadata'];
            if (um is Map<String, dynamic>) {
              usage = (usage ?? const TokenUsage()).merge(TokenUsage(
                promptTokens: (um['promptTokenCount'] ?? 0) as int,
                completionTokens: (um['candidatesTokenCount'] ?? 0) as int,
                totalTokens: (um['totalTokenCount'] ?? 0) as int,
              ));
              totalTokens = usage!.totalTokens;
            }

            final candidates = obj['candidates'];
            if (candidates is List && candidates.isNotEmpty) {
              String textDelta = '';
              String reasoningDelta = '';
              String? finishReason; // detect stream completion from server
              for (final cand in candidates) {
                if (cand is! Map) continue;
                final content = cand['content'];
                if (content is! Map) continue;
                final parts = content['parts'];
                if (parts is! List) continue;
                for (final p in parts) {
                  if (p is! Map) continue;
                  final t = (p['text'] ?? '') as String? ?? '';
                  final thought = p['thought'] as bool? ?? false;
                  if (t.isNotEmpty) {
                    if (thought) {
                      reasoningDelta += t;
                    } else {
                      textDelta += t;
                    }
                  }
                  // Parse inline image data from Gemini (inlineData)
                  // Response shape: { inlineData: { mimeType: 'image/png', data: '...base64...' } }
                  final inline = (p['inlineData'] ?? p['inline_data']);
                  if (inline is Map) {
                    final mime = (inline['mimeType'] ?? inline['mime_type'] ?? 'image/png').toString();
                    final data = (inline['data'] ?? '').toString();
                    if (data.isNotEmpty) {
                      _imageMime = mime.isNotEmpty ? mime : 'image/png';
                      if (!_imageOpen) {
                        textDelta += '\n\n![image](data:${_imageMime};base64,';
                        _imageOpen = true;
                      }
                      textDelta += data;
                      _receivedImage = true;
                    }
                  }
                  // Parse fileData: { fileUri: 'https://...', mimeType: 'image/png' }
                  final fileData = (p['fileData'] ?? p['file_data']);
                  if (fileData is Map) {
                    final mime = (fileData['mimeType'] ?? fileData['mime_type'] ?? 'image/png').toString();
                    final uri = (fileData['fileUri'] ?? fileData['file_uri'] ?? fileData['uri'] ?? '').toString();
                    if (uri.startsWith('http')) {
                      try {
                        final b64 = await _downloadRemoteAsBase64(client, config, uri);
                        _imageMime = mime.isNotEmpty ? mime : 'image/png';
                        if (!_imageOpen) {
                          textDelta += '\n\n![image](data:${_imageMime};base64,';
                          _imageOpen = true;
                        }
                        textDelta += b64;
                        _receivedImage = true;
                      } catch (_) {}
                    }
                  }
                  final fc = p['functionCall'];
                  if (fc is Map) {
                    final name = (fc['name'] ?? '').toString();
                    Map<String, dynamic> args = const <String, dynamic>{};
                    final rawArgs = fc['args'];
                    if (rawArgs is Map) {
                      args = rawArgs.cast<String, dynamic>();
                    } else if (rawArgs is String && rawArgs.isNotEmpty) {
                      try { args = (jsonDecode(rawArgs) as Map).cast<String, dynamic>(); } catch (_) {}
                    }
                    final id = 'call_${DateTime.now().microsecondsSinceEpoch}';
                    // Emit placeholder immediately
                    yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolCalls: [ToolCallInfo(id: id, name: name, arguments: args)]);
                    String resText = '';
                    if (onToolCall != null) {
                      resText = await onToolCall(name, args) ?? '';
                      yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: [ToolResultInfo(id: id, name: name, arguments: args, content: resText)]);
                    }
                    calls.add({'id': id, 'name': name, 'args': args, 'result': resText});
                  }
                }
                // Capture explicit finish reason if present
                final fr = cand['finishReason'];
                if (fr is String && fr.isNotEmpty) finishReason = fr;

                // Parse grounding metadata for citations if present
                final gm = cand['groundingMetadata'] ?? obj['groundingMetadata'];
                final cite = _parseCitations(gm);
                if (cite.isNotEmpty) {
                  // merge unique by url
                  final existingUrls = _builtinCitations.map((e) => e['url']?.toString() ?? '').toSet();
                  for (final it in cite) {
                    final u = it['url']?.toString() ?? '';
                    if (u.isEmpty || existingUrls.contains(u)) continue;
                    _builtinCitations.add(it);
                    existingUrls.add(u);
                  }
                  // emit a tool result chunk so UI can render citations card
                  final payload = jsonEncode({'items': _builtinCitations});
                  yield ChatStreamChunk(
                    content: '',
                    isDone: false,
                    totalTokens: totalTokens,
                    usage: usage,
                    toolResults: [ToolResultInfo(id: 'builtin_search', name: 'builtin_search', arguments: const <String, dynamic>{}, content: payload)],
                  );
                }
              }

              if (reasoningDelta.isNotEmpty) {
                yield ChatStreamChunk(content: '', reasoning: reasoningDelta, isDone: false, totalTokens: totalTokens, usage: usage);
              }
              if (textDelta.isNotEmpty) {
                yield ChatStreamChunk(content: textDelta, isDone: false, totalTokens: totalTokens, usage: usage);
              }

              // If server signaled finish, close image markdown and end stream immediately
              if (finishReason != null && calls.isEmpty && (!_expectImage || _receivedImage)) {
                if (_imageOpen) {
                  yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
                  _imageOpen = false;
                }
                // Emit final citations if any not emitted
                if (_builtinCitations.isNotEmpty) {
                  final payload = jsonEncode({'items': _builtinCitations});
                  yield ChatStreamChunk(content: '', isDone: false, totalTokens: totalTokens, usage: usage, toolResults: [ToolResultInfo(id: 'builtin_search', name: 'builtin_search', arguments: const <String, dynamic>{}, content: payload)]);
                }
                yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
                return;
              }
            }
          } catch (_) {
            // ignore malformed chunk
          }
        }
      }

      // If we streamed an inline image but never closed the markdown, close it now
      if (_imageOpen) {
        yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
        _imageOpen = false;
      }

      if (calls.isEmpty) {
        // No tool calls; this round finished
        if (_imageOpen) {
          yield ChatStreamChunk(content: ')', isDone: false, totalTokens: totalTokens, usage: usage);
          _imageOpen = false;
        }
        yield ChatStreamChunk(content: '', isDone: true, totalTokens: totalTokens, usage: usage);
        return;
      }

      // Append model functionCall(s) and user functionResponse(s) to conversation, then loop
      for (final c in calls) {
        final name = (c['name'] ?? '').toString();
        final args = (c['args'] as Map<String, dynamic>? ?? const <String, dynamic>{});
        final resText = (c['result'] ?? '').toString();
        // Add the model's functionCall turn
        convo.add({'role': 'model', 'parts': [
          {'functionCall': {'name': name, 'args': args}},
        ]});
        // Prepare JSON response object
        Map<String, dynamic> responseObj;
        try {
          responseObj = (jsonDecode(resText) as Map).cast<String, dynamic>();
        } catch (_) {
          // Wrap plain text result
          responseObj = {'result': resText};
        }
        // Add user's functionResponse turn
        convo.add({'role': 'user', 'parts': [
          {'functionResponse': {'name': name, 'response': responseObj}},
        ]});
      }
      // Continue while(true) for next round
    }
  }

  static Future<String> _downloadRemoteAsBase64(http.Client client, ProviderConfig config, String url) async {
    final req = http.Request('GET', Uri.parse(url));
    // Add Vertex auth if enabled
    if (config.vertexAI == true) {
      try {
        final token = await _maybeVertexAccessToken(config);
        if (token != null && token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
      } catch (_) {}
      final proj = (config.projectId ?? '').trim();
      if (proj.isNotEmpty) req.headers['X-Goog-User-Project'] = proj;
    }
    final resp = await client.send(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final err = await resp.stream.bytesToString();
      throw HttpException('HTTP ${resp.statusCode}: $err');
    }
    final bytes = await resp.stream.fold<List<int>>(<int>[], (acc, b) { acc.addAll(b); return acc; });
    return base64Encode(bytes);
  }
  // Returns OAuth token for Vertex AI when serviceAccountJson is configured; otherwise null.
  static Future<String?> _maybeVertexAccessToken(ProviderConfig cfg) async {
    if (cfg.vertexAI == true) {
      final jsonStr = (cfg.serviceAccountJson ?? '').trim();
      if (jsonStr.isEmpty) {
        // Fallback: some users may paste a temporary OAuth token into apiKey
        if (cfg.apiKey.isNotEmpty) return cfg.apiKey;
        return null;
      }
      try {
        return await GoogleServiceAccountAuth.getAccessTokenFromJson(jsonStr);
      } catch (_) {
        // On failure, do not crash streaming; let server return 401 and surface error upstream
        return null;
      }
    }
    return null;
  }

}

class _ImageRef {
  final String kind; // 'data' | 'path' | 'url'
  final String src;
  const _ImageRef(this.kind, this.src);
}

class _ParsedTextAndImages {
  final String text;
  final List<_ImageRef> images;
  const _ParsedTextAndImages(this.text, this.images);
}

class ChatStreamChunk {
  final String content;
  // Optional reasoning delta (when model supports reasoning)
  final String? reasoning;
  final bool isDone;
  final int totalTokens;
  final TokenUsage? usage;
  final List<ToolCallInfo>? toolCalls;
  final List<ToolResultInfo>? toolResults;

  ChatStreamChunk({
    required this.content,
    this.reasoning,
    required this.isDone,
    required this.totalTokens,
    this.usage,
    this.toolCalls,
    this.toolResults,
  });
}

class ToolCallInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  ToolCallInfo({required this.id, required this.name, required this.arguments});
}

class ToolResultInfo {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String content;
  ToolResultInfo({required this.id, required this.name, required this.arguments, required this.content});
}
