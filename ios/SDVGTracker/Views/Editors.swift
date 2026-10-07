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
    /// How many live tasks wear each color: shown under the swatch, so a neglected color can be chosen.
    @State private var uses = [Int](repeating: 0, count: 12)

    static let emojis = [
        "✅", "📞", "💬", "📧", "🛒", "💳", "🧾", "📦", "🛠️", "💡", "🧹", "🧺", "🍲", "🥣", "☕", "💊",
        "💧", "🚿", "🪥", "🛏️", "🧘", "🏋️", "🚶", "🚼", "👶", "❤️", "🎁", "📚", "📖", "📝", "📊", "💻",
        "🗓️", "⏰", "🚗", "🏠", "🪴", "🐶", "🎨", "🎵", "🧠", "🌙", "☀️", "⭐", "🔥", "🎯", "🧪", "🦷",
    ]

    var body: some View {
        HStack(spacing: 14) {
            Button { showEmojis.toggle() } label: { EmojiCircle(emoji: emoji, color: color, size: 52) }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Выбрать эмодзи", "Choose emoji"))
            FlowLayout(spacing: 7) {
                ForEach(0..<12) { i in
                    VStack(spacing: 4) {
                        Circle().fill(Palette.color(i)).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == i ? 2 : 0))
                        if model.settings.showColorUses {
                            // The least and the most worn colors stand out.
                            let extreme = uses[i] == uses.min() || uses[i] == uses.max()
                            Text("\(uses[i])").font(.system(size: 10, weight: extreme ? .bold : .regular))
                                .foregroundStyle(extreme ? .primary : .secondary)
                        }
                    }
                    .onTapGesture { color = i }
                    .accessibilityLabel(model.settings.showColorUses
                        ? tr("Цвет \(i + 1), задач: \(uses[i])", "Color \(i + 1), \(uses[i]) tasks")
                        : tr("Цвет \(i + 1)", "Color \(i + 1)"))
                    .accessibilityAddTraits(color == i ? .isSelected : [])
                }
            }
        }
        .task { if model.settings.showColorUses { uses = (try? model.store.loadColorUses()) ?? uses } }
        .onChange(of: emoji) { if emoji != autoValue { chosen = true } }
        .task(id: title.trimmingCharacters(in: .whitespacesAndNewlines)) { await suggest() }
        if !suggested.isEmpty {
            HStack(spacing: 2) {
                Text(tr("Подходят", "Suggested")).font(.footnote).foregroundStyle(.secondary).padding(.trailing, 6)
                ForEach(suggested, id: \.self) { e in
                    Button { choose(e) } label: { emojiCell(e) }
                        .buttonStyle(.plain)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("Подходят к названию", "Suggested for the title"))
        }
        if showEmojis {
            TextField(tr("Своё эмодзи", "Your own emoji"), text: Binding(get: { emoji ?? "" }, set: { choose($0.isEmpty ? nil : String($0.prefix(8))) }))
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

struct PriorityPicker: View {
    @Binding var priority: Priority

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Приоритет", "Priority")).font(.footnote).foregroundStyle(.secondary)
            FlowLayout {
                ForEach(Priority.allCases, id: \.self) { p in
                    Chip(label: Fmt.priority(p), selected: priority == p) { priority = p }
                }
            }
        }
    }
}

struct TimingPicker: View {
    @Binding var timing: Timing
    @Binding var duration: Int?

