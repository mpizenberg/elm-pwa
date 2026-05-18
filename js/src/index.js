/**
 * Display modes that mean "the page is running as an installed PWA window"
 * — no browser chrome. Note: chrome-less in-app WebViews (Discord, Slack,
 * some Android share-target launchers) can also match these. See
 * `requireStartUrlParam` in `init()` for hardening.
 */
var INSTALLED_DISPLAY_MODES = [
  "standalone",
  "fullscreen",
  "minimal-ui",
  "window-controls-overlay",
];

/**
 * @returns {boolean} true if the page is currently rendered with no browser
 * chrome (any "installed" display mode, or Safari's `navigator.standalone`).
 */
export function isStandalone() {
  return (
    navigator.standalone === true ||
    INSTALLED_DISPLAY_MODES.some(function (mode) {
      return window.matchMedia("(display-mode: " + mode + ")").matches;
    })
  );
}

/**
 * Heuristic in-app browser UA matcher. These WebViews can't install PWAs.
 * @param {string} userAgent
 * @returns {boolean}
 */
export function defaultIsInAppBrowser(userAgent) {
  return /FBAN|FBAV|Instagram|Line\/|Twitter|GSA\/|TikTok|Snapchat|Pinterest|LinkedIn|MicroMessenger|WeChat|Discord/.test(
    userAgent,
  );
}

function detectIsIos() {
  var ua = navigator.userAgent;
  return (
    /iPad|iPhone|iPod/.test(ua) ||
    // iPadOS 13+ reports as MacIntel; disambiguate via touch points.
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
  );
}

/** @returns {boolean} iOS/iPadOS running Safari (not Chrome/Firefox/Edge on iOS). */
export function isIosSafari() {
  var ua = navigator.userAgent;
  var isSafari = /Safari/.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua);
  return (
    detectIsIos() && "standalone" in navigator && isSafari
  );
}

/** @returns {boolean} macOS Safari 17+ context that supports "Add to Dock". */
export function isMacSafari() {
  var ua = navigator.userAgent;
  var isSafari =
    /Safari/.test(ua) && !/Chrome|CriOS|FxiOS|EdgiOS|Edg\//.test(ua);
  var isMac = /Macintosh/.test(ua) && navigator.maxTouchPoints <= 1;
  return isSafari && isMac;
}

/** @returns {boolean} Firefox on Android (no `beforeinstallprompt`; menu install). */
export function isAndroidFirefox() {
  var ua = navigator.userAgent;
  return /Android/.test(ua) && /Firefox\//.test(ua);
}

/**
 * Read the `start_url` hardening param if present. On first observation
 * within a tab, store a session flag and strip the param from the URL so
 * shared links can't propagate it.
 *
 * @param {string} name
 * @returns {boolean}
 */
function consumeStartUrlParam(name) {
  try {
    if (sessionStorage.getItem("elm-pwa:installed-launch") === "1") return true;
    var params = new URLSearchParams(window.location.search);
    if (!params.has(name)) return false;
    sessionStorage.setItem("elm-pwa:installed-launch", "1");
    params.delete(name);
    var newSearch = params.toString();
    var newUrl =
      window.location.pathname +
      (newSearch ? "?" + newSearch : "") +
      window.location.hash;
    window.history.replaceState(window.history.state, "", newUrl);
    return true;
  } catch (e) {
    return false;
  }
}

/**
 * Synchronously evaluate the install hint to show. Use this to compute the
 * initial Elm flag before `Elm.Main.init`. The same options should be passed
 * to `init({ ... })` so dynamic transitions agree with the initial value.
 *
 * @param {Object} [options]
 * @param {(ua: string) => boolean} [options.isInAppBrowser] - Override the
 *   default in-app browser detector.
 * @param {string|null} [options.requireStartUrlParam] - If set, demand a URL
 *   query param of this name to confirm a real PWA launch. Defeats the
 *   "Discord WebView looks standalone" false positive.
 * @returns {string} One of: "launchedAsInstalled", "installableNow",
 *   "manualIosSafari", "manualMacSafari", "manualAndroidMenu",
 *   "alreadyInstalledInBrowser", "noInstallHint".
 *
 *   Note: `evaluateInstallHint()` can never synchronously return
 *   `"installableNow"` (depends on `beforeinstallprompt` having fired) or
 *   `"alreadyInstalledInBrowser"` (depends on the async
 *   `getInstalledRelatedApps`). Those arrive via `installHintChanged` events.
 */
