import SDVGCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack { NowScreen() }
                .tabItem { Label("Сейчас", systemImage: "sparkles") }.tag(Tab.now)
            NavigationStack { DayScreen() }
                .tabItem { Label("День", systemImage: "list.bullet") }.tag(Tab.day)
            NavigationStack { InboxScreen() }
                .tabItem { Label("Входящие", systemImage: "tray") }.tag(Tab.inbox)
            NavigationStack { RoutinesScreen() }
                .tabItem { Label("Рутины", systemImage: "repeat") }.tag(Tab.routines)
            NavigationStack { SettingsScreen() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }.tag(Tab.settings)
        }
        .sheet(item: $model.editor) { target in
            switch target {
            case .task(let id, let draft): TaskEditor(id: id, draft: draft)
            case .routine(let id): RoutineEditor(id: id)
            }
        }
        .sheet(isPresented: $model.showWelcome) { WelcomeScreen() }
        .overlay(alignment: .bottom) {
            if let toast = model.undoToast {
                UndoBar(toast: toast)
                    .id(toast.id)
                    .padding(.bottom, 62)  // clear of the tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: model.undoToast?.id)
        .overlay {
            if let record = model.celebration {
                RecordCelebration(record: record) { model.celebration = nil }
            }
        }
        .overlay {
            if let done = model.doneCelebration {
                DoneCelebrationView(celebration: done) { model.doneCelebration = nil }.id(done.id)
            }
        }
    }
}

struct SyncBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let (color, text): (Color, String) = switch model.syncStatus.state {
        case .idle: (Palette.ok, "синхронизировано")
        case .syncing: (.accentColor, "синхронизация…")
        case .offline: (Palette.warn, "офлайн")
        case .unconfigured: (.gray, "только это устройство")
        default: (Palette.danger, "ошибка синхронизации")
        }
        Button { model.tab = .settings } label: {
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .accessibilityLabel(text)
    }
}

struct NowScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let day = try? model.store.loadDay(model.today, now: model.now)
        let stats = try? model.store.loadStats(today: model.today)
        let top = day.map { pickNow($0) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Fmt.dayTitle(model.today, today: model.today).subtitle).foregroundStyle(.secondary)
                if model.syncStatus.state == .unconfigured {
                    Card {
                        Text("Данные пока хранятся только на этом телефоне. ")
                            + Text("Подключите сервер").foregroundColor(.accentColor)
                            + Text(" в настройках, чтобы синхронизировать с компьютером.")
                    }
                    .font(.subheadline)
                    .onTapGesture { model.tab = .settings }
                }
                HStack(spacing: 8) {
                    stat("🔥 \(stats?.streak ?? 0)", plural(stats?.streak ?? 0, "день подряд", "дня подряд", "дней подряд"))
                    stat("\(day?.done ?? 0)/\(day?.total ?? 0)", "сегодня",
                         progress: day.map { $0.total > 0 ? Double($0.done) / Double($0.total) : 0 })
                    stat("\(stats?.totalDone ?? 0)", "всего сделано")
                }
                if let record = stats?.record, record.bestDate != nil { RecordCard(record: record) }
                Text("ГЛАВНОЕ СЕЙЧАС").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if top.isEmpty {
                    Card {
                        Text((day?.total ?? 0) > 0 ? "Всё на сегодня сделано 🎉" : "На сегодня пока ничего нет")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(top) { ItemRow(item: $0, showHint: true).transition(.row) }
                }
                if let day, day.total - day.done > 0 {
                    Button("Весь день → ещё \(day.total - day.done) \(plural(day.total - day.done, "дело", "дела", "дел"))") {
                        model.dayDate = nil
                        model.tab = .day
                    }
                    .font(.subheadline)
                }
                QuickAdd(date: model.today)
                Text("АКТИВНОСТЬ").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if let stats { Card { HeatmapView(cells: stats.heatmap) } }
            }
            .padding()
            // A done row slides out and the rest close the gap.
            .animation(.snappy(duration: 0.45), value: top.map(\.id))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Сейчас")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncBadge() } }
        .refreshable { await model.sync.sync() }
    }

    private func stat(_ value: String, _ label: String, progress: Double? = nil) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let progress { ProgressView(value: progress).tint(Palette.ok) }
            }
        }
    }
}

