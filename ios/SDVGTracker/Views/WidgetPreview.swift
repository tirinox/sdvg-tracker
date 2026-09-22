import SDVGCore
import SwiftUI

/// Shows the widget layouts with real data, at their real sizes — useful while designing them
/// and when the system widget gallery is unavailable.
struct WidgetPreviewScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter: WidgetFilter = .all

    var body: some View {
        let _ = model.revision
        let snapshot = try? model.store.widgetSnapshot(now: model.now, filter: filter)
        ScrollView {
            VStack(spacing: 18) {
                Picker("Что показывать", selection: $filter) {
                    Text("Всё").tag(WidgetFilter.all)
                    Text("Задачи").tag(WidgetFilter.tasks)
                    Text("Рутины").tag(WidgetFilter.routines)
                }
                .pickerStyle(.segmented)

                tile("Маленький", width: 158, height: 158) { HomeWidgetBody(snapshot: snapshot, size: .small) }
                tile("Средний", width: 338, height: 158) { HomeWidgetBody(snapshot: snapshot, size: .medium) }
                tile("Большой", width: 338, height: 354) { HomeWidgetBody(snapshot: snapshot, size: .large) }
                HStack(alignment: .top, spacing: 12) {
                    tile("Кольцо", width: 72, height: 72) { LockWidgetBody(snapshot: snapshot, size: .circular) }
                    tile("Прямоугольник", width: 160, height: 72) { LockWidgetBody(snapshot: snapshot, size: .rectangular) }
                }
                tile("Строка", width: 240, height: 28) { LockWidgetBody(snapshot: snapshot, size: .inline) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Виджеты")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, width: CGFloat, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 6) {
            content()
                .padding(12)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
