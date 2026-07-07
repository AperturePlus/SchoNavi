package top.schonavi.app

import org.junit.Test
import org.junit.Assert.*
import java.time.LocalDate
import java.time.ZoneId

class DeadlineAlarmSchedulerLogicTest {
    private fun alert(planId: String, alertDay: String) = DeadlineAlert(planId, "竞赛 $planId", alertDay, 7, "2026-08-15")

    @Test
    fun groups_by_day_and_sorts() {
        val alerts = listOf(
            alert("p1", "2026-08-08"),
            alert("p2", "2026-08-08"),
            alert("p3", "2026-08-12"),
        )
        val grouped = DeadlineAlarmScheduler.groupAlertsByDay(alerts)
        assertEquals(listOf("2026-08-08", "2026-08-12"), grouped.keys.toList())
        assertEquals(2, grouped["2026-08-08"]?.size)
    }

    @Test
    fun filters_future_days_only() {
        val now = LocalDate.of(2026, 8, 7).atTime(9, 0).atZone(ZoneId.systemDefault())
        val days = listOf("2026-08-06", "2026-08-07", "2026-08-08", "2026-08-12")
        val future = DeadlineAlarmScheduler.filterFutureDays(days, now)
        // 2026-08-07 9:00 已过 → 丢弃；08-07 当天 9:00 视为 future 则保留，这里以「严格晚于 now」为准
        assertEquals(listOf("2026-08-08", "2026-08-12"), future)
    }
}
