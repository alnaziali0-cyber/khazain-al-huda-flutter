import 'dart:convert';

import '../features/sections/section_catalogue.dart';

/// Section descriptor managed by the developer panel.
///
/// Mirrors `{id,title,iconId,color?,group,order,visible,locked,route}`.
class DevSection {
  const DevSection({
    required this.id,
    required this.title,
    required this.iconId,
    required this.group,
    required this.order,
    required this.route,
    this.color,
    this.visible = true,
    this.locked = false,
  });

  final String id;
  final String title;
  final String iconId;
  final String? color;
  final String group;
  final int order;
  final bool visible;
  final bool locked;
  final String route;

  DevSection copyWith({
    String? title,
    String? iconId,
    String? color,
    String? group,
    int? order,
    bool? visible,
    bool? locked,
    String? route,
  }) =>
      DevSection(
        id: id,
        title: title ?? this.title,
        iconId: iconId ?? this.iconId,
        color: color ?? this.color,
        group: group ?? this.group,
        order: order ?? this.order,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        route: route ?? this.route,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'iconId': iconId,
        'color': color,
        'group': group,
        'order': order,
        'visible': visible,
        'locked': locked,
        'route': route,
      };

  factory DevSection.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) {
      throw const FormatException('A section requires a stable id.');
    }
    return DevSection(
        id: id,
        title: json['title'] as String? ?? '',
        iconId: json['iconId'] as String? ?? '',
        color: json['color'] as String?,
        group: json['group'] as String? ?? 'أخرى',
        order: (json['order'] as num?)?.toInt() ?? 0,
        visible: json['visible'] as bool? ?? true,
        locked: json['locked'] as bool? ?? false,
        route: json['route'] as String? ?? '/',
      );
  }

  @override
  bool operator ==(Object other) =>
      other is DevSection &&
      other.id == id &&
      other.title == title &&
      other.iconId == iconId &&
      other.color == color &&
      other.group == group &&
      other.order == order &&
      other.visible == visible &&
      other.locked == locked &&
      other.route == route;

  @override
  int get hashCode =>
      Object.hash(id, title, iconId, color, group, order, visible, locked, route);
}

/// Icon definition: SVG paths on a 24px canvas with a two-tone palette.
class IconDef {
  const IconDef({
    required this.id,
    required this.paths,
    required this.size,
    required this.stroke,
    required this.primary,
    this.secondary,
    this.secondaryPathCount = 1,
  });

  final String id;
  final List<String> paths;
  final double size;
  final double stroke;
  final String primary;
  final String? secondary;

  /// How many trailing paths in [paths] are painted with [secondary].
  final int secondaryPathCount;

  List<String> get primaryPaths => secondaryPathCount <= 0 ||
          secondary == null
      ? paths
      : paths.sublist(0, paths.length - secondaryPathCount);

  List<String> get accentPaths => secondaryPathCount <= 0 ||
          secondary == null
      ? const <String>[]
      : paths.sublist(paths.length - secondaryPathCount);

  IconDef copyWith({
    List<String>? paths,
    double? size,
    double? stroke,
    String? primary,
    String? secondary,
    int? secondaryPathCount,
  }) =>
      IconDef(
        id: id,
        paths: paths ?? this.paths,
        size: size ?? this.size,
        stroke: stroke ?? this.stroke,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        secondaryPathCount: secondaryPathCount ?? this.secondaryPathCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'paths': paths,
        'size': size,
        'stroke': stroke,
        'primary': primary,
        'secondary': secondary,
        'secondaryPathCount': secondaryPathCount,
      };

