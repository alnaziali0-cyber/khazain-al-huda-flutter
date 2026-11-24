import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_card.dart';
import '../../components/app_text.dart';
import '../../components/state_view.dart';
import '../../design/theme_provider.dart';
import '../../design/tokens/app_tokens.dart';
import '../../devpanel/store.dart';
import 'section_catalogue.dart';

/// The sections screen (S5).
///
/// Every group is a rounded surface holding a responsive grid of branded
/// cards. Every card opens a dedicated app route; no decorative placeholder
/// is mixed into the user's navigation.
class SectionsScreen extends ConsumerStatefulWidget {
  const SectionsScreen({super.key});

  @override
  ConsumerState<SectionsScreen> createState() => _SectionsScreenState();
}

class _SectionsScreenState extends ConsumerState<SectionsScreen> {
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(devStoreProvider.select((state) => state.sections));

    final allSections = _mergeSections(overrides);
    final query = _query.trim().toLowerCase();
    final sections = query.isEmpty
        ? allSections
        : allSections
            .where((section) =>
                section.title.toLowerCase().contains(query) ||
                section.description.toLowerCase().contains(query))
            .toList(growable: false);
    final groups = <String, List<AppSection>>{};
    for (final group in kAppSectionGroups) {
      groups[group] = <AppSection>[];
    }
    for (final section in sections) {
      groups.putIfAbsent(section.group, () => <AppSection>[]).add(section);
    }
    for (final group in groups.keys.toList()) {
      groups[group]!.sort((a, b) => a.order.compareTo(b.order));
    }

    final visibleGroups =
        groups.entries.where((entry) => entry.value.isNotEmpty).toList();

    final theme = ref.watch(uiThemeProvider);

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              sliver: SliverToBoxAdapter(
                child: AppText('المزيد من خزائن الهدى', token: 'display'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن قسم أو خدمة...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح البحث',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
            ),
            if (visibleGroups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: StateView(
                  icon: const Icon(Icons.grid_view_rounded),
                  message: _query.trim().isEmpty
                      ? 'لا توجد أقسام معروضة بعد.'
                      : 'لا توجد نتيجة تطابق بحثك. جرّب كلمة أخرى.',
                  actionLabel: _query.trim().isEmpty ? 'إدارة الأقسام' : 'مسح البحث',
                  onAction: _query.trim().isEmpty
                      ? () => _openDevPanel(context)
                      : () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.builder(
                  itemCount: visibleGroups.length,
                  itemBuilder: (context, index) {
                    final entry = visibleGroups[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _SectionGroup(
                        title: entry.key,
                        sections: entry.value,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static void _openDevPanel(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تُدار الأقسام من لوحة المطوّر: اضغط مطولاً على شعار التطبيق في الشريط السفلي.',
        ),
        duration: Duration(milliseconds: 2600),
      ),
    );
  }

  /// Merges the shipped catalogue with the developer-panel overrides.
  List<AppSection> _mergeSections(List<dynamic> overrides) {
    final overridesById = <String, dynamic>{
      for (final section in overrides) section.id as String: section,
    };
    final result = <AppSection>[];

    // Always start from the complete shipped catalogue. Older installations
    // may have a persisted 18-section developer list; new destinations must
    // not disappear just because they were added in a later app version.
    for (final base in kAppSections) {
      final override = overridesById[base.id];
      if (override != null && override.visible == false) continue;

      final customTitle = override?.title as String?;
      final customIcon = override?.iconId as String?;
      final customGroup = override?.group as String?;
      final customRoute = override?.route as String?;
      final customOrder = override?.order as int?;

      result.add(AppSection(
        id: base.id,
        title: customTitle != null && customTitle.trim().isNotEmpty
            ? customTitle
            : base.title,
        iconId: customIcon != null && customIcon.trim().isNotEmpty
            ? customIcon
            : base.iconId,
        group: customGroup != null && customGroup.trim().isNotEmpty
            ? customGroup
            : base.group,
        route: customRoute != null &&
                customRoute.trim().isNotEmpty &&
                customRoute != '/'
            ? customRoute
            : base.route,
        description: base.description,
        order: customOrder ?? base.order,
      ));
    }

    // Keep developer-created entries too. They remain separate from the
    // shipped catalogue and are never allowed to shadow a built-in id.
    for (final entry in overrides) {
      final id = entry.id as String;
      if (appSectionById(id) != null || entry.visible == false) continue;
      final title = (entry.title as String?)?.trim() ?? '';
      final route = (entry.route as String?)?.trim() ?? '';
      if (title.isEmpty || route.isEmpty || route == '/' || !route.startsWith('/')) continue;
      result.add(AppSection(
        id: id,
        title: title,
        iconId: (entry.iconId as String?) ?? '',
        group: (entry.group as String?)?.trim().isNotEmpty == true
            ? entry.group as String
            : 'أرشيف',
        route: route,
        description: '',
        order: (entry.order as int?) ?? 999,
      ));
    }

    result.sort((a, b) {
      final groupOrderA = kAppSectionGroups.indexOf(a.group);
      final groupOrderB = kAppSectionGroups.indexOf(b.group);
      final byGroup = (groupOrderA < 0 ? kAppSectionGroups.length : groupOrderA)
          .compareTo(groupOrderB < 0 ? kAppSectionGroups.length : groupOrderB);
      if (byGroup != 0) return byGroup;
      return a.order.compareTo(b.order);
    });
    return result;
  }
}

class _SectionGroup extends StatelessWidget {
  const _SectionGroup({
    required this.title,
    required this.sections,
  });

  final String title;
  final List<AppSection> sections;

  @override
  Widget build(BuildContext context) {
    return KzSurface(
      level: 1,
      radiusToken: 'card',
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppText(
              title,
              token: 'h2',
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = KhazainGrid.columnsFor(width + 56);
              const gutter = 12.0;
              final tile = (width - gutter * (columns - 1)) / columns;
              final heightFactor = width < 280
                  ? 1.46
                  : width < 420
                      ? 1.58
                      : width < 600
                          ? 1.35
                          : 1.12;
              return Wrap(
                spacing: gutter,
                runSpacing: gutter,
                children: [
                  for (final section in sections)
                    _SectionTile(section: section, size: tile, heightFactor: heightFactor),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.size, required this.heightFactor});

  final AppSection section;
  final double size;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: section.title,
      child: SizedBox(
        width: size,
        height: size * heightFactor,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push(section.route),
            borderRadius: BorderRadius.circular(KhazainRadius.tile),
            child: KzTile(
              iconId: section.iconId,
              label: section.title,
              description: section.description,
              iconSize: 28,
            ),
          ),
        ),
      ),
    );
  }
}

