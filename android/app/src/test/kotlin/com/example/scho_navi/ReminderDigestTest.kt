package top.schonavi.app

import org.junit.Test
import org.junit.Assert.*

class ReminderDigestTest {
    private fun task(id: String, due: String) = ReminderTask(id, "t$id", due, 0)
    private fun plan(id: String, target: String, pending: List<ReminderTask>) =
        ReminderPlan(id, "竞赛 $id", target, "阶段", 0, 1, pending.firstOrNull()?.title, pending.firstOrNull()?.dueIsoDay, emptyList(), pending)

    @Test
    fun digest_counts_remainingToday_and_upcoming_and_nearest() {
        val today = java.time.LocalDate.of(2026, 7, 2)
        val snapshot = ReminderSnapshot(
            currentStreak = 1, lastActivityDay = "2026-07-01",
            plans = listOf(
                plan("p1", "2026-07-31", listOf(task("t1", "2026-07-02"), task("t2", "2026-07-03"))),
                plan("p2", "2026-07-20", listOf(task("t3", "2026-07-02"))),
                plan("p3", "2026-06-30", emptyList()), // 过期，不计入 upcoming
            ),
            deadlineAlerts = emptyList(),
            schemaVersion = 3,
        )
        val digest = ReminderDigest.project(snapshot, today)
        assertEquals(2, digest.remainingToday)
        assertEquals(2, digest.upcomingDeadlines) // p1, p2
        assertEquals("竞赛 p2", digest.nearestDeadlineName)
        assertEquals("2026-07-20", digest.nearestDeadlineDay)
    }

    @Test
    fun digest_handles_no_active_plan() {
        val today = java.time.LocalDate.of(2026, 7, 2)
        val snapshot = ReminderSnapshot(0, null, emptyList(), emptyList(), 3)
        val digest = ReminderDigest.project(snapshot, today)
        assertEquals(0, digest.remainingToday)
        assertEquals(0, digest.upcomingDeadlines)
        assertNull(digest.nearestDeadlineName)
    }
}
