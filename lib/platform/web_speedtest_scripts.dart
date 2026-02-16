import "../domain/models/speed_test_engine.dart";

String buildWebStartScript(SpeedTestEngine engine) {
  switch (engine) {
    case SpeedTestEngine.nperf:
      return _nperfAutoStart;
    case SpeedTestEngine.openSpeedTest:
      return _openSpeedTestAutoStart;
    case SpeedTestEngine.cloudflareWeb:
      return _cloudflareAutoStart;
    default:
      return "";
  }
}

const String baseBridgeScript = """
(function() {
  if (window.__speedtestBridgeInstalled) return;
  window.__speedtestBridgeInstalled = true;

  window.SpeedTestFlutterBridge = {
    emit: function(payload) {
      try {
        if (window.SpeedTestBridge && window.SpeedTestBridge.postMessage) {
          window.SpeedTestBridge.postMessage(JSON.stringify(payload));
        }
      } catch (_) {}
    }
  };

  window.addEventListener("message", function(event) {
    if (!event || !event.data) return;
    var data = event.data;
    if (typeof data === "string") {
      try { data = JSON.parse(data); } catch (_) { return; }
    }
    if (data && data.type && (data.type === "progress" || data.type === "result" || data.type === "error")) {
      window.SpeedTestFlutterBridge.emit(data);
    }
  });

  function parseByLabel(text, label) {
    var re = new RegExp(label + "[^0-9]{0,20}([0-9]+(?:\\\\.[0-9]+)?)", "i");
    var m = text.match(re);
    if (!m) return null;
    var value = parseFloat(m[1]);
    return isNaN(value) ? null : value;
  }

  var emitted = false;
  setInterval(function() {
    if (emitted || !document.body) return;
    var text = (document.body.innerText || "").replace(/\\s+/g, " ");
    var dl = parseByLabel(text, "download");
    var ul = parseByLabel(text, "upload");
    if (dl !== null && ul !== null) {
      emitted = true;
      window.SpeedTestFlutterBridge.emit({
        type: "result",
        downloadMbps: dl,
        uploadMbps: ul
      });
    }
  }, 1000);
})();
""";

const String _openSpeedTestAutoStart = """
(function() {
  var tries = 0;
  var timer = setInterval(function() {
    tries += 1;
    var btn = document.querySelector("#startStopBtn") ||
              document.querySelector(".start-button") ||
              document.querySelector("button[title*='Start']") ||
              Array.prototype.find.call(document.querySelectorAll("button"), function(el) {
                return /start/i.test(el.innerText || "");
              });
    if (btn) {
      btn.click();
      clearInterval(timer);
    }
    if (tries > 40) clearInterval(timer);
  }, 500);
})();
""";

const String _nperfAutoStart = """
(function() {
  var tries = 0;
  var timer = setInterval(function() {
    tries += 1;
    var btn = document.querySelector("#startButton") ||
              document.querySelector(".start-button") ||
              Array.prototype.find.call(document.querySelectorAll("button"), function(el) {
                return /start|go|test/i.test(el.innerText || "");
              });
    if (btn) {
      btn.click();
      clearInterval(timer);
    }
    if (tries > 60) clearInterval(timer);
  }, 500);
})();
""";

const String _cloudflareAutoStart = """
(function() {
  var clicked = false;
  var tries = 0;
  var clickTimer = setInterval(function() {
    tries += 1;
    if (clicked) return;
    var btn = Array.prototype.find.call(document.querySelectorAll("button"), function(el) {
      return /start|go|begin/i.test(el.innerText || "");
    });
    if (btn) {
      btn.click();
      clicked = true;
      clearInterval(clickTimer);
    }
    if (tries > 40) clearInterval(clickTimer);
  }, 500);
})();
""";
