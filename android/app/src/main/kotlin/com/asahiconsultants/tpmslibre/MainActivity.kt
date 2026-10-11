package com.asahiconsultants.tpmslibre

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import androidx.core.location.LocationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Whether location services are switched on.
 *
 * Android hides BLE advertisements from apps unless location is enabled, and
 * the Bluetooth plugin gives no way to ask — a scan started with location off is
 * accepted and then silently delivers nothing. Inferring it from silence
 * works but takes a minute and can only ever be a guess. LocationManager
 * answers directly, needs no permission to query, and broadcasts every time
 * the setting changes.
 */
private const val METHOD_CHANNEL = "tpmslibre/location"
private const val EVENT_CHANNEL = "tpmslibre/location/changes"

class MainActivity : FlutterActivity() {

    private var receiver: BroadcastReceiver? = null

    private fun locationEnabled(): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return LocationManagerCompat.isLocationEnabled(manager)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(locationEnabled())
                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    sink?.success(locationEnabled())
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            sink?.success(locationEnabled())
                        }
                    }
                    registerReceiver(
                        receiver,
                        IntentFilter(LocationManager.MODE_CHANGED_ACTION),
                    )
                }

                override fun onCancel(args: Any?) {
                    receiver?.let { runCatching { unregisterReceiver(it) } }
                    receiver = null
                }
            })
    }
}
