import SDVGCore
import SwiftUI

/// Server address + token form, shared by the welcome sheet and settings.
struct ConnectForm: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""
    @State private var state: ConnectResult?
    @State private var checking = false
    var onConnected: () -> Void = {}

    var body: some View {
        TextField("Адрес сервера", text: $url)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        SecureField("Токен — API_TOKEN из .env", text: $token)
        Button {
            checking = true
            Task {
                state = await model.connect(baseURL: url, token: token)
                checking = false
                if state == .ok { onConnected() }
            }
        } label: {
            HStack {
                Text(checking ? "Проверяю…" : "Подключить")
                if state == .ok { Spacer(); Text("Подключено ✓").foregroundStyle(Palette.ok) }
            }
        }
        .disabled(url.isEmpty || token.isEmpty || checking)
        .onAppear { if url.isEmpty { url = model.baseURL } }
        switch state {
        case .badToken: Text("Неверный токен — проверьте значение в .env.").foregroundStyle(Palette.danger)
        case .offline: Text("Сервер не отвечает. Он запущен, и телефон в той же сети?").foregroundStyle(Palette.danger)
        case .badURL: Text("Адрес должен начинаться с http:// или https://").foregroundStyle(Palette.danger)
        default: EmptyView()
        }
    }
}

struct WelcomeScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    Text("Трекер работает и без сети — всё хранится на телефоне. Чтобы задачи были одинаковыми на телефоне и компьютере, подключите свой сервер.")
                }
                SwiftUI.Section {
                    ConnectForm { Task { try? await Task.sleep(for: .seconds(0.8)); model.showWelcome = false } }
                } header: {
                    Text("Сервер")
                } footer: {
                    Text("Адрес компьютера, где запущен make up, например http://192.168.1.10:8420. Токен — API_TOKEN из файла .env.")
                }
                SwiftUI.Section {
                    Button("Пока без сервера") { model.skipOnboarding() }
                }
            }
            .navigationTitle("Добро пожаловать 👋")
        }
        .interactiveDismissDisabled()
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let s = model.settings
        let pending = (try? model.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }) ?? 0
        let rejected = (try? model.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM rejected") }) ?? 0
        Form {
            SwiftUI.Section {
                ConnectForm()
            } header: {
                Text("Синхронизация")
            } footer: {
                Text("Приложение работает и без сервера. Адрес — компьютер, где запущен make up (например, http://192.168.1.10:8420).")
            }
            SwiftUI.Section {
                LabeledContent("Состояние", value: stateText)
                LabeledContent("Последняя синхронизация", value: model.syncStatus.lastSyncAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                LabeledContent("Ждут отправки", value: "\(pending ?? 0)")
                if (rejected ?? 0) > 0 { LabeledContent("Отклонены сервером", value: "\(rejected ?? 0)") }
                Button("Синхронизировать сейчас") { model.syncNow() }
            }
            SwiftUI.Section {
                stepper("День начинается в", s.dayStartHour, 0...12, "day_start_hour")
                stepper("Утро с", s.partMorningFrom, 0...23, "part_morning_from")
                stepper("День с", s.partDayFrom, 0...23, "part_day_from")
                stepper("Вечер с", s.partEveningFrom, 0...23, "part_evening_from")
                Stepper("Стрик: минимум дел — \(s.streakMinDone)", value: binding(s.streakMinDone, "streak_min_done"), in: 1...50)
            } header: {
                Text("День")
            } footer: {
                Text("После полуночи и до начала дня всё ещё считается «вчера» и «вечер».")
            }
        }
        .navigationTitle("Настройки")
    }

    private var stateText: String {
        switch model.syncStatus.state {
        case .idle: "синхронизировано"
        case .syncing: "синхронизация…"
        case .offline: "сервер недоступен — работаем офлайн"
        case .unauthorized: "неверный токен"
        case .unconfigured: "сервер не подключён"
        case .error: "ошибка: \(model.syncStatus.error ?? "")"
        }
    }

    private func stepper(_ label: String, _ value: Int, _ range: ClosedRange<Int>, _ key: String) -> some View {
        Stepper("\(label) \(value):00", value: binding(value, key), in: range)
    }

    private func binding(_ value: Int, _ key: String) -> Binding<Int> {
        Binding(get: { value }, set: { v in model.perform { try $0.updateSettings([key: .int(v)]) } })
    }
}
