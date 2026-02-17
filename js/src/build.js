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
 * @returns {string} Complete service worker source code
 *
 * @example
 * // Node.js
 * import { generateSW } from "elm-pwa/build";
 * import { writeFileSync } from "node:fs";
 * writeFileSync("static/sw.js", generateSW({
 *   cacheName: "my-app-v1",
 *   precacheUrls: ["/", "/elm.js", "/style.css", "/manifest.webmanifest"],
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
//   - Fetch (other): cache-first, falling back to network
//   - Message "SKIP_WAITING": activate a waiting service worker immediately
//
// To add network-first for API routes, edit the generated sw.js and add
// a check in the fetch handler before the default cache-first block:
//
//   if (new URL(event.request.url).pathname.startsWith("/api/")) {
//     event.respondWith(
//       fetch(event.request).catch(function () {
//         return caches.match(event.request);
//       })
//     );
//     return;
//   }
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

// Fetch: navigation fallback + cache-first for static assets
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

  // Everything else: cache-first
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
`;
