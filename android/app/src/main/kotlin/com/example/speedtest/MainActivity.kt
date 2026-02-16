package com.example.speedtest

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import net.measurementlab.ndt7.android.Downloader
import net.measurementlab.ndt7.android.NDTTest
import net.measurementlab.ndt7.android.Uploader
import net.measurementlab.ndt7.android.models.CallbackRegistry
import net.measurementlab.ndt7.android.models.ClientResponse
import net.measurementlab.ndt7.android.models.Measurement
import net.measurementlab.ndt7.android.utils.DataConverter
import okhttp3.OkHttpClient
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME = "speedtest"
        private const val EVENT_CHANNEL_NAME = "speedtest_progress"
        private const val DOWNLOAD_TIMEOUT_SECONDS = 25L
        private const val UPLOAD_TIMEOUT_SECONDS = 25L
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var runningTest: RunningSpeedTest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME).setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTest" -> startTest(call, result)
            "cancelTest" -> {
                runningTest?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startTest(call: MethodCall, result: MethodChannel.Result) {
        if (runningTest != null) {
            result.error("already_running", "A speed test is already running", null)
            return
        }
        val downloadUrl = call.argument<String>("downloadUrl")
        val uploadUrl = call.argument<String>("uploadUrl")
        val engine = call.argument<String>("engine")
        if (engine != "ndt7") {
            result.error("unsupported_engine", "Selected engine is not implemented on native layer", null)
            return
        }
        if (downloadUrl.isNullOrBlank() || uploadUrl.isNullOrBlank()) {
            result.error("invalid_args", "engine, downloadUrl and uploadUrl are required", null)
            return
        }

        val test = RunningSpeedTest(downloadUrl, uploadUrl, result)
        runningTest = test
        test.start()
    }

    private fun emitProgress(phase: String, mbps: Double, progress: Double) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "phase" to phase,
                    "mbps" to mbps,
                    "progress" to progress.coerceIn(0.0, 1.0),
                ),
            )
        }
    }

    private fun completeSuccess(result: MethodChannel.Result, downloadMbps: Double, uploadMbps: Double, serverInfo: String?) {
        mainHandler.post {
            result.success(
                mapOf(
                    "downloadMbps" to downloadMbps,
                    "uploadMbps" to uploadMbps,
                    "serverInfo" to serverInfo,
                ),
            )
            runningTest = null
        }
    }

    private fun completeError(result: MethodChannel.Result, message: String) {
        mainHandler.post {
            result.error("native_test_error", message, null)
            runningTest = null
        }
    }

    private inner class RunningSpeedTest(
        private val downloadUrl: String,
        private val uploadUrl: String,
        private val methodResult: MethodChannel.Result,
    ) {
        private val httpClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        @Volatile
        private var cancelled = false

        private var currentExecutor: ExecutorService? = null
        private var downloader: Downloader? = null

        fun start() {
            val launcher = Executors.newSingleThreadExecutor()
            launcher.submit {
                try {
                    val download = runDownload()
                    if (cancelled) {
                        completeError(methodResult, "cancelled")
                        return@submit
                    }
                    if (download.error != null) {
                        completeError(methodResult, download.error.localizedMessage ?: "Download phase failed")
                        return@submit
                    }

                    val upload = runUpload()
                    if (cancelled) {
                        completeError(methodResult, "cancelled")
                        return@submit
                    }
                    if (upload.error != null) {
                        completeError(methodResult, upload.error.localizedMessage ?: "Upload phase failed")
                        return@submit
                    }
                    val serverInfo = try {
                        java.net.URI(downloadUrl).host
                    } catch (_: Exception) {
                        null
                    }
                    completeSuccess(methodResult, download.mbps, upload.mbps, serverInfo)
                } catch (error: Exception) {
                    completeError(methodResult, error.localizedMessage ?: "Unexpected error")
                } finally {
                    launcher.shutdownNow()
                }
            }
        }

        fun cancel() {
            cancelled = true
            downloader?.cancel()
            currentExecutor?.shutdownNow()
        }

        private fun runDownload(): PhaseOutcome {
            val latch = CountDownLatch(1)
            val callback = DownloadCallbacks(latch)
            val executor = Executors.newSingleThreadExecutor()
            currentExecutor = executor
            val lock = Semaphore(0)
            val registry = CallbackRegistry(callback::onProgress, callback::onMeasurement, callback::onFinished)
            val phaseDownloader = Downloader(registry, executor, lock)
            downloader = phaseDownloader
            phaseDownloader.beginDownload(downloadUrl, httpClient)
            val completed = latch.await(DOWNLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            executor.shutdownNow()
            if (!completed) {
                return PhaseOutcome(callback.lastMbps, RuntimeException("Download timeout"))
            }
            return PhaseOutcome(callback.finalMbps, callback.error)
        }

        private fun runUpload(): PhaseOutcome {
            val latch = CountDownLatch(1)
            val callback = UploadCallbacks(latch)
            val executor = Executors.newSingleThreadExecutor()
            currentExecutor = executor
            val lock = Semaphore(0)
            val registry = CallbackRegistry(callback::onProgress, callback::onMeasurement, callback::onFinished)
            val uploader = Uploader(registry, executor, lock)
            uploader.beginUpload(uploadUrl, httpClient)
            val completed = latch.await(UPLOAD_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            executor.shutdownNow()
            if (!completed) {
                return PhaseOutcome(callback.lastMbps, RuntimeException("Upload timeout"))
            }
            return PhaseOutcome(callback.finalMbps, callback.error)
        }
    }

    private data class PhaseOutcome(val mbps: Double, val error: Throwable?)

    private abstract inner class BaseCallbacks(private val phase: String, private val latch: CountDownLatch) {
        var lastMbps: Double = 0.0
        var finalMbps: Double = 0.0
        var error: Throwable? = null

        fun onMeasurement(measurement: Measurement) {
            // No-op: measurements are not required for current UI, but callback is mandatory.
            measurement.hashCode()
        }

        fun onProgress(clientResponse: ClientResponse) {
            val mbps = DataConverter.convertToMbps(clientResponse).toDoubleOrNull() ?: 0.0
            lastMbps = mbps
            val elapsedMicros = clientResponse.appInfo.elapsedTime.toDouble()
            val progress = (elapsedMicros / 10_000_000.0).coerceIn(0.0, 1.0)
            emitProgress(phase, mbps, progress)
        }

        fun onFinished(clientResponse: ClientResponse, failure: Throwable?, testType: NDTTest.TestType) {
            testType.hashCode()
            error = failure
            finalMbps = DataConverter.convertToMbps(clientResponse).toDoubleOrNull() ?: lastMbps
            emitProgress(phase, finalMbps, 1.0)
            latch.countDown()
        }
    }

    private inner class DownloadCallbacks(latch: CountDownLatch) : BaseCallbacks("download", latch)

    private inner class UploadCallbacks(latch: CountDownLatch) : BaseCallbacks("upload", latch)
}
