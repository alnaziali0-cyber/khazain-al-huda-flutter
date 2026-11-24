import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'store.dart';
import 'pin.dart';
import 'tabs/audit_tab.dart';
import 'tabs/data_tab.dart';
import 'tabs/fonts_tab.dart';
import 'tabs/icons_tab.dart';
import 'tabs/image_to_ui_tab.dart';
import 'tabs/log_tab.dart';
import 'tabs/sections_tab.dart';
import 'tabs/strings_tab.dart';
import 'tabs/theme_tab.dart';
import 'tabs/tokens_tab.dart';

/// The hidden developer panel.
///
/// Ten tabs: design tokens, sections manager, icon manager, font manager,
/// theme, the image→UI engine, strings, data, audit and the dev log. Every
/// edit goes through the developer store reducer, which keeps a 50-step
/// undo/redo history and rolls a failed transaction back completely.
class DevPanelScreen extends ConsumerStatefulWidget {
  const DevPanelScreen({super.key});

  @override
  ConsumerState<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends ConsumerState<DevPanelScreen>
    with WidgetsBindingObserver {
  final DevLogController _log = DevLogController();

  static const List<String> _tabs = <String>[
    'التوكنات',
    'الأقسام',
    'الأيقونات',
    'الخطوط',
    'المظهر',
    'صورة→واجهة',
    'النصوص',
    'البيانات',
    'التدقيق',
    'السجل',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Auto-lock when the app goes to the background (spec §5).
      DevPinService(
              ProviderScope.containerOf(context, listen: false)
                  .read(sharedPreferencesProvider))
          .lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(devStoreProvider.notifier);
    final canUndo = ref.watch(devStoreProvider.notifier).canUndo;
    final canRedo = ref.watch(devStoreProvider.notifier).canRedo;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF243D39),
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('لوحة المطوّر', style: TextStyle(fontSize: 17)),
          actions: [
            IconButton(
              tooltip: 'تراجع',
              onPressed: canUndo
                  ? () {
                      store.undo();
                      _log.add('تراجع');
                    }
                  : null,
              icon: const Icon(Icons.undo_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'إعادة',
              onPressed: canRedo
                  ? () {
                      store.redo();
                      _log.add('إعادة');
                    }
                  : null,
              icon: const Icon(Icons.redo_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'قفل',
              onPressed: () {
                DevPinService(
                        ProviderScope.containerOf(context, listen: false)
                            .read(sharedPreferencesProvider))
                    .lock();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.lock_outline_rounded, size: 20),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: const Color(0xFFBC9551),
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFBC9551),
            tabs: [
              for (final tab in _tabs) Tab(text: tab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TokensTab(log: _log),
            SectionsTab(log: _log),
            IconsTab(log: _log),
            FontsTab(log: _log),
            const ThemeTab(),
            ImageToUiTab(log: _log),
            StringsTab(log: _log),
            DataTab(log: _log),
            const AuditTab(),
            LogTab(log: _log),
          ],
        ),
      ),
    );
  }
}

/// A tiny in-memory log shown by the Dev Log tab.
class DevLogController extends ChangeNotifier {
  final List<String> _entries = <String>[];

  List<String> get entries => List<String>.unmodifiable(_entries.reversed);

  void add(String message) {
    _entries.add(
      '${DateTime.now().toIso8601String().substring(11, 19)} · $message',
    );
    if (_entries.length > 200) _entries.removeAt(0);
    notifyListeners();
  }
}
