# Progressive Web Apps with Elm

This document captures research on building Progressive Web Apps (PWAs) with Elm,
covering modern PWA best practices and Elm-specific integration patterns.

## What Makes a PWA

A PWA requires three things: HTTPS hosting, a web app manifest, and a service worker.
Together they enable installability, offline support, and native-app-like UX.

## Web App Manifest

The manifest is a JSON file linked from every HTML page:

```html
<link rel="manifest" href="/manifest.webmanifest" />
```

### Minimum Required Fields (for installability)

```jsonc
{
  "name": "My Elm App",
  "short_name": "ElmApp",
  "start_url": "/",
  "display": "standalone",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
  ],
}
```

Chrome requires `name` or `short_name`, `icons` (192x192 and 512x512), `start_url`,
and `display` set to `standalone`, `fullscreen`, or `minimal-ui`.

### Recommended Fields

```jsonc
{
  "name": "My Elm App",
  "short_name": "ElmApp",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#60B5CC",
  "description": "A description of the application",
  "scope": "/",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    {
      "src": "/icons/icon-maskable-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable",
    },
  ],
  "screenshots": [
    {
      "src": "/screenshots/wide.png",
      "sizes": "1280x720",
      "type": "image/png",
      "form_factor": "wide",
    },
    {
      "src": "/screenshots/narrow.png",
      "sizes": "750x1334",
      "type": "image/png",
      "form_factor": "narrow",
    },
  ],
}
```

Adding `screenshots` (with `form_factor: "wide"` and `"narrow"`) plus a `description`
transforms Android's install dialog into a richer app-store-like experience.

Provide a **maskable** icon variant for adaptive icon rendering on Android 8+.
Avoid transparent PNG icons -- iOS and Android fill transparency with an uncontrollable background color.

### Display Modes

Standard `display` values: `fullscreen`, `standalone`, `minimal-ui`, `browser`.

The `display_override` field provides a fallback chain of newer experimental modes:

- `window-controls-overlay` -- gives the PWA the full title bar area (desktop Chromium only)
- `tabbed` -- experimental; adds a tab strip to standalone apps

The browser picks the first supported value from `display_override`, then falls back to `display`.

### Elm-Specific Notes

Since Elm SPAs use `Browser.element` with client-side routing (see navigation example),
set `"start_url": "/"` and ensure your server returns `index.html` for all routes.
The manifest file itself has no Elm-specific considerations -- it is standard JSON
placed alongside the static assets.

## Service Workers

Service workers are entirely JavaScript -- Elm cannot directly create or run as a service worker.
The service worker is a separate `.js` file registered from `index.html`,
operating independently of the Elm runtime.

### Registration

```javascript
if ("serviceWorker" in navigator) {
  window.addEventListener("load", function () {
    navigator.serviceWorker.register("/sw.js");
  });
}
```

Best practice: register after `load` to avoid competing for bandwidth during initial page load.
Place the file at the root (`/sw.js`) so its scope covers the entire origin.

### Lifecycle

1. **Install** -- cache essential assets (the "app shell"). Use `event.waitUntil()` with cache operations.
2. **Activate** -- clean up old caches from previous versions.
3. **Fetch** -- intercept network requests and apply caching strategies.

### Caching Strategies

| Strategy                   | Use For                                           | Behavior                                           |
| -------------------------- | ------------------------------------------------- | -------------------------------------------------- |
| **Cache First**            | Static assets (elm.js, CSS, fonts, images)        | Check cache; on miss, fetch and cache              |
| **Network First**          | API responses, frequently updated content         | Try network; on failure, fall back to cache        |
| **Stale While Revalidate** | Semi-dynamic content (avatars, non-critical data) | Serve from cache immediately, update in background |
| **Cache Only**             | Versioned/immutable assets                        | Always serve from cache                            |
| **Network Only**           | Real-time data (auth tokens, payments)            | Always go to network                               |

### Recommended Strategy for Elm Apps

Elm compiles to a **single JS file**, which simplifies caching:

- **Cache First** for the Elm JS bundle (immutable once deployed if content-hashed)
- **Cache First** for CSS, fonts, and images
- **Network First** for API calls (fresh data when online, cached data when offline)
- **Stale While Revalidate** for non-critical assets

### Minimal Hand-Written Service Worker

