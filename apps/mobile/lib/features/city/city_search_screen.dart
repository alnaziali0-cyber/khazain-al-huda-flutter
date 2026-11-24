import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/app_text.dart';
import '../../components/state_view.dart';
import '../../core/city_search.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/theme_provider.dart';

/// The city search screen (S1).
///
/// A dark rounded search field with the magnifier on the right (RTL), then
/// four scopes: the current city, favourites, the last five chosen cities and
/// the most searched ones (G13, G14).
class CitySearchScreen extends ConsumerStatefulWidget {
  const CitySearchScreen({super.key});

  @override
  ConsumerState<CitySearchScreen> createState() => _CitySearchScreenState();
}

class _CitySearchScreenState extends ConsumerState<CitySearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text == _query) return;
      setState(() => _query = _controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(uiThemeProvider);
    final cities = ref.watch(prayerCitiesProvider);
    final governorates = ref.watch(governoratesProvider);
    final selectedCityId = ref.watch(selectedPrayerCityProvider);
    final selectedGovernorateId = ref.watch(selectedGovernorateProvider);
    final store = CityUsageStore(ref.read(sharedPreferencesProvider));

    final recents = store.recents();
    final mostUsed = store.mostUsed();
    final favourites = store.favourites();

    return Container(
      color: theme.color('bgApp'),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: _SearchField(
                controller: _controller,
                onClear: () => _controller.clear(),
              ),
            ),
            Expanded(
              child: cities.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => StateView(
                  icon: const Icon(Icons.cloud_off_rounded),
                  message: 'تعذر تحميل قائمة المدن. تحقّق من الشبكة ثم أعد المحاولة.',
                  actionLabel: 'إعادة المحاولة',
                  onAction: () => ref.invalidate(prayerCitiesProvider),
                ),
                data: (items) {
                  final catalogue = _buildCatalogue(items, governorates.valueOrNull ?? const []);
                  if (_query.trim().isNotEmpty) {
                    final results = _search(catalogue, _query);
                    if (results.isEmpty) {
                      return StateView(
                        icon: const Icon(Icons.search_off_rounded),
                        message: 'لا توجد مدينة مطابقة لـ «${_query.trim()}».',
                      );
                    }
                    return _CityList(
                      cities: results,
                      selectedCityId: selectedCityId,
                      favourites: favourites,
                      onSelect: (city) => _select(city, store),
                      onToggleFavourite: (cityId) {
                        store.toggleFavourite(cityId);
                        setState(() {});
                      },
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    children: [
                      if (selectedCityId != null || selectedGovernorateId != null)
                        _Scope(
                          title: 'المدينة الحالية',
                          children: [
                            for (final city in catalogue)
                              if (city.cityId == selectedCityId ||
                                  city.cityId == selectedGovernorateId)
                                _CityRow(
                                  city: city,
                                  selected: true,
                                  favourite: favourites.contains(city.cityId),
                                  onTap: () => _select(city, store),
                                  onToggleFavourite: () {
                                    store.toggleFavourite(city.cityId);
                                    setState(() {});
                                  },
                                ),
                          ],
                        ),
                      _Scope(
                        title: 'المفضلة',
                        children: [
                          for (final city in catalogue)
                            if (favourites.contains(city.cityId))
                              _CityRow(
                                city: city,
                                favourite: true,
                                onTap: () => _select(city, store),
                                onToggleFavourite: () {
                                  store.toggleFavourite(city.cityId);
                                  setState(() {});
                                },
                              ),
                          if (favourites.isEmpty)
                            const _ScopeEmpty(
                              message: 'اضغط النجمة بجانب أي مدينة لحفظها هنا.',
                            ),
                        ],
                      ),
                      _Scope(
                        title: 'مدن قمت باختيارها مؤخراً',
                        children: [
                          for (final item in recents)
                            _CityRow(
                              city: _fromUsage(item),
                              onTap: () => _select(_fromUsage(item), store),
                            ),
                          if (recents.isEmpty)
                            const _ScopeEmpty(
                              message: 'لم تختر مدينة بعد. ما تختاره هنا يظهر في هذه القائمة.',
                            ),
                        ],
                      ),
                      _Scope(
                        title: 'المدن الأكثر بحثاً',
                        children: [
                          for (final item in mostUsed)
                            _CityRow(
                              city: _fromUsage(item),
                              onTap: () => _select(_fromUsage(item), store),
                            ),
                          if (mostUsed.isEmpty)
                            const _ScopeEmpty(
                              message: 'لا توجد مدن شائعة بعد. ستُرتَّب هنا تلقائياً.',
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_City> _buildCatalogue(
      List<PrayerCityEntry> cities, List<Governorate> governorates) {
    final result = <_City>[];
    for (final city in cities) {
      result.add(_City(
        cityId: city.cityId,
        nameAr: city.cityNameAr,
        governorateAr: city.governorateNameAr,
        latitude: city.latitude,
        longitude: city.longitude,
        verified: city.verified,
      ));
    }
    if (result.isEmpty) {
      for (final governorate in governorates) {
        result.add(_City(
          cityId: governorate.id,
          nameAr: governorate.nameAr,
          governorateAr: governorate.nameAr,
          latitude: governorate.latitude,
          longitude: governorate.longitude,
          verified: false,
        ));
      }
    }
    return result;
  }

  List<_City> _search(List<_City> cities, String query) {
    final needle = normalizeSearchKey(query);
    if (needle.isEmpty) return cities;
    return cities
        .where((city) =>
            normalizeSearchKey(city.nameAr).contains(needle) ||
            normalizeSearchKey(city.governorateAr).contains(needle))
        .take(60)
        .toList(growable: false);
  }

  _City _fromUsage(CityUsage usage) => _City(
        cityId: usage.cityId,
        nameAr: usage.nameAr,
        governorateAr: usage.governorateAr,
        latitude: 0,
        longitude: 0,
        verified: false,
      );

  Future<void> _select(_City city, CityUsageStore store) async {
    store.recordSelection(
      cityId: city.cityId,
      nameAr: city.nameAr,
      governorateAr: city.governorateAr,
    );
    await ref.read(selectedPrayerCityProvider.notifier).select(city.cityId);
    ref.invalidate(prayerTimesProvider);
    if (!mounted) return;
    context.pop();
  }
}

/// A city row model used by the screen.
class _City {
  const _City({
    required this.cityId,
    required this.nameAr,
    required this.governorateAr,
    required this.latitude,
    required this.longitude,
    required this.verified,
  });

  final String cityId;
  final String nameAr;
  final String governorateAr;
  final double latitude;
  final double longitude;
  final bool verified;
}

class _SearchField extends ConsumerWidget {
  const _SearchField({required this.controller, required this.onClear});

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: TextStyle(
        fontSize: 15 * theme.fontScale,
        fontFamily: theme.fontFamily,
        color: theme.color('textPrimary'),
      ),
      decoration: InputDecoration(
        hintText: 'ابحث عن المدينة هنا',
        hintStyle: TextStyle(
          color: theme.color('textMuted'),
          fontSize: 14 * theme.fontScale,
          fontFamily: theme.fontFamily,
        ),
        filled: true,
        fillColor: theme.color('surface3'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.color('green')),
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? Icon(Icons.search_rounded, color: theme.color('textMuted'))
              : IconButton(
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded,
                      color: theme.color('textMuted'), size: 20),
                ),
        ),
      ),
    );
  }
}

class _Scope extends StatelessWidget {
  const _Scope({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: AppText(title, token: 'h2'),
        ),
        ...children,
      ],
    );
  }
}

class _ScopeEmpty extends StatelessWidget {
  const _ScopeEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: AppText(
        message,
        token: 'bodyDim',
        color: theme.colorScheme.onSurface.withOpacity(.6),
      ),
    );
  }
}

