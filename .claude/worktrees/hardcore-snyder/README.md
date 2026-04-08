# Janarym — Дауыстық AI Ассистент

Қазақша, орысша және ағылшынша жұмыс істейтін дауыстық AI-ассистент.

## Жылдам бастау

### 1. Secrets.plist құру

`Janarym/Resources/Secrets.example.plist` файлын `Janarym/Resources/Secrets.plist` деп көшіріп, кілттерді толтырыңыз:

```bash
cp Janarym/Resources/Secrets.example.plist Janarym/Resources/Secrets.plist
```

Қажетті кілттер:
- `OPENAI_API_KEY` — OpenAI API кілті (міндетті)
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
- **Info.plist:** Camera, Microphone, Speech Recognition usage descriptions қосылған

### 4. Құрылғыда іске қосу

Нағыз iPhone-да іске қосыңыз (камера мен микрофон симуляторда толық жұмыс істемейді).

## Архитектура

```
Janarym/
├── App/                          # App entry point, root view, lifecycle
├── Core/                         # Config, enums, utilities
├── Features/
│   ├── Assistant/                # Coordinator, wake word, recorder, conversation
│   ├── Camera/                   # Camera service and preview
│   ├── Modes/                    # Modes bottom sheet
│   └── Permissions/              # Permission manager and UI
├── Services/
│   ├── OpenAI/                   # Whisper + GPT REST clients
│   └── Speech/                   # TTS service
└── Resources/                    # Info.plist, Secrets
```

## Жұмыс принципі

1. Қосымша ашылғанда камера фон ретінде көрсетіледі
2. Wake word listener **«Жанарым»** сөзін тыңдайды
3. Wake word анықталғанда — пайдаланушы командасы жазылады
4. Аудио OpenAI Whisper API-ға жіберіледі (STT)
5. Мәтін GPT-4o-mini-ге жіберіледі
6. Жауап AVSpeechSynthesizer арқылы айтылады
7. TTS аяқталғанда — қайтадан wake word тыңдайды

## iOS шектеулері

- Wake word тек қосымша foreground-да болғанда жұмыс істейді (iOS шектеуі)
- `kk-KZ` locale SFSpeechRecognizer-де кейбір құрылғыларда қолжетімсіз болуы мүмкін, бұл жағдайда `ru-RU` fallback қолданылады
- Симуляторда камера мен микрофон толық жұмыс істемейді — нағыз құрылғыда тестілеңіз
