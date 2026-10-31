package com.altair.humanos

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

/**
 * Geofences through Google Play services' GeofencingClient only: no
 * foreground service, no continuous location updates, no route history.
 * The system wakes [GeofenceReceiver] on ENTER and EXIT.
 */
object Geofences {
    private const val ACTION = "com.altair.humanos.GEOFENCE"

    fun playServicesAvailable(context: Context): Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    fun hasFine(context: Context) =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun hasBackground(context: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, GeofenceReceiver::class.java).setAction(ACTION),
        // Mutable: Play services adds the transition to the intent.
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    /**
     * Replaces every geofence with [zones]. [done] receives null on success
     * or a Spanish message.
     */
    @SuppressLint("MissingPermission")
    fun register(context: Context, zones: List<ContextState.Zone>, responsivenessMs: Int, done: (String?) -> Unit) {
        if (!playServicesAvailable(context)) {
            done("Google Play services no está disponible en este teléfono.")
            return
        }
        val client = LocationServices.getGeofencingClient(context)
        val intent = pendingIntent(context)
        client.removeGeofences(intent).addOnCompleteListener {
            if (zones.isEmpty()) {
                done(null)
                return@addOnCompleteListener
            }
            if (!hasFine(context) || !hasBackground(context)) {
                done("Falta el permiso de ubicación «Permitir todo el tiempo».")
                return@addOnCompleteListener
            }
            val fences = zones.map {
                Geofence.Builder()
                    .setRequestId(it.id.toString())
                    .setCircularRegion(it.latitude, it.longitude, it.radiusM)
                    .setExpirationDuration(Geofence.NEVER_EXPIRE)
                    .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                    .setNotificationResponsiveness(responsivenessMs)
                    .build()
            }
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(fences)
                .build()
            client.addGeofences(request, intent)
                .addOnSuccessListener { done(null) }
                .addOnFailureListener { e -> done(describe(e)) }
        }
    }

    /** After a reboot or an app update: the stored zones again. */
    fun reRegister(context: Context) {
        val zones = ContextState.zones(context)
        if (zones.isEmpty()) return
        register(context, zones, ContextState.responsivenessMs(context)) { error ->
            if (error != null) ContextState.markLost(context, -1)
        }
    }

    private fun describe(e: Exception): String {
        val code = (e as? com.google.android.gms.common.api.ApiException)?.statusCode
        return when (code) {
            GeofenceStatusCodes.GEOFENCE_NOT_AVAILABLE ->
                "La ubicación del teléfono está apagada o sin Google: no se pudieron activar las zonas."
            GeofenceStatusCodes.GEOFENCE_TOO_MANY_GEOFENCES -> "Demasiadas zonas para el sistema."
            else -> "No se pudieron activar las zonas (${code ?: e.javaClass.simpleName})."
        }
    }
}

/** ENTER/EXIT from Play services, also while the app is closed. */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) {
            ContextState.markLost(context, event.errorCode)
            return
        }
        val transition = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "entrar"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "salir"
            else -> return
        }
        val now = System.currentTimeMillis()
        val wasSilenced = ContextState.isSilenced(context, now)
        val ids = event.triggeringGeofences?.mapNotNull { it.requestId.toIntOrNull() } ?: emptyList()
        for (id in ids) {
            ContextState.onTransition(context, id, transition, now)
            ContextState.fireEventReminders(context, if (transition == "entrar") "llegar" else "salir", id)
        }
        if (wasSilenced && !ContextState.isSilenced(context, now)) Scheduler.flushDeferred(context)
        ContextBridge.notifyChanged()
    }
}

/** Geofences and alarms are lost on reboot and on app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            -> {
                Geofences.reRegister(context)
                Scheduler.scheduleNext(context)
                Alarms.rescheduleAll(context)
            }
        }
    }
}

/** Runs [block] on the main thread (MethodChannel calls must). */
fun onMain(block: () -> Unit) {
    Handler(Looper.getMainLooper()).post(block)
}
