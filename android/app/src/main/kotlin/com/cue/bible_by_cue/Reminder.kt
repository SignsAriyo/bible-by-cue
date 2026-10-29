package com.cue.bible_by_cue

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * A battery-friendly daily reminder. Each alarm may fire within a 15-minute window and
 * schedules the next day's when it fires; an inexact repeating alarm could arrive up to
 * 18 hours late. Windowed alarms do not need the exact-alarm permission.
 */
object Reminder {
    private const val PREFS = "reminder"
    private const val CHANNEL = "daily_reading"
    const val ACTION = "com.cue.bible_by_cue.REMIND"
    private const val WINDOW_MS = 15 * 60 * 1000L

    fun configure(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("enabled", enabled).putInt("hour", hour).putInt("minute", minute).apply()
        schedule(context)
    }

    fun schedule(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            context, 1, Intent(context, ReminderReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms.cancel(pi)
        if (!prefs.getBoolean("enabled", false)) return
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, prefs.getInt("hour", 7))
            set(Calendar.MINUTE, prefs.getInt("minute", 0))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        alarms.setWindow(AlarmManager.RTC_WAKEUP, next.timeInMillis, WINDOW_MS, pi)
    }

    fun show(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Daily reading", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_book)
            .setContentTitle("Time for today’s reading")
            .setContentText("Take a quiet moment with the Scriptures.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(1, n)
        } catch (_: SecurityException) {
            // Notification permission was revoked; nothing to show.
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Reminder.ACTION -> {
                Reminder.show(context)
                Reminder.schedule(context) // tomorrow's reminder
            }
            else -> Reminder.schedule(context) // boot completed or app updated
        }
    }
}