    private static var choices: [(String, TimeKind, PartOfDay?)] {
        [
            (Fmt.sectionTitle(.anytime), .none, nil), ("🌅 " + Fmt.partTitle(.morning), .part, .morning),
            ("☀️ " + Fmt.partTitle(.day), .part, .day), ("🌙 " + Fmt.partTitle(.evening), .part, .evening),
            (tr("⏰ Точное время", "⏰ Exact time"), .exact, nil),
        ]
    }
    private static var durations: [(Int, String)] { [5, 10, 15, 30, 60, 120, 180].map { ($0, Fmt.duration($0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Когда", "When")).font(.footnote).foregroundStyle(.secondary)
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
            DatePicker(tr("Время", "Time"), selection: timeBinding, displayedComponents: .hourAndMinute)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Длительность", "Duration")).font(.footnote).foregroundStyle(.secondary)
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
    /// What the title of a new task is checked against (Rules.checkTitle).
    @State private var listed: [Rules.ListedItem] = []
    /// Saving under a taken title or one done today was refused; the notice shakes.
    @State private var nudges = 0
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
        let suggestions = id == nil && titleFocused ? Rules.suggestTitles(Rules.withoutTaken(history, listed), query: draft.title) : []
        let check = Rules.checkTitle(listed, title: draft.title)
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField(tr("Что нужно сделать?", "What needs doing?"), text: $draft.title, axis: .vertical).font(.title3.weight(.semibold))
                        .focused($titleFocused)
                    if !check.isClear {
                        TitleCheckNotice(check: check, nudges: nudges) { next in
                            draft.title = next
                            add()
                        }
                    }
                    if !suggestions.isEmpty {
                        TitleSuggestions(items: suggestions) { s in
                            draft.apply(s)
                            titleFocused = false
                        }
                    }
                    AppearancePicker(emoji: $draft.emoji, color: $draft.color, title: draft.title, auto: id == nil)
                }
                SwiftUI.Section(tr("День", "Day")) {
                    FlowLayout {
                        Chip(label: tr("Сегодня", "Today"), selected: draft.date == today) { draft.date = today }
                        Chip(label: tr("Завтра", "Tomorrow"), selected: draft.date == Dates.addDays(today, 1)) { draft.date = Dates.addDays(today, 1) }
                        Chip(label: tr("📥 Во входящие", "📥 To inbox"), selected: draft.date == nil) { draft.date = nil }
                    }
                    if draft.date != nil {
                        DatePicker(tr("Дата", "Date"), selection: dateBinding($draft.date, default: today), displayedComponents: .date)
                    }
                }
                SwiftUI.Section { TimingPicker(timing: $draft.timing, duration: $draft.durationMin) }
                SwiftUI.Section { PriorityPicker(priority: $draft.priority) }
                SwiftUI.Section(tr("Дедлайн", "Deadline")) {
                    Toggle(tr("Есть дедлайн", "Has a deadline"), isOn: Binding(
                        get: { draft.deadlineDate != nil },
                        set: { draft.deadlineDate = $0 ? Dates.addDays(today, 3) : nil }))
                    if draft.deadlineDate != nil {
                        DatePicker(tr("Дата", "Date"), selection: dateBinding($draft.deadlineDate, default: today), displayedComponents: .date)
                        Toggle(tr("До определённого времени", "By a specific time"), isOn: Binding(
                            get: { draft.deadlineTime != nil },
                            set: { draft.deadlineTime = $0 ? "18:00" : nil }))
                        if draft.deadlineTime != nil {
                            TextField(tr("ЧЧ:ММ", "HH:MM"), text: Binding(get: { draft.deadlineTime ?? "" }, set: { draft.deadlineTime = $0 }))
                                .keyboardType(.numbersAndPunctuation)
                        }
                    }
                }
                SwiftUI.Section(tr("Заметки", "Notes")) {
                    TextField(tr("Шаги, ссылки, мысли…", "Steps, links, thoughts…"), text: $draft.notes, axis: .vertical).lineLimit(2...6)
                }
                if moves > 0 {
                    SwiftUI.Section {
                        Text(tr("↻ Задачу переносили уже \(moves) \(plural(moves, "раз", "раза", "раз")). Может, разбить её на шаги поменьше?",
                                 "↻ This task has been moved \(moves == 1 ? "once" : "\(moves) times") already. Maybe break it into smaller steps?"))
                            .foregroundStyle(Palette.warn)
                    }
                }
                if let id {
                    SwiftUI.Section(tr("Копия задачи", "Copy of the task")) {
                        let target = copyDate ?? Dates.addDays(today, 1)
                        DatePicker(tr("День", "Day"), selection: dateBinding($copyDate, default: Dates.addDays(today, 1)),
                                   in: calendarDate(today)..., displayedComponents: .date)
                        Button(tr("⧉ Копировать на \(dayLabel(target))", "⧉ Copy to \(dayLabel(target))")) { copy(to: target) }
                            .disabled(!valid || target < today)
                        if let copied {
                            HStack {
                                Label(tr("Копия на \(dayLabel(copied.date)) готова", "Copied to \(dayLabel(copied.date))"), systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.ok)
                                Spacer()
                                Button(tr("Отменить", "Undo")) { undoCopy() }.buttonStyle(.borderless)
                            }
                        }
                    }
                    SwiftUI.Section {
                        if !done {
                            Button(tr("↷ Перенести на завтра", "↷ Move to tomorrow")) { save(); model.perform { try $0.postponeTask(id, today: today) }; dismiss() }
                                .disabled(!valid)
                        }
                        Button(tr("Удалить задачу", "Delete task"), role: .destructive) { model.perform { try $0.deleteTask(id) }; dismiss() }
                    }
                }
            }
            .navigationTitle(id == nil ? tr("Новая задача", "New task") : tr("Задача", "Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Сохранить", "Save")) { if id == nil { add() } else { save(); dismiss() } }.disabled(!valid)
                }
            }
            .onAppear {
                guard let id else {
                    history = (try? model.store.loadTitleHistory(today: today)) ?? []
                    loadListed()
                    return
                }
                moves = (try? model.store.moveCount(id)) ?? 0
                done = (try? model.store.get(.task, id).map(TaskRecord.init))?.doneOn != nil
            }
            .onChange(of: model.revision) { if id == nil { loadListed() } }
        }
    }

    private var valid: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A new task, unless its title is taken or done today: the notice says why, and offers a numbered one for the latter.
    private func add() {
        guard valid else { return }
        loadListed()
        if case .free = Rules.checkTitle(listed, title: trimmed.title) {
            save()
            dismiss()
        } else {
            nudges += 1
        }
    }

    private func loadListed() {
        listed = (try? model.store.loadListed(today: model.today)) ?? []
    }

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
        d == model.today ? tr("сегодня", "today") : d == Dates.addDays(model.today, 1) ? tr("завтра", "tomorrow") : Fmt.shortDate(d)
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
    @State private var history: Rules.RoutineHistory?

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    TextField(tr("Например, «Пообедать»", "E.g. “Have lunch”"), text: $draft.title).font(.title3.weight(.semibold))
                    AppearancePicker(emoji: $draft.emoji, color: $draft.color, title: draft.title, auto: id == nil)
                }
                SwiftUI.Section { TimingPicker(timing: $draft.timing, duration: $draft.durationMin) }
                SwiftUI.Section { PriorityPicker(priority: $draft.priority) }
                SwiftUI.Section {
                    FlowLayout {
                        ForEach(0..<7) { i in
                            Chip(label: Fmt.weekdays[i], selected: draft.weekdays & (1 << i) != 0) { draft.weekdays ^= 1 << i }
                        }
                    }
                } header: {
                    Text(tr("Дни недели", "Days of the week"))
                } footer: {
                    Text(tr("Регулярные задачи не переносятся. Изменения действуют с сегодняшнего дня (или с завтрашнего, если сегодня уже отмечено) — прошлые дни остаются как были.",
                             "Routines don’t move to the next day. Changes apply from today (or from tomorrow if today is already marked); past days stay as they were."))
                }
                if let a = adherence, let percent = a.percent {
                    SwiftUI.Section {
                        LabeledContent {
                            Text("\(percent)\u{00A0}%").monospacedDigit().fontWeight(.semibold)
                                .foregroundStyle(a.warning ? Palette.warn : .secondary)
                        } label: {
                            Text(a.warning ? tr("⚠︎ Пропускается", "⚠︎ Being skipped") : tr("Выполняется", "On track"))
                                .foregroundStyle(a.warning ? Palette.warn : .primary)
                            Text(Fmt.adherence(a))
                        }
                        if let h = history {
                            VStack(alignment: .leading, spacing: 8) {
                                DayMarks(marks: h.days, big: true)
                                HStack {
                                    Text(Fmt.shortDate(Dates.addDays(model.today, 1 - h.days.count)))
                                    Spacer()
                                    Text(tr("сегодня", "today"))
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    count(tr("сделано", "done"), h, .done, Palette.ok)
                                    count(tr("не сделано", "missed"), h, .missed, Palette.danger)
                                    count(tr("пропущено", "skipped"), h, .skipped, Color(.tertiaryLabel))
                                }
                                .font(.footnote)
                            }
                            .padding(.vertical, 4)
                            Text(verbatim: "🔥 \(Fmt.streak(h))").fontWeight(.semibold)
                        }
                    } footer: {
                        Text(tr("Считается за последние 30 дней, но не раньше первого выполнения; пропуски кнопкой «Пропуск» не в счёт.",
                                "Counted over the last 30 days, but not before the first time it was done; days marked “Skip” don’t count.")
                            + (a.warning ? tr(" Порог — \(model.settings.routineWarnBelow)\u{00A0}%, меняется в настройках.",
                                              " The threshold is \(model.settings.routineWarnBelow)%, change it in Settings.") : ""))
                    }
                }
                if let id {
                    SwiftUI.Section {
                        Button(tr("Убрать рутину", "Remove routine"), role: .destructive) {
                            let today = model.today
                            model.perform { try $0.archiveRoutine(id, today: today) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(id == nil ? tr("Новая рутина", "New routine") : tr("Рутина", "Routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Отмена", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Сохранить", "Save")) { save(); dismiss() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.weekdays == 0)
                }
            }
            .onAppear {
                if let id, let v = try? model.store.latestVersion(id) { draft = RoutineDraft(v) }
                if let id {
                    adherence = try? model.store.loadRoutineAdherence(id, today: model.today)
                    history = try? model.store.loadRoutineHistory(id, today: model.today)
                }
            }
        }
    }

    /// One line of the legend under the month of marks.
    private func count(_ label: String, _ h: Rules.RoutineHistory, _ mark: Rules.DayMark, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(verbatim: "\(label) \(h.days.filter { $0 == mark }.count)")
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
