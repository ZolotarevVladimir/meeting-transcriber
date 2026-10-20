import Foundation

/// Calendar events during which nothing is recorded automatically: a block the
/// user keeps for themselves, where a call that happens to start (or a prompt
/// that happens to fire) is not a meeting worth keeping. Pure, so the rule is
/// pinned without EventKit; `WatchLoop+CalendarIgnore.swift` and
/// `InRoomMeetingPrompter` are the two callers.
///
/// One pattern per line, matched as a case- and diacritic-insensitive
/// substring of the event title, so a recurring block keeps matching when a
/// date or a suffix is appended to its title. Blank lines are ignored.
///
/// Manual recordings are not affected: a click is a decision, and this list
/// only speaks for the triggers nobody clicked for.
enum CalendarIgnoreList {
    static func patterns(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func matches(_ title: String, patterns: [String]) -> Bool {
        patterns.contains { title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The ignored event running at `now`, if any. All-day events never count:
    /// a matching all-day entry would silence a whole day of meetings, which is
    /// not what a title rule for a time slot means. Declined events do not
    /// count either: the user is not in them.
    static func runningEvent(
        at now: Date, among events: [CalendarEventCandidate], patterns: [String],
    ) -> CalendarEventCandidate? {
        guard !patterns.isEmpty else { return nil }
        return events.first { event in
            !event.isAllDay && !event.isDeclined
                && event.start <= now && now < event.end
                && matches(event.title, patterns: patterns)
        }
    }
}
