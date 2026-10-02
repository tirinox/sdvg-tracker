import Foundation
import SDVGCore
import UserNotifications

/// Local reminders, rebuilt from the database after changes: one at the start of every open
/// item with an exact time today and tomorrow, and a morning summary. Works offline.
enum Notifications {
    private static let prefix = "sdvg."

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func reschedule(store: Store, now: LocalDateTime) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        guard let settings = try? store.settings() else { return }
        let today = Dates.logicalDay(now, dayStartHour: settings.dayStartHour)
        var requests: [UNNotificationRequest] = []
        for date in [today, Dates.addDays(today, 1)] {
            guard let day = try? store.loadDay(date, now: now) else { continue }
            let open = day.items.filter { !$0.done && !$0.skipped }

            // Morning summary.
            let morning = "\(date)T\(String(format: "%02d", settings.partMorningFrom)):00"
            if morning > now, !open.isEmpty {
                let things = trn(open.count, ru: ("дело", "дела", "дел"), en: ("thing", "things"))
                requests.append(request(
                    id: "\(prefix)summary.\(date)", at: morning,
                    title: tr("Доброе утро ☀️", "Good morning ☀️"),
                    body: tr("Сегодня \(things). Начнём с первого?", "\(things) for today. Start with the first one?")))
            }
            for item in open {
                guard let time = item.timing.time else { continue }
                // Times before the day start belong to the next calendar date.
                let calDate = (Int(time.prefix(2)) ?? 0) < settings.dayStartHour ? Dates.addDays(date, 1) : date
                let at = "\(calDate)T\(time)"
                guard at > now else { continue }
                requests.append(request(
                    id: "\(prefix)\(item.id).\(date)", at: at,
                    title: "\(item.emoji ?? "⏰") \(item.title)", body: tr("Пора: \(time)", "Time for it: \(time)")))
            }
        }
        // iOS keeps at most 64 pending requests per app.
        for r in requests.prefix(60) { try? await center.add(r) }
    }

    private static func request(id: String, at: LocalDateTime, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var c = DateComponents()
        c.year = Int(at.prefix(4))
        c.month = Int(at.dropFirst(5).prefix(2))
        c.day = Int(at.dropFirst(8).prefix(2))
        c.hour = Int(at.dropFirst(11).prefix(2))
        c.minute = Int(at.dropFirst(14).prefix(2))
        return UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
    }
}
