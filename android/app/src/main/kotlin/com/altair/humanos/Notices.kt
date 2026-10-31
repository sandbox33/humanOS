package com.altair.humanos

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager

/**
 * Notification channels and posting. Every notification is private on the
 * lock screen: only "HumanOS" shows until the phone is unlocked.
 */
object Notices {
    const val MEALS = "humanos_comidas"
    const val THERMOS = "humanos_termo"
    const val TRAINING = "humanos_entreno"
    const val DAY_CLOSE = "humanos_cierre"
    const val EVENTS = "humanos_eventos"
    const val ALARM = "humanos_alarma_v1"

    private val names = mapOf(
        MEALS to ("Comidas" to "Recordatorios de comidas alrededor de tu trabajo"),
        THERMOS to ("Termo" to "Antes de un trabajo con calor y en su pausa"),
        TRAINING to ("Heavy Duty" to "Día de la próxima sesión"),
        DAY_CLOSE to ("Cierre del día" to "Recordatorio opcional para registrar el día"),
        EVENTS to ("Al llegar o salir" to "Tus recordatorios al llegar a una zona o al salir"),
    )

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        for ((id, text) in names) {
            val importance = if (id == DAY_CLOSE) {
                NotificationManager.IMPORTANCE_DEFAULT
            } else {
                NotificationManager.IMPORTANCE_HIGH
            }
            manager.createNotificationChannel(
                NotificationChannel(id, text.first, importance).apply {
                    description = text.second
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }
        manager.createNotificationChannel(
            NotificationChannel(ALARM, "Alarmas", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Tus alarmas de la mañana: suenan con volumen de alarma"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            },
        )
    }

    fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun publicVersion(context: Context, channel: String): Notification =
        Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_humanos)
            .setContentTitle("HumanOS")
            .setContentText("Tienes un recordatorio")
            .build()

    fun post(context: Context, id: Int, channel: String, title: String, body: String) {
        ensureChannels(context)
        val notification = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_humanos)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion(context, channel))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(id, notification)
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(NotificationManager::class.java).cancel(id)
    }
}
