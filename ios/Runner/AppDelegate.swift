import Flutter
import NDT7
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let methodChannelName = "speedtest"
  private let eventChannelName = "speedtest_progress"
  private var eventSink: FlutterEventSink?
  private var ndt7Test: NDT7Test?
  private var pendingResult: FlutterResult?
  private var lastDownloadMbps: Double = 0
  private var lastUploadMbps: Double = 0
  private var lastServerInfo: String?
  private var cancelRequested = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let flutterController = window?.rootViewController as? FlutterViewController {
      let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: flutterController.binaryMessenger)
      methodChannel.setMethodCallHandler { [weak self] call, result in
        self?.handleMethodCall(call: call, result: result)
      }

      let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: flutterController.binaryMessenger)
      eventChannel.setStreamHandler(self)
    }

    URLProtocol.registerClass(LocateOverrideURLProtocol.self)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startTest":
      startTest(arguments: call.arguments, result: result)
    case "cancelTest":
      cancelRequested = true
      ndt7Test?.cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startTest(arguments: Any?, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "already_running", message: "Speed test already running", details: nil))
      return
    }
    guard
      let map = arguments as? [String: Any],
      let engine = map["engine"] as? String,
      let downloadUrl = map["downloadUrl"] as? String,
      let uploadUrl = map["uploadUrl"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "engine, downloadUrl and uploadUrl are required", details: nil))
      return
    }
    if engine != "ndt7" {
      result(FlutterError(code: "unsupported_engine", message: "Selected engine is not implemented on native layer", details: nil))
      return
    }

    let locateOverride = buildLocateOverride(downloadUrl: downloadUrl, uploadUrl: uploadUrl)
    LocateOverrideURLProtocol.responseData = locateOverride
    cancelRequested = false
    pendingResult = result
    lastDownloadMbps = 0
    lastUploadMbps = 0
    lastServerInfo = URL(string: downloadUrl)?.host

    let settings = NDT7Settings()
    let test = NDT7Test(settings: settings)
    ndt7Test = test
    test.delegate = self
    test.startTest(download: true, upload: true) { [weak self] error in
      guard let self = self else { return }
      guard let pending = self.pendingResult else { return }
      self.pendingResult = nil
      LocateOverrideURLProtocol.responseData = nil

      if self.cancelRequested {
        pending(FlutterError(code: "cancelled", message: "Speed test cancelled", details: nil))
        return
      }
      if let error = error {
        pending(FlutterError(code: "native_test_error", message: error.localizedDescription, details: nil))
        return
      }
      pending([
        "downloadMbps": self.lastDownloadMbps,
        "uploadMbps": self.lastUploadMbps,
        "serverInfo": self.lastServerInfo as Any,
      ])
    }
  }

  private func buildLocateOverride(downloadUrl: String, uploadUrl: String) -> Data? {
    let insecureDownload = downloadUrl.replacingOccurrences(of: "wss://", with: "ws://")
    let insecureUpload = uploadUrl.replacingOccurrences(of: "wss://", with: "ws://")
    let payload: [String: Any] = [
      "results": [
        [
          "machine": URL(string: downloadUrl)?.host ?? "unknown",
          "location": [
            "city": "unknown",
            "country": "unknown",
          ],
          "urls": [
            "wss:///ndt/v7/download": downloadUrl,
            "wss:///ndt/v7/upload": uploadUrl,
            "ws:///ndt/v7/download": insecureDownload,
            "ws:///ndt/v7/upload": insecureUpload,
          ],
        ],
      ],
    ]
    return try? JSONSerialization.data(withJSONObject: payload)
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

extension AppDelegate: NDT7TestInteraction {
  func test(kind: NDT7TestConstants.Kind, running: Bool) {}

  func measurement(origin: NDT7TestConstants.Origin, kind: NDT7TestConstants.Kind, measurement: NDT7Measurement) {
    guard let appInfo = measurement.appInfo else {
      return
    }
    guard let elapsed = appInfo.elapsedTime, let numBytes = appInfo.numBytes, elapsed > 0 else {
      return
    }
    let elapsedSeconds = Double(elapsed) / 1_000_000
    let mbps = (Double(numBytes) * 8 / elapsedSeconds) / 1_000_000
    let phase: String = kind == .download ? "download" : "upload"
    if kind == .download {
      lastDownloadMbps = mbps
    } else {
      lastUploadMbps = mbps
    }
    let progress = min(max(Double(elapsed) / 10_000_000, 0), 1)
    eventSink?([
      "phase": phase,
      "mbps": mbps,
      "progress": progress,
    ])
  }

  func error(kind: NDT7TestConstants.Kind, error: NSError) {
    eventSink?([
      "phase": kind == .download ? "download" : "upload",
      "mbps": 0.0,
      "progress": 0.0,
      "error": error.localizedDescription,
    ])
  }
}

final class LocateOverrideURLProtocol: URLProtocol {
  static var responseData: Data?

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host else { return false }
    return host.contains("locate.measurementlab.net") && responseData != nil
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let data = LocateOverrideURLProtocol.responseData else {
      client?.urlProtocol(self, didFailWithError: NSError(domain: "LocateOverride", code: -1))
      return
    }
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://locate.measurementlab.net")!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
