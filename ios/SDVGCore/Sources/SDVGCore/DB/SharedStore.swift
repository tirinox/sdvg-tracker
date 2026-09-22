import Foundation

extension Store {
    /// The database in the App Group container, shared by the app and the widget extension.
    /// Falls back to Application Support when the group is unavailable (unsigned builds).
    public static func openShared(appGroup: String = "group.com.tirinox.sdvgtracker") throws -> Store {
        let fm = FileManager.default
        let dir = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try open(path: dir.appendingPathComponent("sdvg.sqlite").path)
    }
}
