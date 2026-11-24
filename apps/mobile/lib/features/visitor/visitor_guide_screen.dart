import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class VisitorPlace {
  const VisitorPlace({
    required this.id,
    required this.name,
    required this.governorate,
    required this.city,
    required this.type,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.coordinateSource,
    required this.sourceUrl,
    required this.coordinateStatus,
  });

  final String id, name, governorate, city, type, description;
  final double latitude, longitude;
  final String coordinateSource, sourceUrl, coordinateStatus;

  factory VisitorPlace.fromJson(Map<String, dynamic> json) {
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null ||
        latitude < 29 || latitude > 38 || longitude < 38 || longitude > 49) {
      throw const FormatException('إحداثيات موقع الزائر خارج نطاق العراق.');
    }
    return VisitorPlace(
      id: json['id'] as String,
      name: json['name'] as String,
      governorate: json['governorate'] as String,
      city: json['city'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      latitude: latitude,
      longitude: longitude,
      coordinateSource: json['coordinate_source'] as String,
      sourceUrl: json['source_url'] as String,
      coordinateStatus: json['coordinate_status'] as String,
    );
  }

  String get coordinates => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  IconData get icon => type == 'mosque'
      ? Icons.mosque_rounded
      : type == 'shrine'
          ? Icons.account_balance_rounded
          : Icons.place_rounded;
  String get typeLabel => type == 'mosque' ? 'مسجد' : type == 'shrine' ? 'مرقد أو مزار' : 'مكان ديني';
}

class VisitorGuideScreen extends StatefulWidget {
  const VisitorGuideScreen({super.key});
  @override
  State<VisitorGuideScreen> createState() => _VisitorGuideScreenState();
}

class _VisitorGuideScreenState extends State<VisitorGuideScreen> {
  static const _assetPath = 'assets/data/visitor_guide/iraq_places.json';
  final _searchController = TextEditingController();
  List<VisitorPlace> _places = const [];
  String _coverageNote = '', _mapNote = '', _query = '', _governorate = 'الكل', _type = 'الكل';
  String? _selectedId, _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      final decoded = jsonDecode(await rootBundle.loadString(_assetPath)) as Map<String, dynamic>;
      final entries = decoded['items'] as List<dynamic>;
      final places = entries.map((entry) => VisitorPlace.fromJson(Map<String, dynamic>.from(entry as Map))).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _places = places;
        _coverageNote = decoded['coverage_note'] as String? ?? '';
        _mapNote = decoded['map_note'] as String? ?? '';
        _selectedId = places.isEmpty ? null : places.first.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'تعذر تحميل دليل الزائر المحلي: $error';
        _loading = false;
      });
    }
  }

  List<VisitorPlace> get _filteredPlaces {
    final query = _query.trim().toLowerCase();
    return _places.where((place) {
      final governorateMatch = _governorate == 'الكل' || place.governorate == _governorate;
      final typeMatch = _type == 'الكل' || place.type == _type;
      final searchable = '${place.name} ${place.city} ${place.governorate}'.toLowerCase();
      return governorateMatch && typeMatch && (query.isEmpty || searchable.contains(query));
    }).toList(growable: false);
  }

  VisitorPlace? get _selectedPlace {
    for (final place in _filteredPlaces) {
      if (place.id == _selectedId) return place;
    }
    return _filteredPlaces.isEmpty ? null : _filteredPlaces.first;
  }

  void _selectPlace(VisitorPlace place) => setState(() => _selectedId = place.id);

  Future<void> _copyCoordinates(VisitorPlace place) async {
    await Clipboard.setData(ClipboardData(text: place.coordinates));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الإحداثيات.')));
  }

  Future<void> _openSource(VisitorPlace place) async {
    final uri = Uri.tryParse(place.sourceUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط المصدر غير صالح أو غير آمن.')),
        );
      }
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح صفحة مصدر الإحداثيات.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح صفحة مصدر الإحداثيات.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.map_outlined, size: 42),
          const SizedBox(height: 12),
          Text(_loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () { setState(() { _loading = true; _loadError = null; }); _loadPlaces(); }, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة')),
        ]),
      ));
    }

    final filtered = _filteredPlaces;
    final selected = _selectedPlace;
    final governorates = <String>{'الكل', ..._places.map((p) => p.governorate)}.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        Text('دليل الزائر في العراق', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text('المراقد والجوامع والمواقع الدينية على خريطة محلية لا تحتاج إلى اتصال.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SummaryPill(icon: Icons.place_rounded, label: '${_places.length} مواقع مسجلة'),
          const _SummaryPill(icon: Icons.offline_pin_rounded, label: 'تعمل دون إنترنت'),
        ]),
        const SizedBox(height: 14),
        Container(
          height: 286,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(.55),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor.withOpacity(.7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Expanded(child: _OfflineIraqMap(places: filtered, selectedId: selected?.id, onSelect: _selectPlace)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              color: theme.colorScheme.surface.withOpacity(.9),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 7),
                Expanded(child: Text('خريطة جغرافية مبسطة • ${filtered.length} مواقع ظاهرة', style: theme.textTheme.labelSmall)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(_mapNote, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'ابحث عن مرقد أو جامع أو محافظة',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty ? null : IconButton(tooltip: 'مسح البحث', onPressed: () { _searchController.clear(); setState(() => _query = ''); }, icon: const Icon(Icons.close_rounded)),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _governorate,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المحافظة', prefixIcon: Icon(Icons.location_city_rounded)),
          items: governorates.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
          onChanged: (value) => setState(() { _governorate = value ?? 'الكل'; _selectedId = null; }),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'الكل', label: Text('الكل')), ButtonSegment(value: 'shrine', label: Text('المراقد')), ButtonSegment(value: 'mosque', label: Text('الجوامع'))],
          selected: {_type}, showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() { _type = values.first; _selectedId = null; }),
        ),
        const SizedBox(height: 14),
        if (selected != null) ...[
          _SelectedPlaceCard(place: selected, onCopy: () => _copyCoordinates(selected), onSource: () => _openSource(selected)),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Text('المواقع المسجلة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('${filtered.length} نتيجة', style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('لا توجد مواقع تطابق البحث الحالي.', textAlign: TextAlign.center))
        else
          for (final place in filtered)
            _PlaceListTile(place: place, selected: place.id == selected?.id, onTap: () => _selectPlace(place)),
        const SizedBox(height: 14),
        ExpansionTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('نطاق التغطية ومصادر البيانات'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(_coverageNote, style: theme.textTheme.bodySmall?.copyWith(height: 1.6)),
            const SizedBox(height: 8),
            const Text('توجد قائمة مزارات مقسمة حسب المحافظات في تطبيق «مزاراتنا» التابع للأمانة العامة للمزارات الشيعية. لم تُنسخ قاعدة التطبيق أو صوره هنا؛ يلزم مصدر بيانات قابل للتصدير وإذن استخدام قبل الاستيراد الجماعي.', style: TextStyle(fontSize: 12, height: 1.6)),
          ],
        ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: theme.colorScheme.primary.withOpacity(.09), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: theme.colorScheme.primary), const SizedBox(width: 6), Text(label, style: theme.textTheme.labelSmall)]),
    );
  }
}

