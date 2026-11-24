import 'package:flutter/material.dart';

/// One entry of the sections grid.
@immutable
class AppSection {
  const AppSection({
    required this.id,
    required this.title,
    required this.iconId,
    required this.group,
    required this.route,
    this.description = '',
    this.order = 0,
  });

  final String id;
  final String title;
  final String iconId;
  final String group;
  final String route;

  /// One-line description shown under the title in list contexts.
  final String description;

  /// Sort order inside its group.
  final int order;
}

/// The five groups the sections are divided into (G7).
const List<String> kAppSectionGroups = <String>[
  'عبادات',
  'قرآن وأذكار',
  'أدوات',
  'مواسم',
  'أرشيف',
];

/// The 18 shipped sections.
///
/// Every entry points at a real route — the developer panel's Sections
/// Manager can add, remove, reorder, hide, lock or re-icon them at runtime.
const List<AppSection> kAppSections = <AppSection>[
  // عبادات
  AppSection(
    id: 'prayerTimes',
    title: 'أوقات الصلاة',
    iconId: 'prayerTimes',
    group: 'عبادات',
    route: '/prayer',
    description: 'مواقيت اليوم والتنبيهات والتنسيق',
    order: 0,
  ),
  AppSection(
    id: 'qibla',
    title: 'القبلة',
    iconId: 'qibla',
    group: 'عبادات',
    route: '/qibla',
    description: 'اتجاه الكعبة بالبوصلة',
    order: 1,
  ),
  AppSection(
    id: 'rakCounter',
    title: 'عداد الركع',
    iconId: 'rakCounter',
    group: 'عبادات',
    route: '/rak-counter',
    description: 'عدّ الركعات والسجدات',
    order: 2,
  ),
  AppSection(
    id: 'tazkiya',
    title: 'الأخلاقيات',
    iconId: 'tazkiya',
    group: 'أرشيف',
    route: '/ethics',
    description: 'دروس أخلاقية محفوظة محلياً',
    order: 3,
  ),
  AppSection(
    id: 'farai',
    title: 'المكتبة الإسلامية',
    iconId: 'farai',
    group: 'عبادات',
    route: '/library',
    description: 'فروضك وواجباتك وكتبك',
    order: 4,
  ),

  // قرآن وأذكار
  AppSection(
    id: 'quran',
    title: 'القرآن الكريم',
    iconId: 'quran',
    group: 'قرآن وأذكار',
    route: '/quran',
    description: 'المصحف والتلاوة',
    order: 0,
  ),
  AppSection(
    id: 'adhkar',
    title: 'الأذكار',
    iconId: 'adhkar',
    group: 'قرآن وأذكار',
    route: '/adhkar',
    description: 'أذكار الصباح والمساء وبعد الصلاة',
    order: 1,
  ),
  AppSection(
    id: 'taqiyat',
    title: 'تعقيبات',
    iconId: 'taqiyat',
    group: 'قرآن وأذكار',
    route: '/duas',
    description: 'أدعية ومناجاة موثقة',
    order: 2,
  ),
  AppSection(
    id: 'tasbih',
    title: 'التسبيح',
    iconId: 'tasbih',
    group: 'قرآن وأذكار',
    route: '/tasbih',
    description: 'عدّاد التسبيح باهتزاز',
    order: 3,
  ),
  AppSection(
    id: 'misira',
    title: 'المسيرة',
    iconId: 'misira',
    group: 'قرآن وأذكار',
    route: '/tasbih?preset=misira',
    description: 'سبحان الله والحمد لله',
    order: 4,
  ),

  // أدوات
  AppSection(
    id: 'amal',
    title: 'الأعمال',
    iconId: 'amal',
    group: 'أدوات',
    route: '/amal',
    description: 'أعمال القلب واللسان',
    order: 0,
  ),
  AppSection(
    id: 'mukhalafat',
    title: 'مساحتي',
    iconId: 'mukhalafat',
    group: 'أدوات',
    route: '/mukhalafat',
    description: 'أذكارك وأورادك وما تحفظه لنفسك',
    order: 1,
  ),
  AppSection(
    id: 'arbaeen',
    title: 'زائر الأربعين',
    iconId: 'arbaeen',
    group: 'أدوات',
    route: '/visitor-guide',
    description: 'دليل الزائر والمراقد',
    order: 2,
  ),

  // مواسم
  AppSection(
    id: 'hijriCalendar',
    title: 'التقويم الهجري',
    iconId: 'hijriCalendar',
    group: 'مواسم',
    route: '/calendar',
    description: 'شهر هجري كامل',
    order: 0,
  ),
  AppSection(
    id: 'ramadan',
    title: 'إمساكية رمضان',
    iconId: 'ramadan',
    group: 'مواسم',
    route: '/calendar?mode=ramadan',
    description: 'أوقات الإمساك والإفطار',
    order: 1,
  ),
  AppSection(
    id: 'hajj',
    title: 'المناسبات الدينية',
    iconId: 'hajj',
    group: 'مواسم',
    route: '/events',
    description: 'مناسبات الحج والسفر',
    order: 2,
  ),

  // أرشيف
  AppSection(
    id: 'ziyara',
    title: 'الزيارات',
    iconId: 'ziyara',
    group: 'أرشيف',
    route: '/visits',
    description: 'نصوص الزيارات موثقة',
    order: 0,
  ),
  AppSection(
    id: 'khamat',
    title: 'الخمسة الطاهرون',
    iconId: 'khamat',
    group: 'أرشيف',
    route: '/khamaat',
    description: 'سيرة الخمسة الطاهرين',
    order: 1,
  ),
  
  // أدوات إضافية — each card opens its own feature screen.
  AppSection(
    id: 'audioLibrary',
    title: 'مكتبة الصوتيات',
    iconId: 'adhkar',
    group: 'أدوات',
    route: '/audio',
    description: 'تلاوات وأدعية ومواد صوتية',
    order: 3,
  ),
  AppSection(
    id: 'radio',
    title: 'الراديو',
    iconId: 'misira',
    group: 'أدوات',
    route: '/radio',
    description: 'البث والمصادر الصوتية',
    order: 4,
  ),
  AppSection(
    id: 'shiavoice',
    title: 'مكتبة صوت الشيعة',
    iconId: 'ziyara',
    group: 'أدوات',
    route: '/shiavoice',
    description: 'فهرس صوتي وروابط المصدر الأصلي',
    order: 5,
  ),
  AppSection(
    id: 'wallpapers',
    title: 'الخلفيات',
    iconId: 'mukhalafat',
    group: 'أدوات',
    route: '/wallpapers',
    description: 'خلفيات الهاتف والمناسبات',
    order: 6,
  ),
  AppSection(
    id: 'favorites',
    title: 'المفضلة',
    iconId: 'khamat',
    group: 'أدوات',
    route: '/favorites',
    description: 'النصوص والمواد المحفوظة',
    order: 7,
  ),
  AppSection(
    id: 'sources',
    title: 'المصادر والتوثيق',
    iconId: 'farai',
    group: 'أدوات',
    route: '/sources',
    description: 'المراجع والتراخيص وبيانات النشر',
    order: 8,
  ),
  AppSection(
    id: 'cityGuide',
    title: 'دليل المدن',
    iconId: 'arbaeen',
    group: 'أدوات',
    route: '/city',
    description: 'البحث عن المدن والمواقع',
    order: 9,
  ),

  // القرآن والمعرفة
  AppSection(
    id: 'quranRecitations',
    title: 'تلاوات القرآن',
    iconId: 'quran',
    group: 'قرآن وأذكار',
    route: '/quran/recitations',
    description: 'اختيار القارئ ومتابعة التلاوة',
    order: 5,
  ),
  AppSection(
    id: 'hadith',
    title: 'الروايات والأحاديث',
    iconId: 'taqiyat',
    group: 'قرآن وأذكار',
    route: '/hadith',
    description: 'نصوص مع المصدر والبيانات المتاحة',
    order: 6,
  ),

  // أهل البيت والعلوم التربوية
  AppSection(
    id: 'ahlAlBayt',
    title: 'أهل البيت',
    iconId: 'khamat',
    group: 'أرشيف',
    route: '/ahl-al-bayt',
    description: 'سير ومحتوى تعريفي موثق',
    order: 2,
  ),
  AppSection(
    id: 'imams',
    title: 'الأئمة',
    iconId: 'ziyara',
    group: 'أرشيف',
    route: '/imams',
    description: 'صفحات السيرة والتعريف',
    order: 3,
  ),
  AppSection(
    id: 'stories',
    title: 'القصص التربوية',
    iconId: 'taqiyat',
    group: 'أرشيف',
    route: '/stories',
    description: 'قصص تعليمية مع تمييز القصص الخيالية',
    order: 5,
  ),
  AppSection(
    id: 'readingProgress',
    title: 'متابعتي',
    iconId: 'farai',
    group: 'أدوات',
    route: '/fada',
    description: 'متابعة النصوص والصفحات التي فتحتها',
    order: 10,
  ),
  AppSection(
    id: 'libraryAssistant',
    title: 'مساعد المكتبة',
    iconId: 'quran',
    group: 'أدوات',
    route: '/assistant',
    description: 'مساعدة في البحث داخل المكتبة والمصادر',
    order: 11,
  ),
  AppSection(
    id: 'settings',
    title: 'الإعدادات',
    iconId: 'misira',
    group: 'أدوات',
    route: '/settings',
    description: 'الموقع والمظهر والخط والتنبيهات',
    order: 12,
  ),
];

/// Looks a section up by id.
AppSection? appSectionById(String id) {
  for (final section in kAppSections) {
    if (section.id == id) return section;
  }
  return null;
}
