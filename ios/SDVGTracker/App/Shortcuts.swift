import AppIntents

/// App Shortcuts: shown in Spotlight under the app and answered by Siri.
struct SDVGShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowTodayIntent(),
            phrases: [
                "Задачи в \(.applicationName)",
                "Что сегодня в \(.applicationName)",
                "Открой \(.applicationName)",
            ],
            shortTitle: "Задачи на сегодня",
            systemImageName: "sparkles")
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Новая задача в \(.applicationName)",
                "Добавь задачу в \(.applicationName)",
            ],
            shortTitle: "Новая задача",
            systemImageName: "plus.circle")
    }
}

/// Opens the app on the "Now" screen.
struct ShowTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Задачи на сегодня"
    static let description = IntentDescription("Открывает SDVG на экране «Сейчас».")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.tab = .now
        return .result()
    }
}

/// Opens the app with an empty task for today.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Новая задача"
    static let description = IntentDescription("Открывает SDVG с новой задачей на сегодня.")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.tab = .now
        model.openTask(nil)
        return .result()
    }
}
