package com.altair.humanos

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Channels used by the Dart side:
 *  - `com.altair.humanos/context`: location permissions, zones
 *    (geofences), transitions, the user's correction and system settings
 *    that keep reminders alive on Xiaomi/HyperOS;
 *  - `com.altair.humanos/scheduler`: reminders and morning alarms.
 */
object ContextBridge {
    private const val REQUEST_FOREGROUND = 7101
    private const val REQUEST_BACKGROUND = 7102
    private const val REQUEST_NOTIFICATIONS = 7103

    private var contextChannel: MethodChannel? = null
    private var pending: MethodChannel.Result? = null
    private var activity: Activity? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        this.activity = activity
        Notices.ensureChannels(activity)
        val channel = MethodChannel(messenger, "com.altair.humanos/context")
        contextChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "access" -> result.success(access(activity))
                "requestForeground" -> request(
                    activity,
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                    REQUEST_FOREGROUND,
                    result,
                )
                "requestBackground" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    request(activity, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQUEST_BACKGROUND, result)
                } else {
                    result.success(access(activity))
                }
                "requestNotifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    request(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS, result)
                } else {
                    result.success(access(activity))
                }
                "playServices" -> result.success(Geofences.playServicesAvailable(activity))
                "currentLocation" -> currentLocation(activity, result)
                "registerZones" -> {
                    val zones = (call.argument<List<Map<String, Any>>>("zones") ?: emptyList()).map {
                        ContextState.Zone(
                            (it["id"] as Number).toInt(),
                            (it["latitude"] as Number).toDouble(),
                            (it["longitude"] as Number).toDouble(),
                            (it["radiusM"] as Number).toFloat(),
                            it["silences"] == true,
                        )
                    }
                    val responsiveness = call.argument<Int>("responsivenessMs") ?: 180_000
                    val stale = (call.argument<Number>("staleMs") ?: 16L * 3_600_000L).toLong()
                    ContextState.saveZones(activity, zones, responsiveness, stale)
                    Geofences.register(activity, zones, responsiveness) { error ->
                        onMain { result.success(mapOf("ok" to (error == null), "error" to error, "count" to zones.size)) }
                    }
                }
                "drainEvents" -> {
                    val queue = ContextState.drain(activity)
                    result.success((0 until queue.length()).map {
                        val o = queue.getJSONObject(it)
                        mapOf("zoneId" to o.getInt("zoneId"), "transition" to o.getString("transition"), "atMs" to o.getLong("atMs"))
                    })
                }
                "state" -> result.success(ContextState.snapshot(activity))
                "setManual" -> {
                    val silencing = call.argument<Boolean>("silencing")
                    val until = call.argument<Number>("untilMs")?.toLong()
                    val was = ContextState.isSilenced(activity)
                    ContextState.setManual(activity, silencing, until)
                    if (was && !ContextState.isSilenced(activity)) Scheduler.flushDeferred(activity)
                    result.success(null)
                }
                "setEventReminders" -> {
                    ContextState.saveEventReminders(activity, JSONArray(call.argument<List<Any>>("reminders") ?: emptyList<Any>()).toString())
                    result.success(null)
                }
                "fireManual" -> {
                    ContextState.fireEventReminders(activity, call.argument<String>("trigger") ?: "llegar", call.argument<Int>("zoneId"))
                    result.success(null)
                }
                "ignoringBatteryOptimizations" -> result.success(ignoringBattery(activity))
                "requestIgnoreBatteryOptimizations" -> result.success(
                    open(activity, Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, packageUri(activity))),
                )
                "openAutostart" -> result.success(
                    open(activity, Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"))) ||
                        open(activity, appDetails(activity)),
                )
                "openBatterySaver" -> result.success(
                    open(activity, Intent("miui.intent.action.HIDDEN_APPS_CONFIG_ACTIVITY")
                        .putExtra("package_name", activity.packageName)
                        .putExtra("package_label", "HumanOS")) ||
                        open(activity, appDetails(activity)),
                )
                "openAppDetails" -> result.success(open(activity, appDetails(activity)))
                "openLocationSettings" -> result.success(open(activity, Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)))
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "com.altair.humanos/scheduler").setMethodCallHandler { call, result ->
            when (call.method) {
                "setReminders" -> {
                    Scheduler.setReminders(activity, JSONArray(call.argument<List<Any>>("reminders") ?: emptyList<Any>()))
                    result.success(null)
                }
                "setAlarms" -> {
                    Alarms.set(activity, JSONArray(call.argument<List<Any>>("alarms") ?: emptyList<Any>()))
                    result.success(null)
                }
                "nextAlarms" -> result.success(Alarms.nextRings(activity))
                "ringNow" -> {
                    Alarms.ring(activity, 0, call.argument<String>("label") ?: "Prueba de alarma", 5)
                    result.success(null)
                }
                "state" -> result.success(Scheduler.snapshot(activity))
                "openExactAlarmSettings" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        open(activity, Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri(activity))),
                )
                else -> result.notImplemented()
            }
        }
    }

    /** The main engine is alive: ask the app to read the new transitions. */
    fun notifyChanged() {
        val channel = contextChannel ?: return
        onMain { channel.invokeMethod("changed", null) }
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode !in listOf(REQUEST_FOREGROUND, REQUEST_BACKGROUND, REQUEST_NOTIFICATIONS)) return
        val a = activity ?: return
        pending?.success(access(a))
        pending = null
    }

    private fun granted(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun access(context: Context): Map<String, Any> = mapOf(
        "fine" to granted(context, Manifest.permission.ACCESS_FINE_LOCATION),
        "coarse" to granted(context, Manifest.permission.ACCESS_COARSE_LOCATION),
        "background" to Geofences.hasBackground(context),
        "notifications" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            granted(context, Manifest.permission.POST_NOTIFICATIONS)),
    )

    private fun request(activity: Activity, permissions: Array<String>, code: Int, result: MethodChannel.Result) {
        pending?.success(access(activity))
        pending = result
        activity.requestPermissions(permissions, code)
    }

    @SuppressLint("MissingPermission")
    private fun currentLocation(activity: Activity, result: MethodChannel.Result) {
        if (!Geofences.hasFine(activity)) {
            result.success(null)
            return
        }
        // One reading, on request: never continuous updates.
        LocationServices.getFusedLocationProviderClient(activity)
            .getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, CancellationTokenSource().token)
            .addOnSuccessListener { location ->
                result.success(location?.let {
                    mapOf("latitude" to it.latitude, "longitude" to it.longitude, "accuracyM" to it.accuracy.toDouble())
                })
            }
            .addOnFailureListener { result.success(null) }
    }

    private fun ignoringBattery(context: Context): Boolean =
        context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)

    private fun packageUri(context: Context): Uri = Uri.parse("package:${context.packageName}")

    private fun appDetails(context: Context) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri(context))

    private fun open(activity: Activity, intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }
}
