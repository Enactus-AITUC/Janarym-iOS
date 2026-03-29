import Foundation
import Combine

// MARK: - UserProfile

struct UserProfile: Codable {
    var language:       Language       = .kazakh
    var name:           String         = ""
    var formality:      Formality      = .formal
    var ageRange:       AgeRange       = .age26_35
    var occupation:     Occupation     = .other
    var city:           String         = ""
    var purpose:        Purpose        = .all
    var hobbies:        String         = ""
    var responseLength: ResponseLength = .medium
    var speechRate:     SpeechRate     = .normal

    // MARK: Enums

    enum Language: String, Codable, CaseIterable, Equatable {
        case kazakh = "kk"
        case russian = "ru"
        var displayName: String {
            switch self {
            case .kazakh:  return "Қазақша"
            case .russian: return "Орысша"
            }
        }
    }

    enum Formality: String, Codable, CaseIterable, Equatable {
        case formal, informal
        func display(_ lang: Language) -> String {
            switch (self, lang) {
            case (.formal,   .kazakh):  return "Сіз"
            case (.informal, .kazakh):  return "Сен"
            case (.formal,   .russian): return "Вы"
            case (.informal, .russian): return "ты"
            }
        }
    }

    enum AgeRange: String, Codable, CaseIterable, Equatable {
        case age18_25 = "18–25"
        case age26_35 = "26–35"
        case age36_50 = "36–50"
        case age50plus = "50+"
    }

    enum Occupation: String, Codable, CaseIterable, Equatable {
        case student, business, tech, medicine, other
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .student:  return "Студент"
                case .business: return "Бизнес"
                case .tech:     return "Технология"
                case .medicine: return "Медицина"
                case .other:    return "Өзге"
                }
            case .russian:
                switch self {
                case .student:  return "Студент"
                case .business: return "Бизнес"
                case .tech:     return "Технологии"
                case .medicine: return "Медицина"
                case .other:    return "Другое"
                }
            }
        }
    }

    enum Purpose: String, Codable, CaseIterable, Equatable {
        case daily, study, entertainment, all
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .daily:         return "Күнделікті сұрақтар"
                case .study:         return "Оқу / Жұмыс"
                case .entertainment: return "Ойын-сауық"
                case .all:           return "Барлығы"
                }
            case .russian:
                switch self {
                case .daily:         return "Повседневные вопросы"
                case .study:         return "Учёба / Работа"
                case .entertainment: return "Развлечения"
                case .all:           return "Всё"
                }
            }
        }
    }

    enum ResponseLength: String, Codable, CaseIterable, Equatable {
        case short, medium, long
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .short:  return "Қысқа (1–2 сөйлем)"
                case .medium: return "Орташа"
                case .long:   return "Толық"
                }
            case .russian:
                switch self {
                case .short:  return "Кратко (1–2 предл.)"
                case .medium: return "Умеренно"
                case .long:   return "Подробно"
                }
            }
        }
    }

    enum SpeechRate: String, Codable, CaseIterable, Equatable {
        case slow, normal, fast
        func display(_ lang: Language) -> String {
            switch lang {
            case .kazakh:
                switch self {
                case .slow:   return "Баяу"
                case .normal: return "Қалыпты"
                case .fast:   return "Жылдам"
                }
            case .russian:
                switch self {
                case .slow:   return "Медленно"
                case .normal: return "Обычно"
                case .fast:   return "Быстро"
                }
            }
        }
        var avRate: Float {
            switch self {
            case .slow:   return 0.42
            case .normal: return 0.50
            case .fast:   return 0.58
            }
        }
    }
}

// MARK: - OnboardingStore

final class OnboardingStore: ObservableObject {
    static let shared = OnboardingStore()

    @Published private(set) var isCompleted: Bool
    @Published var profile: UserProfile

    private let completedKey = "onboarding_v1_completed"
    private let profileKey   = "onboarding_v1_profile"

