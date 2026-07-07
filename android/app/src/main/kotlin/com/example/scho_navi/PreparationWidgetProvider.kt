package top.schonavi.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Typeface
import android.os.Bundle
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.temporal.ChronoUnit

internal enum class PreparationWidgetSize {
    COMPACT_HORIZONTAL,
    COMPACT_VERTICAL,
    TALL,
    WIDE,
    HERO,
}

internal fun preparationWidgetSizeFor(minWidth: Int, minHeight: Int): PreparationWidgetSize = when {
    minWidth <= 0 || minHeight <= 0 -> PreparationWidgetSize.COMPACT_HORIZONTAL
    minWidth < 100 && minHeight >= minWidth -> PreparationWidgetSize.COMPACT_VERTICAL
    minHeight < 100 -> PreparationWidgetSize.COMPACT_HORIZONTAL
    minWidth < 100 -> PreparationWidgetSize.COMPACT_VERTICAL
    minWidth < 180 && minHeight <= minWidth + 32 -> PreparationWidgetSize.COMPACT_HORIZONTAL
    minWidth < 180 && minHeight < 250 -> PreparationWidgetSize.COMPACT_VERTICAL
    minWidth < 180 -> PreparationWidgetSize.TALL
    minHeight < 180 -> PreparationWidgetSize.WIDE
    minWidth < 250 -> PreparationWidgetSize.TALL
    else -> PreparationWidgetSize.HERO
}

internal fun countdownNumberRange(text: String): IntRange? {
    val start = text.indexOfFirst(Char::isDigit)
    if (start < 0) return null
    var end = start
    while (end + 1 < text.length && text[end + 1].isDigit()) end++
    return start..end
}

class PreparationWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_REFRESH = "top.schonavi.app.action.REFRESH_PREPARATION_WIDGET"
        const val ACTION_ROTATE = "top.schonavi.app.action.ROTATE_PREPARATION_WIDGET"

        fun refreshAll(context: Context) {
            context.sendBroadcast(
                Intent(context, PreparationWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH
                },
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, PreparationWidgetProvider::class.java))
                ids.forEach { render(context, manager, it, rotate = false) }
            }
            ACTION_ROTATE -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, PreparationWidgetProvider::class.java))
                ids.forEach { render(context, manager, it, rotate = true) }
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it, rotate = true) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId, rotate = false)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        appWidgetIds.forEach { ReminderStorage.deleteWidgetIndex(context, it) }
        val manager = AppWidgetManager.getInstance(context)
        val remaining = manager.getAppWidgetIds(
            ComponentName(context, PreparationWidgetProvider::class.java),
        )
        if (remaining.isEmpty()) WidgetRotationScheduler.stop(context)
    }

    private data class WidgetLayout(
        val resourceId: Int,
        val hasPosition: Boolean,
        val hasPhaseText: Boolean,
        val hasStreak: Boolean,
        val hasTaskDetails: Boolean,
        val compact: Boolean,
    )

    private fun layoutFor(context: Context, options: Bundle): WidgetLayout {
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        // The launcher reports MIN/MAX as the range across orientations: portrait is
        // the narrow+tall pair (MIN_WIDTH × MAX_HEIGHT), landscape the wide+short pair.
        // Reading MIN_HEIGHT alone makes a tall portrait widget look short and pick a
        // horizontal layout, so use the current orientation's actual footprint instead.
        val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val width = ((if (landscape) maxWidth else minWidth)).takeIf { it > 0 } ?: maxOf(minWidth, maxWidth)
        val height = ((if (landscape) minHeight else maxHeight)).takeIf { it > 0 } ?: maxOf(minHeight, maxHeight)
        return when (preparationWidgetSizeFor(width, height)) {
            PreparationWidgetSize.COMPACT_HORIZONTAL -> WidgetLayout(
                resourceId = R.layout.preparation_widget_micro,
                hasPosition = false,
                hasPhaseText = true,
                hasStreak = false,
                hasTaskDetails = false,
                compact = true,
            )
            PreparationWidgetSize.COMPACT_VERTICAL -> WidgetLayout(
                resourceId = R.layout.preparation_widget_micro_vertical,
                hasPosition = false,
                hasPhaseText = true,
                hasStreak = false,
                hasTaskDetails = false,
                compact = true,
            )
            PreparationWidgetSize.TALL -> WidgetLayout(
                resourceId = R.layout.preparation_widget_small,
                hasPosition = true,
                hasPhaseText = true,
                hasStreak = true,
                hasTaskDetails = true,
                compact = false,
            )
            PreparationWidgetSize.WIDE -> WidgetLayout(
                resourceId = R.layout.preparation_widget_wide,
                hasPosition = true,
                hasPhaseText = true,
                hasStreak = true,
                hasTaskDetails = true,
                compact = false,
            )
            PreparationWidgetSize.HERO -> WidgetLayout(
                resourceId = R.layout.preparation_widget_hero,
                hasPosition = true,
                hasPhaseText = true,
                hasStreak = true,
                hasTaskDetails = true,
                compact = false,
            )
        }
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        rotate: Boolean,
    ) {
        val snapshot = ReminderStorage.loadSnapshot(context)
        val options = manager.getAppWidgetOptions(appWidgetId)
        val layout = layoutFor(context, options)
        val views = RemoteViews(context.packageName, layout.resourceId)
        if (snapshot.plans.isEmpty()) {
            renderEmpty(context, views, appWidgetId, layout.compact)
            manager.updateAppWidget(appWidgetId, views)
            return
        }

        val previous = ReminderStorage.widgetIndex(context, appWidgetId)
        val index = when {
            previous !in snapshot.plans.indices -> 0
            rotate && snapshot.plans.size > 1 -> (previous + 1) % snapshot.plans.size
            else -> previous
        }
        ReminderStorage.saveWidgetIndex(context, appWidgetId, index)
        val plan = snapshot.plans[index]
        val today = LocalDate.now()
        val target = parseDay(plan.targetDate) ?: today
        val days = ChronoUnit.DAYS.between(today, target).toInt()
        val progress = if (plan.totalTasks == 0) 0 else plan.completedTasks * 100 / plan.totalTasks
        val lastActivity = snapshot.lastActivityDay?.let(::parseDay)
        val preparedToday = lastActivity == today
        val activeStreak = lastActivity != null &&
            ChronoUnit.DAYS.between(lastActivity, today) <= 1
        val streak = if (activeStreak) snapshot.currentStreak else 0

        views.setViewVisibility(R.id.widget_empty_group, View.GONE)
        views.setViewVisibility(R.id.widget_content_group, View.VISIBLE)
        views.setTextViewText(
            R.id.widget_competition,
            if (layout.compact) compactCompetitionName(plan.competitionName) else plan.competitionName,
        )
        if (layout.hasPosition) {
            views.setTextViewText(
                R.id.widget_position,
                if (snapshot.plans.size > 1) "${index + 1}/${snapshot.plans.size}" else "备赛中",
            )
        }
        views.setTextViewText(R.id.widget_countdown, buildCountdown(context, days))
        if (layout.hasPhaseText) {
            views.setTextViewText(
                R.id.widget_phase,
                if (layout.compact) compactPhaseLabel(plan.currentPhase) else "当前阶段 · ${plan.currentPhase}",
            )
        }
        if (layout.hasStreak) {
            views.setTextViewText(
                R.id.widget_streak,
                when {
                    preparedToday && streak > 0 -> "连续 $streak 天 · 今天已推进"
                    streak > 0 -> "连续 $streak 天 · 完成 1 项续上"
                    else -> "从今天开始推进一小步"
                },
            )
        }
        if (layout.hasTaskDetails) {
            views.setTextViewText(
                R.id.widget_next_task,
                plan.nextTaskTitle?.let { "下一项 · $it" } ?: "当前任务已全部完成",
            )
            views.setTextViewText(
                R.id.widget_due,
                plan.nextTaskDueDate?.let { dueLabel(it, today) } ?: "去计划中查看下一阶段",
            )
        }
        views.setProgressBar(R.id.widget_progress, 100, progress, false)
        views.setTextViewText(
            R.id.widget_progress_text,
            if (layout.compact) "$progress%" else "${plan.completedTasks}/${plan.totalTasks} · $progress%",
        )
        val openPlan = routePendingIntent(context, appWidgetId, "/preparation-plans/${plan.planId}")
        views.setOnClickPendingIntent(R.id.widget_root, openPlan)
        views.setContentDescription(
            R.id.widget_root,
            "${plan.competitionName}，${viewsCountdown(days)}，下一项${plan.nextTaskTitle ?: "任务已完成"}",
        )
        manager.updateAppWidget(appWidgetId, views)
    }

    private fun renderEmpty(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        compact: Boolean,
    ) {
        views.setViewVisibility(R.id.widget_content_group, View.GONE)
        views.setViewVisibility(R.id.widget_empty_group, View.VISIBLE)
        views.setTextViewText(
            R.id.widget_empty_title,
            if (compact) "暂无计划" else "还没有进行中的备赛计划",
        )
        views.setTextViewText(
            R.id.widget_empty_action,
            if (compact) "打开创建" else "打开 SchoNavi 创建计划",
        )
        views.setOnClickPendingIntent(
            R.id.widget_root,
            routePendingIntent(context, appWidgetId, "/preparation-plans"),
        )
        views.setContentDescription(R.id.widget_root, "还没有进行中的备赛计划，点击打开 SchoNavi")
    }

    private fun compactCompetitionName(name: String): String {
        val compact = name.removePrefix("全国大学生").removeSuffix("竞赛").trim()
        return compact.ifBlank { name }.take(6)
    }

    private fun compactPhaseLabel(phase: String): String =
        if (phase.endsWith("中")) phase else "${phase}中"

    private fun routePendingIntent(
        context: Context,
        appWidgetId: Int,
        route: String,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "top.schonavi.app.OPEN_${appWidgetId}_${route.hashCode()}"
            putExtra(MainActivity.EXTRA_ROUTE, route)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId * 31 + route.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun dueLabel(raw: String, today: LocalDate): String {
        val due = parseDay(raw) ?: return "查看截止日期"
        val delta = ChronoUnit.DAYS.between(today, due).toInt()
        return when {
            delta < 0 -> "已逾期 ${-delta} 天"
            delta == 0 -> "今天截止"
            delta == 1 -> "明天截止"
            else -> "${due.monthValue}月${due.dayOfMonth}日截止"
        }
    }

    private fun viewsCountdown(days: Int): String = when {
        days > 0 -> "距离目标还有$days 天"
        days == 0 -> "今天比赛"
        else -> "目标日期已过${-days}天"
    }

    private fun buildCountdown(context: Context, days: Int): CharSequence {
        val text = when {
            days > 0 -> "D-$days"
            days == 0 -> "今天比赛"
            else -> "已过 ${-days} 天"
        }
        val spannable = SpannableString(text)
        val range = countdownNumberRange(text)
        if (range == null) {
            spannable.setSpan(StyleSpan(Typeface.BOLD), 0, text.length, Spannable.SPAN_INCLUSIVE_EXCLUSIVE)
            return spannable
        }
        spannable.setSpan(StyleSpan(Typeface.BOLD), range.first, range.last + 1, Spannable.SPAN_INCLUSIVE_EXCLUSIVE)
        val affixColor = context.getColor(R.color.widget_text_secondary)
        fun dimAffix(start: Int, end: Int) {
            if (start >= end) return
            spannable.setSpan(RelativeSizeSpan(0.46f), start, end, Spannable.SPAN_INCLUSIVE_EXCLUSIVE)
            spannable.setSpan(ForegroundColorSpan(affixColor), start, end, Spannable.SPAN_INCLUSIVE_EXCLUSIVE)
        }
        dimAffix(0, range.first)
        dimAffix(range.last + 1, text.length)
        return spannable
    }

    private fun parseDay(value: String): LocalDate? = try {
        LocalDate.parse(value)
    } catch (_: Exception) {
        null
    }
}