```javascript
var CACHE_NAME = "elm-pwa-v1";
var PRECACHE_URLS = ["/", "/elm.js", "/style.css", "/manifest.webmanifest"];

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(PRECACHE_URLS);
    }),
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(
        names
          .filter(function (n) {
            return n !== CACHE_NAME;
          })
          .map(function (n) {
            return caches.delete(n);
          }),
      );
    }),
  );
});

self.addEventListener("fetch", function (event) {
  // For navigation requests, always serve the cached app shell
  // (Elm handles routing client-side)
  if (event.request.mode === "navigate") {
    event.respondWith(
      caches.match("/").then(function (cached) {
        return cached || fetch(event.request);
      }),
    );
    return;
  }
  event.respondWith(
    caches.match(event.request).then(function (cached) {
      return cached || fetch(event.request);
    }),
  );
});

// Only skip waiting when explicitly told to by the client
self.addEventListener("message", function (event) {
  if (event.data && event.data.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});
```

Bump `CACHE_NAME` (e.g., `"elm-pwa-v2"`) on each deploy to trigger the update flow
and purge stale caches.

### SPA-Specific Concern: Update Checking

In SPAs, the user rarely does full page navigations (Elm handles routing via `pushState`),
so the browser does not automatically check for service worker updates on in-app navigation.
You must manually trigger update checks:

```javascript
navigator.serviceWorker.register("/sw.js").then(function (registration) {
  // Check for updates periodically (SPAs stay on the same page for hours)
  setInterval(
    function () {
      registration.update();
    },
    60 * 60 * 1000,
  );

  // Also check when the user returns to the tab
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") {
      registration.update();
    }
  });
});
```

### Cache Busting for Elm Output

Since `elm make` always outputs to a fixed filename (e.g., `elm.js`),
you need a cache busting strategy:

- **Service worker versioning**: bump `CACHE_NAME` when assets change (simplest)
- **Content hashing**: hash the compiled output, rename (e.g., `elm.a1b2c3d4.js`), update the script tag
- **Build script**: a small script can automate hashing and manifest generation (see Build Tooling below)

### Update Notification Pattern

The complete flow to notify users and apply updates:

```javascript
// In index.html, after Elm.Main.init
navigator.serviceWorker.register("/sw.js").then(function (reg) {
  // Handle a SW that's already waiting (e.g., user reopened the tab)
  if (reg.waiting) {
    app.ports.onNewVersionAvailable.send(null);
  }

  // Detect new service workers becoming available
  reg.addEventListener("updatefound", function () {
    var newWorker = reg.installing;
    newWorker.addEventListener("statechange", function () {
      if (
        newWorker.state === "installed" &&
        navigator.serviceWorker.controller
      ) {
        // New version installed but waiting to activate
        app.ports.onNewVersionAvailable.send(null);
      }
    });
  });
});

// When the user accepts the update (triggered from Elm via port)
app.ports.acceptUpdate.subscribe(function () {
  navigator.serviceWorker.getRegistration().then(function (reg) {
    if (reg && reg.waiting) {
      reg.waiting.postMessage({ type: "SKIP_WAITING" });
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
```

Elm side:

```elm
port onNewVersionAvailable : (() -> msg) -> Sub msg
port acceptUpdate : () -> Cmd msg
```

The Elm app shows an "Update available" banner.
When the user clicks it, send `acceptUpdate ()`, which tells the waiting
service worker to `skipWaiting`, triggering `controllerchange` and a page reload.

## Why Workbox Is Unnecessary for Elm Apps

