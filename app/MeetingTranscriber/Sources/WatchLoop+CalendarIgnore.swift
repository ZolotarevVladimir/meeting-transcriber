import Foundation
import os

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "WatchLoopCalendarIgnore")

/// The calendar's veto over automatic recording; see `CalendarIgnoreList`.
/// Checked in the poll loop after a detection and before the consent gate, so
/// an ignored slot neither records nor asks.
extension WatchLoop {
    /// True when a detected meeting must be skipped because an ignored event is
    /// running. Logged once per event rather than once per poll.
    func isInIgnoredCalendarEvent() -> Bool {
        let patterns = ignoredCalendarTitles()
        guard !patterns.isEmpty else { return false }
        let now = nowProvider()
        guard let event = CalendarIgnoreList.runningEvent(
            at: now, among: calendarLookup.events(around: now), patterns: patterns,
        ) else { return false }
        let key = InRoomMeetingPolicy.Key(event)
        if lastIgnoredCalendarEvent != key {
            lastIgnoredCalendarEvent = key
            logger.info("Not recording: ignored calendar event \(event.title, privacy: .private) is running")
        }
        return true
    }
}
