import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Resolves persisted absolute file paths that include the iOS sandbox UUID
/// to the current app container path after an app update.
///
/// Example:
///   Before update: /var/mobile/Containers/Data/Application/ABC/Documents/upload/x.png
///   After update:  /var/mobile/Containers/Data/Application/XYZ/Documents/upload/x.png
///
/// We store absolute paths in message content. On iOS, the container prefix
/// changes after update. This helper rewrites any path that points into our
/// previous container's Documents subfolders (upload/avatars) to the current
/// Documents directory. If the rewritten file exists, it returns the new path;
/// otherwise returns the original path.
class SandboxPathResolver {
  SandboxPathResolver._();

  static String? _docsDir;

  /// Call once during app startup to cache the current Documents directory.
  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _docsDir = dir.path;
    } catch (_) {
      // Leave null; fix() will no-op in this case.
      _docsDir = null;
    }
  }

  /// Synchronously map an old absolute path to the current container's path
  /// when it points under Documents/upload or Documents/avatars.
  /// If mapping succeeds and the target exists, returns the mapped path;
  /// otherwise returns [path] unchanged.
  static String fix(String path) {
    if (path.isEmpty) return path;

    // Strip file:// scheme if present
    final String raw = path.startsWith('file://') ? path.substring(7) : path;

    // Only attempt to fix known app-internal folders
    // Note: inline base64 images are persisted under Documents/images
    const candidates = ['/Documents/upload/', '/Documents/avatars/', '/Documents/images/'];
    final hasCandidate = candidates.any((c) => raw.contains(c));
    if (!hasCandidate) return raw;

    final docs = _docsDir;
    if (docs == null || docs.isEmpty) return raw;

    final int idx = raw.indexOf('/Documents/');
    if (idx == -1) return raw;

    final String tail = raw.substring(idx + '/Documents'.length); // includes the slash
    final String mapped = '$docs$tail';

    try {
      if (File(mapped).existsSync()) {
        return mapped;
      }
    } catch (_) {}
    return raw;
  }
}
