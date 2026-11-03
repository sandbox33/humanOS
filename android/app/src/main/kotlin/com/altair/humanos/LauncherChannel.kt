package com.altair.humanos

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.provider.Settings
import android.telecom.TelecomManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * HumanOS as the phone's home screen (`com.altair.humanos/launcher`).
 *
 * - `apps`: every launchable app (package, label) except HumanOS.
 * - `icon`: one app's icon as PNG bytes (small, cached by Dart).
 * - `launch`, `appDetails`: open an app or its system settings page.
 * - `openHomeSettings`: Ajustes → Apps predeterminadas (the escape route).
 * - `isDefaultHome`: whether HumanOS is the current home screen.
 * - `dialer`: the phone's own dialer app, never a hard-coded package.
 *
 * Calls that touch the package manager run off the main thread.
 */
object LauncherChannel {
    private const val NAME = "com.altair.humanos/launcher"
    private val worker = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, NAME)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            val context = activity.applicationContext
            when (call.method) {
                "apps" -> background(activity, result) { apps(context) }
                "icon" -> background(activity, result) {
                    icon(context, call.argument<String>("package") ?: "", call.argument<Int>("size") ?: 96)
                }
                "launch" -> result.success(launch(activity, call.argument<String>("package") ?: ""))
                "appDetails" -> result.success(
                    start(activity, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:" + (call.argument<String>("package") ?: "")))),
                )
                "openHomeSettings" -> result.success(
                    start(activity, Intent(Settings.ACTION_HOME_SETTINGS)) ||
                        start(activity, Intent(Settings.ACTION_SETTINGS)),
                )
                "isDefaultHome" -> result.success(defaultHome(context) == context.packageName)
                "dialer" -> result.success(dialer(context))
                "openDialer" -> result.success(start(activity, Intent(Intent.ACTION_DIAL)))
                else -> result.notImplemented()
            }
        }
    }

    /** The home button was pressed while HumanOS was already the home screen. */
    fun homePressed() {
        channel?.invokeMethod("homePressed", null)
    }

    private fun background(activity: Activity, result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            val value = try {
                Result.success(work())
            } catch (e: Exception) {
                Result.failure(e)
            }
            activity.runOnUiThread {
                value.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("launcher", it.message, null) },
                )
            }
        }
    }

    private fun apps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val found = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any>>()
        for (info in found) {
            val pkg = info.activityInfo.packageName
            if (pkg == context.packageName || !seen.add(pkg)) continue
            out.add(mapOf("package" to pkg, "label" to info.loadLabel(pm).toString()))
        }
        return out.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun icon(context: Context, pkg: String, size: Int): ByteArray? {
        val drawable = try {
            context.packageManager.getApplicationIcon(pkg)
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private fun launch(activity: Activity, pkg: String): Boolean {
        val intent = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return start(activity, intent)
    }

    private fun start(activity: Activity, intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    private fun defaultHome(context: Context): String? = context.packageManager
        .resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo?.packageName

    private fun dialer(context: Context): String? {
        val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
        return telecom?.defaultDialerPackage
            ?: context.packageManager.resolveActivity(Intent(Intent.ACTION_DIAL), 0)?.activityInfo?.packageName
    }
}
