package com.altair.humanos

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Reminders computed by the app (already filtered by the notification
 * policy) wait here, encrypted, and fire one alarm at a time. When one falls
 * due while the context silences reminders (chamba or entreno), its rule
 * decides: "allow" shows it, "defer" keeps it for the exit the same day,
 * "drop" discards it.
 */
object Scheduler {
    private const val STORE = "reminders"
    private const val REQUEST = 1
    private const val LATE_LIMIT_MS = 30L * 60_000L

    private fun load(context: Context): JSONObject =
        SecureStore.read(context, STORE)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()

    private fun items(o: JSONObject, key: String): MutableList<JSONObject> {
        val array = o.optJSONArray(key) ?: JSONArray()
        return (0 until array.length()).map { array.getJSONObject(it) }.toMutableList()
    }

    private fun save(context: Context, pending: List<JSONObject>, deferred: List<JSONObject>) {
        val o = JSONObject()
            .put("items", JSONArray(pending))
            .put("deferred", JSONArray(deferred))
        SecureStore.write(context, STORE, o.toString())
    }

    /** Replaces every pending reminder; deferred ones are kept. */
    fun setReminders(context: Context, reminders: JSONArray) {
        synchronized(SecureStore.lock) {
            val deferred = items(load(context), "deferred")
            save(context, (0 until reminders.length()).map { reminders.getJSONObject(it) }, deferred)
        }
        scheduleNext(context)
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST,
        Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun canScheduleExact(context: Context): Boolean {
        val manager = context.getSystemService(AlarmManager::class.java)
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
    }

    fun scheduleNext(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val next = items(load(context), "items").minOfOrNull { it.getLong("atMs") }
        val intent = pendingIntent(context)
        if (next == null) {
            manager.cancel(intent)
            return
        }
        val at = maxOf(next, System.currentTimeMillis() + 1_000L)
        if (canScheduleExact(context)) {
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent)
        }
    }

    private fun show(context: Context, r: JSONObject) {
        Notices.post(context, 100 + (r.optInt("id") % 900), r.optString("channel"), r.optString("title"), r.optString("body"))
    }

    fun onDue(context: Context) {
        val now = System.currentTimeMillis()
        synchronized(SecureStore.lock) {
            val o = load(context)
            val pending = items(o, "items")
            val deferred = items(o, "deferred")
            val due = pending.filter { it.getLong("atMs") <= now + 30_000L }
            pending.removeAll(due)
            val silenced = ContextState.isSilenced(context, now)
            for (r in due) {
                if (now - r.getLong("atMs") > LATE_LIMIT_MS) continue
                if (!silenced) {
                    show(context, r)
                    continue
                }
                when (r.optString("rule")) {
                    "allow" -> show(context, r)
                    "defer" -> deferred.add(r)
                    else -> Unit
                }
            }
            save(context, pending, deferred)
        }
        scheduleNext(context)
    }

    /** On leaving a silencing zone: deferred reminders of today. */
    fun flushDeferred(context: Context) {
        synchronized(SecureStore.lock) {
            val o = load(context)
            val today = Calendar.getInstance()
            for (r in items(o, "deferred")) {
                val at = Calendar.getInstance().apply { timeInMillis = r.getLong("atMs") }
                val sameDay = at.get(Calendar.YEAR) == today.get(Calendar.YEAR) &&
                    at.get(Calendar.DAY_OF_YEAR) == today.get(Calendar.DAY_OF_YEAR)
                if (sameDay) show(context, r)
            }
            save(context, items(o, "items"), emptyList())
        }
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val o = load(context)
        val pending = items(o, "items")
        return mapOf(
            "pending" to pending.size,
            "deferred" to items(o, "deferred").size,
            "nextMs" to pending.minOfOrNull { it.getLong("atMs") },
            "exact" to canScheduleExact(context),
        )
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Scheduler.onDue(context)
    }
}
