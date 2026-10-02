import SDVGCore
import SwiftUI

/// The latest done mark, offered for undo.
struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    /// Row key from AppModel.doneKey.
    var key: String
    var text: String
}

/// Floats above the tab bar for a few seconds after a check.
struct UndoBar: View {
    @Environment(AppModel.self) private var model
    var toast: UndoToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
            Text(toast.text).lineLimit(1)
            Spacer(minLength: 0)
            Button { model.undo() } label: {
                Label(tr("Отменить", "Undo"), systemImage: "arrow.uturn.backward").font(.body.weight(.semibold))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.4)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}
