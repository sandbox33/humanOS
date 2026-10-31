package com.altair.humanos

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Morning alarms: exact alarm-clock alarms (they survive Doze and show in
 * the status bar), an alarm channel with alarm volume and a full-screen
 * screen with big buttons. Re-scheduled after a reboot or an app update.
 */
object Alarms {
    private const val STORE = "alarms"
    const val ACTION_RING = "com.altair.humanos.ALARM_RING"
    const val ACTION_STOP = "com.altair.humanos.ALARM_STOP"
    const val ACTION_SNOOZE = "com.altair.humanos.ALARM_SNOOZE"

    private fun load(context: Context): List<JSONObject> {
        val array = SecureStore.read(context, STORE)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: JSONArray()
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    fun notificationId(alarmId: Int) = 3000 + alarmId

    /** Next ring strictly after [nowMs] (same rule as the app's `nextAlarmAt`). */
    fun nextAt(minuteOfDay: Int, daysMask: Int, nowMs: Long): Long? {
        if (daysMask and 0x7F == 0) return null
        for (i in 0..7) {
            val c = Calendar.getInstance().apply {
                timeInMillis = nowMs
                add(Calendar.DAY_OF_MONTH, i)
                set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
                set(Calendar.MINUTE, minuteOfDay % 60)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            // Calendar: Sunday = 1 … Saturday = 7; mask bit 0 = Monday.
            val bit = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7
            if ((daysMask shr bit) and 1 == 1 && c.timeInMillis > nowMs) return c.timeInMillis
        }
        return null
    }

    private fun ringIntent(context: Context, alarm: JSONObject, request: Int): PendingIntent = PendingIntent.getBroadcast(
        context,
        request,
        Intent(context, AlarmReceiver::class.java)
            .setAction(ACTION_RING)
            .putExtra("id", alarm.getInt("id"))
            .putExtra("label", alarm.optString("label"))
            .putExtra("snooze", alarm.optInt("snoozeMin", 5)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun scheduleAt(context: Context, alarm: JSONObject, atMs: Long, request: Int) {
        val manager = context.getSystemService(AlarmManager::class.java)
        val operation = ringIntent(context, alarm, request)
        if (Scheduler.canScheduleExact(context)) {
            manager.setAlarmClock(AlarmManager.AlarmClockInfo(atMs, Notices.openApp(context)), operation)
        } else {
            // Without the exact-alarm permission the system may ring late.
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, operation)
        }
    }

    private fun cancelAll(context: Context, alarms: List<JSONObject>) {
        val manager = context.getSystemService(AlarmManager::class.java)
        for (a in alarms) {
            val id = a.getInt("id")
            manager.cancel(ringIntent(context, a, 1000 + id))
            manager.cancel(ringIntent(context, a, 2000 + id))
        }
    }

    /** Replaces every alarm with [alarms] and schedules each next ring. */
    fun set(context: Context, alarms: JSONArray) {
        synchronized(SecureStore.lock) {
            cancelAll(context, load(context))
            SecureStore.write(context, STORE, alarms.toString())
        }
        rescheduleAll(context)
    }

    fun rescheduleAll(context: Context) {
        val now = System.currentTimeMillis()
        for (a in load(context)) {
            val next = nextAt(a.getInt("minuteOfDay"), a.getInt("daysMask"), now) ?: continue
            scheduleAt(context, a, next, 1000 + a.getInt("id"))
        }
    }

    fun nextRings(context: Context): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        return load(context).mapNotNull { a ->
            nextAt(a.getInt("minuteOfDay"), a.getInt("daysMask"), now)?.let { mapOf("id" to a.getInt("id"), "atMs" to it) }
        }
    }

    fun ring(context: Context, id: Int, label: String, snoozeMin: Int) {
        Notices.ensureChannels(context)
        val screen = PendingIntent.getActivity(
            context,
            5000 + id,
            Intent(context, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                .putExtra("id", id)
                .putExtra("label", label)
                .putExtra("snooze", snoozeMin),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        fun action(kind: String, request: Int) = PendingIntent.getBroadcast(
            context,
            request,
            Intent(context, AlarmReceiver::class.java)
                .setAction(kind)
                .putExtra("id", id)
                .putExtra("label", label)
                .putExtra("snooze", snoozeMin),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(context, Notices.ALARM)
            .setSmallIcon(R.drawable.ic_stat_humanos)
            .setContentTitle("ALARMA")
            .setContentText(label)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setFullScreenIntent(screen, true)
            .setContentIntent(screen)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "APAGAR", action(ACTION_STOP, 6000 + id)).build())
            .addAction(Notification.Action.Builder(null, "POSPONER $snoozeMin MIN", action(ACTION_SNOOZE, 7000 + id)).build())
            .build()
        // Repeats the alarm sound until the user answers.
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        context.getSystemService(NotificationManager::class.java).notify(notificationId(id), notification)

        // Repeating alarms: schedule the next ring right away.
        load(context).firstOrNull { it.getInt("id") == id }?.let { a ->
            nextAt(a.getInt("minuteOfDay"), a.getInt("daysMask"), System.currentTimeMillis() + 60_000L)
                ?.let { scheduleAt(context, a, it, 1000 + id) }
        }
    }

    fun stop(context: Context, id: Int) = Notices.cancel(context, notificationId(id))

    fun snooze(context: Context, id: Int, label: String, minutes: Int) {
        stop(context, id)
        val alarm = JSONObject().put("id", id).put("label", label).put("snoozeMin", minutes)
        scheduleAt(context, alarm, System.currentTimeMillis() + minutes * 60_000L, 2000 + id)
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val label = intent.getStringExtra("label") ?: "Alarma"
        val snooze = intent.getIntExtra("snooze", 5)
        when (intent.action) {
            Alarms.ACTION_RING -> Alarms.ring(context, id, label, snooze)
            Alarms.ACTION_STOP -> Alarms.stop(context, id)
            Alarms.ACTION_SNOOZE -> Alarms.snooze(context, id, label, snooze)
        }
    }
}

/** Full-screen alarm over the lock screen: two big buttons. */
class AlarmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val id = intent.getIntExtra("id", 0)
        val label = intent.getStringExtra("label") ?: "Alarma"
        val snooze = intent.getIntExtra("snooze", 5)
        val accent = Color.rgb(0x39, 0xFF, 0x14)

        fun big(text: String, onTap: () -> Unit) = Button(this).apply {
            this.text = text
            textSize = 28f
            setTextColor(Color.BLACK)
            setBackgroundColor(accent)
            setPadding(0, 48, 0, 48)
            setOnClickListener {
                onTap()
                finish()
            }
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(48, 48, 48, 48)
            addView(TextView(this@AlarmActivity).apply {
                text = label
                textSize = 36f
                setTextColor(accent)
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 96)
            })
            val spaced = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { setMargins(0, 24, 0, 24) }
            addView(big("APAGAR") { Alarms.stop(this@AlarmActivity, id) }, spaced)
            addView(big("POSPONER $snooze MIN") { Alarms.snooze(this@AlarmActivity, id, label, snooze) }, spaced)
        }
        setContentView(root)
    }
}
