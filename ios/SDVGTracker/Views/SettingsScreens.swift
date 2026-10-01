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
        TextField(tr("Адрес сервера", "Server address"), text: $url)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        SecureField(tr("Токен — API_TOKEN из .env", "Token: API_TOKEN from .env"), text: $token)
        Button {
            checking = true
            Task {
                state = await model.connect(baseURL: url, token: token)
                checking = false
                if state == .ok { onConnected() }
            }
        } label: {
            HStack {
                Text(checking ? tr("Проверяю…", "Checking…") : tr("Подключить", "Connect"))
                if state == .ok { Spacer(); Text(tr("Подключено ✓", "Connected ✓")).foregroundStyle(Palette.ok) }
            }
        }
        .disabled(url.isEmpty || token.isEmpty || checking)
        .onAppear { if url.isEmpty { url = model.baseURL } }
        switch state {
        case .badToken: Text(tr("Неверный токен — проверьте значение в .env.", "Wrong token. Check the value in .env.")).foregroundStyle(Palette.danger)
        case .offline: Text(tr("Сервер не отвечает. Он запущен, и телефон в той же сети?", "The server isn’t responding. Is it running, and is the phone on the same network?")).foregroundStyle(Palette.danger)
        case .badURL: Text(tr("Адрес должен начинаться с http:// или https://", "The address must start with http:// or https://")).foregroundStyle(Palette.danger)
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
                    Text(tr("Трекер работает и без сети — всё хранится на телефоне. Чтобы задачи были одинаковыми на телефоне и компьютере, подключите свой сервер.",
                             "The tracker works offline too: everything is stored on your phone. To keep the same tasks on your phone and computer, connect your own server."))
                }
                SwiftUI.Section {
                    ConnectForm { Task { try? await Task.sleep(for: .seconds(0.8)); model.showWelcome = false } }
                } header: {
                    Text(tr("Сервер", "Server"))
                } footer: {
                    Text(tr("Адрес компьютера, где запущен make up, например http://192.168.1.10:8420. Токен — API_TOKEN из файла .env.",
                             "The address of the computer running make up, e.g. http://192.168.1.10:8420. The token is API_TOKEN from the .env file."))
                }
                SwiftUI.Section {
                    Button(tr("Пока без сервера", "No server for now")) { model.skipOnboarding() }
                }
            }
            .navigationTitle(tr("Добро пожаловать 👋", "Welcome 👋"))
        }
        .interactiveDismissDisabled()
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(ServerChangePrompt.self) private var prompt: ServerChangePrompt?

    var body: some View {
        let _ = model.revision
        let s = model.settings
        let pending = (try? model.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }) ?? 0
        let rejected = (try? model.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM rejected") }) ?? 0
        Form {
            SwiftUI.Section {
                Picker(tr("Язык", "Language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    Text(tr("Как в системе", "System default")).tag(LanguagePreference.system)
                    Text("Русский").tag(LanguagePreference.ru)
                    Text("English").tag(LanguagePreference.en)
                }
            } header: {
                Text(tr("Язык", "Language"))
            } footer: {
                Text(tr("Только на этом устройстве.", "This device only."))
            }
            SwiftUI.Section {
                ConnectForm()
            } header: {
                Text(tr("Синхронизация", "Sync"))
            } footer: {
                Text(tr("Приложение работает и без сервера. Адрес — компьютер, где запущен make up (например, http://192.168.1.10:8420).",
                         "The app works without a server too. The address is the computer running make up (e.g. http://192.168.1.10:8420)."))
            }
            SwiftUI.Section {
                LabeledContent(tr("Состояние", "Status"), value: stateText)
                LabeledContent(tr("Последняя синхронизация", "Last sync"), value: model.syncStatus.lastSyncAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.current.locale)) ?? "—")
                LabeledContent(tr("Ждут отправки", "Waiting to send"), value: "\(pending ?? 0)")
                if (rejected ?? 0) > 0 { LabeledContent(tr("Отклонены сервером", "Rejected by the server"), value: "\(rejected ?? 0)") }
                if model.syncStatus.state == .serverChanged, let prompt {
                    Button(tr("Решить, что делать с данными…", "Decide what to do with the data…")) { prompt.ask() }
                } else {
                    Button(tr("Синхронизировать сейчас", "Sync now")) { model.syncNow() }
                }
            }
            SwiftUI.Section {
                Toggle(tr("Показывать «сделано из всего»", "Show “done out of total”"), isOn: Binding(
                    get: { s.showDayTotal },
                    set: { v in model.perform { try $0.updateSettings(["show_day_total": .bool(v)]) } }))
                NavigationLink(tr("Как выглядят виджеты", "Widget preview")) { WidgetPreviewScreen() }
            } header: {
                Text(tr("Вид", "Appearance"))
            } footer: {
                Text(tr("Без общего числа виджеты и экран «Сейчас» показывают только количество сделанного.",
                         "Without the total, the widgets and the Now screen show only how much is done."))
            }
            SwiftUI.Section {
                stepper(tr("День начинается в", "Day starts at"), s.dayStartHour, 0...12, "day_start_hour")
                stepper(tr("Утро с", "Morning from"), s.partMorningFrom, 0...23, "part_morning_from")
                stepper(tr("День с", "Afternoon from"), s.partDayFrom, 0...23, "part_day_from")
                stepper(tr("Вечер с", "Evening from"), s.partEveningFrom, 0...23, "part_evening_from")
                Stepper(tr("Стрик: минимум дел — \(s.streakMinDone)", "Streak: at least \(s.streakMinDone) done a day"), value: binding(s.streakMinDone, "streak_min_done"), in: 1...50)
            } header: {
                Text(tr("День", "Day"))
            } footer: {
                Text(tr("После полуночи и до начала дня всё ещё считается «вчера» и «вечер».",
                         "From midnight until the day starts, it still counts as “yesterday” and “evening”."))
            }
            SwiftUI.Section {
                Stepper(
                    s.routineWarnBelow == 0 ? tr("Не предупреждать", "Don’t warn") : tr("Предупреждать ниже \(s.routineWarnBelow)\u{00A0}%", "Warn below \(s.routineWarnBelow)%"),
                    value: binding(s.routineWarnBelow, "routine_warn_below"), in: 0...100, step: 5)
            } header: {
                Text(tr("Рутины", "Routines"))
            } footer: {
                Text(tr("Выполняемость рутины — какая доля её дней за последние 30 выполнена (у новой — с первого выполнения). Дни, пропущенные кнопкой «Пропуск», не в счёт, сегодняшний — только когда сделан. Ниже порога рутина помечается как пропускаемая.",
                         "A routine’s completion rate is the share of its days done over the last 30 (for a new one, since it was first done). Days marked “Skip” don’t count, and today counts only once it’s done. Below the threshold, the routine is marked as being skipped."))
            }
        }
        .navigationTitle(tr("Настройки", "Settings"))
    }

    private var stateText: String {
        switch model.syncStatus.state {
        case .idle: tr("синхронизировано", "synced")
        case .syncing: tr("синхронизация…", "syncing…")
        case .offline: tr("сервер недоступен — работаем офлайн", "server unreachable, working offline")
        case .unauthorized: tr("неверный токен", "wrong token")
        case .unconfigured: tr("сервер не подключён", "no server connected")
        case .serverChanged: tr("на паузе: данные на сервере сменились", "paused: the server’s data changed")
        case .error: tr("ошибка: \(model.syncStatus.error ?? "")", "error: \(model.syncStatus.error ?? "")")
        }
    }

    private func stepper(_ label: String, _ value: Int, _ range: ClosedRange<Int>, _ key: String) -> some View {
        Stepper("\(label) \(value):00", value: binding(value, key), in: range)
    }

    private func binding(_ value: Int, _ key: String) -> Binding<Int> {
        Binding(get: { value }, set: { v in model.perform { try $0.updateSettings([key: .int(v)]) } })
    }
}
