package com.altair.humanos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the phone knows about the user's zones while the app is closed:
 * which zones it is inside (from ENTER/EXIT transitions), which of them
 * silence reminders, the user's manual correction and the transitions the
 * app has not read yet. Zone names and kinds never reach this file; only
 * ids, coordinates (for re-registration) and a "silences" flag.
 */
object ContextState {
    private const val STATE = "context_state"
    private const val QUEUE = "context_events"
    private const val EVENT_REMINDERS = "event_reminders"
    private const val MAX_QUEUE = 500

    data class Zone(
        val id: Int,
        val latitude: Double,
        val longitude: Double,
        val radiusM: Float,
        val silences: Boolean,
    )

    private fun state(context: Context): JSONObject =
        SecureStore.read(context, STATE)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()

    private fun save(context: Context, value: JSONObject) = SecureStore.write(context, STATE, value.toString())

    fun saveZones(context: Context, zones: List<Zone>, responsivenessMs: Int, staleMs: Long) {
        synchronized(SecureStore.lock) {
            val s = state(context)
            s.put("zones", JSONArray().apply {
                for (z in zones) {
                    put(JSONObject()
                        .put("id", z.id)
                        .put("lat", z.latitude)
                        .put("lon", z.longitude)
                        .put("radius", z.radiusM.toDouble())
                        .put("silences", z.silences))
                }
            })
            s.put("responsivenessMs", responsivenessMs)
            s.put("staleMs", staleMs)
            // Zones removed by the user no longer count as "inside".
            val ids = zones.map { it.id.toString() }.toSet()
            val inside = s.optJSONObject("inside") ?: JSONObject()
            val keep = JSONObject()
            for (key in inside.keys()) if (key in ids) keep.put(key, inside.getLong(key))
            s.put("inside", keep)
            s.remove("lostCode")
            save(context, s)
        }
    }

    fun zones(context: Context): List<Zone> {
        val array = state(context).optJSONArray("zones") ?: return emptyList()
        return (0 until array.length()).map {
            val o = array.getJSONObject(it)
            Zone(
                o.getInt("id"),
                o.getDouble("lat"),
                o.getDouble("lon"),
                o.getDouble("radius").toFloat(),
                o.optBoolean("silences"),
            )
        }
    }

    fun responsivenessMs(context: Context): Int = state(context).optInt("responsivenessMs", 180_000)

    /** Records a transition and queues it for the app. */
    fun onTransition(context: Context, zoneId: Int, transition: String, atMs: Long) {
        synchronized(SecureStore.lock) {
            val s = state(context)
            val inside = s.optJSONObject("inside") ?: JSONObject()
            if (transition == "entrar") inside.put(zoneId.toString(), atMs) else inside.remove(zoneId.toString())
            s.put("inside", inside)
            s.put("lastEventMs", atMs)
            save(context, s)

            val queue = SecureStore.read(context, QUEUE)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: JSONArray()
            queue.put(JSONObject().put("zoneId", zoneId).put("transition", transition).put("atMs", atMs))
            val trimmed = JSONArray()
            val from = maxOf(0, queue.length() - MAX_QUEUE)
            for (i in from until queue.length()) trimmed.put(queue.get(i))
            SecureStore.write(context, QUEUE, trimmed.toString())
        }
    }

    /** Transitions not yet stored by the app, oldest first; the queue empties. */
    fun drain(context: Context): JSONArray {
        synchronized(SecureStore.lock) {
            val queue = SecureStore.read(context, QUEUE)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: JSONArray()
            SecureStore.write(context, QUEUE, "[]")
            return queue
        }
    }

    /** Geofences dropped by the system (location turned off, for example). */
    fun markLost(context: Context, code: Int) {
        synchronized(SecureStore.lock) {
            val s = state(context)
            s.put("lostCode", code)
            save(context, s)
        }
    }

    /** The user's correction: silencing or not until [untilMs]; null clears it. */
    fun setManual(context: Context, silencing: Boolean?, untilMs: Long?) {
        synchronized(SecureStore.lock) {
            val s = state(context)
            if (silencing == null || untilMs == null) {
                s.remove("manual")
            } else {
                s.put("manual", JSONObject().put("silencing", silencing).put("untilMs", untilMs))
            }
            save(context, s)
        }
    }

    /** Reminders are held back: by the user's correction, or by a silencing zone. */
    fun isSilenced(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean {
        val s = state(context)
        val manual = s.optJSONObject("manual")
        if (manual != null && manual.optLong("untilMs") > nowMs) return manual.optBoolean("silencing")
        val stale = s.optLong("staleMs", 16L * 3_600_000L)
        val silencing = zones(context).filter { it.silences }.map { it.id.toString() }.toSet()
        val inside = s.optJSONObject("inside") ?: return false
        for (key in inside.keys()) {
            if (key in silencing && nowMs - inside.getLong(key) < stale) return true
        }
        return false
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val s = state(context)
        val inside = s.optJSONObject("inside") ?: JSONObject()
        return mapOf(
            "inside" to inside.keys().asSequence().mapNotNull { it.toIntOrNull() }.toList(),
            "silenced" to isSilenced(context),
            "zones" to zones(context).size,
            "lostCode" to (if (s.has("lostCode")) s.getInt("lostCode") else null),
            "lastEventMs" to (if (s.has("lastEventMs")) s.getLong("lastEventMs") else null),
        )
    }

    fun saveEventReminders(context: Context, json: String) = SecureStore.write(context, EVENT_REMINDERS, json)

    /**
     * Posts the user's reminders for [trigger] ("llegar" or "salir") at
     * [zoneId] (null: the manual buttons without a zone).
     */
    fun fireEventReminders(context: Context, trigger: String, zoneId: Int?) {
        val array = SecureStore.read(context, EVENT_REMINDERS)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: return
        for (i in 0 until array.length()) {
            val r = array.getJSONObject(i)
            if (r.optString("trigger") != trigger) continue
            val ids = r.optJSONArray("zoneIds") ?: JSONArray()
            val any = ids.length() == 0
            val matches = any || (zoneId != null && (0 until ids.length()).any { ids.getInt(it) == zoneId })
            if (!matches) continue
            Notices.post(
                context,
                4000 + r.getInt("id"),
                Notices.EVENTS,
                if (trigger == "llegar") "AL LLEGAR" else "AL SALIR",
                r.optString("message"),
            )
        }
    }
}
