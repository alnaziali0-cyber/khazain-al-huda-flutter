# إغلاق الفجوات G1–G22

| # | البند | الحالة | الملف / الدليل | كيف تحقّقت |
|---|---|---|---|---|
| G1 | خمس بلاطات بيضاء فارغة في S3 | مُغلق | `features/mukhalafat/mukhalafat_screen.dart` (`_adhkarCategories`) | ست بطاقات أذكار حقيقية (أذكار الصباح والمساء، بعد الصلاة، النوم، الاستغفار والتسبيح، دعاء الكرب، الرقية الشرعية) بكل بطاقة أيقونة + عنوان + سطر وصف + رابط؛ اختبار `test/features/mukhalafat_screen_test.dart` |
| G2 | بلاطة بنص أخضر مكسور | مُغلق | `features/mukhalafat/mukhalafat_screen.dart` | البطاقة تعرض `title` + `description` + `iconId` من `LocalLibraryEntry` (مصدر ورخصة) بدل النص المكسور |
| G3 | لا يوجد زر إضافة | مُغلق | `features/mukhalafat/mukhalafat_screen.dart` + `mukhalafat_store.dart` | زر عائم «إضافة مقصودة» يكتب في `mukhalafat_entries_v1` ويظهر في الشبكة فوراً |
| G4 | فقرة بديلة داخل شبكة S5 | مُغلق | `features/sections/sections_screen.dart` (`_AddSectionTile`) | حُذفت الفقرة وحلّت محلها بلاطة «إضافة قسم» بشرطة متقطعة |
| G5 | خلايا فارغة في S5 | مُغلق | `features/sections/sections_screen.dart` | كل خلية بلاطة أو بلاطة إضافة؛ `test/features/sections_screen_test.dart` يتحقق من 18+1 بلاطة بلا عنوان فارغ |
| G6 | تكرار «الأذكار» | مُغلق | `features/sections/section_catalogue.dart` | 18 قسماً بمعرّفات وعناوين فريدة؛ `test/icons/khazain_icons_test.dart` |
| G7 | ~620px فراغ رأسي في S5 | مُغلق | `features/sections/section_catalogue.dart` (`kAppSectionGroups`) | خمسة أقسام: عبادات · قرآن وأذكار · أدوات · مواسم · أرشيف، كلٌّ على سطح `#303030` r20 |
| G8 | رقاقة «الأخرى» مقصوصة | مُغلق | `components/chip_row.dart` | `SingleChildScrollView` أفقي حقيقي + تلاشٍ عند الحافة + بلا مؤشر تمرير |
| G9 | لا توجد حالة فارغة حقيقية | مُغلق | `components/state_view.dart` | `StateView` موحّد (أيقونة 64dp + سطر + إجراء) مستخدم في الفضلة والمخلفات والأذكار والأعمال والتقويم والصوتيات |
| G10 | خانة إعلان بديلة | مُغلق | `components/ad_slot.dart` + `features/home/home_announcement_slot.dart` | `AdSlot` يعرض صورة محلية وعنواناً ورابطاً من لوحة المطوّر، وبديله بطاقة متدرّجة بالعلامة التجارية لا نص تعليمي؛ الإعلانات المنشورة من الخادم تُعرض أيضاً |
| G11 | «خزائن مخلفات كثيرة» + 3 خلايا فارغة | مُغلق | `features/home/home_screen.dart` (`_HomeSheet`) | ثلاث بطاقات حيّة: آخر أذكار، الصلاة القادمة مع عدّاد تنازلي، المسبحة (عدّاد 0–33 مع اهتزاز) |
| G12 | زر الدعم بلا فعل | مُغلق | `features/settings/support_sheet.dart` | ورقة دعم حقيقية: واتساب + بريد + نسخ، مع سجل محلي لآخر الطلبات |
| G13 | «المدن الأخيرة» فارغة | مُغلق | `core/city_search.dart` + `features/city/city_search_screen.dart` | آخر 5 مدن محفوظة + حالة فارغة + علامة ✓ للمدينة الحالية + ★ للمفضلة |
| G14 | نطاقات مفقودة في S1 | مُغلق | `features/city/city_search_screen.dart` | نطاقا «المدينة الحالية» و«المفضلة» |
| G15 | نص S6 تعليمي | مُغلق | `features/radio/audio_library_screen.dart` | «تسجيلات موثّقة الحقوق، تعمل دون اتصال بعد التنزيل.» |
| G16 | لا يوجد مشغّل | مُغلق | `features/radio/audio_library_screen.dart` + `core/audio_playback_service.dart` | شريط مشغّل: موضع + مدة + سرعة 0.75/1.0/1.25× + تنزيل بتقدّم ميغابايت + وسم «مُنزّل ✓» |
| G17 | روابط S2 ميتة | مُغلق | `features/settings/settings_screen.dart` | كل بند يفتح شاشة أو ورقة حقيقية (١٥ بنداً) |
| G18 | لا توجد شاشة إعدادات | مُغلق | `features/settings/settings_screen.dart` + `settings_subpages.dart` | المظهر، حجم الخط، الخط، اللغة، الموقع، الأذان، الإشعارات، الخصوصية، مسح البيانات، تصدير/استيراد المظهر، أيقونة التطبيق |
| G19 | لا توجد حالات تحميل/خطأ/انقطاع | مُغلق | كل الشاشات الجديدة | `StateView` + `CircularProgressIndicator` + رسالة خطأ + زر إعادة محاولة |
| G20 | لا يوجد مؤشّر تبويب | مُغلق | `components/bottom_nav.dart` | `AnimatedScale` بمقياس 1.06 خلال 200ms + `HapticFeedback.selectionClick` |
| G21 | أخطاء نصية | مُغلق | بحث نصّي على `lib/` | «أوقات الصلاة» و«الأخرى» و«صوت الإذان» — لا وجود لأي خطأ منقولة؛ `grep` يعطي صفراً |
| G22 | لا يوجد عرض خطي | مُغلق | `components/app_text.dart` (`CalligraphicText`) + `core/app_preferences.dart` | خط `AmiriQuran` بمقياس مستقل + مفتاح إظهار/إخفاء التشكيل (مطبّق في قارئ النصوص المحلية) |

