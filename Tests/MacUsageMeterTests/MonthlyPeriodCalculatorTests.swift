import XCTest
@testable import MacUsageMeter

final class MonthlyPeriodCalculatorTests: XCTestCase {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }()

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - resetDay = 1 (デフォルト: 暦月と一致)

    func test_resetDay1_midMonth_returnsCalendarMonth() {
        let ref = date(year: 2026, month: 3, day: 15)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 1, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-01")
        XCTAssertEqual(period.endDate, "2026-03-31")
    }

    func test_resetDay1_firstDay_returnsCalendarMonth() {
        let ref = date(year: 2026, month: 3, day: 1)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 1, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-01")
        XCTAssertEqual(period.endDate, "2026-03-31")
    }

    func test_resetDay1_lastDay_returnsCalendarMonth() {
        let ref = date(year: 2026, month: 3, day: 31)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 1, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-01")
        XCTAssertEqual(period.endDate, "2026-03-31")
    }

    // MARK: - resetDay = 15 (典型的な中間日)

    func test_resetDay15_afterReset_returnsCurrentCycle() {
        // 3月20日 → resetDay=15 → 期間は 3/15〜4/14
        let ref = date(year: 2026, month: 3, day: 20)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 15, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-15")
        XCTAssertEqual(period.endDate, "2026-04-14")
    }

    func test_resetDay15_onResetDay_returnsCurrentCycle() {
        // 3月15日 → resetDay=15 → 期間は 3/15〜4/14
        let ref = date(year: 2026, month: 3, day: 15)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 15, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-15")
        XCTAssertEqual(period.endDate, "2026-04-14")
    }

    func test_resetDay15_beforeReset_returnsPreviousCycle() {
        // 3月10日 → resetDay=15 → 期間は 2/15〜3/14
        let ref = date(year: 2026, month: 3, day: 10)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 15, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-02-15")
        XCTAssertEqual(period.endDate, "2026-03-14")
    }

    func test_resetDay15_dayBeforeReset_returnsPreviousCycle() {
        // 3月14日 → resetDay=15 → 期間は 2/15〜3/14
        let ref = date(year: 2026, month: 3, day: 14)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 15, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-02-15")
        XCTAssertEqual(period.endDate, "2026-03-14")
    }

    // MARK: - resetDay = 28 (上限値)

    func test_resetDay28_afterReset_returnsCurrentCycle() {
        // 3月30日 → resetDay=28 → 期間は 3/28〜4/27
        let ref = date(year: 2026, month: 3, day: 30)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 28, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-03-28")
        XCTAssertEqual(period.endDate, "2026-04-27")
    }

    func test_resetDay28_beforeReset_returnsPreviousCycle() {
        // 3月5日 → resetDay=28 → 期間は 2/28〜3/27
        let ref = date(year: 2026, month: 3, day: 5)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 28, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2026-02-28")
        XCTAssertEqual(period.endDate, "2026-03-27")
    }

    // MARK: - 年またぎ

    func test_resetDay15_january_crossesYearBoundary() {
        // 1月10日 → resetDay=15 → 期間は 前年12/15〜1/14
        let ref = date(year: 2026, month: 1, day: 10)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 15, referenceDate: ref, calendar: calendar)
        XCTAssertEqual(period.startDate, "2025-12-15")
        XCTAssertEqual(period.endDate, "2026-01-14")
    }

    // MARK: - クランプ (範囲外の値)

    func test_resetDayOver28_clampedTo28() {
        let ref = date(year: 2026, month: 3, day: 30)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 31, referenceDate: ref, calendar: calendar)
        // 31 は 28 にクランプされる
        XCTAssertEqual(period.startDate, "2026-03-28")
        XCTAssertEqual(period.endDate, "2026-04-27")
    }

    func test_resetDayZero_clampedTo1() {
        let ref = date(year: 2026, month: 3, day: 15)
        let period = MonthlyPeriodCalculator.currentPeriod(resetDay: 0, referenceDate: ref, calendar: calendar)
        // 0 は 1 にクランプされる
        XCTAssertEqual(period.startDate, "2026-03-01")
        XCTAssertEqual(period.endDate, "2026-03-31")
    }
}
