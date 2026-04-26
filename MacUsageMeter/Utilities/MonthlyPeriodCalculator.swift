import Foundation

/// 月次リセット日に基づく月次期間の計算ユーティリティ (第9.5節)
///
/// `monthly_reset_day` を起算日として、現在の月次期間 (開始日〜終了日) を算出する。
///
/// 例: `monthly_reset_day=15` の場合:
/// - 3月15日〜4月14日 が1つの月次期間
/// - 3月1日時点では、2月15日〜3月14日 の期間に属する
///
/// `monthly_reset_day=1` (デフォルト) の場合:
/// - 3月1日〜3月31日 が月次期間 (通常の暦月と一致)
enum MonthlyPeriodCalculator {

    /// 月次期間の開始日と終了日 (yyyy-MM-dd 形式)
    struct MonthlyPeriod: Equatable, Sendable {
        /// 月次期間の開始日 (リセット日)
        let startDate: String
        /// 月次期間の終了日 (次のリセット日の前日)
        let endDate: String
    }

    /// 指定日が属する月次期間を計算する
    ///
    /// - Parameters:
    ///   - resetDay: 月次リセット日 (1〜28)
    ///   - referenceDate: 基準日 (デフォルト: 今日)
    ///   - calendar: カレンダー (デフォルト: .current)
    /// - Returns: 月次期間 (開始日〜終了日)
    static func currentPeriod(
        resetDay: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyPeriod {
        let clampedResetDay = max(1, min(28, resetDay))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        guard let currentDay = components.day,
              let currentMonth = components.month,
              let currentYear = components.year else {
            // フォールバック: 当月1日〜当月末日
            let startOfMonth = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            return MonthlyPeriod(
                startDate: formatter.string(from: startOfMonth),
                endDate: formatter.string(from: endOfMonth)
            )
        }

        let periodStart: Date
        let periodEnd: Date

        if currentDay >= clampedResetDay {
            // 当月のリセット日以降 → 期間は当月リセット日〜翌月リセット日前日
            periodStart = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: clampedResetDay))!
            let nextResetDate = calendar.date(byAdding: .month, value: 1, to: periodStart)!
            periodEnd = calendar.date(byAdding: .day, value: -1, to: nextResetDate)!
        } else {
            // 当月のリセット日より前 → 期間は前月リセット日〜当月リセット日前日
            let thisMonthReset = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: clampedResetDay))!
            periodStart = calendar.date(byAdding: .month, value: -1, to: thisMonthReset)!
            periodEnd = calendar.date(byAdding: .day, value: -1, to: thisMonthReset)!
        }

        return MonthlyPeriod(
            startDate: formatter.string(from: periodStart),
            endDate: formatter.string(from: periodEnd)
        )
    }
}