struct DayScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let date = model.dayDate ?? model.today
        let day = try? model.store.loadDay(date, now: model.now)
        let title = Fmt.dayTitle(date, today: model.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { go(Dates.addDays(date, -1)) } label: { Image(systemName: "chevron.left").padding(8) }
                        .accessibilityLabel("Предыдущий день")
                    Spacer()
                    VStack {
                        Text(title.title).font(.title2.bold())
                        Text(title.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { go(Dates.addDays(date, 1)) } label: { Image(systemName: "chevron.right").padding(8) }
                        .accessibilityLabel("Следующий день")
                }
                HStack {
                    if date != model.today { Button("К сегодняшнему дню") { go(model.today) }.buttonStyle(.bordered) }
                    Spacer()
                    if let day { Text("Сделано \(day.done) из \(day.total)").font(.subheadline).foregroundStyle(.secondary) }
                }
                if date >= model.today { QuickAdd(date: date) }
                ForEach(DaySection.allCases, id: \.self) { section in
                    let items = day?.items(in: section) ?? []
                    if !items.isEmpty {
                        Text(Fmt.sectionTitles[section]!.uppercased())
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(items) { ItemRow(item: $0, date: date).transition(.row) }
                    }
                }
                if day?.items.isEmpty == true {
                    Text("На этот день ничего нет.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding()
            // Another day swaps the list at once; within a day, done rows slide to the end of their section.
            .transaction(value: date) { $0.animation = nil }
            .animation(.snappy(duration: 0.45), value: day?.items.map(\.id))
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncBadge() } }
        .refreshable { await model.sync.sync() }
    }

    private func go(_ d: LocalDate) { model.dayDate = d == model.today ? nil : d }
}

struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let items = (try? model.store.loadInbox(now: model.now)) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Всё, что пока без дня. Когда будете готовы — отправьте на сегодня или завтра.")
                    .font(.subheadline).foregroundStyle(.secondary)
                QuickAdd(date: nil, placeholder: "Записать мысль или задачу…")
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button { model.openTask(item.refID) } label: {
                            HStack(spacing: 10) {
                                EmojiCircle(emoji: item.emoji, color: item.color, size: 34)
                                Text(item.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        Button("Сегодня") { plan(item, model.today) }.buttonStyle(.bordered).controlSize(.small)
                        Button("Завтра") { plan(item, Dates.addDays(model.today, 1)) }.buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                }
                if items.isEmpty { Text("Входящие пусты ✨").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Входящие")
    }

    private func plan(_ item: DayItem, _ date: LocalDate) {
        model.perform { try $0.updateTask(item.refID, ["date": .string(date)]) }
    }
}

struct RoutinesScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let routines = (try? model.store.loadRoutines(today: model.today)) ?? []
        List {
            SwiftUI.Section {
                Text("\(routines.count) \(plural(routines.count, "регулярная задача", "регулярные задачи", "регулярных задач")). Они повторяются по расписанию и не переносятся.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(DaySection.allCases, id: \.self) { section in
                let items = routines.filter { $0.section == section }
                if !items.isEmpty {
                    SwiftUI.Section(Fmt.sectionTitles[section]!) {
                        ForEach(items) { r in
                            Button { model.openRoutine(r.id) } label: {
                                HStack(spacing: 12) {
                                    EmojiCircle(emoji: r.version.emoji, color: r.version.color, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.version.title).foregroundStyle(.primary)
                                        Text([Fmt.timing(r.version.timing, duration: r.version.durationMin), Fmt.weekdays(r.version.weekdays)]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.footnote).foregroundStyle(.secondary)
                                        if let from = r.pendingFrom {
                                            Text("изменения с \(Fmt.shortDate(from))").font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Рутины")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.openRoutine(nil) } label: { Image(systemName: "plus") }.accessibilityLabel("Добавить рутину")
            }
        }
    }
}
