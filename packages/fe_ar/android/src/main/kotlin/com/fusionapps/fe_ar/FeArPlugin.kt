package com.fusionapps.fe_ar

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * fe_ar: the FieldOps native AR engine (docs/ar-bim-overlay.md §6.1).
 *
 * Registers the three names of CONTRACT C8:
 *  - MethodChannel "fusioneco/ar"        commands (method name = ArEngine command)
 *  - EventChannel  "fusioneco/ar/events" low-rate events ({type: ...} maps)
 *  - platform view "fusioneco/ar/view"   the camera + model surface
 * Every argument map is described in packages/fe_ar/CHANNEL.md.
 */
class FeArPlugin : FlutterPlugin, ActivityAware {
    private var controller: FeArController? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val c = FeArController(binding.applicationContext)
        controller = c
        methods = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { it.setMethodCallHandler(c) }
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also { it.setStreamHandler(c) }
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, FeArViewFactory(c))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        controller?.dispose()
        methods = null
        events = null
        controller = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        controller?.attachActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        controller?.detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        controller?.attachActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        controller?.detachActivity()
    }

    companion object {
        const val METHOD_CHANNEL = "fusioneco/ar"
        const val EVENT_CHANNEL = "fusioneco/ar/events"
        const val VIEW_TYPE = "fusioneco/ar/view"
    }
}
