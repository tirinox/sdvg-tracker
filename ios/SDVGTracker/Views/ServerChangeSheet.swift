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
                        ? tr("Задачи есть и на этом телефоне, и на сервере. Синхронизация на паузе, пока вы не решите, что делать с данными.",
                             "There are tasks both on this phone and on the server. Sync is paused until you decide what to do with the data.")
                        : tr("Базу на сервере пересоздали, или это другой сервер. Синхронизация на паузе, пока вы не решите, что делать с данными.",
                             "The server’s database was recreated, or this is a different server. Sync is paused until you decide what to do with the data."))
                }
                SwiftUI.Section {
                    LabeledContent(tr("На сервере", "On the server"), value: describe(change.server))
                    LabeledContent(tr("На этом телефоне", "On this phone"), value: describe(change.local))
                }
                SwiftUI.Section {
                    choice(tr("Взять данные сервера", "Take the server’s data"),
                           tr("Данные этого телефона удалятся, загрузятся серверные.", "This phone’s data will be deleted and the server’s loaded.")) {
                        try await model.sync.takeServerData()
                    }
                    choice(tr("Объединить", "Merge"), tr("Данные этого телефона добавятся к серверным.", "This phone’s data will be added to the server’s.")) {
                        try await model.sync.mergeWithServer()
                    }
                }
            }
            .disabled(busy)
            .navigationTitle(change.kind == .first ? tr("На сервере уже есть данные", "The server already has data") : tr("Данные на сервере сменились", "The server’s data changed"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Позже", "Later")) { dismiss() } }
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
        if c.isEmpty { return tr("пусто", "empty") }
        return trn(c.task, ru: ("задача", "задачи", "задач"), en: ("task", "tasks")) + " · "
            + trn(c.routine, ru: ("рутина", "рутины", "рутин"), en: ("routine", "routines"))
    }
}
