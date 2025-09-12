import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Transport type supported on mobile: SSE and Streamable HTTP.
enum McpTransportType { sse, http }

/// Connection status for an MCP server.
enum McpStatus { idle, connecting, connected, error }

class McpParamSpec {
  final String name;
  final bool required;
  final String? type;
  final dynamic defaultValue;

  McpParamSpec({
    required this.name,
    required this.required,
    this.type,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'required': required,
        'type': type,
        'default': defaultValue,
      };

  factory McpParamSpec.fromJson(Map<String, dynamic> json) => McpParamSpec(
        name: json['name'] as String? ?? '',
        required: json['required'] as bool? ?? false,
        type: json['type'] as String?,
        defaultValue: json['default'],
      );
}

class McpToolConfig {
  final bool enabled;
  final String name;
  final String? description;
  final List<McpParamSpec> params;

  McpToolConfig({
    required this.enabled,
    required this.name,
    this.description,
    this.params = const [],
  });

  McpToolConfig copyWith({bool? enabled, String? name, String? description, List<McpParamSpec>? params}) =>
      McpToolConfig(
        enabled: enabled ?? this.enabled,
        name: name ?? this.name,
        description: description ?? this.description,
        params: params ?? this.params,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'name': name,
        'description': description,
        'params': params.map((e) => e.toJson()).toList(),
      };

  factory McpToolConfig.fromJson(Map<String, dynamic> json) => McpToolConfig(
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        params: (json['params'] as List?)
                ?.map((e) => McpParamSpec.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

class McpServerConfig {
  final String id; // stable id
  final bool enabled;
  final String name;
  final McpTransportType transport;
  final String url; // SSE endpoint or HTTP base URL
  final List<McpToolConfig> tools;
  final Map<String, String> headers; // custom HTTP headers

  McpServerConfig({
    required this.id,
    required this.enabled,
    required this.name,
    required this.transport,
    required this.url,
    this.tools = const [],
    this.headers = const {},
  });

  McpServerConfig copyWith({
    String? id,
    bool? enabled,
    String? name,
    McpTransportType? transport,
    String? url,
    List<McpToolConfig>? tools,
    Map<String, String>? headers,
  }) =>
      McpServerConfig(
        id: id ?? this.id,
        enabled: enabled ?? this.enabled,
        name: name ?? this.name,
        transport: transport ?? this.transport,
        url: url ?? this.url,
        tools: tools ?? this.tools,
        headers: headers ?? this.headers,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'name': name,
        'transport': transport.name,
        'url': url,
        'tools': tools.map((e) => e.toJson()).toList(),
        'headers': headers,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) => McpServerConfig(
        id: json['id'] as String? ?? const Uuid().v4(),
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        transport: (json['transport'] as String?) == 'http' ? McpTransportType.http : McpTransportType.sse,
        url: json['url'] as String? ?? '',
        tools: (json['tools'] as List?)
                ?.map((e) => McpToolConfig.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        headers: ((json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString()))) ?? const {},
      );
}

class McpProvider extends ChangeNotifier {
  static const String _prefsKey = 'mcp_servers_v1';

  final Map<String, mcp.Client> _clients = {};
  final Map<String, McpStatus> _status = {}; // id -> status
  final Map<String, String> _errors = {}; // id -> last error
  List<McpServerConfig> _servers = [];
  // Reconnect bookkeeping to avoid duplicate concurrent retries
  final Set<String> _reconnecting = <String>{};
  // Heartbeat timers for live-connection health checks
  final Map<String, Timer> _heartbeats = <String, Timer>{};

  McpProvider() {
    _load();
  }

  List<McpServerConfig> get servers => List.unmodifiable(_servers);
  McpStatus statusFor(String id) => _status[id] ?? McpStatus.idle;
  String? errorFor(String id) => _errors[id];
  bool get hasAnyEnabled => _servers.any((s) => s.enabled);
  bool isConnected(String id) => _clients.containsKey(id) && statusFor(id) == McpStatus.connected;
  List<McpServerConfig> get connectedServers =>
      _servers.where((s) => statusFor(s.id) == McpStatus.connected).toList(growable: false);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => McpServerConfig.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _servers = list;
      } catch (_) {}
    }
    // initialize statuses
    for (final s in _servers) {
      _status[s.id] = McpStatus.idle;
      _errors.remove(s.id);
    }
    notifyListeners();

    // Auto-connect enabled servers
    for (final s in _servers.where((e) => e.enabled)) {
      // fire and forget
      unawaited(connect(s.id));
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_servers.map((e) => e.toJson()).toList()));
  }