export function evaluateInstallHint(options) {
  options = options || {};
  var isInAppBrowserFn = options.isInAppBrowser || defaultIsInAppBrowser;
  var ua = navigator.userAgent;

  if (isStandalone()) {
    if (!options.requireStartUrlParam) return "launchedAsInstalled";
    if (consumeStartUrlParam(options.requireStartUrlParam))
      return "launchedAsInstalled";
    // Param missing. Chromium-based in-app WebViews (Discord, Slack, …) can
    // fake a standalone display mode — that's what the param is meant to
    // catch. Real Safari windows can't be spoofed that way, and Safari
    // historically ignored manifest `start_url` (iOS < 16.4; macOS "Add to
    // Dock" bookmarks the visible URL), so trust the standalone signal there.
    if (navigator.standalone === true || isIosSafari() || isMacSafari())
      return "launchedAsInstalled";
    // Otherwise fall through — likely a chrome-less in-app webview.
  }

  if (isInAppBrowserFn(ua)) return "noInstallHint";
  if (isIosSafari()) return "manualIosSafari";
  if (isMacSafari()) return "manualMacSafari";
  if (isAndroidFirefox()) return "manualAndroidMenu";
  return "noInstallHint";
}

/**
 * Initialize PWA event wiring between browser APIs and Elm ports.
 *
 * @param {Object} options
 * @param {Object} options.ports
 * @param {Object} options.ports.pwaIn
 * @param {Object} options.ports.pwaOut
 * @param {string} [options.swUrl="/sw.js"]
 * @param {(ua: string) => boolean} [options.isInAppBrowser]
 * @param {string|null} [options.requireStartUrlParam]
 */
export function init(options) {
  var ports = options.ports;
  var pwaIn = ports.pwaIn;
  var pwaOut = ports.pwaOut;
  var serviceWorkerUrl = options.swUrl || "/sw.js";
  var isInAppBrowser = options.isInAppBrowser;
  var requireStartUrlParam = options.requireStartUrlParam || null;

  // --- Install-hint state machine ---

  var deferredPrompt = null;
  var hasInstalledRelatedApp = false;

  function currentHint() {
    if (deferredPrompt) return "installableNow";
    var base = evaluateInstallHint({
      isInAppBrowser: isInAppBrowser,
      requireStartUrlParam: requireStartUrlParam,
    });
    if (base === "launchedAsInstalled") return base;
    if (hasInstalledRelatedApp) return "alreadyInstalledInBrowser";
    return base;
  }

  function emitHint() {
    var hint = currentHint();
    if (hint === lastHint) return;
    lastHint = hint;
    pwaIn.send({ tag: "installHintChanged", hint: hint });
  }

  // Seed lastHint with whatever the flag already showed, so we only emit on
  // genuine transitions. Callers pass the same options to `evaluateInstallHint`
  // for the flag and to `init` here, so the values match.
  var lastHint = currentHint();

  INSTALLED_DISPLAY_MODES.forEach(function (mode) {
    var mq = window.matchMedia("(display-mode: " + mode + ")");
    if (mq.addEventListener) {
      mq.addEventListener("change", emitHint);
    } else if (mq.addListener) {
      mq.addListener(emitHint);
    }
  });

  // --- Online/Offline Detection ---

  function sendConnectionStatus() {
    pwaIn.send({ tag: "connectionChanged", online: navigator.onLine });
  }
  window.addEventListener("online", sendConnectionStatus);
  window.addEventListener("offline", sendConnectionStatus);

  // --- Notification Permission (initial state) ---

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
            data: event.data.data || {},
          });
        }
      });
    });
  }

  // --- Install Prompt ---

  window.addEventListener("beforeinstallprompt", function (e) {
    e.preventDefault();
    deferredPrompt = e;
    emitHint();
  });

  window.addEventListener("appinstalled", function () {
    deferredPrompt = null;
    // display-mode change usually follows; emit now too for snappy UI.
    emitHint();
  });

  // --- Detect installed PWA opened in the browser ---

  if (!isStandalone() && "getInstalledRelatedApps" in navigator) {
    navigator.getInstalledRelatedApps().then(function (apps) {
      if (apps && apps.length > 0) {
        hasInstalledRelatedApp = true;
        emitHint();
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
            // Whether accepted or dismissed, Chrome won't fire
            // beforeinstallprompt again for this session. Drop it and
            // recompute the hint so the UI hides the button.
            deferredPrompt = null;
            emitHint();
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