class _SelectedPlaceCard extends StatelessWidget {
  const _SelectedPlaceCard({required this.place, required this.onCopy, required this.onSource});
  final VisitorPlace place;
  final VoidCallback onCopy, onSource;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(margin: EdgeInsets.zero, child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: theme.colorScheme.primary.withOpacity(.1), child: Icon(place.icon, color: theme.colorScheme.primary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(place.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${place.city} • ${place.governorate} • ${place.typeLabel}', style: theme.textTheme.bodySmall),
          ])),
        ]),
        const SizedBox(height: 10),
        Text(place.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        const SizedBox(height: 9),
        SelectableText('الإحداثيات: ${place.coordinates}', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(place.coordinateStatus, style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(onPressed: onCopy, icon: const Icon(Icons.copy_rounded, size: 17), label: const Text('نسخ الإحداثيات')),
          TextButton.icon(onPressed: onSource, icon: const Icon(Icons.open_in_new_rounded, size: 17), label: const Text('مصدر الموقع')),
        ]),
        Text('مصدر الإحداثيات: ${place.coordinateSource}', style: theme.textTheme.labelSmall?.copyWith(height: 1.4)),
      ]),
    ));
  }
}

class _PlaceListTile extends StatelessWidget {
  const _PlaceListTile({required this.place, required this.selected, required this.onTap});
  final VisitorPlace place;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(padding: const EdgeInsets.only(bottom: 7), child: Material(
      color: selected ? theme.colorScheme.primary.withOpacity(.09) : theme.colorScheme.surface.withOpacity(.88),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(place.icon, color: theme.colorScheme.primary),
        title: Text(place.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${place.city} • ${place.governorate}'),
        trailing: Icon(selected ? Icons.radio_button_checked : Icons.chevron_left_rounded, color: theme.colorScheme.primary),
      ),
    ));
  }
}

class _OfflineIraqMap extends StatelessWidget {
  const _OfflineIraqMap({required this.places, required this.selectedId, required this.onSelect});
  final List<VisitorPlace> places;
  final String? selectedId;
  final ValueChanged<VisitorPlace> onSelect;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          VisitorPlace? closest;
          var closestDistance = 28.0;
          for (final place in places) {
            final point = _IraqMapPainter.project(size, place.latitude, place.longitude);
            final distance = (point - details.localPosition).distance;
            if (distance < closestDistance) { closest = place; closestDistance = distance; }
          }
          if (closest != null) onSelect(closest);
        },
        child: CustomPaint(size: size, painter: _IraqMapPainter(places: places, selectedId: selectedId, colorScheme: Theme.of(context).colorScheme)),
      );
    });
  }
}

