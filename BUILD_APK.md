# بناء تطبيق خزائن الهدى

يتولى GitHub Actions بناء نسخة Android release عند دفع وسم يبدأ بـ `v`، ثم ينشر ملف `Khazain-Al-Huda.apk` في صفحة Releases العامة.

للبناء محليًا:

```bash
cd apps/mobile
flutter pub get
flutter build apk --release
```
