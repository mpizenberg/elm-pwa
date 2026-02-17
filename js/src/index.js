/**
 * Initialize PWA event wiring between browser APIs and Elm ports.
 *
 * @param {Object} options
 * @param {Object} options.ports - The two Elm port objects
 * @param {Object} options.ports.pwaIn - Incoming port (JS -> Elm), must have `.send(value)`
 * @param {Object} options.ports.pwaOut - Outgoing port (Elm -> JS), must have `.subscribe(fn)`
 * @param {string} [options.swUrl="/sw.js"] - URL of the service worker file
 */
export function init({ ports, swUrl }) {
  var pwaIn = ports.pwaIn;
  var pwaOut = ports.pwaOut;
  var serviceWorkerUrl = swUrl || "/sw.js";

  // --- Online/Offline Detection ---

  function sendConnectionStatus() {
    pwaIn.send({ tag: "connectionChanged", online: navigator.onLine });
  }
  window.addEventListener("online", sendConnectionStatus);
  window.addEventListener("offline", sendConnectionStatus);

  // --- Service Worker Registration & Update Flow ---

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register(serviceWorkerUrl).then(function (reg) {
        // A new SW is already waiting (e.g., user reopened the tab)
        if (reg.waiting) {
          pwaIn.send({ tag: "updateAvailable" });
        }

        // Detect new service workers becoming available
        reg.addEventListener("updatefound", function () {
          var newWorker = reg.installing;
          newWorker.addEventListener("statechange", function () {
            if (
              newWorker.state === "installed" &&
              navigator.serviceWorker.controller
            ) {
              pwaIn.send({ tag: "updateAvailable" });
            }
          });
        });

        // Check for updates periodically (SPAs stay on the same page)
        setInterval(
          function () {
            reg.update();
          },
          60 * 60 * 1000,
        );

        // Also check when the user returns to the tab
        document.addEventListener("visibilitychange", function () {
          if (document.visibilityState === "visible") {
            reg.update();
          }
        });
      });

      // Reload when the new SW takes control
      var refreshing = false;
      navigator.serviceWorker.addEventListener("controllerchange", function () {
        if (!refreshing) {
          refreshing = true;
          location.reload();
        }
      });
    });
  }

  // --- Install Prompt ---

  var deferredPrompt;
  window.addEventListener("beforeinstallprompt", function (e) {
    e.preventDefault();
    deferredPrompt = e;
    pwaIn.send({ tag: "installAvailable" });
  });

  window.addEventListener("appinstalled", function () {
    pwaIn.send({ tag: "installed" });
  });

  // --- Commands from Elm ---

  pwaOut.subscribe(function (msg) {
    switch (msg.tag) {
      case "acceptUpdate":
        if ("serviceWorker" in navigator) {
          navigator.serviceWorker.getRegistration().then(function (reg) {
            if (reg && reg.waiting) {
              reg.waiting.postMessage({ type: "SKIP_WAITING" });
            }
          });
        }
        break;

      case "requestInstall":
        if (deferredPrompt) {
          deferredPrompt.prompt();
          deferredPrompt.userChoice.then(function () {
            deferredPrompt = null;
          });
        }
        break;
    }
  });
}
