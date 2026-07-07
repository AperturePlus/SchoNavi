package top.schonavi.app

import org.junit.Assert.assertEquals
import org.junit.Test

class PreparationWidgetSizeTest {
    @Test
    fun defaultsToCompactHorizontalWhenLauncherOptionsAreMissing() {
        assertEquals(
            PreparationWidgetSize.COMPACT_HORIZONTAL,
            preparationWidgetSizeFor(0, 0),
        )
    }

    @Test
    fun selectsCompactHorizontalForOneRowTwoColumnFootprint() {
        assertEquals(
            PreparationWidgetSize.COMPACT_HORIZONTAL,
            preparationWidgetSizeFor(110, 60),
        )
        assertEquals(
            PreparationWidgetSize.COMPACT_HORIZONTAL,
            preparationWidgetSizeFor(160, 160),
        )
    }

    @Test
    fun selectsCompactVerticalForTwoRowOneColumnFootprint() {
        assertEquals(
            PreparationWidgetSize.COMPACT_VERTICAL,
            preparationWidgetSizeFor(60, 120),
        )
        assertEquals(
            PreparationWidgetSize.COMPACT_VERTICAL,
            preparationWidgetSizeFor(60, 90),
        )
    }

    @Test
    fun selectsDetailedLayoutsForLargerFootprints() {
        assertEquals(PreparationWidgetSize.TALL, preparationWidgetSizeFor(160, 260))
        assertEquals(PreparationWidgetSize.WIDE, preparationWidgetSizeFor(320, 140))
        assertEquals(PreparationWidgetSize.HERO, preparationWidgetSizeFor(320, 300))
    }

    @Test
    fun usesVerticalCompactForTallFootprintsTooShortForTheRichLayout() {
        // A narrow, portrait footprint that is taller than it is wide but not tall
        // enough to fit the rich TALL layout should fill vertically as compact-vertical
        // rather than clip the rich layout or float in a stretched horizontal one.
        assertEquals(PreparationWidgetSize.COMPACT_VERTICAL, preparationWidgetSizeFor(140, 220))
        assertEquals(PreparationWidgetSize.COMPACT_VERTICAL, preparationWidgetSizeFor(150, 240))
        // Once it is genuinely tall, promote to the rich TALL layout.
        assertEquals(PreparationWidgetSize.TALL, preparationWidgetSizeFor(150, 300))
    }
}
