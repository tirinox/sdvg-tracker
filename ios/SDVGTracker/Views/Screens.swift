import SDVGCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack { NowScreen() }
                .tabItem { Label(tr("Сейчас", "Now"), systemImage: "sparkles") }.tag(Tab.now)
            NavigationStack { DayScreen() }
                .tabItem { Label(tr("День", "Day"), systemImage: "list.bullet") }.tag(Tab.day)
            NavigationStack { InboxScreen() }
                .tabItem { Label(tr("Входящие", "Inbox"), systemImage: "tray") }.tag(Tab.inbox)
            NavigationStack { RoutinesScreen() }
                .tabItem { Label(tr("Рутины", "Routines"), systemImage: "repeat") }.tag(Tab.routines)
            NavigationStack { SettingsScreen() }
                .tabItem { Label(tr("Настройки", "Settings"), systemImage: "gearshape") }.tag(Tab.settings)
        }
        .sheet(item: $model.editor) { target in
            switch target {
            case .task(let id, let draft): TaskEditor(id: id, draft: draft)
            case .routine(let id): RoutineEditor(id: id)
            }
        }
        .sheet(isPresented: $model.showWelcome) { WelcomeScreen() }
        .serverChangeSheet()
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
        case .idle: (Palette.ok, tr("синхронизировано", "synced"))
        case .syncing: (.accentColor, tr("синхронизация…", "syncing…"))
        case .offline: (Palette.warn, tr("офлайн", "offline"))
        case .unconfigured: (.gray, tr("только это устройство", "this device only"))
        default: (Palette.danger, tr("ошибка синхронизации", "sync error"))
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
                HStack {
                    Text(Fmt.dayTitle(model.today, today: model.today).subtitle).foregroundStyle(.secondary)
                    Spacer()
                    DayCountdown()
                }
                if model.syncStatus.state == .unconfigured {
                    Card {
                        Text(tr("Данные пока хранятся только на этом телефоне. ", "Your data lives only on this phone for now. "))
                            + Text(tr("Подключите сервер", "Connect a server")).foregroundColor(.accentColor)
                            + Text(tr(" в настройках, чтобы синхронизировать с компьютером.", " in Settings to sync with your computer."))
                    }
                    .font(.subheadline)
                    .onTapGesture { model.tab = .settings }
                }
                HStack(spacing: 8) {
                    stat("🔥 \(stats?.streak ?? 0)", trWord(stats?.streak ?? 0, ru: ("день подряд", "дня подряд", "дней подряд"),
                                                            en: ("day in a row", "days in a row")))
                    stat("\(day?.done ?? 0)/\(day?.total ?? 0)", tr("сегодня", "today"),
                         progress: day.map { $0.total > 0 ? Double($0.done) / Double($0.total) : 0 })
                    stat("\(stats?.totalDone ?? 0)", tr("всего сделано", "done in total"))
                }
                if let record = stats?.record, record.bestDate != nil { RecordCard(record: record) }
                Text(tr("ГЛАВНОЕ СЕЙЧАС", "UP NEXT")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if top.isEmpty {
                    Card {
                        Text((day?.total ?? 0) > 0 ? tr("Всё на сегодня сделано 🎉", "All done for today 🎉") : tr("На сегодня пока ничего нет", "Nothing for today yet"))
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(top) { ItemRow(item: $0, showHint: true).transition(.row) }
                }
                if let day, day.total - day.done > 0 {
                    let left = trn(day.total - day.done, ru: ("дело", "дела", "дел"), en: ("thing", "things"))
                    Button(tr("Весь день → ещё \(left)", "Whole day → \(left) more")) {
                        model.dayDate = nil
                        model.tab = .day
                    }
                    .font(.subheadline)
                }
                QuickAdd(date: model.today)
                Text(tr("АКТИВНОСТЬ", "ACTIVITY")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if let stats { Card { HeatmapView(cells: stats.heatmap) } }
            }
            .padding()
            // A done row slides out and the rest close the gap.
            .animation(.snappy(duration: 0.45), value: top.map(\.id))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tr("Сейчас", "Now"))
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
        let rows = day.map(DayListRow.rows) ?? []
        let title = Fmt.dayTitle(date, today: model.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button { go(Dates.addDays(date, -1)) } label: { Image(systemName: "chevron.left").padding(8) }
                        .accessibilityLabel(tr("Предыдущий день", "Previous day"))
                    Spacer()
                    VStack {
                        Text(title.title).font(.title2.bold())
                        Text(title.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { go(Dates.addDays(date, 1)) } label: { Image(systemName: "chevron.right").padding(8) }
                        .accessibilityLabel(tr("Следующий день", "Next day"))
                }
                HStack {
                    if date == model.today { DayCountdown() }
                    Spacer()
                    if let day { Text(tr("Сделано \(day.done) из \(day.total)", "\(day.done) of \(day.total) done")).font(.subheadline).foregroundStyle(.secondary) }
                }
                if date == model.today {
                    QuickAdd(date: date)
                } else if date > model.today {
                    let when = date == Dates.addDays(model.today, 1) ? tr("завтра", "tomorrow") : Fmt.shortDate(date)
                    QuickAdd(date: date, placeholder: tr("Добавить задачу на \(when)", "Add a task for \(when)"))
                }
                ForEach(rows) { row in
                    switch row {
                    case .header(let group):
                        Text(Fmt.groupTitle(group).uppercased())
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                    case .item(let item):
                        ItemRow(item: item, date: date).transition(.row)
                    }
                }
                if day?.items.isEmpty == true {
                    Text(tr("На этот день ничего нет.", "Nothing on this day.")).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding()
            // Another day swaps the list at once; within a day, done rows slide down into "Сделано".
            .transaction(value: date) { $0.animation = nil }
            .animation(.snappy(duration: 0.45), value: rows.map(\.id))
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // In the bar it stays in view while scrolling, so nothing is added or checked on another day by mistake.
            ToolbarItem(placement: .principal) {
                if date != model.today {
                    NotTodayBadge(distance: Fmt.dayDistance(date, today: model.today)) { go(model.today) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { SyncBadge() }
        }
        .refreshable { await model.sync.sync() }
    }

    private func go(_ d: LocalDate) { model.dayDate = d == model.today ? nil : d }
}

/// Headers and rows of the Day screen in one flat list, so a row that gets done moves down into
/// "Сделано" instead of leaving one list and appearing in another.
private enum DayListRow: Identifiable {
    case header(DayGroup)
    case item(DayItem)

    var id: String {
        switch self {
        case .header(.section(let s)): "head:\(s.rawValue)"
        case .header(.done): "head:done"
        case .item(let item): item.id
        }
    }

    static func rows(_ day: DayView) -> [DayListRow] {
        day.groups.flatMap { [.header($0.group)] + $0.items.map(DayListRow.item) }
    }
}

/// The Day screen shows another day than today; a tap anywhere on it goes back to today.
private struct NotTodayBadge: View {
    var distance: String
    var back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                Text(tr("Не сегодня — \(distance)", "Not today: \(distance)"))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(tr("К сегодня", "Back to today"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.warn.opacity(0.18)))
            }
            .font(.subheadline)
            .foregroundStyle(Palette.warn)
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.warn.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Palette.warn.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Не сегодня — \(distance)", "Not today: \(distance)"))
        .accessibilityHint(tr("Вернуться к сегодняшнему дню", "Go back to today"))
    }
}

struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let items = (try? model.store.loadInbox(now: model.now)) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Всё, что пока без дня. Когда будете готовы — отправьте на сегодня или завтра.",
                         "Everything without a day yet. When you’re ready, send it to today or tomorrow."))
                    .font(.subheadline).foregroundStyle(.secondary)
                QuickAdd(date: nil, placeholder: tr("Записать мысль или задачу…", "Jot down a thought or a task…"))
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Button { model.openTask(item.refID) } label: {
                            HStack(spacing: 10) {
                                EmojiCircle(emoji: item.emoji, color: item.color, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.body.weight(item.priority == .high ? .bold : item.priority == .low ? .regular : .medium))
                                        .foregroundStyle(item.priority == .low ? .secondary : .primary)
                                        .multilineTextAlignment(.leading)
                                    if item.priority == .high {
                                        Tag(text: Fmt.priorityTag, fg: Palette.text(item.color), bg: Palette.color(item.color).opacity(0.24))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        Button(tr("Сегодня", "Today")) { plan(item, model.today) }.buttonStyle(.bordered).controlSize(.small)
                        Button(tr("Завтра", "Tomorrow")) { plan(item, Dates.addDays(model.today, 1)) }.buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                    .overlay {
                        if item.priority == .high {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.color(item.color).opacity(0.45))
                                PriorityMarks(color: item.color, key: item.id, pulse: true)
                            }
                        }
                    }
                }
                if items.isEmpty { Text(tr("Входящие пусты ✨", "Inbox is empty ✨")).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 30) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(tr("Входящие", "Inbox"))
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
        let lagging = routines.filter(\.adherence.warning).count
        List {
            SwiftUI.Section {
                Text(tr("\(routines.count) \(plural(routines.count, "регулярная задача", "регулярные задачи", "регулярных задач")). Они повторяются по расписанию и не переносятся.",
                         "\(routines.count) \(routines.count == 1 ? "routine" : "routines"). They repeat on a schedule and never move to another day."))
                    .font(.subheadline).foregroundStyle(.secondary)
                if lagging > 0 {
                    Label(
                        tr("\(lagging) \(plural(lagging, "рутина пропускается", "рутины пропускаются", "рутин пропускаются")): за последние 30 дней сделано меньше \(model.settings.routineWarnBelow)\u{00A0}%.",
                           "\(lagging) \(lagging == 1 ? "routine is" : "routines are") being skipped: done less than \(model.settings.routineWarnBelow)% of the last 30 days."),
                        systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.warn)
                }
            }
            ForEach(DaySection.allCases, id: \.self) { section in
                let items = routines.filter { $0.section == section }
                if !items.isEmpty {
                    SwiftUI.Section(Fmt.sectionTitle(section)) {
                        ForEach(items) { r in
                            Button { model.openRoutine(r.id) } label: {
                                HStack(spacing: 12) {
                                    EmojiCircle(emoji: r.version.emoji, color: r.version.color, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        let p = r.version.priority
                                        Text(r.version.title)
                                            .fontWeight(p == .high ? .bold : nil)
                                            .foregroundStyle(p == .low ? .secondary : .primary)
                                        HStack(spacing: 6) {
                                            if p == .high {
                                                Tag(text: Fmt.priorityTag, fg: Palette.text(r.version.color), bg: Palette.color(r.version.color).opacity(0.24))
                                            }
                                            Text(([p == .low ? Fmt.lowPriority : ""] + [Fmt.timing(r.version.timing, duration: r.version.durationMin), Fmt.weekdays(r.version.weekdays)])
                                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.footnote).foregroundStyle(.secondary)
                                        }
                                        if let from = r.pendingFrom {
                                            Text(tr("изменения с \(Fmt.shortDate(from))", "changes from \(Fmt.shortDate(from))")).font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if let percent = r.adherence.percent {
                                        Group {
                                            if r.adherence.warning {
                                                Tag(text: "⚠︎ \(percent)\u{00A0}%", fg: Palette.warn, bg: Palette.warn.opacity(0.14))
                                            } else {
                                                Text("\(percent)\u{00A0}%").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                            }
                                        }
                                        .monospacedDigit()
                                        .accessibilityLabel("\(r.adherence.warning ? tr("Пропускается", "Being skipped") : tr("Выполняется", "On track")): \(percent)\u{00A0}%, \(Fmt.adherence(r.adherence))")
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(ZStack {
                                Color(.secondarySystemGroupedBackground)
                                if r.version.priority == .high {
                                    PriorityMarks(color: r.version.color, key: r.id, pulse: true, cornerRadius: 0)
                                }
                            })
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("Рутины", "Routines"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.openRoutine(nil) } label: { Image(systemName: "plus") }.accessibilityLabel(tr("Добавить рутину", "Add routine"))
            }
        }
    }
}
