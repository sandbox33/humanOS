package com.altair.humanos

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * Platform channels used by the Dart side:
 *  - `com.altair.humanos/usage_stats`: screen time from UsageStatsManager.
 *  - `com.altair.humanos/screen`: keeps the screen on during a session.
 */
object DeviceChannels {
    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.altair.humanos/usage_stats").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasUsageAccess(activity))
                "openSettings" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "foregroundMsToday" ->
                    result.success(if (hasUsageAccess(activity)) foregroundMsToday(activity) else null)
                // B2: raw resume/pause events per app (paired in Dart), the
                // same source as the system's digital-wellbeing screen.
                "events" -> {
                    if (!hasUsageAccess(activity)) {
                        result.success(null)
                    } else {
                        val from = (call.argument<Number>("fromMs") ?: 0).toLong()
                        val to = (call.argument<Number>("toMs") ?: System.currentTimeMillis()).toLong()
                        Thread {
                            val value = try {
                                usageEvents(activity, from, to)
                            } catch (e: Exception) {
                                null
                            }
                            activity.runOnUiThread { result.success(value) }
                        }.start()
                    }
                }
                // The category each app declares (game, video, social…), for
                // the first suggestion only; the user classifies.
                "appCategories" -> {
                    Thread {
                        val value = try {
                            appCategories(activity)
                        } catch (e: Exception) {
                            emptyMap<String, Int>()
                        }
                        activity.runOnUiThread { result.success(value) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "com.altair.humanos/screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    activity.runOnUiThread {
                        if (on) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun usageEvents(context: Context, from: Long, to: Long): List<Map<String, Any>> {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to)
        val event = UsageEvents.Event()
        val out = ArrayList<Map<String, Any>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.packageName == context.packageName) continue
            val type = when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> "resumed"
                UsageEvents.Event.MOVE_TO_BACKGROUND -> "paused"
                else -> continue
            }
            out.add(
                mapOf(
                    "package" to event.packageName,
                    "activity" to (event.className ?: ""),
                    "type" to type,
                    "at" to event.timeStamp,
                ),
            )
        }
        return out
    }

    private fun appCategories(context: Context): Map<String, Int> {
        val pm = context.packageManager
        val out = HashMap<String, Int>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return out
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        for (info in pm.queryIntentActivities(intent, 0)) {
            out[info.activityInfo.packageName] = info.activityInfo.applicationInfo.category
        }
        return out
    }

    private fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Foreground time of every app since local midnight, in milliseconds,
     * excluding HumanOS itself and the home screen.
     */
    @Suppress("DEPRECATION")
    private fun foregroundMsToday(context: Context): Long {
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val now = System.currentTimeMillis()
        val home = context.packageManager
            .resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY,
            )?.activityInfo?.packageName
        val excluded = setOfNotNull(context.packageName, home)
        val events = manager.queryEvents(start, now)
        val event = UsageEvents.Event()
        val resumedAt = HashMap<String, Long>()
        var total = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.packageName in excluded) continue
            val key = event.packageName + "/" + event.className
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> resumedAt[key] = event.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val from = resumedAt.remove(key)
                    if (from != null) total += event.timeStamp - from
                }
            }
        }
        for (from in resumedAt.values) total += now - from
        return total
    }
}
