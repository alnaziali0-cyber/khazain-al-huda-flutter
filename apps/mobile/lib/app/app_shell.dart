import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../components/bottom_nav.dart';

/// The application shell: five primary destinations plus the hidden
/// developer-panel gesture on the brand mark.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex() {
    for (var index = 0; index < kBottomNavItems.length; index++) {
      final destination = kBottomNavItems[index].route;
      if (destination == '/') {
        if (widget.location == '/') return index;
      } else if (widget.location == destination ||
          widget.location.startsWith('$destination/')) {
        return index;
      }
    }
    final sectionsIndex =
        kBottomNavItems.indexWhere((item) => item.route == '/sections');
    return sectionsIndex < 0 ? 0 : sectionsIndex;
  }

  bool get _isReader => RegExp(r'^/quran/\d+$').hasMatch(widget.location) ||
      RegExp(r'^/visits/volume_[0-9]+$').hasMatch(widget.location) ||
      RegExp(r'^/duas/\d+$').hasMatch(widget.location) ||
      RegExp(r'^/visits/treasures/\d+$').hasMatch(widget.location) ||
      RegExp(r'^/library/imported/\d+$').hasMatch(widget.location);

  bool get _isAssistant => widget.location == '/assistant';

  String get _fallbackLocation {
    if (widget.location.startsWith('/quran/')) return '/quran';
    if (widget.location.startsWith('/visits/')) return '/visits';
    if (widget.location.startsWith('/duas/')) return '/duas';
    if (widget.location.startsWith('/book/') ||
        widget.location.startsWith('/library/imported/')) {
      return '/library';
    }
    if (widget.location == '/assistant') return '/sections';
    if (widget.location.startsWith('/visitor-guide')) return '/sections';
    if (widget.location.startsWith('/hadith/local')) return '/hadith';
    return '/';
  }

  void _handleBack(BuildContext context) {
    if (widget.location != '/') {
      context.go(_fallbackLocation);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('أنت في الصفحة الرئيسية.'),
          duration: Duration(milliseconds: 1100),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex();
    final canPop = GoRouter.of(context).canPop();
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(top: false, child: widget.child),
        bottomNavigationBar: _isReader || _isAssistant
            ? null
            : KhazainBottomNav(
                selectedRoute: kBottomNavItems[selected].route,
                onSelect: (route) {
                  if (widget.location != route) context.go(route);
                },
              ),
      ),
    );
  }
}
