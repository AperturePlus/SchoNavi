package top.schonavi.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PreparationWidgetCountdownTest {
    @Test
    fun emphasizesTheDayNumberInAFutureCountdown() {
        assertEquals(2..3, countdownNumberRange("D-30"))
    }

    @Test
    fun emphasizesSingleDigitCountdown() {
        assertEquals(2..2, countdownNumberRange("D-5"))
    }

    @Test
    fun emphasizesTheNumberInAnOverdueCountdown() {
        assertEquals(3..3, countdownNumberRange("已过 3 天"))
    }

    @Test
    fun emphasizesMultiDigitOverdueCountdown() {
        assertEquals(3..4, countdownNumberRange("已过 12 天"))
    }

    @Test
    fun hasNoNumberRangeWhenCountdownIsAllText() {
        assertNull(countdownNumberRange("今天比赛"))
    }
}
