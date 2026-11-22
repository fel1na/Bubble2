package com.bubble.bubble

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Native Android LocalOnlyHotspot controller.
 * Fixes the hardcoded 192.168.43.1 bug from Bubble v1 by inspecting active IPv4 interfaces.
 */
class LocalHotspotPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var isActive = false

    companion object {
        const val CHANNEL = "com.bubble/hotspot"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(LocalHotspotPlugin(context))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startHotspot" -> startHotspot(result)
            "stopHotspot" -> {
                stopHotspot()
                result.success(true)
            }
            "isHotspotActive" -> result.success(isActive)
            "getLocalIpAddress" -> result.success(resolveHotspotIp())
            else -> result.notImplemented()
        }
    }

    private fun startHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED_OS", "LocalOnlyHotspot requires Android 8.0+", null)
            return
        }

        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation?) {
                        super.onStarted(res)
                        reservation = res
                        isActive = true

                        val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            res?.softApConfiguration?.ssid ?: "BubbleHotspot"
                        } else {
                            @Suppress("DEPRECATION")
                            res?.wifiConfiguration?.SSID ?: "BubbleHotspot"
                        }

                        val password = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            res?.softApConfiguration?.passphrase ?: ""
                        } else {
                            @Suppress("DEPRECATION")
                            res?.wifiConfiguration?.preSharedKey ?: ""
                        }

                        val ip = resolveHotspotIp()
                        result.success(
                            mapOf(
                                "ssid" to ssid,
                                "password" to password,
                                "ip" to ip
                            )
                        )
                    }

                    override fun onStopped() {
                        super.onStopped()
                        isActive = false
                        reservation = null
                    }

                    override fun onFailed(reason: Int) {
                        super.onFailed(reason)
                        isActive = false
                        result.error("HOTSPOT_FAILED", "Failed with reason code $reason", null)
                    }
                },
                Handler(Looper.getMainLooper())
            )
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: Exception) {
            result.error("HOTSPOT_ERROR", e.message, null)
        }
    }

    private fun stopHotspot() {
        try {
            reservation?.close()
        } catch (_: Exception) {
        } finally {
            reservation = null
            isActive = false
        }
    }

    private fun resolveHotspotIp(): String {
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            val candidates = mutableListOf<String>()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (!iface.isUp || iface.isLoopback) continue
                val addrs = iface.inetAddresses
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement()
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val host = addr.hostAddress ?: continue
                        // Prefer AP interfaces (ap0 / wlan / swlan) and common soft-AP subnets
                        if (iface.name.contains("ap", ignoreCase = true) || host.startsWith("192.168.")) {
                            return host
                        }
                        candidates.add(host)
                    }
                }
            }
            candidates.firstOrNull() ?: "192.168.43.1"
        } catch (_: Exception) {
            "192.168.43.1"
        }
    }
}