[Workbox](https://github.com/GoogleChrome/workbox) is the industry-standard library for service
worker management. However, Elm apps have a much simpler caching profile than typical JS SPAs:
a single compiled JS file, a CSS file, and a handful of static assets.
This makes Workbox's abstractions unnecessary overhead.

Here is what Workbox provides and the hand-written equivalent for an Elm PWA:

| Workbox Feature                           | Hand-Written Equivalent                                   | Lines of JS        |
| ----------------------------------------- | --------------------------------------------------------- | ------------------ |
| Precache manifest (file list + revisions) | Build script that hashes files and writes a JSON list     | ~15 (build script) |
| CacheFirst strategy                       | `caches.match(req).then(c => c \|\| fetch(req))`          | ~10                |
| NetworkFirst strategy                     | `fetch(req).catch(() => caches.match(req))`               | ~15                |
| StaleWhileRevalidate                      | Serve from cache, `fetch` in background, update cache     | ~12                |
| Cache expiration                          | Set `Date` header on cached responses; purge on activate  | ~20                |
| Navigation preload                        | Not needed -- Elm SPAs serve a single cached `index.html` | 0                  |
| workbox-window (update flow)              | `updatefound` + `controllerchange` listeners              | ~30                |

**Total: ~80-100 lines of hand-written service worker JS + a ~15 line build script**
replaces the entire Workbox dependency for a typical Elm PWA.

Key edge cases to handle in hand-written code:

- **Clone responses** before caching: `response.clone()` (a Response body can only be read once)
- **Check response status**: only cache `response.ok` responses (avoid caching error pages)
- **Opaque responses** (cross-origin, no CORS): have `status === 0` so `response.ok` is `false`;
  cache them explicitly if needed (e.g., external fonts)

The minimal service worker in the previous section already handles precaching, cache-first
for static assets, navigation fallback, cache cleanup, and the skip-waiting update flow.

## Elm/JS Boundary for PWA Features

### Ports for Online/Offline Detection

```javascript
// JS side
window.addEventListener("online", function () {
  app.ports.onConnectionChange.send(true);
});
window.addEventListener("offline", function () {
  app.ports.onConnectionChange.send(false);
});
// Also send initial state
app.ports.onConnectionChange.send(navigator.onLine);
```

```elm
-- Elm side
port onConnectionChange : (Bool -> msg) -> Sub msg

type alias Model =
    { isOnline : Bool
    , pendingActions : List Action
    }

update msg model =
    case msg of
        ConnectionChanged online ->
            if online then
                -- flush pending actions
                ...
            else
                ( { model | isOnline = False }, Cmd.none )

subscriptions model =
    onConnectionChange ConnectionChanged
```

Caveat: `navigator.onLine` is unreliable -- it only detects whether the device
has a network connection, not whether the internet is reachable.
Use it as a hint, not a guarantee.

### Service Worker as FFI (Alternative to Ports)

A pattern discussed on [Elm Discourse](https://discourse.elm-lang.org/t/service-worker-ffi/6408):
the service worker intercepts HTTP requests made by `elm/http` to specially-defined URLs
and returns computed responses. This turns `Http.get` into a kind of FFI
without needing port subscriptions.

Advantage: HTTP requests in Elm are ergonomic -- JSON encoding/decoding, tasks, error handling.
Limitation: service workers cannot access the DOM.

Key fact: [elm/http works with ServiceWorker](https://discourse.elm-lang.org/t/psa-elm-http-works-with-serviceworker/2562) --
any fetch request from the Elm app will be intercepted by the service worker.

### IndexedDB and Offline Data Storage

Elm has no native access to IndexedDB or localStorage.
Offline data persistence requires JS interop.

The Cache API (used by service workers) is for **network responses**.
IndexedDB is for **structured application data** that needs to be queried, updated, or synced.

Use [elm-indexeddb](https://github.com/mpizenberg/elm-indexeddb), which wraps IndexedDB
as composable `ConcurrentTask` values. It uses phantom types to enforce key discipline
at compile time and handles all IndexedDB operations (CRUD, batch, schema migrations).
See the [IndexedDB section in README.md](README.md#indexeddb-with-elm-indexeddb) for the full API.

Key advantages over raw ports for offline storage:

- **Composable**: chain DB reads, HTTP calls, and writes in a single task pipeline
- **Concurrent**: use `ConcurrentTask.map2`/`batch` to read multiple stores in parallel
- **Typed errors**: `AlreadyExists`, `QuotaExceeded`, etc. flow through the task chain
- **No port ping-pong**: a multi-step workflow is a single task, not multiple port round-trips

**Offline action queue**: queue failed writes in a dedicated store,
then replay them when connectivity returns (via the `online` event or Background Sync).

## Install Experience

### Install Criteria (Chrome, 2025)

- Served over HTTPS (or localhost)
- Valid web app manifest with required fields
- User has interacted with the page
- Not already installed

Note: a service worker with a fetch handler is **no longer required** for the install prompt
since Chrome 108 (mobile) and 112 (desktop).
Chrome provides a default offline page for apps without their own.
However, implementing a service worker is still recommended for a quality experience.

### Custom Install Button

`beforeinstallprompt` lets you capture the browser's install prompt and defer it
to show your own install UI:

```javascript
var deferredPrompt;
window.addEventListener("beforeinstallprompt", function (e) {
  e.preventDefault();
  deferredPrompt = e;
  // Notify Elm to show install button
  app.ports.onInstallAvailable.send(null);
});

// When user clicks your install button (triggered from Elm via port):
app.ports.requestInstall.subscribe(function () {
  if (deferredPrompt) {
    deferredPrompt.prompt();
    deferredPrompt.userChoice.then(function (choice) {
      deferredPrompt = null;
    });
  }
});
```

Browser support: Chromium only. Safari uses "Add to Home Screen" from the share menu.
Firefox 143+ supports PWA install on Windows.

## Push Notifications

Web Push is now supported across all major browsers:

| Platform                        | Status                                                |
| ------------------------------- | ----------------------------------------------------- |
| Chrome/Edge (desktop & Android) | Full support via VAPID keys                           |
| Firefox (desktop)               | Full support                                          |
| Safari (macOS)                  | Supported since Safari 16.1                           |
| Safari (iOS/iPadOS)             | Since iOS 16.4, only for installed (home screen) PWAs |

### Declarative Web Push (Safari 18.4+)

Apple introduced Declarative Web Push in Safari 18.4 (March 2025),
which does **not require a service worker** for push delivery.
This reduces battery/CPU usage and simplifies implementation.
Available on macOS (Safari 18.5+) and iOS/iPadOS 18.4+ for home screen web apps.

### Elm Integration Pattern

Push notifications operate entirely in the service worker context.
The Elm app participates only through ports:

1. **Permission request**: JS calls `Notification.requestPermission()`, sends result to Elm via port
2. **Subscription**: JS calls `PushManager.subscribe()`, sends the subscription endpoint to Elm,
   which forwards it to the backend
3. **Receiving pushes**: handled entirely by the service worker -- no Elm involvement
4. **Notification click**: the service worker can focus/open the app window

## Browser Support Summary (Early 2026)

| Feature         | Chrome | Edge | Firefox             | Safari (macOS) | Safari (iOS)         |
| --------------- | ------ | ---- | ------------------- | -------------- | -------------------- |
| Install PWA     | Yes    | Yes  | Windows only (143+) | No             | Home Screen only     |
| Service Workers | Yes    | Yes  | Yes                 | Yes            | Yes                  |
| Web Push        | Yes    | Yes  | Yes                 | Yes            | Yes (installed only) |
| Background Sync | Yes    | Yes  | No                  | No             | No                   |
| Badging API     | Yes    | Yes  | No                  | Partial        | No                   |

### iOS/Safari Limitations (Still Present in 2026)

- PWAs can only be installed from Safari (not Chrome/Edge on iOS)
- No Background Sync or Periodic Background Sync
- Storage may be purged if the PWA is unused for ~7 days
- `beforeinstallprompt` not supported; install is only via Safari's share menu

## Build Tooling

### Recommended Stack: elm-watch + esbuild + Hand-Written Files

The Elm philosophy is to minimize JS tool dependencies.
A PWA needs only a few static files alongside the Elm build tooling already in use:

```
static/
  index.html              # links manifest, registers SW
  manifest.webmanifest    # static JSON file
  sw.js                   # hand-written service worker (~80 lines)
  elm.js                  # compiled by elm-watch / elm make
  style.css               # compiled by tailwind or hand-written
  icons/
    icon-192.png
    icon-512.png
```

- **[elm-watch](https://lydell.github.io/elm-watch/)** handles Elm compilation with HMR in development
- **[esbuild](https://esbuild.github.io/)** minifies `elm.js` and other JS for production
- **brotli** compresses the output (already used in the project)
- **manifest.webmanifest** is a static JSON file, no generation needed
- **sw.js** is a hand-written file (~80-100 lines, see Service Workers section above)

This stack requires **zero additional npm dependencies** beyond what the project already uses.

### Optional: Precache Manifest Build Script

For automated cache busting, a small build script can hash files and inject
a precache manifest into the service worker:

```bash
#!/bin/sh
# generate-sw-manifest.sh -- hash static assets for precache manifest
ASSETS="static/elm.js static/style.css static/index.html"
echo "var PRECACHE_MANIFEST = ["
for f in $ASSETS; do
  HASH=$(sha256sum "$f" | cut -c1-8)
  echo "  { url: \"/${f#static/}\", revision: \"$HASH\" },"
done
echo "];"
```

Then in `sw.js`, use `PRECACHE_MANIFEST` to build `CACHE_NAME` and the URL list.
Alternatively, simply bump `CACHE_NAME` manually on each deploy -- this is sufficient
for most Elm apps where deploys are deliberate.

### Other Approaches

- **[elm-starter](https://github.com/lucamug/elm-starter)** -- Generates service worker config
  from Elm itself (`Starter/ServiceWorker.elm`). Supports prerendering for SEO.
- **Vite** with [vite-plugin-elm-watch](https://github.com/ryan-haskell/vite-plugin-elm-watch)
  and [vite-plugin-pwa](https://vite-pwa-org.netlify.app/guide/) provides automatic SW generation
  via Workbox, but adds significant JS tooling dependencies.

## Existing Elm PWA Examples

| Project                                                                                       | Approach                        | Notes                                             |
| --------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------- |
| [dwyl/elm-pwa-example](https://github.com/dwyl/elm-pwa-example)                               | Hand-written SW + PouchDB       | 100% Lighthouse score, offline data via IndexedDB |
| [dennistruemper/elm-land-pwa-example](https://github.com/dennistruemper/elm-land-pwa-example) | elm-land + simple SW            | Recent, deployed on Vercel                        |
| [fpapado/elm-pwa-basic-starter](https://github.com/fpapado/elm-pwa-basic-starter)             | Webpack + offline-plugin        | Webpack-centric, older                            |
| [lucamug/elm-starter](https://github.com/lucamug/elm-starter)                                 | Elm-generated SW + prerendering | SSG approach                                      |
| [halfzebra/elm-scrum-cards-pwa](https://github.com/halfzebra/elm-scrum-cards-pwa)             | create-elm-app                  | Simple example                                    |

## Lighthouse PWA Audit

The Lighthouse PWA audit checks three areas:

**Installable**: valid manifest with required fields, `prefer_related_applications` not set to `true`.

**PWA Optimized**: HTTPS, service worker registered, custom offline page (HTTP 200 when offline),
`theme_color` and proper viewport set, content sized for viewport, Apple touch icon provided.

**Performance**: Time to Interactive under 10 seconds on simulated slow 4G.
Core Web Vitals: LCP < 2.5s, INP < 200ms, CLS < 0.1.

## Key Architectural Insight

There is no "Elm PWA framework" -- PWA features are orthogonal to the Elm runtime.
Elm compiles to JS, and all PWA features (service workers, manifest, Cache API,
Push API, Background Sync) operate at the browser/network level outside Elm's scope.

The integration points are:

1. The service worker **caches the compiled Elm bundle** as part of the app shell
2. **Ports** bridge Elm to browser APIs for connectivity state, install prompts,
   notification permissions, and offline storage (IndexedDB)
3. `elm/http` requests are **transparently intercepted** by the service worker,
   enabling offline API responses without any changes to the Elm code

## Sources

- [MDN: Best practices for PWAs](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Best_practices)
- [web.dev: Learn PWA](https://web.dev/learn/pwa/)
- [Chrome: Workbox caching strategies](https://developer.chrome.com/docs/workbox/caching-strategies-overview)
- [Chrome: Revisiting installability criteria](https://developer.chrome.com/blog/update-install-criteria)
- [Chrome: Service worker lifecycle](https://developer.chrome.com/docs/workbox/service-worker-lifecycle)
- [Chrome: Handling service worker updates](https://developer.chrome.com/docs/workbox/handling-service-worker-updates)
- [Chrome: Precaching dos and don'ts](https://developer.chrome.com/docs/workbox/precaching-dos-and-donts)
- [WebKit: Features in Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)
- [Apple: Declarative Web Push (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/235/)
- [gHacks: Firefox 143 PWA support](https://www.ghacks.net/2025/09/16/mozilla-firefox-143-0-adds-support-for-progressive-web-apps-copilot-on-sidebar-important-dates-in-the-address-bar/)
- [Elm Discourse: Service Worker FFI](https://discourse.elm-lang.org/t/service-worker-ffi/6408)
- [Elm Discourse: elm/http works with ServiceWorker](https://discourse.elm-lang.org/t/psa-elm-http-works-with-serviceworker/2562)
- [Offline POST requests with Elm and Service Worker](https://notes.eellson.com/2018/02/26/offline-post-requests-with-elm-and-service-worker/)
- [Elm Guide: Asset Size Optimization](https://guide.elm-lang.org/optimization/asset_size.html)
- [elm-concurrent-task](https://github.com/andrewMacmurray/elm-concurrent-task)
- [dwyl/elm-pwa-example](https://github.com/dwyl/elm-pwa-example)
- [dennistruemper/elm-land-pwa-example](https://github.com/dennistruemper/elm-land-pwa-example)
- [lucamug/elm-starter](https://github.com/lucamug/elm-starter)