  McpServerConfig? getById(String id) {
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<String> addServer({
    required bool enabled,
    required String name,
    required McpTransportType transport,
    required String url,
    Map<String, String> headers = const {},
  }) async {
    final id = const Uuid().v4();
    final cfg = McpServerConfig(
      id: id,
      enabled: enabled,
      name: name.trim().isEmpty ? 'MCP' : name.trim(),
      transport: transport,
      url: url.trim(),
      headers: headers,
    );
    _servers = [..._servers, cfg];
    _status[id] = McpStatus.idle;
    await _persist();
    notifyListeners();
    if (enabled) {
      unawaited(connect(id));
    }
    return id;
  }

  Future<void> updateServer(McpServerConfig updated) async {
    final idx = _servers.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    _servers = List<McpServerConfig>.of(_servers)..[idx] = updated;
    await _persist();
    notifyListeners();
    if (!updated.enabled) {
      await disconnect(updated.id);
    } else {
      // Always reconnect after saving to apply changes (url/transport/name)
      await disconnect(updated.id);
      unawaited(connect(updated.id));
    }
  }

  Future<void> removeServer(String id) async {
    await disconnect(id);
    _servers = _servers.where((e) => e.id != id).toList(growable: false);
    _status.remove(id);
    await _persist();
    notifyListeners();
  }

  Future<void> setToolEnabled(String serverId, String toolName, bool enabled) async {
    final idx = _servers.indexWhere((e) => e.id == serverId);
    if (idx < 0) return;
    final server = _servers[idx];
    final tools = server.tools.map((t) => t.name == toolName ? t.copyWith(enabled: enabled) : t).toList();
    _servers[idx] = server.copyWith(tools: tools);
    await _persist();
    notifyListeners();
  }

  Future<void> connect(String id) async {
    final server = _servers.firstWhere((e) => e.id == id, orElse: () => throw StateError('Server not found'));
    // If already connected, try a ping by listing tools quickly; else return
    if (_clients.containsKey(id)) {
      // Already connected; update status just in case
      _status[id] = McpStatus.connected;
      _errors.remove(id);
      notifyListeners();
      return;
    }
    _status[id] = McpStatus.connecting;
    _errors.remove(id);
    notifyListeners();

    try {
      final clientConfig = mcp.McpClient.simpleConfig(
        name: 'Kelivo MCP',
        version: '1.0.0',
        enableDebugLogging: false,
      );

      final mergedHeaders = <String, String>{...server.headers};
      final transportConfig = server.transport == McpTransportType.sse
          ? mcp.TransportConfig.sse(
              serverUrl: server.url,
              headers: mergedHeaders.isEmpty ? null : mergedHeaders,
            )
          : mcp.TransportConfig.streamableHttp(
              baseUrl: server.url,
              headers: mergedHeaders.isEmpty ? null : mergedHeaders,
            );

      final clientResult = await mcp.McpClient.createAndConnect(
        config: clientConfig,
        transportConfig: transportConfig,
      );

      final client = clientResult.fold((c) => c, (err) => throw Exception(err.toString()));
      _clients[id] = client;
      _status[id] = McpStatus.connected;
      _errors.remove(id);
      notifyListeners();

      // Try to refresh tools once connected
      await refreshTools(id);

      // Start/refresh heartbeat for this connection
      _startHeartbeat(id);
    } catch (e, st) {
      _status[id] = McpStatus.error;
      _errors[id] = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect(String id) async {
    final client = _clients.remove(id);
    try {
      client?.disconnect();
    } catch (_) {}
    _status[id] = McpStatus.idle;
    _errors.remove(id);
    _stopHeartbeat(id);
    notifyListeners();
  }

  Future<void> reconnect(String id) async {
    await disconnect(id);
    await connect(id);
  }

  Future<void> _reconnectWithBackoff(String id, {int maxAttempts = 3}) async {
    if (_reconnecting.contains(id)) return;
    _reconnecting.add(id);
    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        await reconnect(id);
        if (isConnected(id)) return;
        // progressive backoff: 600ms, 1200ms, 2400ms
        final delayMs = 600 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    } finally {
      _reconnecting.remove(id);
    }
  }

  void _startHeartbeat(String id, {Duration interval = const Duration(seconds: 12)}) {
    _stopHeartbeat(id);
    _heartbeats[id] = Timer.periodic(interval, (t) async {
      // Heartbeat only when we think we're connected
      if (!isConnected(id)) return;
      final client = _clients[id];
      if (client == null) return;
      try {
        // A lightweight call to verify liveness
        // listTools is relatively cheap and available
        final fut = client.listTools();
        // Add a soft timeout to avoid piling up
        await fut.timeout(const Duration(seconds: 6));
      } catch (e) {
        // Consider connection lost; mark error and try auto-reconnect
        _status[id] = McpStatus.error;
        _errors[id] = e.toString();
        notifyListeners();
        await _reconnectWithBackoff(id, maxAttempts: 3);
        // If reconnected, restart heartbeat (connect() also starts it)
        if (!isConnected(id)) {
          // keep error state; next heartbeat tick will be a no-op
        }
      }
    });
  }

  void _stopHeartbeat(String id) {
    _heartbeats.remove(id)?.cancel();
  }

  Future<void> refreshTools(String id) async {
    final client = _clients[id];
    if (client == null) return;
    try {
      final tools = await client.listTools();
      // Preserve enabled state from existing config
      final idx = _servers.indexWhere((e) => e.id == id);
      if (idx < 0) return;
      final existing = _servers[idx].tools;
      final existingMap = {for (final t in existing) t.name: t};

      List<McpToolConfig> merged = [];
      for (final t in tools) {
        final prior = existingMap[t.name];
        // Extract params from inputSchema if present
        final params = <McpParamSpec>[];
        try {
          final schema = t.inputSchema; // dynamic; depends on package
          if (schema != null) {
            // We attempt to read JSON schema-ish fields via toJson if provided
            final Map<String, dynamic> js = (schema is Map<String, dynamic>)
                ? schema
                : (schema is Object && schema.toString().isNotEmpty)
                    ? (schema as dynamic).toJson?.call() as Map<String, dynamic>? ?? {}
                    : {};
            final props = (js['properties'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
            final req = (js['required'] as List?)?.map((e) => e.toString()).toSet() ?? const <String>{};
            props.forEach((key, val) {
              params.add(McpParamSpec(
                name: key,
                required: req.contains(key),
              ));
            });
          }
        } catch (_) {}

        merged.add(McpToolConfig(
          enabled: prior?.enabled ?? true,
          name: t.name,
          description: t.description,
          params: params,
        ));
      }

      _servers[idx] = _servers[idx].copyWith(tools: merged);
      await _persist();
      notifyListeners();
    } catch (_) {
      // ignore tool refresh errors; status stays connected
    }
  }

  Future<void> ensureConnected(String id) async {
    // Do not attempt to connect if the server is disabled
    final cfg = getById(id);
    if (cfg == null || !cfg.enabled) return;
    if (isConnected(id)) return;
    // Try a few times with short backoff in case server blips
    await _reconnectWithBackoff(id, maxAttempts: 3);
  }

  Future<mcp.CallToolResult?> callTool(String serverId, String toolName, Map<String, dynamic> args) async {
    try {
      await ensureConnected(serverId);
      var client = _clients[serverId];
      if (client == null) return null;
      final result = await client.callTool(toolName, args);
      return result;
    } catch (e) {
      _status[serverId] = McpStatus.error;
      _errors[serverId] = e.toString();
      notifyListeners();
      // Auto-reconnect a few times and try once more
      try {
        await _reconnectWithBackoff(serverId, maxAttempts: 3);
        if (!isConnected(serverId)) return null;
        final client = _clients[serverId];
        if (client == null) return null;
        final result = await client.callTool(toolName, args);
        // Mark healthy again
        _status[serverId] = McpStatus.connected;
        _errors.remove(serverId);
        notifyListeners();
        return result;
      } catch (_) {
        // Keep error state; give up
        return null;
      }
    }
  }

  List<McpToolConfig> getEnabledToolsForServers(Set<String> serverIds) {
    // Only expose tools for servers that are both selected AND currently connected
    final tools = <McpToolConfig>[];
    for (final s in _servers.where((s) => serverIds.contains(s.id))) {
      if (statusFor(s.id) != McpStatus.connected) continue;
      if (!s.enabled) continue;
      tools.addAll(s.tools.where((t) => t.enabled));
    }
    return tools;
  }

  @override
  void dispose() {
    // Clean up timers
    for (final t in _heartbeats.values) {
      t.cancel();
    }
    _heartbeats.clear();
    super.dispose();
  }
}
