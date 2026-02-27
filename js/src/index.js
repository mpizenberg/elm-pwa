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

  // --- Notification Permission (initial state) ---

  function sendNotificationPermission() {
    if (!("Notification" in window)) {
      pwaIn.send({
        tag: "notificationPermissionChanged",
        permission: "unsupported",
      });
    } else {
      pwaIn.send({
        tag: "notificationPermissionChanged",
        permission: Notification.permission,
      });
    }
  }
  sendNotificationPermission();

  // --- Service Worker Registration & Update Flow ---

  var swRegistration;

  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register(serviceWorkerUrl).then(function (reg) {
        swRegistration = reg;

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

        // Check for existing push subscription
        if (reg.pushManager) {
          reg.pushManager.getSubscription().then(function (sub) {
            if (sub) {
              pwaIn.send({
                tag: "pushSubscription",
                subscription: sub.toJSON(),
              });
            }
          });
        }
      });

      // Reload when the new SW takes control
      var refreshing = false;
      navigator.serviceWorker.addEventListener("controllerchange", function () {
        if (!refreshing) {
          refreshing = true;
          location.reload();
        }
      });

      // Listen for messages from the service worker (e.g., notification clicks)
      navigator.serviceWorker.addEventListener("message", function (event) {
        if (event.data && event.data.tag === "notificationClicked") {
          pwaIn.send({
            tag: "notificationClicked",
            url: event.data.url || "/",
          });
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

  // --- Detect installed PWA opened in the browser ---

  var isStandalone =
    window.matchMedia("(display-mode: standalone)").matches ||
    navigator.standalone === true;
  if (!isStandalone && "getInstalledRelatedApps" in navigator) {
    navigator.getInstalledRelatedApps().then(function (apps) {
      if (apps.length > 0) {
        pwaIn.send({ tag: "installedInBrowser" });
      }
    });
  }

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

      case "requestNotificationPermission":
        if (!("Notification" in window)) {
          pwaIn.send({
            tag: "notificationPermissionChanged",
            permission: "unsupported",
          });
        } else {
          Notification.requestPermission().then(function (result) {
            pwaIn.send({
              tag: "notificationPermissionChanged",
              permission: result,
            });
          });
        }
        break;

      case "subscribePush":
        if (!swRegistration || !swRegistration.pushManager) {
          break;
        }
        var vapidPublicKey = msg.vapidPublicKey;
        var padding = "=".repeat((4 - (vapidPublicKey.length % 4)) % 4);
        var base64 = (vapidPublicKey + padding)
          .replace(/-/g, "+")
          .replace(/_/g, "/");
        var rawKey = atob(base64);
        var keyArray = new Uint8Array(rawKey.length);
        for (var i = 0; i < rawKey.length; i++) {
          keyArray[i] = rawKey.charCodeAt(i);
        }
        swRegistration.pushManager
          .subscribe({
            userVisibleOnly: true,
            applicationServerKey: keyArray,
          })
          .then(function (sub) {
            pwaIn.send({
              tag: "pushSubscription",
              subscription: sub.toJSON(),
            });
          })
          .catch(function (err) {
            pwaIn.send({
              tag: "pushSubscriptionError",
              error: err
                ? err.message || String(err)
                : "Push subscription failed",
            });
          });
        break;

      case "unsubscribePush":
        if (swRegistration && swRegistration.pushManager) {
          swRegistration.pushManager.getSubscription().then(function (sub) {
            if (sub) {
              sub.unsubscribe().then(function () {
                pwaIn.send({ tag: "pushUnsubscribed" });
              });
            }
          });
        }
        break;
    }
  });
}
