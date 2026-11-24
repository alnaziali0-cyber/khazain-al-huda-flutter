# تقرير Round 39 — مساعد خزائن الهدى ومحرك استيراد المكتبات

## 1. الملخص التنفيذي

تم تطوير التكامل داخل بنية المشروع القائمة، دون إعادة بناء التطبيق من الصفر. أضيف قسم واحد باسم **المساعد الذكي للمكتبة**، ومحرك Backend مستقل لاكتشاف المصادر والبحث ومعاينة الاستيراد واستخراج النصوص وتخزين النسخ الخاصة وفهرسة الصفحات والطبعات وعناوين الفهرس.

الصورة التي زوّد بها المستخدم استُخدمت مرجعاً بصرياً لشاشة المساعد فقط: خلفية كحلية، نجوم خافتة، فقاعات زجاجية، تباين تركوازي، أيقونة المساعد، وحقل إدخال ثابت. بقية شاشات التطبيق لا تُغيّر هويتها.

## 2. ما أضيف فعلياً

### تطبيق Flutter

- `apps/mobile/lib/features/assistant/library_assistant_screen.dart`: واجهة المساعد واتصال الرسائل بأداة Backend.
- `apps/mobile/lib/core/library_assistant_repository.dart`: عميل نقاط المساعد والمكتبة.
- `apps/mobile/lib/features/library/imported_books_screen.dart`: قائمة الكتب المستوردة لهذا الجهاز.
- `apps/mobile/lib/features/library/imported_book_reader_screen.dart`: قارئ صفحات متدرّج، عرض الفهرس، بحث داخل النص، والنسخ.
- أضيفت بطاقة واحدة باسم «المساعد الذكي للمكتبة» إلى الأقسام.
- أضيفت مسارات `/assistant` و`/library/imported/:bookId`، وأصبحت شاشة `/library` تعرض كتب الجهاز المستوردة.
- جرى إخفاء شريط التنقل السفلي في شاشة المحادثة والقارئ حتى تبقى مساحة القراءة والمحادثة واسعة.

### Backend

- `services/api/app/services/shia_library_import_engine.py`: موصلات المصادر، البحث، تقييم أولي للحقوق، التنزيل المقيد، استخراج PDF وEPUB وTXT وMarkdown وJSON، بصمة SHA-256، والتحقق من حدود الأحجام والمسارات.
- `services/api/app/routers/library.py`: واجهات البحث والمعاينة والتأكيد والرفع ومتابعة المهام وقائمة الكتب والصفحات والطبعات والفهرس والبحث داخل الكتاب والتصدير.
- `services/api/app/routers/assistant.py`: نقطة محادثة محدودة الأدوات. تستخدم DeepSeek عبر الخادم فقط عند ضبط مفتاحه.
- `services/api/app/core/config.py` و`services/api/.env.example`: إعدادات DeepSeek الآمنة من جهة الخادم.
- `services/api/app/services/pdf_text_worker.py`: إرجاع نص كل صفحة من بيئة استخراج PDF المعزولة، بالإضافة إلى النص المجمع.
- رُبطت المسارات في `services/api/app/main.py`، وأُضيف موصلَا Internet Archive وABLibrary إلى سجل المصادر.

## 3. الأدوات المسموحة للمساعد

أدوات النموذج محددة في الخادم ولا تملك وصولاً عشوائياً إلى النظام:

- `discover_sources`: عرض الموصلات وقدراتها وحدودها.
- `search_books`: البحث في كتب الجهاز، والكتب العامة التي اجتازت حالة النشر/الحقوق، وبيانات Internet Archive.
- `get_library_status`: إحصاءات مكتبة الجهاز ومهام الاستيراد.
- `get_import_status`: قراءة حالة مهمة مرتبطة بالجهاز الحالي.
- `prepare_book_import`: جلب بيانات المصدر وإنشاء معاينة فقط؛ لا يبدأ التنزيل.

لا يستطيع النموذج تشغيل أوامر shell أو فتح ملفات عامة أو بدء تنزيل دون موافقة منفصلة من المستخدم عبر زر التأكيد.

## 4. مصادر الكتب والتعامل مع الحقوق

