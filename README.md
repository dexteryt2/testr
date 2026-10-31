# Claude Pool — APK

Multi-account claude.ai session pool برای Android (ARM64-v8a)

## ساختار پروژه

```
claude_pool_app/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── app_state.dart       ← Pool manager + exhaustion/RR mode
│   │   ├── claude_client.dart   ← claude.ai unofficial API
│   │   ├── subscription.dart    ← VLESS parser
│   │   └── xray_manager.dart    ← Xray ARM64 process manager
│   ├── db/session_store.dart    ← SQLite local
│   └── screens/
│       ├── login_screen.dart    ← WebView → Google login → کوکی
│       ├── accounts_screen.dart
│       ├── chat_screen.dart
│       ├── subscription_screen.dart
│       └── settings_screen.dart
├── android/                     ← Flutter v2 Android project (کامل)
├── assets/
│   ├── xray-arm64-v8a           ← دانلود میشه توی CI
│   └── fonts/                   ← دانلود میشه توی CI
└── .github/workflows/build.yml  ← GitHub Actions
```

## Build روی GitHub Actions

### ۱. آپلود پروژه
```bash
# محتوای zip رو extract کن
cd claude_pool_app

git init
git add .
git commit -m "initial"
git remote add origin https://github.com/USERNAME/claude-pool.git
git push -u origin main
```

### ۲. GitHub Actions خودکار build میکنه
- بعد از push → Actions → **Build APK (ARM64)** شروع میشه
- Xray ARM64 دانلود میشه
- فونت دانلود میشه  
- APK ساخته میشه

### ۳. دانلود APK
```
Actions → آخرین run → Artifacts → claude-pool-apk → دانلود
```

## استفاده روی گوشی

```
۱. APK نصب کن (نصب از منابع ناشناس فعال باشه)

۲. پروکسی → لینک ساب VLESS → Sync → Health Check

۳. حساب‌ها → + → ایمیل Google → لاگین
   (WebView باز میشه، با Google لاگین کن، کوکی خودکار ذخیره)

۴. چت → پیام بفرست
   حالت Exhaustion: یه اکانت تا تموم شدن توکن، بعد اکانت بعدی
   حالت RR: چرخش یکسان بین همه اکانت‌ها
```

## معماری

```
APK (ARM64)
├── WebView   → Google login → کوکی استخراج
├── Xray      → VLESS proxy per account
├── SQLite    → sessions, bindings, configs
└── HTTP      → claude.ai با کوکی از طریق پروکسی
```
