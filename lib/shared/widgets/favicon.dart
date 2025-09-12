import 'package:flutter/material.dart';

class Favicon extends StatelessWidget {
  const Favicon({super.key, required this.url, this.size = 20});

  final String url;
  final double size;

  String _faviconUrl(String raw) {
    try {
      final u = Uri.parse(raw);
      final scheme = u.scheme.isNotEmpty ? u.scheme : 'https';
      final host = u.host.isNotEmpty ? u.host : raw;
      return '$scheme://$host/favicon.ico';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ico = _faviconUrl(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        ico,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => Icon(Icons.public, size: size * 0.9, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