    private init() {
        isCompleted = UserDefaults.standard.bool(forKey: "onboarding_v1_completed")
        if let data    = UserDefaults.standard.data(forKey: "onboarding_v1_profile"),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        } else {
            profile = UserProfile()
        }
    }

    func complete(with p: UserProfile) {
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
        UserDefaults.standard.set(true, forKey: completedKey)
        isCompleted = true
    }

    func reset() {
        profile = UserProfile()
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        isCompleted = false
    }

    // MARK: - Dynamic system prompt

    var systemPrompt: String {
        let p  = profile
        let kk = p.language == .kazakh

        let langRule = kk
            ? "МАҢЫЗДЫ: ТЕК ҚАЗАҚША жауап бер. Орысша немесе ағылшынша ЖАЗБА."
            : "ВАЖНО: Отвечай ТОЛЬКО по-русски. Английский и казахский НЕ ИСПОЛЬЗОВАТЬ."

        let nameClause = p.name.isEmpty ? ""
            : kk ? " Пайдаланушының аты — \(p.name)."
                 : " Пользователя зовут \(p.name)."

        let formalClause = kk
            ? "Пайдаланушыға '\(p.formality.display(.kazakh))' деп жүгін."
            : "Обращайся к пользователю на '\(p.formality.display(.russian))'."

        // Хобби — тек сәйкес болса пайдалану, мәжбүрлемеу
        let hobbyClause = p.hobbies.isEmpty ? ""
            : kk ? "\nПайдаланушының қызығушылықтары: \(p.hobbies). Тек пайдаланушы өзі сол тақырыпты бастаса немесе сұраса ғана айт — басқа кезде мәжбүрлеп кіргізбе."
                 : "\nИнтересы пользователя: \(p.hobbies). Упоминай только если пользователь сам поднял тему — не вставляй насильно."

        let lengthRule: String
        switch p.responseLength {
        case .short:
            lengthRule = kk ? "Жауап 1–2 сөйлемнен аспасын."
                            : "Ответ — не более 1–2 предложений."
        case .medium:
            lengthRule = kk ? "Жауап орташа ұзындықта болсын."
                            : "Отвечай умеренно, без лишних деталей."
        case .long:
            lengthRule = kk ? "Толық жауап бере аласың."
                            : "Можно отвечать подробно, если нужно."
        }

        let visionRule = kk
            ? "Әрбір сұрақпен бірге пайдаланушының камерасынан түсірілген сурет жіберіледі. Сен сол суретті КӨРЕ АЛАСЫҢ. 'Алдымда не тұр?', 'бұл не?', 'қарашы' деген сұрақтарға суретті талдап нақты жауап бер. Сурет болмаса — сұрақ бойынша жауап бер."
            : "К каждому вопросу прилагается снимок с камеры пользователя. Ты МОЖЕШЬ ВИДЕТЬ этот снимок. На вопросы 'что передо мной?', 'что это?', 'посмотри' — анализируй снимок и отвечай конкретно. Если снимка нет — отвечай по контексту вопроса."

        let base = """
Сен — Жанарым, нашар көретін немесе мүлде көрмейтін адамдарға арналған дауыстық AI-ассистентсің.\(nameClause)
\(langRule)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Пайдаланушы не сұраса сол туралы жауап бер — өз тақырыбыңды мәжбүрлеп кіргізбе.
Markdown, тізімдер, жұлдызшалар ПАЙДАЛАНБА — жауап TTS үшін. Тек табиғи сөйлеу.
"""
        // Жад контексті — пайдаланушы сақтауды өтінген деректер
        let memoriesCtx = MemoryStore.shared.promptContext(kazakh: kk)

        return memoriesCtx.isEmpty ? base : base + "\n\n" + memoriesCtx
    }

    // MARK: - Mode-specific prompt addition

    func modePrompt(for mode: AppMode) -> String {
        let kk = profile.language == .kazakh
        switch mode {
        case .general:
            return ""  // базалық prompt жеткілікті

        case .navigation:
            return kk
                ? "Сен қазір НАВИГАЦИЯ режимінде жұмыс жасайсың. Пайдаланушыға орналасуын, жақын жерлерді, маршрутты анық дауыстық нұсқаулармен түсіндір. Солға, оңға, алға, артқа деп нақты бағыт бер."
                : "Ты в режиме НАВИГАЦИИ. Давай пользователю чёткие голосовые инструкции: налево, направо, прямо, назад. Указывай расстояния в метрах."

        case .security:
            return kk
                ? """
Сен қазір АЛАЯҚТЫҚҚА ҚАРСЫ режимінде жұмыс жасайсың. Камерадан көрінген нәрсені алаяқтық белгілері үшін талда:
- Жалған банкноттар: номиналды оқы, "Банк приколов", "сувенир", "образец" жазуларын іздес
- Жалған құжаттар: паспорт, куәлік, диплом, сертификат — мөр, қол, реквизиттерді тексер
- Күдікті QR кодтар мен сілтемелер
- Фишинг SMS/хабарламалар
- Жалған лотерея, жеңіс хабарламалары
Алаяқтық белгісі тапсаң — ДЕРЕУ ескерт. Таппасаң — "Алаяқтық белгісі байқалмады" де.
"""
                : """
Ты в режиме АНТИМОШЕННИЧЕСТВА. Анализируй изображение с камеры на признаки мошенничества:
- Фальшивые купюры: читай номинал, ищи надписи "Банк приколов", "сувенир", "образец"
- Поддельные документы: паспорт, удостоверение, диплом — проверяй печати, подписи
- Подозрительные QR-коды и ссылки
- Фишинговые SMS/сообщения
- Фальшивые лотереи, уведомления о "выигрыше"
Нашёл признак мошенничества — НЕМЕДЛЕННО предупреди. Если всё чисто — скажи "Признаков мошенничества не обнаружено".
"""

        case .shopping:
            return kk
                ? "Сен қазір САУДА режимінде жұмыс жасайсың. Камерадан өнімді тани: атауы, брендi, құрамы, срок годности, баға (егер көрінсе). Аллергендерді ерекше айт. Пайдаланушы салыстыруды сұраса — екі өнімнің айырмашылығын айт."
                : "Ты в режиме ПОКУПОК. Распознавай товары с камеры: название, бренд, состав, срок годности, цену (если видна). Обязательно выделяй аллергены. Если просят сравнить — объясни разницу."

        case .reading:
            return kk
                ? "Сен қазір ОҚЫТУ режимінде жұмыс жасайсың. Камерадан барлық мәтінді оқы: кітап, газет, мәзір, жапсырма, хабарландыру, форма. Мәтінді дәл, нақты, толық оқы — ештеңені өткізіп жібермe. Сан, дата, мекенжайды дауыстап айт."
                : "Ты в режиме ЧТЕНИЯ. Читай весь текст с камеры: книга, газета, меню, этикетка, объявление, форма. Читай точно, полностью — ничего не пропускай. Числа, даты, адреса произноси вслух."
        case .agent:
            return kk
                ? "Сен қазір АГЕНТ режимінде жұмыс жасайсың. Камерадан нақты уақытта не көрінсе соны 1-2 сөйлеммен қысқа сипатта. Светофор, жол белгілері, адамдар, кедергілер — бәрін атап өт."
                : "Ты в режиме АГЕНТА. Описывай в реальном времени что видно на камере в 1-2 предложениях. Светофор, знаки, люди, препятствия — указывай всё."
        }
    }
}
