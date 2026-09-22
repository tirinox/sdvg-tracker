import BackgroundTasks
import SDVGCore
import SwiftUI

@main
struct SDVGTrackerApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "com.tirinox.sdvgtracker.sync"

    init() {
        let store: Store
        do {
            store = try AppModel.openStore()
        } catch {
            fatalError("Cannot open the database: \(error)")
        }
        let model = AppModel(store: store)
        _model = State(initialValue: model)

        // Periodic background sync; iOS decides the actual timing.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Self.scheduleRefresh()
            let work = Task { @MainActor in
                await model.sync.sync()
                task.setTaskCompleted(success: model.syncStatus.state == .idle)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.syncNow()
            case .background: Self.scheduleRefresh()
            default: break
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