## لوحة المطوّر (§5)

| المتطلب | الحالة | الدليل |
|---|---|---|
| فتح بلا أثر بصري | مُغلق | `devpanel/open.dart`: ضغط مطوّل 900ms مع حلقة تقدّم، ٧ نقرات/٣ ثوانٍ، ٣ نقرات بإصبعين |
| رمز 4 أرقام بـ SHA-256 + ملح | مُغلق | `devpanel/pin.dart`؛ `test/devpanel/dev_pin_test.dart` يتحقق من عدم تخزين النص الصريح ومن اختلاف الملح |
| قفل تلقائي بعد 5 دقائق/الخلفية | مُغلق | `devpanel/pin.dart` (`isIdleLocked`) + `devpanel/dev_panel_screen.dart` (`didChangeAppLifecycleState`) |
| 10 تبويبات | مُغلق | `devpanel/tabs/*` (توكنات، أقسام، أيقونات، خطوط، مظهر، صورة→واجهة، نصوص، بيانات، تدقيق، سجل) |
| مخطّطات `UITheme` / `Section` / `IconDef` / `Asset` / `UIPatch` / `LayoutNode` | مُغلق | `devpanel/models.dart` |
| تخزين تحت `khzain.dev.v1` | مُغلق | `devpanel/store.dart` |
| تراجع/إعادة 50 خطوة + إرجاع كامل عند الفشل | مُغلق | `devpanel/store.dart`؛ `test/devpanel/dev_store_test.dart` |
| محرك صورة→واجهة | مُغلق جزئياً | `devpanel/image_to_ui/extractor.dart`: عنقدرة k-means + تقدير الخط والشبكة + مطابقة أقرب توكن (ΔE<6) + معاينة قبل/بعد + بوابة تحقق. **توليد الشيفرة من الصورة يبقى خارج التطبيق** (أداة `tools/image-to-ui` الاختيارية) — وهذا موثّق في واجهة التبويب نفسها. |
