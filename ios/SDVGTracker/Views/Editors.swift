import SDVGCore
import SwiftUI

/// `title`: the server suggests emoji for it. `auto`: a new item without an emoji takes the
/// server's pick as the title is typed, until the user chooses one.
struct AppearancePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var emoji: String?
    @Binding var color: Int
    var title = ""
    var auto = false
    @State private var showEmojis = false
    @State private var suggested: [String] = []
    /// The emoji this view set by itself; any other value is the user's choice.
    @State private var autoValue: String?
    @State private var chosen: Bool?

    static let emojis = [
        "✅", "📞", "💬", "📧", "🛒", "💳", "🧾", "📦", "🛠️", "💡", "🧹", "🧺", "🍲", "🥣", "☕", "💊",
        "💧", "🚿", "🪥", "🛏️", "🧘", "🏋️", "🚶", "🚼", "👶", "❤️", "🎁", "📚", "📖", "📝", "📊", "💻",
        "🗓️", "⏰", "🚗", "🏠", "🪴", "🐶", "🎨", "🎵", "🧠", "🌙", "☀️", "⭐", "🔥", "🎯", "🧪", "🦷",
    ]

    var body: some View {
        HStack(spacing: 14) {
            Button { showEmojis.toggle() } label: { EmojiCircle(emoji: emoji, color: color, size: 52) }
                .buttonStyle(.plain)
                .accessibilityLabel("Выбрать эмодзи")
            FlowLayout(spacing: 7) {
                ForEach(0..<12) { i in
                    Circle().fill(Palette.color(i)).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == i ? 2 : 0))
                        .onTapGesture { color = i }
                        .accessibilityLabel("Цвет \(i + 1)")
                        .accessibilityAddTraits(color == i ? .isSelected : [])
                }
            }
        }
        .onChange(of: emoji) { if emoji != autoValue { chosen = true } }
        .task(id: title.trimmingCharacters(in: .whitespacesAndNewlines)) { await suggest() }
        if !suggested.isEmpty {
            HStack(spacing: 2) {
                Text("Подходят").font(.footnote).foregroundStyle(.secondary).padding(.trailing, 6)
                ForEach(suggested, id: \.self) { e in
                    Button { choose(e) } label: { emojiCell(e) }
                        .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Подходят к названию")
        }
        if showEmojis {
            TextField("Своё эмодзи", text: Binding(get: { emoji ?? "" }, set: { choose($0.isEmpty ? nil : String($0.prefix(8))) }))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 6) {
                ForEach(Self.emojis, id: \.self) { e in
                    emojiCell(e).onTapGesture { choose(e); showEmojis = false }
                }
            }
        }
    }

    private func emojiCell(_ e: String) -> some View {
        Text(e).font(.title2)
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(emoji == e ? Color(.tertiarySystemFill) : .clear))
            .accessibilityAddTraits(emoji == e ? .isSelected : [])
    }

    private func choose(_ e: String?) {
        chosen = true
        emoji = e
    }

    /// Runs as the title settles: a new title cancels the previous run, sleep included.
    private func suggest() async {
        if chosen == nil { chosen = !auto || emoji != nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return suggested = [] }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let s = await model.suggestEmoji(for: title)
        guard !Task.isCancelled else { return }
        suggested = s.emoji
        if chosen == false, s.pick != emoji {
            autoValue = s.pick
            emoji = s.pick
        }
    }
}

struct TimingPicker: View {
    @Binding var timing: Timing
    @Binding var duration: Int?

    private static let choices: [(String, TimeKind, PartOfDay?)] = [
        ("В любое время", .none, nil), ("🌅 Утро", .part, .morning), ("☀️ День", .part, .day),
        ("🌙 Вечер", .part, .evening), ("⏰ Точное время", .exact, nil),
    ]
    private static let durations: [(Int, String)] = [
        (5, "5 мин"), (10, "10 мин"), (15, "15 мин"), (30, "30 мин"), (60, "1 ч"), (120, "2 ч"), (180, "3 ч"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Когда").font(.footnote).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(Self.choices, id: \.0) { label, kind, part in
                    Chip(label: label, selected: timing.kind == kind && (kind != .part || timing.part == part)) {
                        timing.kind = kind
                        if let part { timing.part = part }
                        if kind == .exact && timing.time == nil { timing.time = "09:00" }
                    }
                }
            }
        }
        if timing.kind == .exact {
            DatePicker("Время", selection: timeBinding, displayedComponents: .hourAndMinute)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Длительность").font(.footnote).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(Self.durations, id: \.0) { min, label in
                    Chip(label: label, selected: duration == min) { duration = duration == min ? nil : min }
                }
            }
        }
    }

    /// "HH:MM" <-> Date on an arbitrary day, in the local calendar.
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let p = (timing.time ?? "09:00").split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                timing.time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            })
    }
}

