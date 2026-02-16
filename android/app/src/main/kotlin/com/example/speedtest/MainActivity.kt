package com.example.speedtest

import android.os.Build
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
        val providerOrder = (call.argument<List<Any?>>("providerOrder") ?: emptyList())
            .mapNotNull { (it as? String)?.trim()?.lowercase() }
            .filter { it.isNotBlank() }
            .ifEmpty { listOf("ookla") }
        val test = RunningCliSpeedTest(result, providerOrder)
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

    private fun completeError(
        result: MethodChannel.Result,
        message: String,
        code: String = "native_test_error",
        details: Any? = null,
    ) {
        mainHandler.post {
            result.error(code, message, details)
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
        private val methodResult: MethodChannel.Result,
        private val providerOrder: List<String>,
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
                    if (cancelled) {
                        completeError(methodResult, "cancelled", "cancelled")
                        return@submit
                    }
                    val command = buildOoklaCommand()
                    emitProgress("download", 0.0, 0.20)
                    val output = executeCliCommand(command.args)
                    val parsed = parseOoklaResult(output)
                    emitProgress("upload", parsed.uploadMbps, 1.0)
                    completeSuccess(
                        methodResult,
                        parsed.downloadMbps,
                        parsed.uploadMbps,
                        parsed.serverInfo,
                    )
                } catch (error: CliBinaryMissingException) {
                    completeError(
                        methodResult,
                        error.message ?: "CLI binary missing",
                        "binary_missing",
                        mapOf(
                            "providerOrder" to providerOrder,
                            "supportedAbis" to (Build.SUPPORTED_ABIS?.toList() ?: emptyList<String>()),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
                } catch (error: CliExecutionException) {
                    completeError(
                        methodResult,
                        error.message ?: "CLI execution failed",
                        error.code,
                        error.details,
                    )
                } catch (error: Exception) {
                    completeError(
                        methodResult,
                        error.localizedMessage ?: "CLI execution failed",
                        details = mapOf(
                            "providerOrder" to providerOrder,
                            "supportedAbis" to (Build.SUPPORTED_ABIS?.toList() ?: emptyList<String>()),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
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
            val started = try {
                ProcessBuilder(args)
                    .redirectErrorStream(true)
                    .start()
            } catch (error: Exception) {
                throw CliExecutionException(
                    "binary_not_executable",
                    error.localizedMessage ?: "Failed to start CLI process",
                    mapOf(
                        "command" to args.joinToString(" "),
                        "cause" to (error.localizedMessage ?: error.javaClass.simpleName),
                    ),
                )
            }
            process = started
            val outputExecutor = Executors.newSingleThreadExecutor()
            val outputFuture = outputExecutor.submit<String> {
                started.inputStream.bufferedReader().use { it.readText() }
            }
            val finished = started.waitFor(CLI_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!finished) {
                started.destroyForcibly()
                val output = readOutputSafely(outputFuture)
                outputExecutor.shutdownNow()
                process = null
                throw CliExecutionException(
                    "cli_timeout",
                    "Speedtest CLI timed out",
                    mapOf(
                        "command" to args.joinToString(" "),
                        "output" to summarizeOutput(output),
                    ),
                )
            }
            val output = readOutputSafely(outputFuture)
            outputExecutor.shutdownNow()
            if (started.exitValue() != 0) {
                process = null
                throw CliExecutionException(
                    "cli_failed",
                    "CLI exited with ${started.exitValue()}: ${summarizeOutput(output)}",
                    mapOf(
                        "command" to args.joinToString(" "),
                        "exitCode" to started.exitValue(),
                        "output" to summarizeOutput(output),
                    ),
                )
            }
            process = null
            return output
        }

        private fun readOutputSafely(outputFuture: java.util.concurrent.Future<String>): String {
            return try {
                outputFuture.get(3, TimeUnit.SECONDS)
            } catch (_: Exception) {
                ""
            }
        }

        private fun buildOoklaCommand(): CliCommand {
            if (providerOrder.none { it == "ookla" }) {
                throw CliExecutionException(
                    "cli_provider_unavailable",
                    "No supported CLI provider in providerOrder",
                    mapOf(
                        "providerOrder" to providerOrder,
                        "supportedProviders" to listOf("ookla"),
                    ),
                )
            }
            val supportedAbis = Build.SUPPORTED_ABIS?.toList() ?: emptyList()
            for (abi in supportedAbis) {
                val assetPath = when (abi) {
                    "arm64-v8a" -> "cli/arm64-v8a/speedtest"
                    "armeabi-v7a" -> "cli/armeabi-v7a/speedtest"
                    "x86_64" -> "cli/x86_64/speedtest"
                    "x86" -> "cli/x86/speedtest"
                    else -> null
                } ?: continue
                val embedded = prepareEmbeddedBinary(assetPath, abi)
                if (embedded != null) {
                    return CliCommand(
                        listOf(
                            embedded.absolutePath,
                            "--accept-license",
                            "--accept-gdpr",
                            "--format=json",
                            "--progress=no",
                        ),
                    )
                }
            }
            throw CliBinaryMissingException(
                "CLI binary not bundled for supported ABIs: ${supportedAbis.joinToString(", ")}",
            )
        }

        private fun prepareEmbeddedBinary(assetPath: String, abi: String): File? {
            val outputDir = File(filesDir, "cli/$abi").apply { mkdirs() }
            val outputFile = File(outputDir, "speedtest")
            val input = try {
                assets.open(assetPath)
            } catch (_: Exception) {
                return null
            }
            input.use { stream ->
                FileOutputStream(outputFile).use { output ->
                    stream.copyTo(output)
                }
            }
            outputFile.setExecutable(true, true)
            if (!outputFile.canExecute()) {
                throw CliExecutionException(
                    "binary_not_executable",
                    "Extracted CLI binary cannot be executed ($abi)",
                )
            }
            return outputFile
        }

        private fun parseOoklaResult(raw: String): CliParsedResult {
            val jsonText = extractJsonObject(raw.trim()) ?: throw CliExecutionException(
                "json_parse_failed",
                "Failed to locate JSON payload in CLI output",
                mapOf("rawOutput" to summarizeOutput(raw)),
            )
            val json = try {
                JSONObject(jsonText)
            } catch (error: Exception) {
                throw CliExecutionException(
                    "json_parse_failed",
                    "Failed to parse CLI JSON: ${summarizeOutput(raw)}",
                    mapOf("rawOutput" to summarizeOutput(raw), "cause" to error.localizedMessage),
                )
            }
            val downloadBandwidth = json.optJSONObject("download")?.optDouble("bandwidth", 0.0) ?: 0.0
            val uploadBandwidth = json.optJSONObject("upload")?.optDouble("bandwidth", 0.0) ?: 0.0
            val download = if (downloadBandwidth > 0) {
                downloadBandwidth * 8 / 1_000_000
            } else {
                json.optDouble("download", 0.0) / 1_000_000
            }
            val upload = if (uploadBandwidth > 0) {
                uploadBandwidth * 8 / 1_000_000
            } else {
                json.optDouble("upload", 0.0) / 1_000_000
            }
            if (download <= 0 && upload <= 0) {
                throw CliExecutionException(
                    "json_parse_failed",
                    "Ookla CLI result parsing failed: ${summarizeOutput(raw)}",
                    mapOf("rawOutput" to summarizeOutput(raw)),
                )
            }
            val server = json.optJSONObject("server")
            val serverInfo = listOf(
                server?.optString("name"),
                server?.optString("location"),
                server?.optString("country"),
            ).filterNotNull().filter { it.isNotBlank() }.joinToString(" / ").ifBlank { null }
            return CliParsedResult(download, upload, serverInfo)
        }

        private fun extractJsonObject(raw: String): String? {
            if (raw.isBlank()) {
                return null
            }
            val start = raw.indexOf("{")
            val end = raw.lastIndexOf("}")
            if (start < 0 || end <= start) {
                return null
            }
            return raw.substring(start, end + 1)
        }

        private fun summarizeOutput(output: String): String {
            val normalized = output.replace("\n", " ").replace("\r", " ").trim()
            return if (normalized.length > 400) normalized.substring(0, 400) else normalized
        }
    }

    private class CliBinaryMissingException(message: String) : RuntimeException(message)
    private class CliExecutionException(
        val code: String,
        message: String,
        val details: Map<String, Any?>? = null,
    ) : RuntimeException(message)
    private data class CliCommand(val args: List<String>)
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
