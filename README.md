# Janarym — Дауыстық AI Ассистент

Қазақша, орысша және ағылшынша жұмыс істейтін дауыстық AI-ассистент.

## Жылдам бастау

### 1. Secrets.plist құру

`Janarym/Resources/Secrets.example.plist` файлын `Janarym/Resources/Secrets.plist` деп көшіріп, кілттерді толтырыңыз:

```bash
cp Janarym/Resources/Secrets.example.plist Janarym/Resources/Secrets.plist
```

Қажетті кілттер:
- `GEMINI_API_KEY` — Gemini API кілті (міндетті)
- `YANDEX_MAPKIT_API_KEY` — Yandex MapKit кілті (қазір қолданылмайды, болашақ үшін)

### 2. Xcode-да ашу

1. Xcode → File → New → Project → iOS App
2. Product Name: `Janarym`
3. Bundle Identifier: `com.example.Janarym`
4. Interface: SwiftUI, Language: Swift
5. Xcode жасаған бастапқы файлдарды (`ContentView.swift`, `JanarymApp.swift`) жойыңыз
6. Осы репозиторийдегі `Janarym/` папкасын Xcode проектіне drag & drop арқылы қосыңыз
7. Info.plist мәндерін project settings → Info → Custom iOS Target Properties-ке қосыңыз
8. `Secrets.plist` файлын проектке қосыңыз (Copy items if needed)

### 3. Project Settings

- **iOS Deployment Target:** 16.0
- **Supported Orientations:** Portrait Only
- **Info.plist:** Camera және Microphone usage descriptions қосылған

### 4. Құрылғыда іске қосу

Нағыз iPhone-да іске қосыңыз (камера мен микрофон симуляторда толық жұмыс істемейді).

## Архитектура

```
Janarym/
├── App/                          # App entry point, root view, lifecycle
├── Core/                         # Config, enums, utilities
├── Features/
│   ├── Assistant/                # Coordinator and Gemini voice flow
│   ├── Camera/                   # Camera service and preview
│   ├── Modes/                    # Modes bottom sheet
│   └── Permissions/              # Permission manager and UI
├── Services/
│   ├── Gemini/                   # Gemini Live WebSocket voice service
│   └── Speech/                   # TTS service
└── Resources/                    # Info.plist, Secrets
```

## Жұмыс принципі

1. Қосымша ашылғанда камера фон ретінде көрсетіледі
2. Пайдаланушы Gemini батырмасын бір рет басып, жазуды бастайды
3. Екінші рет басқанда аудио Gemini Live сессиясына жіберіледі
4. Gemini аудио жауап берсе, ол тікелей ойнатылады
5. Егер тек мәтін келсе, жауап AVSpeechSynthesizer арқылы айтылады
6. Жауап аяқталғанда ассистент қайтадан күту режиміне өтеді

## iOS шектеулері

- Gemini Live үшін тұрақты интернет байланысы керек
- Симуляторда камера мен микрофон толық жұмыс істемейді — нағыз құрылғыда тестілеңіз
