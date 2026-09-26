import SDVGCore
import SwiftUI

/// Whether the question about another data set on the server was put off ("Решить позже").
@MainActor @Observable
final class ServerChangePrompt {
    /// The server the user put off; the sheet shows again for any other, or when asked from settings.
    var dismissed: String?

    func ask() { dismissed = nil }
}

extension View {
    /// Shows ServerChangeSheet while sync is paused on another data set.
    func serverChangeSheet() -> some View { modifier(ServerChangeModifier()) }
}

private struct ServerChangeModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var prompt = ServerChangePrompt()

    func body(content: Content) -> some View {
        content
            .environment(prompt)
            .sheet(item: Binding(
                get: { model.syncStatus.serverChange.flatMap { $0.serverID == prompt.dismissed ? nil : $0 } },
                set: { if $0 == nil { prompt.dismissed = model.syncStatus.serverChange?.serverID } }
            )) { ServerChangeSheet(change: $0) }
    }
}

/// Sync is paused: the server holds another data set, and merging into it is the user's call.
struct ServerChangeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let change: ServerChange
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    Text(change.kind == .first
                        ? "Задачи есть и на этом телефоне, и на сервере. Синхронизация на паузе, пока вы не решите, что делать с данными."
                        : "Базу на сервере пересоздали, или это другой сервер. Синхронизация на паузе, пока вы не решите, что делать с данными.")
                }
                SwiftUI.Section {
                    LabeledContent("На сервере", value: describe(change.server))
                    LabeledContent("На этом телефоне", value: describe(change.local))
                }
                SwiftUI.Section {
                    choice("Взять данные сервера", "Данные этого телефона удалятся, загрузятся серверные.") {
                        try await model.sync.takeServerData()
                    }
                    choice("Объединить", "Данные этого телефона добавятся к серверным.") {
                        try await model.sync.mergeWithServer()
                    }
                }
            }
            .disabled(busy)
            .navigationTitle(change.kind == .first ? "На сервере уже есть данные" : "Данные на сервере сменились")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Позже") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func choice(_ title: String, _ detail: String, _ action: @escaping () async throws -> Void) -> some View {
        Button {
            busy = true
            Task {
                do { try await action() } catch { print("server change failed:", error) }
                busy = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func describe(_ c: SyncCounts) -> String {
        if c.isEmpty { return "пусто" }
        return "\(c.task) \(plural(c.task, "задача", "задачи", "задач")) · \(c.routine) \(plural(c.routine, "рутина", "рутины", "рутин"))"
    }
}
