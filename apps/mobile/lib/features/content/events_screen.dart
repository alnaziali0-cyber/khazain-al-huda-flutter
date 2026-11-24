import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late final Future<List<_HijriOccasion>> _events = _loadEvents();
  final _searchController = TextEditingController();
  String _filter = 'all';

  Future<List<_HijriOccasion>> _loadEvents() async {
    final source = await rootBundle
        .loadString('assets/data/shia_occasions_hijri.json');
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Invalid local Hijri occasions dataset.');
    }
    final items = decoded
        .whereType<Map>()
        .map((item) => _HijriOccasion.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    items.sort((a, b) {
      final month = a.month.compareTo(b.month);
      return month != 0 ? month : a.day.compareTo(b.day);
    });
    return items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text('المناسبات الهجرية',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                  'فهرس محلي للمناسبات مرتّب حسب الشهر واليوم الهجري.'),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'ابحث عن مناسبة أو شهر',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'مسح البحث',
                    onPressed: () => setState(_searchController.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('الكل')),
                  ButtonSegment(value: 'Shia', label: Text('شيعية')),
                  ButtonSegment(value: 'General', label: Text('عامة')),
                ],
                selected: {_filter},
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.first),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<_HijriOccasion>>(
                future: _events,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _MessageCard(
                        message: 'تعذر قراءة ملف المناسبات المحلي.');
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final term = _searchController.text.trim();
                  final filtered = snapshot.data!.where((event) {
                    final typeMatches = _filter == 'all' || event.sect == _filter;
                    final text =
                        '${event.name} ${event.monthName} ${event.kind}';
                    final searchMatches = term.isEmpty || text.contains(term);
                    return typeMatches && searchMatches;
                  }).toList(growable: false);
                  if (filtered.isEmpty) {
                    return const _MessageCard(
                        message: 'لا توجد نتائج تطابق البحث.');
                  }
                  return Column(
                    children: filtered.map((event) {
                      final isShia = event.sect == 'Shia';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          leading: Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${event.day}',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900)),
                                Text(event.monthName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ),
                          title: Text(event.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, height: 1.4)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: [
                                _MetaChip(label: event.kind),
                                _MetaChip(label: isShia ? 'شيعية' : 'عامة'),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: 12),
              const _MessageCard(
                message:
                    'التاريخ هجري جدولي من بيانات الحزمة. قد يختلف ثبوت بداية الشهر والمناسبة بحسب الرؤية والجهة الشرعية؛ لا يُعد هذا الفهرس إعلاناً رسمياً أو توقيتاً ميلادياً مؤكداً.',
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HijriOccasion {
  const _HijriOccasion({
    required this.month,
    required this.day,
    required this.monthName,
    required this.name,
    required this.sect,
    required this.kind,
  });

  final int month;
  final int day;
  final String monthName;
  final String name;
  final String sect;
  final String kind;

  factory _HijriOccasion.fromJson(Map<String, dynamic> json) => _HijriOccasion(
        month: (json['hijri_month'] as num).toInt(),
        day: (json['hijri_day'] as num).toInt(),
        monthName: json['month_name_ar'] as String? ?? '',
        name: json['event_ar'] as String? ?? '',
        sect: json['sect'] as String? ?? 'General',
        kind: json['kind'] as String? ?? 'مناسبة',
      );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded),
              const SizedBox(width: 9),
              Expanded(child: Text(message, style: const TextStyle(height: 1.6))),
            ],
          ),
        ),
      );
}