/// Midnight of a local date in the current calendar.
private func calendarDate(_ d: LocalDate) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day) = (Int(d.prefix(4)), Int(d.dropFirst(5).prefix(2)), Int(d.dropFirst(8).prefix(2)))
    return Calendar.current.date(from: c) ?? Date()
}

private func dateBinding(_ value: Binding<LocalDate?>, default fallback: LocalDate) -> Binding<Date> {
    Binding(
        get: { calendarDate(value.wrappedValue ?? fallback) },
        set: { value.wrappedValue = String(Dates.localNow($0).prefix(10)) })
}

struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String?
    @State var draft: TaskDraft
    @State private var moves = 0
    @State private var done = false
    @State private var history: [Rules.TitleGroup] = []
    /// Day for a copy; nil = tomorrow.
    @State private var copyDate: LocalDate?
    @State private var copied: Copied?
    @FocusState private var titleFocused: Bool

    private struct Copied {
        let id: String
        let date: LocalDate
    }

    var body: some View {
        let today = model.today
        // Suggestions only for a new task: an existing one already has its title.
        let suggestions = id == nil && titleFocused ? Rules.suggestTitles(history, query: draft.title) : []
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField("Что нужно сделать?", text: $draft.title, axis: .vertical).font(.title3.weight(.semibold))
                        .focused($titleFocused)
                    if !suggestions.isEmpty {
                        TitleSuggestions(items: suggestions) { s in
                            draft.apply(s)
                            titleFocused = false
                        }
                    }
                    AppearancePicker(emoji: $draft.emoji, color: $draft.color, title: draft.title, auto: id == nil)
                }
                SwiftUI.Section("День") {
                    FlowLayout {
                        Chip(label: "Сегодня", selected: draft.date == today) { draft.date = today }
                        Chip(label: "Завтра", selected: draft.date == Dates.addDays(today, 1)) { draft.date = Dates.addDays(today, 1) }
                        Chip(label: "📥 Во входящие", selected: draft.date == nil) { draft.date = nil }
                    }
                    if draft.date != nil {
                        DatePicker("Дата", selection: dateBinding($draft.date, default: today), displayedComponents: .date)
                    }
                }
                SwiftUI.Section { TimingPicker(timing: $draft.timing, duration: $draft.durationMin) }
                SwiftUI.Section("Дедлайн") {
                    Toggle("Есть дедлайн", isOn: Binding(
                        get: { draft.deadlineDate != nil },
                        set: { draft.deadlineDate = $0 ? Dates.addDays(today, 3) : nil }))
                    if draft.deadlineDate != nil {
                        DatePicker("Дата", selection: dateBinding($draft.deadlineDate, default: today), displayedComponents: .date)
                        Toggle("До определённого времени", isOn: Binding(
                            get: { draft.deadlineTime != nil },
                            set: { draft.deadlineTime = $0 ? "18:00" : nil }))
                        if draft.deadlineTime != nil {
                            TextField("ЧЧ:ММ", text: Binding(get: { draft.deadlineTime ?? "" }, set: { draft.deadlineTime = $0 }))
                                .keyboardType(.numbersAndPunctuation)
                        }
                    }
                }
                SwiftUI.Section("Заметки") {
                    TextField("Шаги, ссылки, мысли…", text: $draft.notes, axis: .vertical).lineLimit(2...6)
                }
                if moves > 0 {
                    SwiftUI.Section {
                        Text("↻ Задачу переносили уже \(moves) \(plural(moves, "раз", "раза", "раз")). Может, разбить её на шаги поменьше?")
                            .foregroundStyle(Palette.warn)
                    }
                }
                if let id {
                    SwiftUI.Section("Копия задачи") {
                        let target = copyDate ?? Dates.addDays(today, 1)
                        DatePicker("День", selection: dateBinding($copyDate, default: Dates.addDays(today, 1)),
                                   in: calendarDate(today)..., displayedComponents: .date)
                        Button("⧉ Копировать на \(dayLabel(target))") { copy(to: target) }
                            .disabled(!valid || target < today)
                        if let copied {
                            HStack {
                                Label("Копия на \(dayLabel(copied.date)) готова", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.ok)
                                Spacer()
                                Button("Отменить") { undoCopy() }.buttonStyle(.borderless)
                            }
                        }
                    }
                    SwiftUI.Section {
                        if !done {
                            Button("↷ Перенести на завтра") { save(); model.perform { try $0.postponeTask(id, today: today) }; dismiss() }
                                .disabled(!valid)
                        }
                        Button("Удалить задачу", role: .destructive) { model.perform { try $0.deleteTask(id) }; dismiss() }
                    }
                }
            }
            .navigationTitle(id == nil ? "Новая задача" : "Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save(); dismiss() }.disabled(!valid) }
            }
            .onAppear {
                guard let id else {
                    history = (try? model.store.loadTitleHistory(today: today)) ?? []
                    return
                }
                moves = (try? model.store.moveCount(id)) ?? 0
                done = (try? model.store.get(.task, id).map(TaskRecord.init))?.doneOn != nil
            }
        }
    }

    private var valid: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var trimmed: TaskDraft {
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return d
    }

    private func save() {
        guard valid else { return }
        let d = trimmed
        let today = model.today
        if let id {
            model.perform { try $0.saveTask(id, d, today: today) }
        } else {
            model.createTask(d)
        }
    }

    private func dayLabel(_ d: LocalDate) -> String {
        d == model.today ? "сегодня" : d == Dates.addDays(model.today, 1) ? "завтра" : Fmt.shortDate(d)
    }

    /// Copies the form as it is now; the task itself changes only on "Сохранить".
    private func copy(to date: LocalDate) {
        guard valid else { return }
        do {
            copied = Copied(id: try model.store.copyTask(trimmed, to: date), date: date)
        } catch {
            print("copy failed:", error)
        }
    }

    private func undoCopy() {
        guard let copied else { return }
        model.perform { try $0.deleteTask(copied.id) }
        self.copied = nil
    }
}

