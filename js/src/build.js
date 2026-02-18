/**
 * Generate a service worker file for an Elm PWA.
 *
 * This is a pure function: it takes a config object and returns
 * the complete service worker source code as a string.
 * The caller is responsible for writing it to disk.
 *
 * @param {Object} config
 * @param {string} config.cacheName - Cache version identifier (e.g., "my-app-v1")
 * @param {string[]} config.precacheUrls - URLs to cache during SW install
 * @param {string} [config.navigationFallback="/"] - Cached URL to serve for navigation requests
 * @param {string[]} [config.networkFirstPrefixes=[]] - URL path prefixes to serve network-first (e.g., ["/api/"])
 * @param {string[]} [config.networkOnlyPrefixes=[]] - URL path prefixes to serve network-only (e.g., ["/auth/"])
 * @returns {string} Complete service worker source code
 *
 * @example
 * // Node.js
 * import { generateSW } from "elm-pwa/build";
 * import { writeFileSync } from "node:fs";
 * writeFileSync("static/sw.js", generateSW({
 *   cacheName: "my-app-v1",
 *   precacheUrls: ["/", "/elm.js", "/style.css", "/manifest.webmanifest"],
 *   networkFirstPrefixes: ["/api/"],
 * }));
 *
 * @example
 * // Deno
 * import { generateSW } from "npm:elm-pwa/build";
 * Deno.writeTextFileSync("static/sw.js", generateSW({
 *   cacheName: "my-app-v1",
 *   precacheUrls: ["/", "/elm.js", "/style.css", "/manifest.webmanifest"],
 * }));
 *
 * @example
 * // Bun
 * import { generateSW } from "elm-pwa/build";
 * await Bun.write("static/sw.js", generateSW({
 *   cacheName: "my-app-v1",
 *   precacheUrls: ["/", "/elm.js", "/style.css", "/manifest.webmanifest"],
 * }));
 */
export function generateSW(config) {
  var configJson = JSON.stringify(
    {
      cacheName: config.cacheName,
      precacheUrls: config.precacheUrls,
      navigationFallback: config.navigationFallback || "/",
      networkFirstPrefixes: config.networkFirstPrefixes || [],
      networkOnlyPrefixes: config.networkOnlyPrefixes || [],
    },
    null,
    2,
  );
  return "var SW_CONFIG = " + configJson + ";\n" + SW_TEMPLATE;
}

// ---------------------------------------------------------------------------
// Service worker template
//
// Strategies:
//   - Install: precache the URLs listed in SW_CONFIG.precacheUrls
//   - Activate: delete old caches (any cache name !== SW_CONFIG.cacheName)
//   - Fetch (navigation): serve the cached navigation fallback (SPA shell)
//   - Fetch (routes): network-only and network-first prefix matching
//   - Fetch (default): cache-first, falling back to network
//   - Message "SKIP_WAITING": activate a waiting service worker immediately
//   - Push: show notifications from push events
//   - Notification click: focus or open the app at the notification's URL
// ---------------------------------------------------------------------------

var SW_TEMPLATE = `
// Install: cache the app shell
self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(SW_CONFIG.cacheName).then(function (cache) {
      return cache.addAll(SW_CONFIG.precacheUrls);
    })
  );
});

// Activate: clean up old caches
self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(
        names
          .filter(function (n) {
            return n !== SW_CONFIG.cacheName;
          })
          .map(function (n) {
            return caches.delete(n);
          })
      );
    })
  );
});

// Fetch: navigation fallback, route strategies, then cache-first default
self.addEventListener("fetch", function (event) {
  // Navigation requests: serve the cached app shell (Elm handles routing)
  if (event.request.mode === "navigate") {
    event.respondWith(
      caches.match(SW_CONFIG.navigationFallback).then(function (cached) {
        return cached || fetch(event.request);
      })
    );
    return;
  }

  // Route-specific strategies (network-only checked first, then network-first)
  var pathname = new URL(event.request.url).pathname;
  for (var i = 0; i < SW_CONFIG.networkOnlyPrefixes.length; i++) {
    if (pathname.startsWith(SW_CONFIG.networkOnlyPrefixes[i])) {
      event.respondWith(fetch(event.request));
      return;
    }
  }
  for (var i = 0; i < SW_CONFIG.networkFirstPrefixes.length; i++) {
    if (pathname.startsWith(SW_CONFIG.networkFirstPrefixes[i])) {
      event.respondWith(
        fetch(event.request)
          .then(function (response) {
            if (response.ok) {
              var clone = response.clone();
              caches.open(SW_CONFIG.cacheName).then(function (cache) {
                cache.put(event.request, clone);
              });
            }
            return response;
          })
          .catch(function () {
            return caches.match(event.request);
          })
      );
      return;
    }
  }

  // Default: cache-first
  event.respondWith(
    caches.match(event.request).then(function (cached) {
      return cached || fetch(event.request);
    })
  );
});

// Skip waiting when told to by the main page (update flow)
self.addEventListener("message", function (event) {
  if (event.data && event.data.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

// Push: show a notification from the push payload
self.addEventListener("push", function (event) {
  var payload = {};
  if (event.data) {
    try {
      payload = event.data.json();
    } catch (e) {
      payload = { title: event.data.text() || "New notification" };
    }
  }
  var title = payload.title || "New notification";
  var options = {
    body: payload.body || "",
    icon: payload.icon || "",
    badge: payload.badge || "",
    tag: payload.tag || "",
    data: payload.data || {},
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// Notification click: focus an existing window or open a new one
self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then(function (windowClients) {
        for (var i = 0; i < windowClients.length; i++) {
          var client = windowClients[i];
          if (new URL(client.url).origin === self.location.origin) {
            return client.focus().then(function (focusedClient) {
              focusedClient.postMessage({ tag: "notificationClicked", url: url });
            });
          }
        }
        return self.clients.openWindow(url);
      })
  );
});
`;
