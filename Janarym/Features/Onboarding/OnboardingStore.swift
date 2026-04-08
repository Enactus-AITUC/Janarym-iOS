import Foundation
import Combine
import SwiftUI

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
    var responseLength: ResponseLength = .short
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
        var isKazakh: Bool { self == .kazakh }
        var detectedLanguage: DetectedLanguage {
            switch self {
            case .kazakh: return .kazakh
            case .russian: return .russian
            }
        }
        var assistantLanguageName: String {
            switch self {
            case .kazakh: return "Kazakh"
            case .russian: return "Russian"
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
            case .slow:   return 0.9
            case .normal: return 1.1
            case .fast:   return 1.3
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
        persistProfile()
        UserDefaults.standard.set(true, forKey: completedKey)
        isCompleted = true
    }

    func updateLanguage(_ language: UserProfile.Language) {
        guard profile.language != language else { return }
        var updated = profile
        updated.language = language
        profile = updated
        persistProfile()
    }

    func reset() {
        profile = UserProfile()
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
        isCompleted = false
    }

    var currentLanguage: UserProfile.Language { profile.language }
    var isKazakh: Bool { currentLanguage.isKazakh }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    // MARK: - Dynamic system prompt

    var systemPrompt: String {
        let p  = profile
        let kk = p.language == .kazakh
        let mismatchMessage = AppText.languageMismatchPrompt(for: p.language)

        let langRule = kk
            ? "МАҢЫЗДЫ: ТЕК ҚАЗАҚША сұранысты қабылда және ТЕК ҚАЗАҚША жауап бер. Орысша немесе ағылшынша ҚАБЫЛДАМА, ЖАЗБА."
            : "ВАЖНО: Принимай ТОЛЬКО русскую речь и отвечай ТОЛЬКО по-русски. Казахский и английский НЕ ПРИНИМАТЬ и НЕ ИСПОЛЬЗОВАТЬ."

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
            lengthRule = kk ? "Әдетте 2 қысқа сөйлеммен жауап бер. Бірінші сөйлемде негізгі жауапты айт, екінші сөйлемде бір нақты пайдалы деталь не жақын объектіні қос."
                            : "Обычно отвечай 2 короткими предложениями. В первом дай прямой ответ, во втором добавь одну полезную конкретную деталь или ближайший объект."
        case .medium:
            lengthRule = kk ? "Әдетте 2 қысқа сөйлеммен жауап бер, тек қажет болса сәл кеңейт."
                            : "Обычно отвечай 2 короткими предложениями, расширяй ответ только если это действительно нужно."
        case .long:
            lengthRule = kk ? "Негізгі жауап бәрібір 2 түсінікті сөйлемнен басталсын, содан кейін ғана қажет болса толықтыр."
                            : "Основной ответ всё равно начинай с 2 понятных предложений, и только потом при необходимости расширяй."
        }

        let visionRule = kk
            ? "Әрбір сұрақпен бірге пайдаланушының камерасынан түсірілген сурет жіберілуі мүмкін. Сен сол суретті КӨРЕ АЛАСЫҢ. 'Алдымда не тұр?', 'бұл не?', 'қарашы' деген сұрақтарға суретті талдап нақты жауап бер. Сурет анық болмаса, оны тура айт."
            : "К каждому вопросу может прилагаться снимок с камеры пользователя. Ты МОЖЕШЬ ВИДЕТЬ этот снимок. На вопросы 'что передо мной?', 'что это?', 'посмотри' — анализируй снимок и отвечай конкретно. Если кадр неясный, скажи об этом прямо."

        let base = kk ? """
Сен — Жанарым, нашар көретін немесе мүлде көрмейтін адамдарға арналған дауыстық AI-ассистентсің.\(nameClause)
\(langRule)
Егер пайдаланушы басқа тілде сөйлесе, дәл былай жауап бер: \(mismatchMessage)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Тек нақты сұрақ туралы жауап бер. Сұрамаған ешбір қосымша ақпарат, кеңес, жалғасты сөз БЕРМE.
Жауапты ешқашан "Жарайды", "Кемел", "Сәлем", "Мен дайынмын", "Міне", "Бастайық" деген кіріспелермен БАСТАМА — тікелей жауапқа кір.
Ешқашан өзіңнің не жасап жатқаныңды түсіндірме ("Суретті талдап жатырмын", "Сізге жауап береін" — БҰЛАЙ ДЕМА).
Пайдаланушы жай сөз айтса (мысалы "сәлем") — қысқа, табиғи жауап бер, ұзақ таныстыру жасама.
Сөйлемнің соңын жұтып қойма, сөздерді қысқартпа, объект атауларын толық айт.
Markdown, тізімдер, жұлдызшалар ПАЙДАЛАНБА — жауап TTS үшін. Тек табиғи сөйлеу.
""" : """
Ты — Жанарым, голосовой AI-ассистент для людей с плохим зрением или полной потерей зрения.\(nameClause)
\(langRule)
Если пользователь говорит на другом языке, ответь точно так: \(mismatchMessage)
\(formalClause)
\(lengthRule)
\(visionRule)\(hobbyClause)
Отвечай строго по теме запроса. Никакой лишней информации, советов, продолжений, которые не просили.
Никогда не начинай ответ с "Конечно!", "Хорошо!", "Отлично!", "Разумеется!", "Здравствуйте" — сразу переходи к сути.
Никогда не объясняй что ты делаешь ("Анализирую изображение", "Сейчас отвечу" — НЕ ГОВОРИ ТАК).
Если пользователь просто поздоровался — ответь коротко и естественно, без длинного представления.
Не обрывай конец фразы, не проглатывай последние слова, произноси названия объектов полностью.
Не используй markdown, списки и звёздочки — ответ предназначен для TTS. Говори естественно.
"""
        return base
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
        }
    }

    func assistantPrompt(for mode: AppMode) -> String {
        let modePrompt = modePrompt(for: mode)
        guard !modePrompt.isEmpty else { return systemPrompt }
        return "\(systemPrompt)\n\(modePrompt)"
    }
}

enum AppText {
    static func pick(_ kk: String, _ ru: String, language: UserProfile.Language = OnboardingStore.shared.currentLanguage) -> String {
        language == .kazakh ? kk : ru
    }

    static func languageMismatchPrompt(for language: UserProfile.Language) -> String {
        pick(
            "Қайталап айтыңыз, тек қазақша сөйлеп сұраңыз.",
            "Повторите, пожалуйста, только по-русски.",
            language: language
        )
    }
}

extension UserRole {
    var label: String {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .developer:
            return AppText.pick("Әзірлеуші", "Разработчик", language: language)
        case .admin:
            return AppText.pick("Әкімші", "Админ", language: language)
        case .mentor:
            return AppText.pick("Ментор", "Ментор", language: language)
        case .parent:
            return AppText.pick("Ата-ана", "Родитель", language: language)
        case .member:
            return AppText.pick("Мүше", "Участник", language: language)
        }
    }
}

extension ApplicationStatus {
    var label: String {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .pending:
            return AppText.pick("Күтуде", "Ожидание", language: language)
        case .approved:
            return AppText.pick("Бекітілді", "Одобрено", language: language)
        case .rejected:
            return AppText.pick("Қабылданбады", "Отклонено", language: language)
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