class _IraqMapPainter extends CustomPainter {
  _IraqMapPainter({required this.places, required this.selectedId, required this.colorScheme});
  final List<VisitorPlace> places;
  final String? selectedId;
  final ColorScheme colorScheme;
  static const double _minLat = 29.0, _maxLat = 37.5, _minLon = 38.7, _maxLon = 48.5;
  // Approximate outline used only for the offline locator graphic, not for borders or navigation.
  static const List<Offset> _outline = [
    Offset(38.80, 32.00), Offset(39.20, 31.50), Offset(40.10, 31.20), Offset(41.20, 31.10),
    Offset(42.20, 31.20), Offset(42.60, 30.75), Offset(43.20, 30.30), Offset(44.30, 29.10),
    Offset(46.25, 29.10), Offset(47.50, 29.95), Offset(48.45, 30.75), Offset(48.45, 31.80),
    Offset(47.90, 32.50), Offset(47.20, 33.40), Offset(46.55, 34.10), Offset(46.45, 35.00),
    Offset(45.50, 36.20), Offset(44.70, 37.20), Offset(43.30, 37.30), Offset(42.25, 37.15),
    Offset(41.45, 36.75), Offset(40.55, 36.85), Offset(39.35, 36.65), Offset(38.85, 35.50),
    Offset(39.10, 34.40), Offset(38.75, 33.35),
  ];

  static Offset project(Size size, double latitude, double longitude) {
    const padding = 24.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    final x = padding + ((longitude - _minLon) / (_maxLon - _minLon)) * width;
    final y = size.height - padding - ((latitude - _minLat) / (_maxLat - _minLat)) * height;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colorScheme.surfaceContainerHighest.withOpacity(.14));
    final grid = Paint()..color = colorScheme.outline.withOpacity(.12)..strokeWidth = 1;
    for (var i = 1; i < 5; i++) { final x = size.width * i / 5; canvas.drawLine(Offset(x, 12), Offset(x, size.height - 12), grid); }
    for (var i = 1; i < 4; i++) { final y = size.height * i / 4; canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), grid); }

    final polygon = Path();
    for (var i = 0; i < _outline.length; i++) {
      final coordinate = _outline[i];
      final point = project(size, coordinate.dy, coordinate.dx);
      if (i == 0) { polygon.moveTo(point.dx, point.dy); } else { polygon.lineTo(point.dx, point.dy); }
    }
    polygon.close();
    canvas.drawShadow(polygon, Colors.black.withOpacity(.12), 5, false);
    canvas.drawPath(polygon, Paint()..style = PaintingStyle.fill..color = colorScheme.primary.withOpacity(.11));
    canvas.drawPath(polygon, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = colorScheme.primary.withOpacity(.46));

    _drawLabel(canvas, size, 'العراق', Offset(size.width * .48, size.height * .48), colorScheme.onSurface.withOpacity(.38), 19, FontWeight.w900);
    _drawLabel(canvas, size, 'بغداد', project(size, 33.34, 44.40), colorScheme.onSurface.withOpacity(.62), 10, FontWeight.w700);
    _drawLabel(canvas, size, 'النجف', project(size, 31.99, 44.31), colorScheme.onSurface.withOpacity(.62), 10, FontWeight.w700);
    _drawLabel(canvas, size, 'كربلاء', project(size, 32.62, 44.03), colorScheme.onSurface.withOpacity(.62), 10, FontWeight.w700);
    _drawLabel(canvas, size, 'سامراء', project(size, 34.20, 43.87), colorScheme.onSurface.withOpacity(.62), 10, FontWeight.w700);

    for (var index = 0; index < places.length; index++) {
      final place = places[index];
      final point = project(size, place.latitude, place.longitude);
      final selected = place.id == selectedId;
      final color = selected ? colorScheme.tertiary : colorScheme.primary;
      canvas.drawCircle(point, selected ? 13 : 10, Paint()..color = color.withOpacity(.18));
      canvas.drawCircle(point, selected ? 7.5 : 6, Paint()..color = color);
      canvas.drawCircle(point, selected ? 7.5 : 6, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.6..color = colorScheme.surface);
      _drawLabel(canvas, size, '${index + 1}', point.translate(0, -19), colorScheme.onSurface, 9, FontWeight.w900);
    }
  }

  void _drawLabel(Canvas canvas, Size size, String text, Offset center, Color color, double fontSize, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight, shadows: const [Shadow(color: Color(0x66FFFFFF), blurRadius: 3)])),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: size.width * .42);
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _IraqMapPainter oldDelegate) => oldDelegate.places != places || oldDelegate.selectedId != selectedId || oldDelegate.colorScheme != colorScheme;
}