struct RoutineEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String?
    @State private var draft = RoutineDraft()
    @State private var adherence: Rules.Adherence?

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField("Например, «Пообедать»", text: $draft.title).font(.title3.weight(.semibold))
                    AppearancePicker(emoji: $draft.emoji, color: $draft.color, title: draft.title, auto: id == nil)
                }
                SwiftUI.Section { TimingPicker(timing: $draft.timing, duration: $draft.durationMin) }
                SwiftUI.Section {
                    FlowLayout {
                        ForEach(0..<7) { i in
                            Chip(label: Fmt.weekdays[i], selected: draft.weekdays & (1 << i) != 0) { draft.weekdays ^= 1 << i }
                        }
                    }
                } header: {
                    Text("Дни недели")
                } footer: {
                    Text("Регулярные задачи не переносятся. Изменения действуют с сегодняшнего дня (или с завтрашнего, если сегодня уже отмечено) — прошлые дни остаются как были.")
                }
                if let a = adherence, let percent = a.percent {
                    SwiftUI.Section {
                        LabeledContent {
                            Text("\(percent)\u{00A0}%").monospacedDigit().fontWeight(.semibold)
                                .foregroundStyle(a.warning ? Palette.warn : .secondary)
                        } label: {
                            Text(a.warning ? "⚠︎ Пропускается" : "Выполняется")
                                .foregroundStyle(a.warning ? Palette.warn : .primary)
                            Text(Fmt.adherence(a))
                        }
                    } footer: {
                        Text("Считается за последние 30 дней, но не раньше первого выполнения; пропуски кнопкой «Пропуск» не в счёт."
                            + (a.warning ? " Порог — \(model.settings.routineWarnBelow)\u{00A0}%, меняется в настройках." : ""))
                    }
                }
                if let id {
                    SwiftUI.Section {
                        Button("Убрать рутину", role: .destructive) {
                            let today = model.today
                            model.perform { try $0.archiveRoutine(id, today: today) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(id == nil ? "Новая рутина" : "Рутина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save(); dismiss() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.weekdays == 0)
                }
            }
            .onAppear {
                if let id, let v = try? model.store.latestVersion(id) { draft = RoutineDraft(v) }
                if let id { adherence = try? model.store.loadRoutineAdherence(id, today: model.today) }
            }
        }
    }

    private func save() {
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = model.today
        model.perform { [id] in
            if let id { try $0.editRoutine(id, d, today: today) } else { try $0.createRoutine(d, today: today) }
        }
    }
}
