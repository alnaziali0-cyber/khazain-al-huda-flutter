import 'package:flutter/widgets.dart';

import '../devpanel/models.dart';

/// A hand-authored icon on the 24px grid with a two-tone stroke palette.
///
/// Each glyph is described by SVG path data so the developer panel can edit
/// the paths live and export them without touching the source files.
@immutable
class KhazainIconDef {
  const KhazainIconDef({
    required this.id,
    required this.label,
    required this.paths,
    required this.accentPaths,
    this.stroke = 2,
  });

  final String id;
  final String label;

  /// Primary stroke paths (brand green).
  final List<String> paths;

  /// Secondary stroke paths (gold accent).
  final List<String> accentPaths;

  final double stroke;

  /// Flattens the definition into the developer-panel schema.
  IconDef toIconDef({
    String primary = '#376E6A',
    String secondary = '#C77A57',
  }) =>
      IconDef(
        id: id,
        paths: <String>[...paths, ...accentPaths],
        size: 24,
        stroke: stroke,
        primary: primary,
        secondary: secondary,
        secondaryPathCount: accentPaths.length,
      );
}

/// The 18 icons required by the design contract, in the order shown on the
/// icon sheet (groups: العقائد · الأخلاق · أوقات الصلاة · …).
const List<KhazainIconDef> kKhazainIcons = <KhazainIconDef>[
  KhazainIconDef(
    id: 'adhkar',
    label: 'الأذكار',
    paths: <String>[
      'M12 3.4 L13.7 9.3 L19.6 11 L13.7 12.7 L12 18.6 L10.3 12.7 L4.4 11 L10.3 9.3 Z',
    ],
    accentPaths: <String>[
      'M18.4 15.2 L19.3 17.6 L21.7 18.5 L19.3 19.4 L18.4 21.8 L17.5 19.4 L15.1 18.5 L17.5 17.6 Z',
    ],
  ),
  KhazainIconDef(
    id: 'ziyara',
    label: 'الزيارات',
    paths: <String>[
      'M5.4 19.6 L5.4 13.2 C5.4 8.9 8.4 5.5 12 5.5 C15.6 5.5 18.6 8.9 18.6 13.2 L18.6 19.6',
      'M12 2.6 C13.2 3.8 13.2 5.1 12 6.3 C10.8 5.1 10.8 3.8 12 2.6 Z',
    ],
    accentPaths: <String>[
      'M4 19.6 L20 19.6',
    ],
  ),
  KhazainIconDef(
    id: 'tazkiya',
    label: 'التزكية',
    paths: <String>[
      'M7.4 13.6 L7.4 8.2 C7.4 7.3 8.6 7.3 8.6 8.2 L8.6 12',
      'M8.6 12 L8.6 6.6 C8.6 5.7 9.8 5.7 9.8 6.6 L9.8 12',
      'M9.8 12 L9.8 7.2 C9.8 6.3 11 6.3 11 7.2 L11 12.4',
      'M11 12.4 L11 9.4 C11 8.5 12.2 8.5 12.2 9.4 L12.2 14.6 '
          'C12.2 17.7 10.4 19.9 7.4 19.9 C5 19.9 7.4 17.7 7.4 15.2 Z',
    ],
    accentPaths: <String>[
      'M18.2 4.2 L19 6.2 L21 7 L19 7.8 L18.2 9.8 L17.4 7.8 L15.4 7 L17.4 6.2 Z',
    ],
  ),
  KhazainIconDef(
    id: 'quran',
    label: 'القرآن الكريم',
    paths: <String>[
      'M12 6.8 C10.4 5.2 8.2 4.4 4 4.4 L4 18 C8.2 18 10.4 18.8 12 20.2 '
          'C13.6 18.8 15.8 18 20 18 L20 4.4 C15.8 4.4 13.6 5.2 12 6.8 Z',
    ],
    accentPaths: <String>[
      'M12 6.8 L12 20.2',
    ],
  ),
  KhazainIconDef(
    id: 'taqiyat',
    label: 'تعقيبات',
    paths: <String>[
      'M12 3.4 L18.6 10 L18.6 20.6 L5.4 20.6 L5.4 10 Z',
    ],
    accentPaths: <String>[
      'M12 7.6 L15.4 11.6 L15.4 20.6 L8.6 20.6 L8.6 11.6 Z',
    ],
  ),
  KhazainIconDef(
    id: 'rakCounter',
    label: 'عداد الركع',
    paths: <String>[
      'M5.4 4.4 L15 4.4 L18.6 8 L18.6 19.6 L5.4 19.6 Z',
      'M15 4.4 L15 8 L18.6 8',
    ],
    accentPaths: <String>[
      'M16.1 12.8 A2.8 2.8 0 1 0 16.1 18.4 A2.8 2.8 0 1 0 16.1 12.8 Z '
          'M18.3 18.3 L20.6 20.6',
    ],
  ),
  KhazainIconDef(
    id: 'amal',
    label: 'الأعمال',
    paths: <String>[
      'M3.4 8.8 L20.6 8.8 L20.6 15.2 L3.4 15.2 Z',
    ],
    accentPaths: <String>[
      'M7 8.8 L7 12 M10.6 8.8 L10.6 13.2 M14.2 8.8 L14.2 12 M17.8 8.8 L17.8 13.2',
    ],
  ),
  KhazainIconDef(
    id: 'misira',
    label: 'المسيرة',
    paths: <String>[
      'M12 5.2 A6.8 6.8 0 1 0 12 18.8 A6.8 6.8 0 1 0 12 5.2',
    ],
    accentPaths: <String>[
      'M12 18.8 L14.9 22.4 M12 18.8 L9.1 22.4',
      'M12 2.4 A1 1 0 1 0 12 4.4 A1 1 0 1 0 12 2.4 Z',
    ],
  ),
  KhazainIconDef(
    id: 'khamat',
    label: 'الخمات',
    paths: <String>[
      'M12 18.8 C12 18.8 4.8 14.2 4.8 9.6 C4.8 7.3 6.4 5.6 8.5 5.6 '
          'C10.1 5.6 11.2 6.4 12 7.4 C12.8 6.4 13.9 5.6 15.5 5.6 '
          'C17.6 5.6 19.2 7.3 19.2 9.6 C19.2 14.2 12 18.8 12 18.8 Z',
    ],
    accentPaths: <String>[
      'M4 15.4 C5.4 17.5 7 18.9 8.8 19.7 M20 15.4 C18.6 17.5 17 18.9 15.2 19.7',
    ],
  ),
  KhazainIconDef(
    id: 'qibla',
    label: 'القبلة',
    paths: <String>[
      'M12 3.6 A8.4 8.4 0 1 0 12 20.4 A8.4 8.4 0 1 0 12 3.6',
    ],
    accentPaths: <String>[
      'M15.6 8.4 L13.4 13.4 L8.4 15.6 L10.6 10.6 Z',
    ],
  ),
  KhazainIconDef(
    id: 'prayerTimes',
    label: 'أوقات الصلاة',
    paths: <String>[
      'M12 3.8 A8.2 8.2 0 1 0 12 20.2 A8.2 8.2 0 1 0 12 3.8',
    ],
    accentPaths: <String>[
      'M12 7.2 L12 12 L15.4 14',
    ],
  ),
  KhazainIconDef(
    id: 'hijriCalendar',
    label: 'التقويم الهجري',
    paths: <String>[
      'M4.5 6.4 L19.5 6.4 L19.5 20 L4.5 20 Z M4.5 10.4 L19.5 10.4 '
          'M8.6 3.8 L8.6 8 M15.4 3.8 L15.4 8',
    ],
    accentPaths: <String>[
      'M9 13.4 L9 17.6 M9 13.4 A2.1 2.1 0 1 0 9 17.6 A2.1 2.1 0 1 0 9 13.4 Z '
          'M14.6 13.4 L14.6 17.6 M14.6 13.4 A2.1 2.1 0 1 0 14.6 17.6 A2.1 2.1 0 1 0 14.6 13.4 Z',
    ],
  ),
  KhazainIconDef(
    id: 'farai',
    label: 'فرائضي',
    paths: <String>[
      'M6 4.4 L14.5 4.4 L18 7.9 L18 19.6 L6 19.6 Z M14.5 4.4 L14.5 7.9 L18 7.9',
    ],
    accentPaths: <String>[
      'M15.9 12.4 A2.9 2.9 0 1 0 15.9 18.2 A2.9 2.9 0 1 0 15.9 12.4 Z '
          'M18 17.9 L20.3 20.2',
    ],
  ),
  KhazainIconDef(
    id: 'tasbih',
    label: 'التسبيح',
    paths: <String>[
      'M19.2 9.2 A7.6 7.6 0 0 0 6.4 5.7 L4.3 7.8 M4.8 14.8 A7.6 7.6 0 0 0 17.6 18.3 L19.7 16.2',
    ],
    accentPaths: <String>[
      'M4.3 4.1 L4.3 7.8 L8 7.8 M19.7 19.9 L19.7 16.2 L16 16.2',
    ],
  ),
  KhazainIconDef(
    id: 'mukhalafat',
    label: 'المخلفات',
    paths: <String>[
      'M3.6 5.4 L14.6 5.4 L14.6 16.4 L3.6 16.4 Z',
      'M6.4 8.6 L18 8.6 L18 19.6 L6.4 19.6 Z',
    ],
    accentPaths: <String>[
      'M8.6 16.2 L11.2 13.6 L13.2 15.6 L14.8 14 L17 16.2',
    ],
  ),
  KhazainIconDef(
    id: 'arbaeen',
    label: 'زائر الأربعين',
    paths: <String>[
      'M12 21 C12 21 18.6 14.8 18.6 10.1 A6.6 6.6 0 0 0 5.4 10.1 '
          'C5.4 14.8 12 21 12 21 Z',
    ],
    accentPaths: <String>[
      'M12 7.4 A2.7 2.7 0 1 0 12 12.8 A2.7 2.7 0 1 0 12 7.4 Z',
    ],
  ),
  KhazainIconDef(
    id: 'ramadan',
    label: 'إمساكية رمضان',
    paths: <String>[
      'M4.5 6.4 L19.5 6.4 L19.5 20 L4.5 20 Z M4.5 10.4 L19.5 10.4 '
          'M8.6 3.8 L8.6 8 M15.4 3.8 L15.4 8',
    ],
    accentPaths: <String>[
      'M16.4 12.2 A3.7 3.7 0 1 0 16.4 18.6 A2.9 2.9 0 0 1 16.4 12.2 Z',
    ],
  ),
  KhazainIconDef(
    id: 'hajj',
    label: 'بوابة الحج',
    paths: <String>[
      'M5 7.4 L12 4 L19 7.4 L19 16.6 L12 20 L5 16.6 Z',
    ],
    accentPaths: <String>[
      'M5.4 10.4 L12 13.8 L18.6 10.4',
    ],
  ),
];

/// Looks an icon up by id.
KhazainIconDef? khazainIconById(String id) {
  for (final icon in kKhazainIcons) {
    if (icon.id == id) return icon;
  }
  return null;
}

/// The section groups shown on the sections screen (G7).
const List<String> kSectionGroups = <String>[
  'عبادات',
  'قرآن وأذكار',
  'أدوات',
  'مواسم',
  'أرشيف',
];