| المصدر | التنفيذ الحالي | الحدّ |
|---|---|---|
| Internet Archive | Advanced Search وMetadata API، معاينة ملف، ثم استيراد بعد موافقة المستخدم | مرشح الترخيص من بيانات المصدر لا يُعد اعتماداً قانونياً مستقلاً |
| Thaqalayn | يحافظ على تكامل البحث الحديثي الموجود | لا يُستخدم هنا كواجهة تنزيل كتب أو نسخ corpus |
| Al-Islam | رابط رسمي ومراجعة يدوية | لا يوجد تنزيل آلي؛ يجب احترام حقوق المحتوى وموافقات أصحاب الحقوق |
| Shia Research | رابط رسمي فقط | لا كشط أو نسخ جماعي أو تنزيل آلي |
| ABLibrary Books Extractor | استيراد تصدير يقدمه المستخدم بصيغ JSON/TXT/Markdown أو ملفات PDF/EPUB/TXT/MD/JSON عامة من مسار الرفع | لا يُشغّل سكربت المصدر على خادم التطبيق ولا يصل إلى تثبيت ABLibrary على جهاز المستخدم |

سياسة الرفع المحلي: الملفات المرفوعة تبقى خاصة بمفتاح الجهاز، ويُنشأ الكتاب في حالة `draft` و`rights_status=unverified`. وجود النص داخل قاعدة البيانات لا يعني أنه مصرح للنشر. كما أن تراخيص Internet Archive تُعامل كادعاء مصدر أولي يحتاج مراجعة بشرية مستقلة قبل أي نشر.

