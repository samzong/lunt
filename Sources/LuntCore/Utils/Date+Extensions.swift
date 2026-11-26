import Foundation

extension Date {
    public func timeAgo() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: self, to: now)

        if let years = components.year, years > 0 {
            let key = years == 1 ? "time.years.ago" : "time.years.ago.plural"
            return String(format: key.localized, years)
        }

        if let months = components.month, months > 0 {
            let key = months == 1 ? "time.months.ago" : "time.months.ago.plural"
            return String(format: key.localized, months)
        }

        if let weeks = components.weekOfYear, weeks > 0 {
            let key = weeks == 1 ? "time.weeks.ago" : "time.weeks.ago.plural"
            return String(format: key.localized, weeks)
        }

        if let days = components.day, days > 0 {
            let key = days == 1 ? "time.days.ago" : "time.days.ago.plural"
            return String(format: key.localized, days)
        }

        if let hours = components.hour, hours > 0 {
            let key = hours == 1 ? "time.hours.ago" : "time.hours.ago.plural"
            return String(format: key.localized, hours)
        }

        if let minutes = components.minute, minutes > 0 {
            let key = minutes == 1 ? "time.minutes.ago" : "time.minutes.ago.plural"
            return String(format: key.localized, minutes)
        }

        return "time.just.now".localized
    }
}
