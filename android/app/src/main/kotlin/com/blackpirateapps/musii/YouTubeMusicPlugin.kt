package com.blackpirateapps.musii

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal class YouTubeMusicPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val videoIdPattern = Regex("[A-Za-z0-9_-]{11}")
    private lateinit var channel: MethodChannel
    private lateinit var worker: ExecutorService
    private lateinit var catalogWorker: ExecutorService
    private val resolver = YouTubeMusicResolver()
    private val catalog = YouTubeMusicCatalog()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        worker = Executors.newFixedThreadPool(2)
        catalogWorker = Executors.newFixedThreadPool(2)
        channel = MethodChannel(binding.binaryMessenger, "musii/youtube_music")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("getTrack", "resolveAudio", "getHome", "searchSongs")) {
            result.notImplemented()
            return
        }
        val videoId = call.argument<String>("videoId")
        if ((call.method == "getTrack" || call.method == "resolveAudio") &&
            (videoId == null || !videoIdPattern.matches(videoId))) {
            result.error("invalid_id", "Invalid video ID", null)
            return
        }
        val executor = if (call.method == "getHome" || call.method == "searchSongs") {
            catalogWorker
        } else {
            worker
        }
        executor.execute {
            val reply = runCatching {
                when (call.method) {
                    "getTrack" -> resolver.getTrack(videoId!!)
                    "resolveAudio" -> mapOf("url" to resolver.resolveAudio(videoId!!))
                    "getHome" -> catalog.getHome()
                    else -> catalog.searchSongs(
                        call.argument<String>("query").orEmpty(),
                        call.argument<String>("nextPage"),
                    )
                }
            }
            main.post {
                if (executor.isShutdown) return@post
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = {
                        val code = when (it) {
                            is ContentNotAvailableException -> "unavailable"
                            is IOException -> "network"
                            else -> "extraction"
                        }
                        // Extractor exception messages may include temporary URLs.
                        result.error(code, null, null)
                    },
                )
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
        catalogWorker.shutdownNow()
    }
}
