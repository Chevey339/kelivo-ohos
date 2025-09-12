import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';

class SponsorPage extends StatefulWidget {
  const SponsorPage({super.key});

  @override
  State<SponsorPage> createState() => _SponsorPageState();
}

class _SponsorPageState extends State<SponsorPage> {
  late Future<_SponsorData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchSponsors();
  }

  Future<_SponsorData> _fetchSponsors() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('https://kelivo.psycheas.top/sponsor.json?kelivo=$ts');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final updatedAt = (obj['updatedAt'] as String?) ?? '';
        final list = (obj['sponsors'] as List?) ?? const [];
        final sponsors = <_Sponsor>[];
        for (final e in list) {
          if (e is Map<String, dynamic>) {
            final name = (e['name'] as String?)?.trim() ?? '';
            final avatar = (e['avatar'] as String?)?.trim() ?? '';
            final since = (e['since'] as String?)?.trim() ?? '';
            if (name.isEmpty || avatar.isEmpty) continue;
            sponsors.add(_Sponsor(name: name, avatar: avatar, since: since));
          }
        }
        return _SponsorData(updatedAt: updatedAt, sponsors: sponsors);
      }
    } catch (_) {}
    return const _SponsorData(updatedAt: '', sponsors: <_Sponsor>[]);
  }

  Widget _sectionHeader(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary),
      ),
    );
  }

  Widget _sponsorMethodCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 76,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 22, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.settingsPageSponsor),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _sectionHeader(context, l10n.sponsorPageMethodsSectionTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _sponsorMethodCard(
                  context: context,
                  icon: Lucide.Heart,
                  title: l10n.sponsorPageAfdianTitle,
                  subtitle: l10n.sponsorPageAfdianSubtitle,
                  // onTap: () => _openUrl('https://afdian.com/a/kelivo'),
                  onTap: () async {
                    final uri = Uri.parse('https://afdian.com/a/kelivo');
                    if (!await launchUrl(
                        uri, mode: LaunchMode.externalApplication)) {
                      await launchUrl(
                          uri, mode: LaunchMode.platformDefault);
                    }
                  },
                ),
                const SizedBox(width: 10),
                _sponsorMethodCard(
                  context: context,
                  icon: Lucide.Link,
                  title: l10n.sponsorPageWeChatTitle,
                  subtitle: l10n.sponsorPageWeChatSubtitle,
                  onTap: () async {
                    final uri = Uri.parse('https://c.img.dasctf.com/LightPicture/2024/12/6c2a6df245ed97b3.jpg');
                    if (!await launchUrl(
                        uri, mode: LaunchMode.externalApplication)) {
                      await launchUrl(
                          uri, mode: LaunchMode.platformDefault);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          _sectionHeader(context, l10n.sponsorPageSponsorsSectionTitle),
          FutureBuilder<_SponsorData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
                    ),
                  ),
                );
              }
              final data = snapshot.data ?? const _SponsorData(updatedAt: '', sponsors: <_Sponsor>[]);
              final sponsors = data.sponsors;
              if (sponsors.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(l10n.sponsorPageEmpty, style: TextStyle(color: cs.onSurface.withOpacity(0.6))),
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  // Aim ~5-6 avatars per row
                  int cross = (w >= 480) ? 6 : 5;
                  final itemSize = (w - 24 - (cross - 1) * 10) / cross; // 12 padding each side, 10 spacing
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: itemSize / (52 + 28), // avatar 52 + space for name
                      ),
                      itemCount: sponsors.length,
                      itemBuilder: (context, i) {
                        final s = sponsors[i];
                        return _SponsorTile(s: s);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Sponsor {
  final String name;
  final String avatar;
  final String since;
  const _Sponsor({required this.name, required this.avatar, required this.since});
}

class _SponsorData {
  final String updatedAt;
  final List<_Sponsor> sponsors;
  const _SponsorData({required this.updatedAt, required this.sponsors});
}

class _SponsorTile extends StatelessWidget {
  const _SponsorTile({required this.s});
  final _Sponsor s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
          ),
          child: ClipOval(
            child: Image.network(
              s.avatar,
              fit: BoxFit.cover,
              width: 52,
              height: 52,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surface,
                alignment: Alignment.center,
                child: Icon(Icons.person, color: cs.onSurface.withOpacity(0.5)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 18,
          child: Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
