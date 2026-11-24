# إعداد التشغيل الصوتي بالخلفية — خزائن الهدى

## ما تم ربطه في طبقة Flutter

- تمت إضافة `audio_service` لتوفير واجهة خدمة الوسائط للنظام، مع `just_audio` كمحرك تشغيل.
- يوجد الآن كائن تشغيل واحد `KhazainAudioHandler` مشترك بين المكتبة الصوتية وقارئ القرآن.
- بيانات المقطع (العنوان والقارئ/الفنان والألبوم) تُرسل إلى طبقة النظام حتى تظهر مع إشعار الوسائط وعناصر التحكم.
- أزرار التشغيل والإيقاف المؤقت والإيقاف والبحث الزمني متصلة بمعالج الصوت.
- مصادر البث البعيدة تقبل HTTPS فقط. الملفات المحلية يجب أن تكون موجودة وغير فارغة.
- إغلاق شاشة المكتبة أو قارئ القرآن لا يتلف مشغل الصوت المشترك.

## تهيئة الاعتماديات

من مجلد `apps/mobile` شغّل:

```bash
flutter pub get
flutter analyze
flutter test
```

تمت إضافة الحزمتين إلى `pubspec.yaml`:

```yaml
audio_service: ^0.18.19
audio_session: ^0.1.25
```

يجب أن يقوم `flutter pub get` بتحديث `pubspec.lock` وفق نظام البناء الفعلي؛ لا تُعدّل أرقام SHA يدويّاً.

## Android — مطلوب قبل اختبار الخلفية

**ملاحظة بنيوية:** نسخة المصدر التي جرى العمل عليها لا تحتوي حالياً على مجلد `android/` أو `ios/`. أنشئ ملفات المنصة من مجلد `apps/mobile` بالأمر:

```bash
flutter create --platforms=android,ios .
```

ثم افتح `android/app/src/main/AndroidManifest.xml` وأضف الصلاحيات داخل عنصر `manifest`:

```xml
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
```

داخل عنصر `application`، عدّل عنصر النشاط الموجود بحيث يستخدم:

```xml
android:name="com.ryanheise.audioservice.AudioServiceActivity"
```

مع الاحتفاظ ببقية خصائص النشاط الحالية (مثل `exported` و`launchMode` و`theme` و`configChanges`). ثم أضف الخدمة والمستقبل:

```xml
<service
    android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>

<receiver
    android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</receiver>
```

لأجهزة Android 13 وما بعدها، اختبر إذن الإشعارات `POST_NOTIFICATIONS` وطلبه من المستخدم عند الحاجة؛ رفضه قد يؤثر في ظهور إشعار الوسائط للمستخدم. لا تطلب الإذن دون شرح الغرض منه.

## iOS — مطلوب قبل اختبار Control Center

في `ios/Runner/Info.plist` أضف داخل جذر `dict`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

هذا الوضع مخصص لاستمرار جلسة صوت فعلية بالخلفية، وليس لتشغيل مهام عامة.

## اختبارات القبول على جهاز حقيقي

1. شغّل تسجيلاً HTTPS منشوراً ومرخصاً من المكتبة الصوتية.
2. انتقل إلى الشاشة الرئيسية ثم اقفل الشاشة؛ يجب استمرار الصوت وظهور عنوان المقطع وعناصر التحكم.
3. اختبر إيقافاً مؤقتاً ثم استئنافاً من الإشعار/شاشة القفل.
4. اختبر زر سماعة الرأس وإيقاف الصوت عند فصل السماعات.
5. اختبر تشغيل ملف قرآن محلي ثم انتقل إلى شاشة أخرى؛ يجب ألا يتوقف بسبب التخلص من الشاشة.
6. اختبر انتهاء التسجيل والإيقاف اليدوي ثم شغّل تسجيلاً آخر.
7. اختبر Android 12/13/14 أو أعلى، مع ملاحظة قيود توفير البطارية وإذن الإشعارات.

## حدود التنفيذ الحالي

- لم تتوفر ملفات Android/iOS الأصلية في الأرشيف عند بدء هذه الجولة؛ لذلك لم تُدمج تعديلات Manifest أو Info.plist في ملفات منصة قائمة.
- لم تتوفر أدوات Flutter/Dart في بيئة العمل لهذه الجولة؛ لذلك لم يُشغّل `flutter pub get` أو `flutter analyze` أو `flutter test` ولم ينتج APK/IPA.
- لا تعتبر ميزة الخلفية مُثبتة على جهاز حتى تنجح خطوات تهيئة المنصة واختبارات القبول أعلاه.
- لا تضف تسجيلات إلى المكتبة إلا بعد توثيق حق البث، وحق التنزيل تحديداً عند تفعيل `can_download`.
