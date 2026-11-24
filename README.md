# خزائن الهدى — Round 40

مستودع مشروع **خزائن الهدى**. تم تحديث مصدر تطبيق Flutter من أرشيف Round 40 مع الإبقاء على إعداد Android وسير GitHub Actions لبناء APK.

## مصدر التطبيق

- تطبيق Flutter: `apps/mobile/`
- مستندات Round 40: `docs/START_HERE_AR.md`، `docs/DEV_PANEL_AR.md`، وتقارير المراجعة داخل `docs/reports/`
- خدمات الخادم ولوحة الإدارة الموروثة من المشروع السابق: `services/api/` و`apps/admin/`
- معرّف Android: `org.khazainalhuda.khazain_al_huda`

## تشغيل وبناء Android

المتطلبات: Flutter مستقر وAndroid SDK.

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter build apk --debug
```

ينتج APK محليًا في `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`. عند رفع تغييرات إلى `main`، سير GitHub Actions المعرّف في `.github/workflows/flutter-android-apk.yml` يبني APK تجريبيًا ويُرفقه كـartifact.

هذا APK تجريبي موقّع بمفتاح Debug، وليس إصدارًا موقّعًا للنشر على Google Play. لم تُنشر خدمات الخادم؛ الميزات التي تعتمد على API تحتاج تشغيل `services/api/` وتحديد `API_BASE_URL` المناسب.

## خدمات الخادم

الخادم مبني على FastAPI وقاعدة PostgreSQL، ويقع في `services/api/`. راجع `.env.example` وإرشادات التشغيل الموجودة في المستندات ذات الصلة. لا تضع أسرارًا أو ملفات `.env` في Git.
