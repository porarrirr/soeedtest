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
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.Semaphore

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME = "speedtest"
        private const val EVENT_CHANNEL_NAME = "speedtest_progress"
        private const val DOWNLOAD_TIMEOUT_SECONDS = 25L
        private const val UPLOAD_TIMEOUT_SECONDS = 25L
        private const val CLI_TIMEOUT_SECONDS = 90L
    }

    private interface RunningTest {
        fun start()
        fun cancel()
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var runningTest: RunningTest? = null

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
            "startTest" -> startNdtStyleTest(call, result)
            "startNperfTest" -> startNperfTest(call, result)
            "startCliTest" -> startCliTest(call, result)
            "cancelTest", "cancelNperfTest", "cancelCliTest" -> {
                runningTest?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startNdtStyleTest(call: MethodCall, result: MethodChannel.Result) {
        if (runningTest != null) {
            result.error("already_running", "A speed test is already running", null)
            return
        }
        val downloadUrl = call.argument<String>("downloadUrl")
        val uploadUrl = call.argument<String>("uploadUrl")
        val engine = call.argument<String>("engine")
        if (engine != "ndt7" && engine != "nperf") {
            result.error("unsupported_engine", "Selected engine is not implemented on native layer", null)
            return
        }
        if (downloadUrl.isNullOrBlank() || uploadUrl.isNullOrBlank()) {
            result.error("invalid_args", "downloadUrl and uploadUrl are required", null)
            return
        }

        val test = RunningNdtSpeedTest(downloadUrl, uploadUrl, result)
        runningTest = test
        test.start()
    }

    private fun startNperfTest(call: MethodCall, result: MethodChannel.Result) {
        if (runningTest != null) {
            result.error("already_running", "A speed test is already running", null)
            return
        }
        val downloadUrl = call.argument<String>("downloadUrl")
        val uploadUrl = call.argument<String>("uploadUrl")
        if (downloadUrl.isNullOrBlank() || uploadUrl.isNullOrBlank()) {
            result.error("invalid_args", "downloadUrl and uploadUrl are required", null)
            return
        }

        // NOTE: Native nPerf SDK integration point.
        // Current implementation runs NDT-style flow to keep end-to-end behavior available.
        val test = RunningNdtSpeedTest(downloadUrl, uploadUrl, result)
        runningTest = test
        test.start()
    }

    private fun startCliTest(call: MethodCall, result: MethodChannel.Result) {
        if (runningTest != null) {
            result.error("already_running", "A speed test is already running", null)
            return
        }
        val providerOrder = call.argument<List<*>>("providerOrder")
            ?.mapNotNull { it?.toString()?.trim()?.lowercase() }
            ?.filter { it.isNotEmpty() }
            ?: listOf("ookla", "python")

        val test = RunningCliSpeedTest(providerOrder, result)
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

    private inner class RunningNdtSpeedTest(
        private val downloadUrl: String,
        private val uploadUrl: String,
        private val methodResult: MethodChannel.Result,
    ) : RunningTest {
        private val httpClient: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()

        @Volatile
        private var cancelled = false

        private var currentExecutor: ExecutorService? = null
        private var downloader: Downloader? = null

        override fun start() {
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

        override fun cancel() {
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

    private inner class RunningCliSpeedTest(
        private val providerOrder: List<String>,
        private val methodResult: MethodChannel.Result,
    ) : RunningTest {
        @Volatile
        private var cancelled = false

        @Volatile
        private var process: Process? = null

        override fun start() {
            val launcher = Executors.newSingleThreadExecutor()
            launcher.submit {
                try {
                    emitProgress("download", 0.0, 0.05)
                    val commands = buildCliCommands(providerOrder)
                    if (commands.isEmpty()) {
                        completeError(methodResult, "No CLI providers configured")
                        return@submit
                    }

                    var lastError: String = "No CLI command succeeded"
                    for ((index, command) in commands.withIndex()) {
                        if (cancelled) {
                            completeError(methodResult, "cancelled")
                            return@submit
                        }
                        val progressBase = 0.15 + (index.toDouble() / commands.size.toDouble()) * 0.5
                        emitProgress("download", 0.0, progressBase)
                        try {
                            val output = executeCliCommand(command.args)
                            val parsed = parseCliResult(command.provider, output)
                            emitProgress("upload", parsed.uploadMbps, 0.95)
                            completeSuccess(
                                methodResult,
                                parsed.downloadMbps,
                                parsed.uploadMbps,
                                parsed.serverInfo,
                            )
                            return@submit
                        } catch (error: Exception) {
                            lastError = error.localizedMessage ?: "CLI execution failed"
                        }
                    }
                    completeError(methodResult, lastError)
                } finally {
                    launcher.shutdownNow()
                }
            }
        }

        override fun cancel() {
            cancelled = true
            process?.destroyForcibly()
        }

        private fun executeCliCommand(args: List<String>): String {
            val started = ProcessBuilder(args)
                .redirectErrorStream(true)
                .start()
            process = started
            val output = started.inputStream.bufferedReader().use { it.readText() }
            val finished = started.waitFor(CLI_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                started.destroyForcibly()
                throw RuntimeException("CLI timeout")
            }
            if (started.exitValue() != 0) {
                throw RuntimeException("CLI exited with ${started.exitValue()}: $output")
            }
            return output
        }

        private fun buildCliCommands(order: List<String>): List<CliCommand> {
            val commands = mutableListOf<CliCommand>()
            for (provider in order) {
                when (provider) {
                    "ookla" -> {
                        val embedded = prepareEmbeddedBinary("cli/speedtest", "speedtest")
                        if (embedded != null) {
                            commands += CliCommand(
                                "ookla",
                                listOf(
                                    embedded.absolutePath,
                                    "--accept-license",
                                    "--accept-gdpr",
                                    "--format=json",
                                ),
                            )
                        }
                        commands += CliCommand(
                            "ookla",
                            listOf(
                                "speedtest",
                                "--accept-license",
                                "--accept-gdpr",
                                "--format=json",
                            ),
                        )
                    }

                    "python" -> {
                        val embedded = prepareEmbeddedBinary("cli/speedtest-cli", "speedtest-cli")
                        if (embedded != null) {
                            commands += CliCommand(
                                "python",
                                listOf(embedded.absolutePath, "--json"),
                            )
                        }
                        commands += CliCommand("python", listOf("speedtest-cli", "--json"))
                    }
                }
            }
            return commands
        }

        private fun prepareEmbeddedBinary(assetPath: String, outputName: String): File? {
            return try {
                val outputDir = File(filesDir, "cli").apply { mkdirs() }
                val outputFile = File(outputDir, outputName)
                assets.open(assetPath).use { input ->
                    FileOutputStream(outputFile).use { output ->
                        input.copyTo(output)
                    }
                }
                outputFile.setExecutable(true, true)
                outputFile
            } catch (_: Exception) {
                null
            }
        }

        private fun parseCliResult(provider: String, raw: String): CliParsedResult {
            val json = JSONObject(raw.trim())
            return if (provider == "ookla") {
                val downloadBandwidth = json.optJSONObject("download")?.optDouble("bandwidth", 0.0) ?: 0.0
                val uploadBandwidth = json.optJSONObject("upload")?.optDouble("bandwidth", 0.0) ?: 0.0
                val download = if (downloadBandwidth > 0) downloadBandwidth * 8 / 1_000_000 else json.optDouble("download", 0.0) / 1_000_000
                val upload = if (uploadBandwidth > 0) uploadBandwidth * 8 / 1_000_000 else json.optDouble("upload", 0.0) / 1_000_000
                if (download <= 0 && upload <= 0) {
                    throw RuntimeException("Ookla CLI result parsing failed")
                }
                val server = json.optJSONObject("server")
                val serverInfo = listOf(
                    server?.optString("name"),
                    server?.optString("location"),
                    server?.optString("country"),
                ).filterNotNull().filter { it.isNotBlank() }.joinToString(" / ").ifBlank { null }
                CliParsedResult(download, upload, serverInfo)
            } else {
                val download = json.optDouble("download", 0.0) / 1_000_000
                val upload = json.optDouble("upload", 0.0) / 1_000_000
                if (download <= 0 && upload <= 0) {
                    throw RuntimeException("speedtest-cli result parsing failed")
                }
                val server = json.optJSONObject("server")
                val serverInfo = listOf(
                    server?.optString("sponsor"),
                    server?.optString("name"),
                    server?.optString("country"),
                ).filterNotNull().filter { it.isNotBlank() }.joinToString(" / ").ifBlank { null }
                CliParsedResult(download, upload, serverInfo)
            }
        }
    }

    private data class CliCommand(val provider: String, val args: List<String>)
    private data class CliParsedResult(val downloadMbps: Double, val uploadMbps: Double, val serverInfo: String?)
    private data class PhaseOutcome(val mbps: Double, val error: Throwable?)

    private abstract inner class BaseCallbacks(private val phase: String, private val latch: CountDownLatch) {
        var lastMbps: Double = 0.0
        var finalMbps: Double = 0.0
        var error: Throwable? = null

        fun onMeasurement(measurement: Measurement) {
            // Measurement callbacks are intentionally ignored by current UI.
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
