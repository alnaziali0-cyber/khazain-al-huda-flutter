import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_provider.dart';
import '../devpanel/store.dart';
import 'app_text.dart';

/// A real advertisement slot (G10).
///
/// The slot renders a local image plus a title and a URL taken from the
/// developer panel. When no advertisement has been configured it falls back
/// to a branded gradient card — never to instructional or placeholder copy.
class AdSlot extends ConsumerWidget {
  const AdSlot({
    super.key,
    this.height = 132,
    this.title,
    this.imagePath,
    this.url,
    this.onTap,
  });

  final double height;
  final String? title;
  final String? imagePath;
  final String? url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final assets = ref.watch(devStoreProvider.select((state) => state.assets));

    String? resolvedTitle = title;
    String? resolvedImage = imagePath;
    String? resolvedUrl = url;
    for (final asset in assets) {
      if (asset.id != 'home_ad' && asset.id != 'ad_slot') continue;
      resolvedTitle = asset.meta['title']?.toString() ?? resolvedTitle;
      resolvedImage = asset.meta['uri']?.toString() ?? resolvedImage;
      resolvedUrl = asset.meta['url']?.toString() ?? resolvedUrl;
    }

    final card = Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: Border.all(color: theme.color('hairline')),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[
            theme.color('greenDark'),
            theme.color('tealSurface'),
            theme.color('skyBottom'),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (resolvedImage != null && resolvedImage.isNotEmpty)
            Image.asset(
              resolvedImage,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (resolvedTitle != null && resolvedTitle.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    resolvedTitle,
                    token: 'h2',
                    color: theme.color('textPrimary'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (resolvedUrl != null && resolvedUrl.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    AppText(
                      resolvedUrl,
                      token: 'bodyDim',
                      color: theme.color('gold'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: card,
      ),
    );
  }
}
