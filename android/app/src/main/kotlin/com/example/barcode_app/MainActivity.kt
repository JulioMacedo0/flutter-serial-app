package com.example.barcode_app

import io.flutter.embedding.android.FlutterActivity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine


import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {
    private val CHANNEL = "kiosk_mode"
    private lateinit var dpm: DevicePolicyManager
    private lateinit var adminComponent: ComponentName

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, AdminReceiver::class.java)

        // Verifica se o app é Device Owner
        if (dpm.isDeviceOwnerApp(packageName)) {
            // Define o app como permitido para Lock Task
            dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
            // Inicia o Lock Task Mode
            startLockTask()
        }
    }

    override fun onBackPressed() {
        // Impede que o botão "voltar" saia do Lock Task Mode
        if (dpm.isLockTaskPermitted(packageName)) {
            return
        }
        super.onBackPressed()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, AdminReceiver::class.java)


        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startKioskMode" -> {
                    if (dpm.isDeviceOwnerApp(packageName)) {
                        dpm.setLockTaskPackages(adminComponent, arrayOf(packageName))
                        startLockTask()
                        result.success("Kiosk Mode iniciado")
                    } else {
                        result.error("NOT_DEVICE_OWNER", "App não é Device Owner", null)
                    }
                }
                "stopKioskMode" -> {
                    if (dpm.isLockTaskPermitted(packageName)) {
                        stopLockTask()
                        result.success("Kiosk Mode parado")
                    } else {
                        result.error("NOT_IN_KIOSK", "App não está em Kiosk Mode", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
