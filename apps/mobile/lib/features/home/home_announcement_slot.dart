import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/theme_provider.dart';

/// The published-announcement carousel of the home screen.
///
/// The ads come from the public content API and are only rendered when the
/// server has published them; each card shows the title and the body without
/// exposing the raw target URL, and opens the campaign in the browser.
class HomeAnnouncementSlot extends ConsumerStatefulWidget {
  const HomeAnnouncementSlot({
    super.key,
    required this.advertisements,
    required this.apiBaseUrl,
  });

  final AsyncValue<List<Map<String, dynamic>>> advertisements;
  final String apiBaseUrl;

  @override
  ConsumerState<HomeAnnouncementSlot> createState() =>
      _HomeAnnouncementSlotState();
}

class _HomeAnnouncementSlotState extends ConsumerState<HomeAnnouncementSlot> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    return widget.advertisements.maybeWhen(
      data: (items) {
        final entries = items.where((item) {
          return announcementText(item['title']).isNotEmpty ||
              announcementText(item['body_markdown']).isNotEmpty ||
              announcementText(item['image_url']).isNotEmpty;
        }).toList(growable: false);
        if (entries.isEmpty) return const SizedBox.shrink();
        final currentPage = _currentPage.clamp(0, entries.length - 1);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 116,
              child: PageView.builder(
                key: const ValueKey('home-announcement-carousel'),
                itemCount: entries.length,
                onPageChanged: (index) {
                  if (mounted) setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: _AnnouncementCard(
                    key: ValueKey('home-announcement-card-$index'),
                    surfaceKey: ValueKey('home-announcement-card-surface-$index'),
                    item: entries[index],
                    apiBaseUrl: widget.apiBaseUrl,
                  ),
                ),
              ),
            ),
            if (entries.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(entries.length, (index) {
                  final selected = index == currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: selected ? 17 : 6,
                    height: 5,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.color('gold')
                          : theme.color('divider'),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _AnnouncementCard extends ConsumerWidget {
  const _AnnouncementCard({
    super.key,
    required this.surfaceKey,
    required this.item,
    required this.apiBaseUrl,
  });

  final Key surfaceKey;
  final Map<String, dynamic> item;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uiTheme = ref.watch(uiThemeProvider);
    final title = announcementText(item['title']);
    final body = announcementText(item['body_markdown']);
    final imageUri =
        announcementImageUri(announcementText(item['image_url']), apiBaseUrl);
    final targetUri = announcementTargetUri(announcementText(item['target_url']));

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            uiTheme.color('greenDark'),
            uiTheme.color('surface1'),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 12),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.88),
                        height: 1.25,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (targetUri != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 17),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: targetUri != null,
      container: true,
      label: title.isEmpty ? 'إعلان' : 'إعلان: $title',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: InkWell(
            key: surfaceKey,
            onTap: targetUri == null
                ? null
                : () => openAnnouncementTarget(context, targetUri),
            child: Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                if (imageUri != null)
                  Image.network(
                    imageUri.toString(),
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                    errorBuilder: (context, error, stackTrace) => fallback,
                  ),
                if (imageUri != null && title.isNotEmpty)
                  PositionedDirectional(
                    start: 10,
                    end: 10,
                    bottom: 8,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.52),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                PositionedDirectional(
                  top: 7,
                  end: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.48),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Text(
                        'إعلان',
                        style: TextStyle(color: Colors.white, fontSize: 9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String announcementText(Object? value) => value is String ? value.trim() : '';

Uri? announcementImageUri(String rawUrl, String apiBaseUrl) {
  if (rawUrl.isEmpty) return null;
  final rawUri = Uri.tryParse(rawUrl);
  final baseUri = Uri.tryParse(apiBaseUrl);
  if (rawUri == null || baseUri == null || !baseUri.hasAuthority) return null;

  final imageUri = rawUri.hasScheme ? rawUri : baseUri.resolveUri(rawUri);
  final isHttp = imageUri.scheme == 'http' || imageUri.scheme == 'https';
  final sameOrigin = imageUri.scheme == baseUri.scheme &&
      imageUri.host == baseUri.host &&
      imageUri.port == baseUri.port;
  if (!isHttp || !imageUri.hasAuthority || !sameOrigin) return null;
  return imageUri;
}

Uri? announcementTargetUri(String rawUrl) {
  if (rawUrl.isEmpty) return null;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<void> openAnnouncementTarget(BuildContext context, Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط الإعلان.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط الإعلان.')),
      );
    }
  }
}
