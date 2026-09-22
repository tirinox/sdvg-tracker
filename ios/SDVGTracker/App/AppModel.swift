import Foundation
import GRDB
import Network
import Observation
import SDVGCore

enum Tab: Hashable { case now, day, inbox, routines, settings }

enum EditorTarget: Identifiable {
    case task(id: String?, draft: TaskDraft)
    case routine(id: String?)

    var id: String {
        switch self {
        case .task(let id, _): "task:\(id ?? "new")"
        case .routine(let id): "routine:\(id ?? "new")"
        }
    }
}

enum ConnectResult { case ok, badToken, offline, badURL }

/// App-wide state: the local store, sync, the clock and what is being edited.
@MainActor @Observable
final class AppModel {
    let store: Store
    @ObservationIgnored private(set) var sync: SyncClient!

    var syncStatus = SyncStatus()
    var now: LocalDateTime = Dates.localNow()
    var settings = Settings()
    /// Bumped after every database change; screens re-read their models when it changes.
    var revision = 0
    var tab: Tab = .now
    var editor: EditorTarget?
    var showWelcome = false
    var dayDate: LocalDate?

    var today: LocalDate { Dates.logicalDay(now, dayStartHour: settings.dayStartHour) }

    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var notifyDebounce: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var lastToday: LocalDate?

    nonisolated static let baseURLKey = "sync_base_url"
    nonisolated static let onboardingKey = "onboarding_done"

    init(store: Store) {
        self.store = store
        let keychain = Keychain.shared
        sync = SyncClient(store: store, config: { [store] in
            let url = (try? store.meta(AppModel.baseURLKey))?.string ?? ""
            guard !url.isEmpty, let token = keychain.token() else { return nil }
            return SyncConfig(baseURL: url, token: token)
        }, onStatus: { status in
            Task { @MainActor [weak self] in self?.syncStatus = status }
        })
    }

    static func openStore() throws -> Store {
        let fm = FileManager.default
        // The App Group container is shared with the (future) widget extension.
        let dir = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.tirinox.sdvgtracker")
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try Store.open(path: dir.appendingPathComponent("sdvg.sqlite").path)
    }

    func start() {
        applyDebugLaunchConfig()
        settings = (try? store.settings()) ?? Settings()
        observation = DatabaseRegionObservation(tracking: .fullDatabase)
            .start(in: store.writer, onError: { print("observation failed:", $0) }) { [weak self] _ in
                Task { @MainActor in self?.databaseChanged() }
            }
        store.onLocalWrite { [weak self] in
            Task { @MainActor in self?.scheduleSync(after: 2) }
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        })
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.syncNow() } }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        tick()
        let configured = (try? store.meta(Self.baseURLKey))?.string?.isEmpty == false && Keychain.shared.token() != nil
        let onboarded = (try? store.meta(Self.onboardingKey))?.bool ?? false
        showWelcome = !configured && !onboarded
        syncNow()
    }

    private func tick() {
        now = Dates.localNow()
        if lastToday != today {
            lastToday = today
            // Open tasks from earlier days move to today, on start and whenever the day turns.
            perform { [today] in try $0.runRollover(today: today) }
        }
    }

    private func databaseChanged() {
        revision &+= 1
        settings = (try? store.settings()) ?? settings
        notifyDebounce?.cancel()
        notifyDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await Notifications.reschedule(store: self.store, now: self.now)
        }
    }

    func syncNow() {
        Task { await sync.sync() }
    }

    private func scheduleSync(after seconds: Double) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// Runs a store action; failures are logged, the UI re-reads from the database anyway.
    func perform(_ action: @escaping (Store) throws -> Void) {
        do { try action(store) } catch { print("action failed:", error) }
    }

    // MARK: connection

    var baseURL: String { (try? store.meta(Self.baseURLKey))?.string ?? "" }

    func connect(baseURL raw: String, token raw2: String) async -> ConnectResult {
        let url = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = raw2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let check = URL(string: url + "/api/auth/check"), check.scheme?.hasPrefix("http") == true else { return .badURL }
        var request = URLRequest(url: check, timeoutInterval: 6)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let code: Int
        do {
            code = try await urlSessionTransport(request).1
        } catch {
            return .offline
        }
        guard code == 200 else { return code == 401 ? .badToken : .offline }
        Keychain.shared.setToken(token)
        try? store.setMeta(Self.baseURLKey, .string(url))
        try? store.setMeta(Self.onboardingKey, true)
        syncNow()
        await Notifications.requestAuthorization()
        return .ok
    }

    func skipOnboarding() {
        try? store.setMeta(Self.onboardingKey, true)
        showWelcome = false
        Task { await Notifications.requestAuthorization() }
    }

    /// DEBUG builds only: preconfigure a (throwaway) test server from the launch environment,
    /// so automated runs never type a token into the UI.
    private func applyDebugLaunchConfig() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let url = env["SDVG_DEBUG_SERVER"], let token = env["SDVG_DEBUG_TOKEN"] {
            Keychain.shared.setToken(token)
            try? store.setMeta(Self.baseURLKey, .string(url))
            try? store.setMeta(Self.onboardingKey, true)
        }
        #endif
    }

    // MARK: editors

    func openTask(_ id: String?, draft: TaskDraft? = nil) {
        if let id, let t = try? store.get(.task, id).map(TaskRecord.init) {
            editor = .task(id: id, draft: TaskDraft(t))
        } else {
            editor = .task(id: nil, draft: draft ?? TaskDraft(date: today))
        }
    }

    func openRoutine(_ id: String?) { editor = .routine(id: id) }
}
