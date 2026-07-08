package top.schonavi.app

import org.junit.Test
import org.junit.Assert.*

class ReminderStorageTest {
    @Test
    fun parse_v3_snapshot_with_pendingTasks_and_deadlineAlerts() {
        val json = """{"schemaVersion":3,"generatedAt":"2026-07-02T12:00:00","currentStreak":1,"preparedToday":true,"lastActivityDay":"2026-07-01","plans":[{"planId":"p1","competitionName":"X","targetDate":"2026-08-15","currentPhase":"阶段","completedTasks":0,"totalTasks":2,"nextTaskTitle":"t1","nextTaskDueDate":"2026-07-02","pendingTasks":[{"taskId":"t1","title":"t1","dueIsoDay":"2026-07-02","sortOrder":0}]}],"deadlineAlerts":[{"planId":"p1","competitionName":"X","alertIsoDay":"2026-08-08","daysBefore":7,"deadlineIsoDay":"2026-08-15"}]}"""
        val snapshot = ReminderStorage.parseSnapshotJson(json)
        assertEquals(3, snapshot.schemaVersion)
        assertEquals(1, snapshot.plans.first().pendingTasks.size)
        assertEquals(1, snapshot.deadlineAlerts.size)
        assertEquals(7, snapshot.deadlineAlerts.first().daysBefore)
    }

    @Test
    fun parse_v2_still_works_with_empty_new_fields() {
        val json = """{"schemaVersion":2,"generatedAt":"2026-07-02T12:00:00","currentStreak":0,"preparedToday":false,"plans":[]}"""
        val snapshot = ReminderStorage.parseSnapshotJson(json)
        assertEquals(2, snapshot.schemaVersion)
        assertTrue(snapshot.plans.isEmpty())
        assertTrue(snapshot.deadlineAlerts.isEmpty())
    }

    @Test
    fun parse_unknown_schema_returns_empty() {
        val snapshot = ReminderStorage.parseSnapshotJson("""{"schemaVersion":99}""")
        assertTrue(snapshot.plans.isEmpty())
        assertTrue(snapshot.deadlineAlerts.isEmpty())
    }
}
