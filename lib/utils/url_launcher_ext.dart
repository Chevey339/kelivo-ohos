import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

extension BuildContextUrlLauncher on BuildContext {
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

