import Foundation

/// Cached date formatters to avoid repeated allocation (Apple recommends reusing DateFormatter)
public enum ScribeDateFormatting {
    // MARK: - Cached Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let weekdayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    // MARK: - Public API

    public static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func fullDate(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    public static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    public static func dayNumber(_ date: Date) -> String {
        dayNumberFormatter.string(from: date)
    }

    public static func dayName(_ date: Date) -> String {
        dayNameFormatter.string(from: date)
    }

    public static func eventTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today, \(time(date))"
        } else if cal.isDateInTomorrow(date) {
            return "Tomorrow, \(time(date))"
        } else {
            return weekdayTimeFormatter.string(from: date)
        }
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m < 1 { return "\(Int(seconds))s" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60)h \(m % 60)m"
    }

    public static func transcriptTime(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    public static func sectionDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let daysAgo = cal.dateComponents([.day], from: date, to: cal.startOfDay(for: Date())).day ?? 0
        if daysAgo < 7 {
            return weekdayFormatter.string(from: date)
        }
        return weekdayTimeFormatter.string(from: date)
    }
}
