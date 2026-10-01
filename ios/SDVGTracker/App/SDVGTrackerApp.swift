import AppIntents
import BackgroundTasks
import CoreSpotlight
import SDVGCore
import SwiftUI
import WidgetKit

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
        // App Shortcuts (Shortcuts.swift) act on the same model.
        AppDependencyManager.shared.add(dependency: model)

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
            LocalizedRoot()
                .environment(model)
                .onAppear { model.start() }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        model.open(spotlightID: id)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.syncNow()
            case .background:
                // A check still waiting for its write must not be lost if the app is suspended.
                model.flushPendingDone()
                Self.scheduleRefresh()
                // Pick up everything done in the app (and pulled by sync) on the home screen.
                WidgetCenter.shared.reloadAllTimelines()
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

/// Rebuilds the whole view tree when the interface language changes, so every tr() is read again;
/// the selected tab and the rest of the state live in the model and survive.
private struct LocalizedRoot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.language
        RootView()
            .id(L10n.current)
            .environment(\.locale, L10n.current.locale)
    }
}