class _CityRow extends ConsumerWidget {
  const _CityRow({
    required this.city,
    this.selected = false,
    this.favourite = false,
    required this.onTap,
    this.onToggleFavourite,
  });

  final _City city;
  final bool selected;
  final bool favourite;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavourite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.color('hairline'), width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AppText(
                          city.nameAr,
                          token: 'body',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: theme.color('greenActive')),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    city.governorateAr,
                    token: 'bodyDim',
                    color: theme.color('textMuted'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onToggleFavourite != null)
              IconButton(
                onPressed: onToggleFavourite,
                tooltip: favourite ? 'إزالة من المفضلة' : 'أضف إلى المفضلة',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  favourite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 20,
                  color: favourite ? theme.color('gold') : theme.color('textMuted'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CityList extends StatelessWidget {
  const _CityList({
    required this.cities,
    required this.selectedCityId,
    required this.favourites,
    required this.onSelect,
    required this.onToggleFavourite,
  });

  final List<_City> cities;
  final String? selectedCityId;
  final List<String> favourites;
  final ValueChanged<_City> onSelect;
  final ValueChanged<String> onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: cities.length,
      itemBuilder: (context, index) {
        final city = cities[index];
        return _CityRow(
          city: city,
          selected: city.cityId == selectedCityId,
          favourite: favourites.contains(city.cityId),
          onTap: () => onSelect(city),
          onToggleFavourite: () => onToggleFavourite(city.cityId),
        );
      },
    );
  }
}
