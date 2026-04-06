# Janarym — AI Voice Assistant

**Enactus AITUC** жобасы | iOS Swift қосымшасы

Қазақша, орысша және ағылшынша жұмыс істейтін дауыстық AI-ассистент. Google Gemini Live API негізінде жасалған.

---

## Мүмкіндіктер

- **Дауыстық ояту** — «Жанарым» сөзімен іске қосу
- **Көп тілді** — қазақша / орысша / ағылшынша
- **Камера интеграциясы** — қоршаған ортаны талдау
- **Firebase Auth** — пайдаланушы аутентификациясы
- **Mentor/Admin Dashboard** — басқару панелі
- **Subscription** — жазылым жүйесі (StoreKit)
- **SOS менеджері** — авариялық хабарлама жүйесі

---

## Жылдам бастау

### 1. Secrets.plist жасау

```bash
cp Janarym/Resources/Secrets.example.plist Janarym/Resources/Secrets.plist
```

`Secrets.plist` ішіне өз кілттеріңізді қосыңыз:

| Кілт | Сипаттама |
|------|-----------|
| `GEMINI_API_KEY` | Google Gemini API кілті (міндетті) |
| `YANDEX_MAPKIT_API_KEY` | Yandex MapKit (болашақ үшін) |

### 2. GoogleService-Info.plist қосу

Firebase консолінен жүктеп алып, `Janarym/App/` папкасына қойыңыз:

```
Janarym/App/GoogleService-Info.plist
```

> **Ескерту:** Бұл файл `.gitignore`-да тіркелген — репозиторийге түспейді.

### 3. Xcode-да ашу

```bash
open Janarym.xcodeproj
```

- **iOS Deployment Target:** 16.0
- **Bundle Identifier:** `com.example.Janarym-AI`
- **Interface:** SwiftUI, Language: Swift

### 4. Нағыз құрылғыда іске қосу

Камера мен микрофон симуляторда жұмыс істемейді — iPhone-да тестілеңіз.

---

## Архитектура

```
Janarym/
├── App/                    # Entry point, lifecycle, root view
├── Core/                   # AppConfig, enums, utilities
├── Features/
│   ├── Assistant/          # AI coordinator, voice input
│   ├── Auth/               # Login, registration, approval
│   ├── Camera/             # Camera service and preview
│   ├── Dashboard/          # Admin and Mentor dashboards
│   ├── Modes/              # Mode selection sheet
│   ├── Onboarding/         # User onboarding flow
│   ├── Permissions/        # iOS permission management
│   └── Subscription/       # Paywall and StoreKit
├── Services/
│   ├── Firebase/           # Auth, Firestore, Storage
│   ├── Gemini/             # Gemini Live API client
│   ├── Memory/             # Conversation memory
│   ├── Presence/           # User presence and SOS
│   ├── Speech/             # TTS (AVSpeechSynthesizer)
│   └── Subscription/       # StoreKit manager
└── Resources/              # Info.plist, Secrets.example.plist
```

---

## Жұмыс принципі

1. Қосымша ашылғанда камера фонда жұмыс істейді
2. **«Жанарым»** wake word тыңдалады
3. Wake word анықталғанда дауыс жазылады
4. Аудио Gemini Live API-ға жіберіледі
5. AI жауабы AVSpeechSynthesizer арқылы айтылады
6. Жауаптан кейін — қайтадан wake word режиміне өтеді

---

## iOS шектеулері

- Wake word тек foreground режимінде жұмыс істейді (iOS шектеуі)
- `kk-KZ` locale кейбір құрылғыларда жоқ болуы мүмкін — `ru-RU` fallback қолданылады
- Нағыз iPhone қажет (камера + микрофон)

---

## Жоба туралы

Бұл жоба **Enactus AITUC** студенттік ұйымының бастамасы. Мақсаты — қазақ тіліндегі AI ассистент технологиясын дамыту.

**Ұйым:** [Enactus AITUC](https://github.com/Enactus-AITUC)
