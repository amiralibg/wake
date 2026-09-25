import Foundation

/// How moments age, resurface and fade. Pure date maths, kept apart from the views.
enum MomentRules {
    /// Unopened this long, a moment starts fading.
    static let fadeAfter: TimeInterval = 30 * 86_400
    /// …and this long, it's archived.
    static let archiveAfter: TimeInterval = 45 * 86_400

    static func isFading(_ moment: MomentRecord, now: Date) -> Bool {
        !moment.isArchived && now.timeIntervalSince(moment.lastSeenAt) >= fadeAfter
    }

    static func shouldArchive(_ moment: MomentRecord, now: Date) -> Bool {
        !moment.isArchived && now.timeIntervalSince(moment.lastSeenAt) >= archiveAfter
    }

    static func daysUntilArchive(_ moment: MomentRecord, now: Date) -> Int {
        max(0, Int(((archiveAfter - now.timeIntervalSince(moment.lastSeenAt)) / 86_400).rounded(.up)))
    }

    /// Due today (or overdue) and not opened since it came due.
    static func isResurfacing(_ moment: MomentRecord, now: Date, calendar: Calendar = .current) -> Bool {
        guard !moment.isArchived, let due = moment.resurfaceAt else { return false }
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), due < endOfToday else { return false }
        if let opened = moment.lastOpenedAt, opened >= due { return false }
        return true
    }

    static func isRelevant(_ moment: MomentRecord, host: String?) -> Bool {
        guard let host, !host.isEmpty, !moment.isArchived else { return false }
        return moment.host == host || moment.host.hasSuffix("." + host) || host.hasSuffix("." + moment.host)
    }
}

/// When a moment should come back.
enum ResurfaceChoice: String, CaseIterable, Identifiable {
    case whenRelevant, tomorrow, weekend, nextWeek, nextMonth

    var id: Self { self }

    var label: String {
        switch self {
        case .whenRelevant: "Only on its site"
        case .tomorrow: "Tomorrow"
        case .weekend: "This weekend"
        case .nextWeek: "Next week"
        case .nextMonth: "In a month"
        }
    }

    /// Mornings, so it's waiting when the day starts.
    func date(from now: Date, calendar: Calendar = .current) -> Date? {
        let morning = { (day: Date) in calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day }
        switch self {
        case .whenRelevant:
            return nil
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now).map(morning)
        case .weekend:
            let saturday = calendar.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
            return saturday.map(morning)
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: now).map(morning)
        case .nextMonth:
            return calendar.date(byAdding: .month, value: 1, to: now).map(morning)
        }
    }
}
