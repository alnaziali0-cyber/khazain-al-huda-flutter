import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/haptics.dart';
import '../design/theme_provider.dart';
import '../devpanel/open.dart';
import 'app_text.dart';

/// A destination of the persistent five-tab navigation.
@immutable
class BottomNavItem {
  const BottomNavItem({
    required this.label,
    required this.route,
    this.icon,
    this.logoAsset,
  });

  final String label;
  final String route;
  final IconData? icon;
  final String? logoAsset;
}

/// The five primary destinations, ordered right-to-left for Arabic:
/// الرئيسية · القرآن · الأدعية · المكتبة · المزيد.
const List<BottomNavItem> kBottomNavItems = <BottomNavItem>[
  BottomNavItem(
    label: 'الرئيسية',
    route: '/',
    logoAsset: 'assets/branding/khazain_logo.jpg',
  ),
  BottomNavItem(
    label: 'القرآن',
    route: '/quran',
    icon: Icons.menu_book_rounded,
  ),
  BottomNavItem(
    label: 'الأدعية',
    route: '/duas',
    icon: Icons.volunteer_activism_rounded,
  ),
  BottomNavItem(
    label: 'المكتبة',
    route: '/library',
    icon: Icons.local_library_outlined,
  ),
  BottomNavItem(
    label: 'المزيد',
    route: '/sections',
    icon: Icons.grid_view_rounded,
  ),
];

/// Floating, frosted navigation. Long-pressing the brand mark still opens
/// the developer panel; normal taps always navigate to a real app destination.
class KhazainBottomNav extends ConsumerWidget {
  const KhazainBottomNav({
    super.key,
    required this.selectedRoute,
    required this.onSelect,
  });

  final String selectedRoute;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: theme.color('surface1').withOpacity(.92),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: theme.color('textSecondary').withOpacity(.14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.22),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    for (final item in kBottomNavItems)
                      Expanded(
                        child: _NavTab(
                          item: item,
                          selected: item.route == selectedRoute,
                          onTap: () {
                            KhazainHaptics.selection();
                            onSelect(item.route);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends ConsumerWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final active = theme.color('greenActive');
    final inactive = theme.color('textMuted');

    Widget icon;
    if (item.logoAsset != null) {
      icon = DevPanelLauncher(
        onTap: onTap,
        child: Container(
          width: 31,
          height: 31,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? active : theme.color('divider'),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Image.asset(
            item.logoAsset!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: selected ? active : inactive,
            ),
          ),
        ),
      );
    } else {
      icon = Icon(
        item.icon,
        size: 22,
        color: selected ? active : inactive,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: const Cubic(0.2, 0, 0, 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? active.withOpacity(.13)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: AnimatedScale(
                    scale: selected ? 1.06 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: icon,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  item.label,
                  token: 'label',
                  color: selected ? active : inactive,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
