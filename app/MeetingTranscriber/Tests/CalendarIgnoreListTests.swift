@testable import MeetingTranscriber
import XCTest

/// The ignore rule on its own, then at its two call sites: the poll loop must
/// neither record nor ask during an ignored event, and the in-room prompter
/// must not ask about one.
@MainActor
final class CalendarIgnoreListTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ title: String, attendees: [String] = [], allDay: Bool = false, declined: Bool = false,
    ) -> CalendarEventCandidate {
        CalendarEventCandidate(
            title: title, start: start, end: start.addingTimeInterval(3600), isAllDay: allDay,
            attendees: attendees, conferenceText: "", isDeclined: declined,
        )
    }

    // MARK: - Pure rule

    func testPatternsDropBlankLinesAndTrim() {
        XCTAssertEqual(CalendarIgnoreList.patterns(from: "  Focus \n\n\tLunch\n  "), ["Focus", "Lunch"])
    }

    func testMatchesASubstringIgnoringCase() {
        XCTAssertTrue(CalendarIgnoreList.matches("Weekly FOCUS block", patterns: ["focus"]))
        XCTAssertTrue(CalendarIgnoreList.matches("Фокус-время 2", patterns: ["фокус"]))
        XCTAssertFalse(CalendarIgnoreList.matches("Design review", patterns: ["focus"]))
        XCTAssertFalse(CalendarIgnoreList.matches("Focus", patterns: []))
    }

    func testOnlyARunningTimedAcceptedEventCounts() {
        let now = start.addingTimeInterval(60)
        let patterns = ["focus"]
        XCTAssertNotNil(CalendarIgnoreList.runningEvent(at: now, among: [event("Focus")], patterns: patterns))
        XCTAssertNil(
            CalendarIgnoreList.runningEvent(at: now, among: [event("Focus", allDay: true)], patterns: patterns),
            "an all-day entry must not silence a whole day",
        )
        XCTAssertNil(CalendarIgnoreList.runningEvent(at: now, among: [event("Focus", declined: true)], patterns: patterns))
        XCTAssertNil(
            CalendarIgnoreList.runningEvent(at: start.addingTimeInterval(3600), among: [event("Focus")], patterns: patterns),
            "the end is exclusive",
        )
        XCTAssertNil(CalendarIgnoreList.runningEvent(at: now, among: [event("Focus")], patterns: []))
    }

    // MARK: - Poll loop

    private final class FixedDetector: MeetingDetecting {
        func checkOnce() -> DetectedMeeting? {
            DetectedMeeting(pattern: .zoom, windowTitle: "Zoom Meeting", ownerName: "zoom.us", windowPID: 4321)
        }

        func isMeetingActive(_: DetectedMeeting) -> Bool {
            true
        }

        func reset(appName _: String?) {}
    }

    private final class EventsLookup: CalendarMeetingLookup {
        let events: [CalendarEventCandidate]
        init(_ events: [CalendarEventCandidate]) {
            self.events = events
        }

        func meeting(startingAt _: Date, appName _: String) -> CalendarMeeting? {
            nil
        }

        func events(around _: Date) -> [CalendarEventCandidate] {
            events
        }
    }

    private func makeLoop(events: [CalendarEventCandidate], ignored: [String]) -> (WatchLoop, MockRecorder) {
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test_calendar_ignore_\(UUID().uuidString).wav")
        let clock: () -> Date = { [start] in start.addingTimeInterval(60) }
        let loop = WatchLoop(
            detector: FixedDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            endGracePeriod: 0.05,
            nowProvider: clock,
            calendarLookup: EventsLookup(events),
            ignoredCalendarTitles: { ignored },
        )
        loop.permissionChecker = {
            HealthCheckResult(screenRecording: .healthy, microphone: .healthy)
        }
        return (loop, recorder)
    }

    func testANativeMeetingDuringAnIgnoredEventIsNotRecorded() async throws {
        let (loop, recorder) = makeLoop(events: [event("My focus slot")], ignored: ["focus slot"])
        loop.start()

        try? await Task.sleep(nanoseconds: 300_000_000) // several polls

        XCTAssertFalse(recorder.startCalled, "the slot is ignored, so the call is not recorded")
        loop.stop()
    }

    func testANativeMeetingDuringAnotherEventStillRecords() async {
        let (loop, recorder) = makeLoop(events: [event("Design review")], ignored: ["focus slot"])
        loop.start()

        await waitFor(recorder.startCalled, timeout: .seconds(2))

        XCTAssertTrue(recorder.startCalled)
        loop.stop()
    }

    // MARK: - In-room prompter

    private final class CountingNotifier: AppNotifying {
        private(set) var prompts = 0

        func notify(title _: String, body _: String, urgency _: NotificationUrgency) {}

        // swiftlint:disable async_without_await
        @MainActor
        func askToRecordMicrophone(title _: String, body _: String) async -> ConsentAnswer {
            prompts += 1
            return .declined
        }
        // swiftlint:enable async_without_await
    }

    func testTheInRoomPrompterDoesNotAskAboutAnIgnoredEvent() async {
        let notifier = CountingNotifier()
        let clock: () -> Date = { [start] in start.addingTimeInterval(60) }
        let prompter = InRoomMeetingPrompter(
            lookup: EventsLookup([event("My focus slot", attendees: ["Anna"])]),
            isEnabled: { true },
            ignoredTitles: { ["focus slot"] },
            notifier: notifier,
            hooks: InRoomMeetingPrompter.Hooks(mayPrompt: { true }, startRecording: { true }),
            nowProvider: clock,
        )

        await prompter.tick()

        XCTAssertEqual(notifier.prompts, 0)
    }
}
