//
//  TallyResetDates.swift
//  Tapp
//
//  Local-midnight boundaries for recurring tally resets.
//

import Foundation

enum TallyResetDates {
    /// Next reset instant when the user first enables a recurring schedule.
    static func initialNextReset(for schedule: String, calendar: Calendar = .current) -> Date? {
        let now = Date()
        switch schedule {
        case TallyResetSchedule.daily:
            return startOfNextDay(after: now, calendar: calendar)
        case TallyResetSchedule.monthly:
            return startOfNextMonth(after: now, calendar: calendar)
        case TallyResetSchedule.yearly:
            return startOfNextYear(after: now, calendar: calendar)
        default:
            return nil
        }
    }

    /// Advance `NextResetAt` until it lies strictly after `now`.
    static func rollForward(schedule: String, from previous: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        var next = previous
        while next <= now {
            next = advanceOnePeriod(schedule: schedule, from: next, calendar: calendar)
        }
        return next
    }

    private static func advanceOnePeriod(schedule: String, from date: Date, calendar: Calendar) -> Date {
        switch schedule {
        case TallyResetSchedule.daily:
            return startOfNextDay(after: date, calendar: calendar)
        case TallyResetSchedule.monthly:
            return startOfNextMonth(after: date, calendar: calendar)
        case TallyResetSchedule.yearly:
            return startOfNextYear(after: date, calendar: calendar)
        default:
            return date
        }
    }

    private static func startOfNextDay(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    private static func startOfNextMonth(after date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let monthStart = calendar.date(from: comps),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return date
        }
        return nextMonth
    }

    private static func startOfNextYear(after date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        var comps = DateComponents()
        comps.year = year + 1
        comps.month = 1
        comps.day = 1
        return calendar.date(from: comps) ?? date
    }
}