  factory IconDef.fromJson(Map<String, dynamic> json) => IconDef(
        id: json['id'] as String? ?? '',
        paths: (json['paths'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[],
        size: (json['size'] as num?)?.toDouble() ?? 24,
        stroke: (json['stroke'] as num?)?.toDouble() ?? 2,
        primary: json['primary'] as String? ?? '#174940',
        secondary: json['secondary'] as String?,
        secondaryPathCount: (json['secondaryPathCount'] as num?)?.toInt() ?? 1,
      );

  @override
  bool operator ==(Object other) =>
      other is IconDef &&
      other.id == id &&
      other.stroke == stroke &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.size == size &&
      other.secondaryPathCount == secondaryPathCount &&
      _samePaths(other.paths, paths);

  static bool _samePaths(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, size, stroke, primary, secondary,
      secondaryPathCount, Object.hashAll(paths));
}

/// A locally registered asset (image / audio / font / svg).
class DevAsset {
  const DevAsset({
    required this.id,
    required this.uri,
    required this.kind,
    this.meta = const <String, dynamic>{},
  });

  final String id;
  final String uri;
  final String kind;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'uri': uri,
        'kind': kind,
        'meta': meta,
      };

  factory DevAsset.fromJson(Map<String, dynamic> json) => DevAsset(
        id: json['id'] as String? ?? '',
        uri: json['uri'] as String? ?? '',
        kind: json['kind'] as String? ?? 'image',
        meta: (json['meta'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );

  @override
  bool operator ==(Object other) =>
      other is DevAsset &&
      other.id == id &&
      other.uri == uri &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, uri, kind);
}

/// A node of a relative layout tree.
class LayoutNode {
  const LayoutNode({
    required this.type,
    this.weight,
    this.flex,
    this.style = const <String, dynamic>{},
    this.children = const <LayoutNode>[],
  });

  final String type;
  final num? weight;
  final num? flex;
  final Map<String, dynamic> style;
  final List<LayoutNode> children;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'weight': weight,
        'flex': flex,
        'style': style,
        'children': children.map((child) => child.toJson()).toList(),
      };

  factory LayoutNode.fromJson(Map<String, dynamic> json) => LayoutNode(
        type: json['type'] as String? ?? 'column',
        weight: json['weight'] as num?,
        flex: json['flex'] as num?,
        style: (json['style'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        children: ((json['children'] as List?) ?? const [])
            .whereType<Map>()
            .map((child) => LayoutNode.fromJson(child.cast<String, dynamic>()))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is LayoutNode &&
      other.type == type &&
      other.weight == weight &&
      other.flex == flex &&
      other.style.length == style.length &&
      other.children.length == children.length;

  @override
  int get hashCode =>
      Object.hash(type, weight, flex, Object.hashAll(style.keys));
}

/// The complete developer state persisted under `khzain.dev.v1`.
class DevState {
  const DevState({
    this.theme,
    this.sections = const <DevSection>[],
    this.icons = const <IconDef>[],
    this.strings = const <String, String>{},
    this.assets = const <DevAsset>[],
    this.layout = const <String, LayoutNode>{},
    this.colorOverrides = const <String, Map<String, String>>{},
    this.typeOverrides = const <String, Map<String, dynamic>>{},
    this.radiusOverrides = const <String, double>{},
    this.spacingOverrides = const <String, double>{},
    this.gridOverrides = const <String, double>{},
    this.direction = 'rtl',
  });

  final Map<String, dynamic>? theme;
  final List<DevSection> sections;
  final List<IconDef> icons;
  final Map<String, String> strings;
  final List<DevAsset> assets;
  final Map<String, LayoutNode> layout;
  final Map<String, Map<String, String>> colorOverrides;
  final Map<String, Map<String, dynamic>> typeOverrides;
  final Map<String, double> radiusOverrides;
  final Map<String, double> spacingOverrides;
  final Map<String, double> gridOverrides;

  /// `rtl` (default) or `ltr` — the RTL/LTR debug switch of the panel.
  final String direction;

  DevState copyWith({
    Map<String, dynamic>? theme,
    List<DevSection>? sections,
    List<IconDef>? icons,
    Map<String, String>? strings,
    List<DevAsset>? assets,
    Map<String, LayoutNode>? layout,
    Map<String, Map<String, String>>? colorOverrides,
    Map<String, Map<String, dynamic>>? typeOverrides,
    Map<String, double>? radiusOverrides,
    Map<String, double>? spacingOverrides,
    Map<String, double>? gridOverrides,
    String? direction,
  }) =>
      DevState(
        theme: theme ?? this.theme,
        sections: sections ?? this.sections,
        icons: icons ?? this.icons,
        strings: strings ?? this.strings,
        assets: assets ?? this.assets,
        layout: layout ?? this.layout,
        colorOverrides: colorOverrides ?? this.colorOverrides,
        typeOverrides: typeOverrides ?? this.typeOverrides,
        radiusOverrides: radiusOverrides ?? this.radiusOverrides,
        spacingOverrides: spacingOverrides ?? this.spacingOverrides,
        gridOverrides: gridOverrides ?? this.gridOverrides,
        direction: direction ?? this.direction,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'theme': theme,
        'sections': sections.map((section) => section.toJson()).toList(),
        'icons': icons.map((icon) => icon.toJson()).toList(),
        'strings': strings,
        'assets': assets.map((asset) => asset.toJson()).toList(),
        'layout': layout.map((key, value) => MapEntry(key, value.toJson())),
        'colorOverrides': colorOverrides,
        'typeOverrides': typeOverrides,
        'radiusOverrides': radiusOverrides,
        'spacingOverrides': spacingOverrides,
        'gridOverrides': gridOverrides,
        'direction': direction,
      };

  factory DevState.fromJson(Map<String, dynamic> json) {
    List<DevSection> sections() {
      final stored = ((json['sections'] as List?) ?? const [])
          .whereType<Map>()
          .map((entry) => DevSection.fromJson(entry.cast<String, dynamic>()))
          .toList();
      if (stored.isEmpty) return stored;

      // Version-1 stores can predate newer built-in sections. Add only the
      // missing catalogue entries while preserving existing user edits,
      // visibility choices, ordering and custom sections.
      final byId = <String, DevSection>{
        for (final section in stored) section.id: section,
      };
      for (final section in kAppSections) {
        byId.putIfAbsent(
          section.id,
          () => DevSection(
            id: section.id,
            title: section.title,
            iconId: section.iconId,
            group: section.group,
            order: section.order,
            route: section.route,
          ),
        );
      }
      return byId.values.toList(growable: false);
    }
    List<IconDef> icons() => ((json['icons'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => IconDef.fromJson(e.cast<String, dynamic>()))
        .toList();
    List<DevAsset> assets() => ((json['assets'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => DevAsset.fromJson(e.cast<String, dynamic>()))
        .toList();
    Map<String, LayoutNode> layout() =>
        ((json['layout'] as Map?) ?? const <String, dynamic>{}).entries.fold(
            <String, LayoutNode>{}, (map, entry) {
      map[entry.key] = LayoutNode.fromJson(
          (entry.value as Map).cast<String, dynamic>());
      return map;
    });
    Map<String, Map<String, String>> colors() =>
        ((json['colorOverrides'] as Map?) ?? const <String, dynamic>{})
            .entries
            .fold(<String, Map<String, String>>{}, (map, entry) {
      map[entry.key] = (entry.value as Map).map(
          (key, value) => MapEntry(key, value.toString()));
      return map;
    });
    Map<String, Map<String, dynamic>> types() =>
        ((json['typeOverrides'] as Map?) ?? const <String, dynamic>{})
            .entries
            .fold(<String, Map<String, dynamic>>{}, (map, entry) {
      map[entry.key] = (entry.value as Map).cast<String, dynamic>();
      return map;
    });

    return DevState(
      theme: (json['theme'] as Map?)?.cast<String, dynamic>(),
      sections: sections(),
      icons: icons(),
      strings: (json['strings'] as Map?)?.map(
              (key, value) => MapEntry(key, value.toString())) ??
          const <String, String>{},
      assets: assets(),
      layout: layout(),
      colorOverrides: colors(),
      typeOverrides: types(),
      radiusOverrides: ((json['radiusOverrides'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key, (value as num).toDouble())),
      spacingOverrides: ((json['spacingOverrides'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key, (value as num).toDouble())),
      gridOverrides: ((json['gridOverrides'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key, (value as num).toDouble())),
      direction: json['direction'] as String? ?? 'rtl',
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// A single UI patch operation.
///
/// `version:1` · optional tokens / sections / layout / icons / strings / assets.
class UIPatch {
  const UIPatch({
    this.version = 1,
    this.tokens,
    this.sections,
    this.layout,
    this.icons,
    this.strings,
    this.assets,
  });

  final int version;
  final Map<String, dynamic>? tokens;
  final List<Map<String, dynamic>>? sections;
  final List<Map<String, dynamic>>? layout;
  final List<Map<String, dynamic>>? icons;
  final Map<String, String>? strings;
  final List<Map<String, dynamic>>? assets;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'tokens': tokens,
        'sections': sections,
        'layout': layout,
        'icons': icons,
        'strings': strings,
        'assets': assets,
      };

  factory UIPatch.fromJson(Map<String, dynamic> json) => UIPatch(
        version: (json['version'] as num?)?.toInt() ?? 1,
        tokens: (json['tokens'] as Map?)?.cast<String, dynamic>(),
        sections: ((json['sections'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        layout: ((json['layout'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        icons: ((json['icons'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        strings: (json['strings'] as Map?)
            ?.map((key, value) => MapEntry(key, value.toString())),
        assets: ((json['assets'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
      );

  static UIPatch decode(String source) =>
      UIPatch.fromJson((jsonDecode(source) as Map).cast<String, dynamic>());
}