الشروط المنشورة لـ [Al-Islam](https://al-islam.org/sw/contact) تقيد استعمال المحتوى وتستلزم مراعاة إذن أصحاب الحقوق؛ وشروط [Shia Research](https://shiaresearch.org/terms) تمنع النسخ الجماعي والكشط الآلي. لذلك لم تُنشأ موصلات تنزيل لهذين المصدرين. كما يوثق [Internet Archive Developer Portal](https://archive.org/developers/) واجهات قراءة البيانات الوصفية والعناصر، لكن وجود ملف ضمن العنصر لا يمنح بذاته حقوق نشر جديدة على محتواه.

## 5. قاعدة البيانات والترحيلات

أضيفت الجداول التالية:

- `book_import_jobs`: مصدر المهمة، الملف المرشح، حالة الحقوق، حالة التنفيذ، النسبة، الخطأ، والبصمة.
- `book_artifacts`: ملف المصدر المحفوظ، حجمه، نوعه، SHA-256، ومالك الجهاز.
- `book_editions`: الطبعات والناشر وسنة الطبع والرقم الدولي واللغة وبيانات الحقوق.
- `book_toc_entries`: فهرس هرمي، مع مرجع العنصر الأب ورقم الصفحة والمجلد وترتيب العرض.

المهاجرتان:

- `0008_shia_library_import_engine`
- `0009_book_editions_and_toc`

اجتازتا ترقية قاعدة SQLite جديدة حتى `head`، ثم اجتاز المخطط `alembic check` دون اختلافات معلقة.

## 6. نقاط API الأساسية

- `GET /api/v1/public/library/sources`
- `GET /api/v1/public/library/search?q=...`
- `POST /api/v1/public/library/imports/preview`
- `POST /api/v1/public/library/imports/{id}/confirm`
- `POST /api/v1/public/library/imports/upload`
- `GET /api/v1/public/library/imports` و`GET /api/v1/public/library/imports/{id}`
- `POST /api/v1/public/library/imports/{id}/resume`
- `GET /api/v1/public/library/books`
- `GET /api/v1/public/library/books/{id}/pages`
- `GET /api/v1/public/library/books/{id}/editions`
- `GET /api/v1/public/library/books/{id}/toc`
- `GET /api/v1/public/library/books/{id}/search?q=...`
- `GET /api/v1/public/library/books/{id}/export?format=txt|md|json`
- `GET /api/v1/public/library/status`
- `POST /api/v1/public/assistant/chat`

تتطلب واجهات المكتبة `X-Device-Key` صالحاً؛ يُحفظ hash مقيّد بسرّ الخادم بدلاً من المفتاح النصي. عمليات القراءة والملفات مرتبطة بذلك الجهاز.

## 7. الاختبارات التي أُجريت

أمر الفحص:

```bash
bash scripts/run_local_checks.sh
```

النتيجة في هذه النسخة:

- **72 اختباراً ناجحاً**.
- **اختبار واحد متجاوز**.
- 39 ملف JSON صالحاً.
- 77 أرشيف ZIP داخلياً سليماً، دون أرشيف تالف.
- بصمات بيانات القرآن: 10/10 مطابقة.
- 9 Alembic migrations.
- فحص Python compilation ناجح.
- ترقية SQLite نظيفة إلى migration head ناجحة.
- `alembic check`: لا توجد عمليات ترحيل معلقة.

الاختبارات الجديدة تغطي عزل بيانات الأجهزة، استيراد JSON/EPUB، استخراج محتوى ABLibrary، علاقة فهرس الكتاب الهرمية، البحث داخل الصفحات، قائمة المصادر والقيود، التحقق من ترشيح التراخيص، وحماية إعادة توجيه التنزيل.

## 8. ما لم يكتمل بعد — بصراحة

1. **مفتاح DeepSeek غير موجود في بيئة العمل.** من دونه يعمل مساعد الأدوات المحدودة للأوامر المعروفة، وليس نموذج محادثة لغوية كاملاً. يجب ضبط `DEEPSEEK_API_KEY` كسِرّ على خادم API فقط.
2. **منتقي الملفات المحلي داخل Flutter لم يُربط بعد.** مسار رفع PDF/EPUB/TXT/MD/JSON يعمل في Backend، لكن زر المرفقات في شاشة الهاتف يفتح إدخال معرّف/رابط Internet Archive، وليس اختيار ملف من مساحة الهاتف. لا توجد حزمة file picker في اعتماديات التطبيق الحالية، ولا يمكن بناء منصة أصلية دون Flutter SDK.
3. **البحث داخل الكتاب مباشر على نص الصفحات** باستخدام SQL `LIKE` مع حد للنتائج؛ لم يُنشأ بعد فهرس FTS مخصص للبحث العربي واسع النطاق.
4. `resume` يعيد المهمة الفاشلة إلى حالة معاينة/تأكيد جديدة. لا يدّعي استئناف تنزيل جزئي من byte offset.
5. لا توجد مزامنة حسابية بين الأجهزة؛ هذه النسخة تستخدم مكتبة خاصة بمعرّف الجهاز.
6. لا يوجد اختبار APK/IPA أو Flutter Analyze أو Dart Test. Flutter/Dart SDK غير متوفرين، ومجلدا Android وiOS غير موجودين في المصدر المرفق. لم يتم الادعاء ببناء التطبيق على جهاز فعلي.
7. يلزم تشغيل الخدمة على بيئة نشر فعلية، وتوفير `APP_SECRET` قوي وPostgreSQL وHTTPS ومسار تخزين دائم، ثم اختبار تسجيل الدخول والرفع والصوت على أجهزة حقيقية.

## 9. تشغيل التكامل

1. انسخ `services/api/.env.example` إلى `services/api/.env`.
2. اضبط `APP_SECRET` فريداً بطول لا يقل عن 32 حرفاً، وأضف إعدادات PostgreSQL ومسار `MEDIA_ROOT`.
3. أضف `DEEPSEEK_API_KEY` إلى أسرار الخادم فقط لتفعيل المحادثة اللغوية. لا تضع المفتاح في ملفات Flutter أو المستودع.
4. من `services/api` نفّذ `alembic upgrade head`، ثم شغّل FastAPI وفق تعليمات Docker/النشر في README.
5. شغّل Flutter مع `--dart-define=API_BASE_URL=<HTTPS API origin>` بعد تثبيت Flutter SDK وتوليد Android/iOS عند الحاجة.

هذه النسخة تمثل دمجاً برمجياً واختبارات Backend ناجحة، وليست إصداراً نهائياً مختبراً على الهاتف حتى إكمال النقاط المذكورة أعلاه.
