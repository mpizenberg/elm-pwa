# elm-pwa

PWA integration for Elm apps via ports.

Provides an Elm module and a JS companion for connecting browser PWA APIs
(service worker lifecycle, install prompt, online/offline detection, push notifications)
to your Elm app through a single pair of ports.

## Setup

### 1. Define two ports in your Elm app

```elm
port pwaIn : (Decode.Value -> msg) -> Sub msg

port pwaOut : Encode.Value -> Cmd msg
```

### 2. Wire the Elm module

```elm
import Pwa

subscriptions _ =
    pwaIn (Pwa.decodeEvent >> GotPwaEvent)

update msg model =
    case msg of
        GotPwaEvent (Ok event) ->
            -- Handle each Pwa.Event variant (see API section below)
            ...

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut )

        RequestInstall ->
            ...

        ...
```

See [`examples/demo/src/Main.elm`](https://github.com/mpizenberg/elm-pwa/blob/main/examples/demo/src/Main.elm) for a complete working example
that handles all events.

### 3. Initialize the JS side

```javascript
import { init } from "elm-pwa";

var app = Elm.Main.init({
  node: document.getElementById("app"),
  flags: navigator.onLine,
});

init({
  ports: {
    pwaIn: app.ports.pwaIn,
    pwaOut: app.ports.pwaOut,
  },
});
```

### 4. Generate the service worker

The package provides a `generateSW` function that returns complete service worker
source code as a string. It has no dependencies — it works with Node.js, Deno, and Bun.

```javascript
// build-sw.mjs
import { generateSW } from "elm-pwa/build";
import { writeFileSync } from "node:fs";

writeFileSync(
  "static/sw.js",
  generateSW({
    cacheName: "my-app-v1",
    precacheUrls: [
      "/",
      "/elm.js",
      "/main.js",
      "/style.css",
      "/manifest.webmanifest",
    ],
  }),
);
```

Run it as part of your build:

```sh
node build-sw.mjs
```

Bump `cacheName` on each deploy to trigger the update flow and purge old caches.

### 5. Add a web app manifest

Create `manifest.webmanifest` with at least:

```json
{
  "name": "My App",
  "short_name": "App",
  "start_url": "/",
  "display": "standalone",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

Link it from your HTML:

```html
<link rel="manifest" href="/manifest.webmanifest" />
```

Chrome requires `name` or `short_name`, `icons` (192x192 and 512x512), `start_url`,
and `display` set to `standalone`, `fullscreen`, or `minimal-ui`.
See the [Web App Manifest](#web-app-manifest) section below for recommended fields.

## API

### Elm (`Pwa` module)

**Events** received via `pwaIn`:

| Event                                                  | Description                                                       |
| ------------------------------------------------------ | ----------------------------------------------------------------- |
| `ConnectionChanged Bool`                               | Device went online (`True`) or offline (`False`)                  |
| `UpdateAvailable`                                      | A new service worker is installed and waiting                     |
| `InstallAvailable`                                     | The browser's install prompt can be triggered                     |
| `Installed`                                            | The app was installed                                             |
| `NotificationPermissionChanged NotificationPermission` | Notification permission state changed                             |
| `PushSubscription Value`                               | Active push subscription (opaque JSON to forward to your backend) |
| `PushUnsubscribed`                                     | Push subscription was removed                                     |
| `NotificationClicked String`                           | A push notification was clicked, carrying the target URL          |

**Commands** sent via `pwaOut`:

| Function                               | Effect                                                           |
| -------------------------------------- | ---------------------------------------------------------------- |
| `acceptUpdate pwaOut`                  | Activates the waiting service worker (triggers page reload)      |
| `requestInstall pwaOut`                | Shows the browser's install dialog (Chromium only)               |
| `requestNotificationPermission pwaOut` | Requests notification permission from the user                   |
| `subscribePush pwaOut vapidKey`        | Subscribes to push notifications with the given VAPID public key |
| `unsubscribePush pwaOut`               | Unsubscribes from push notifications                             |

**Types:**

| `NotificationPermission` | Description                                                      |
| ------------------------ | ---------------------------------------------------------------- |
| `Granted`                | Notifications are allowed                                        |
| `Denied`                 | Notifications are blocked (user must change in browser settings) |
| `Default`                | The user has not been asked yet                                  |
| `Unsupported`            | The Notification API is not available in this browser            |

### JS (`init`)

```javascript
init({
  ports: { pwaIn, pwaOut }, // required: the two Elm port objects
  swUrl: "/sw.js", // optional: service worker URL (default: "/sw.js")
});
```

### JS (`generateSW`)

```javascript
generateSW({
  cacheName: "my-app-v1",       // required: cache version identifier
  precacheUrls: ["/", ...],     // required: URLs to cache during install
  navigationFallback: "/",      // optional: cached URL for navigation requests (default: "/")
  networkFirstPrefixes: ["/api/"],  // optional: path prefixes to serve network-first (default: [])
  networkOnlyPrefixes: ["/auth/"],  // optional: path prefixes to serve network-only (default: [])
})
// Returns: string (complete service worker source code)
```

The generated service worker uses three caching strategies, checked in this order:

1. **Navigation requests** — serve the cached navigation fallback (SPA routing)
2. **Network-only prefixes** — always fetch from the network, never cache
3. **Network-first prefixes** — try the network first, cache successful responses, fall back to cache when offline
4. **Everything else** — cache-first (serve from cache, fall back to network)

It also includes handlers for push notifications and notification clicks (zero overhead if push isn't used).

## Push Notifications

Push notifications let your backend send messages to users even when the app isn't open.
This package handles the client side — subscribing, receiving, and responding to notification clicks.

Web Push is supported across all major browsers:

| Platform                        | Status                                                |
| ------------------------------- | ----------------------------------------------------- |
| Chrome/Edge (desktop & Android) | Full support via VAPID keys                           |
| Firefox (desktop)               | Full support                                          |
| Safari (macOS)                  | Supported since Safari 16.1                           |
| Safari (iOS/iPadOS)             | Since iOS 16.4, only for installed (home screen) PWAs |

### Recommended flow

1. **Request permission** — call `Pwa.requestNotificationPermission pwaOut`. A `NotificationPermissionChanged` event arrives with the result.

2. **Subscribe** — once permission is `Granted`, call `Pwa.subscribePush pwaOut yourVapidPublicKey`. A `PushSubscription` event arrives with an opaque JSON value containing the push endpoint and keys.

3. **Send subscription to your backend** — forward the `PushSubscription` value to your server via HTTP. Your backend uses this to send push messages (via the Web Push protocol with your VAPID keys).

4. **Handle notification clicks** — when the user clicks a notification, a `NotificationClicked` event arrives with the target URL. Use this to navigate within your SPA.

See the push notification handling in [`examples/demo/src/Main.elm`](https://github.com/mpizenberg/elm-pwa/blob/main/examples/demo/src/Main.elm)
for a complete implementation.

### Push payload format

The service worker expects push payloads as JSON:

```json
{
  "title": "New message",
  "body": "You have a new message from Alice",
  "icon": "/icons/icon-192.png",
  "badge": "/icons/badge-72.png",
  "tag": "message-123",
  "data": { "url": "/messages/123" }
}
```

The `data.url` field determines which URL is sent in the `NotificationClicked` event.

### Declarative Web Push (Safari 18.4+)

Apple introduced Declarative Web Push in Safari 18.4 (March 2025),
which does **not require a service worker** for push delivery.
This reduces battery/CPU usage and simplifies implementation.
Available on macOS (Safari 18.5+) and iOS/iPadOS 18.4+ for home screen web apps.

## Web App Manifest

### Recommended fields

The [minimum required fields](#5-add-a-web-app-manifest) get your app installable.
For a polished experience, add these recommended fields:

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

### Display modes

Standard `display` values: `fullscreen`, `standalone`, `minimal-ui`, `browser`.

The `display_override` field provides a fallback chain of newer experimental modes:

- `window-controls-overlay` -- gives the PWA the full title bar area (desktop Chromium only)
- `tabbed` -- experimental; adds a tab strip to standalone apps

The browser picks the first supported value from `display_override`, then falls back to `display`.

### Elm-specific notes

Since Elm SPAs use `Browser.element` with client-side routing,
set `"start_url": "/"` and ensure your server returns `index.html` for all routes.
The manifest file itself has no Elm-specific considerations -- it is standard JSON
placed alongside the static assets.

## Caching Strategies

The `generateSW` function produces a service worker that combines several caching strategies.
Here is what each strategy does and when to use it:

| Strategy                   | Use for                                           | Behavior                                           |
| -------------------------- | ------------------------------------------------- | -------------------------------------------------- |
| **Cache First**            | Static assets (elm.js, CSS, fonts, images)        | Check cache; on miss, fetch and cache              |
| **Network First**          | API responses, frequently updated content         | Try network; on failure, fall back to cache        |
| **Stale While Revalidate** | Semi-dynamic content (avatars, non-critical data) | Serve from cache immediately, update in background |
| **Cache Only**             | Versioned/immutable assets                        | Always serve from cache                            |
| **Network Only**           | Real-time data (auth tokens, payments)            | Always go to network                               |

Elm compiles to a **single JS file**, which simplifies caching compared to typical JS SPAs.
The recommended configuration:

- **Cache First** for the Elm JS bundle, CSS, fonts, and images (via the default strategy)
- **Network First** for API calls via `networkFirstPrefixes: ["/api/"]`
- **Network Only** for auth endpoints via `networkOnlyPrefixes: ["/auth/"]`

### SPA update checking

In SPAs, the user rarely does full page navigations (Elm handles routing via `pushState`),
so the browser does not automatically check for service worker updates on in-app navigation.
The `init()` function handles this automatically by:

- Checking for updates periodically (every hour)
- Checking when the user returns to the tab (`visibilitychange` event)

## Cache Busting

By default, you bump `cacheName` manually on each deploy. For automated cache
invalidation, hash your assets in the build script and include the hash in the URL:

```javascript
// build-sw.mjs
import { generateSW } from "elm-pwa/build";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

function hash(file) {
  return createHash("sha256")
    .update(readFileSync(file))
    .digest("hex")
    .slice(0, 8);
}

var elmHash = hash("static/elm.js");
var cssHash = hash("static/style.css");

writeFileSync(
  "static/sw.js",
  generateSW({
    cacheName: "my-app-" + elmHash,
    precacheUrls: [
      "/",
      "/elm.js?v=" + elmHash,
      "/style.css?v=" + cssHash,
      "/manifest.webmanifest",
    ],
  }),
);
```

Then use the same query strings in your HTML `<script>` and `<link>` tags.
This way, `cacheName` changes automatically whenever the content changes,
triggering the update flow without manual version bumping.

## Install Experience

### Install criteria (Chrome)

- Served over HTTPS (or localhost)
- Valid web app manifest with required fields
- User has interacted with the page
- Not already installed

Note: a service worker with a fetch handler is **no longer required** for the install prompt
since Chrome 108 (mobile) and 112 (desktop).
Chrome provides a default offline page for apps without their own.
However, implementing a service worker is still recommended for a quality experience.

### Custom install button

`beforeinstallprompt` lets you capture the browser's install prompt and defer it
to show your own install UI. The `init()` function captures this event and sends
an `InstallAvailable` event to Elm. When the user clicks your install button,
call `Pwa.requestInstall pwaOut` to show the browser's native install dialog.

Browser support: Chromium only. Safari uses "Add to Home Screen" from the share menu.
Firefox 143+ supports PWA install on Windows.

## Elm/JS Integration Patterns

### Online/offline detection

The `init()` function listens for `online` and `offline` events and sends
`ConnectionChanged` events to Elm. Pass `navigator.onLine` as a flag for the initial state.

Caveat: `navigator.onLine` is unreliable -- it only detects whether the device
has a network connection, not whether the internet is reachable.
Use it as a hint, not a guarantee.

### Service worker as FFI

A pattern discussed on [Elm Discourse](https://discourse.elm-lang.org/t/service-worker-ffi/6408):
the service worker intercepts HTTP requests made by `elm/http` to specially-defined URLs
and returns computed responses. This turns `Http.get` into a kind of FFI
without needing port subscriptions.

Advantage: HTTP requests in Elm are ergonomic -- JSON encoding/decoding, tasks, error handling.
Limitation: service workers cannot access the DOM.

Key fact: [elm/http works with ServiceWorker](https://discourse.elm-lang.org/t/psa-elm-http-works-with-serviceworker/2562) --
any fetch request from the Elm app will be intercepted by the service worker.

### IndexedDB and offline data storage

Elm has no native access to IndexedDB or localStorage.
Offline data persistence requires JS interop.

The Cache API (used by service workers) is for **network responses**.
IndexedDB is for **structured application data** that needs to be queried, updated, or synced.

Use [elm-indexeddb](https://github.com/mpizenberg/elm-indexeddb), which wraps IndexedDB
as composable `ConcurrentTask` values. It uses phantom types to enforce key discipline
at compile time and handles all IndexedDB operations (CRUD, batch, schema migrations).

Key advantages over raw ports for offline storage:

- **Composable**: chain DB reads, HTTP calls, and writes in a single task pipeline
- **Concurrent**: use `ConcurrentTask.map2`/`batch` to read multiple stores in parallel
- **Typed errors**: `AlreadyExists`, `QuotaExceeded`, etc. flow through the task chain
- **No port ping-pong**: a multi-step workflow is a single task, not multiple port round-trips

**Offline action queue**: queue failed writes in a dedicated store,
then replay them when connectivity returns (via the `online` event or Background Sync).

## Browser Support (Early 2026)

| Feature         | Chrome | Edge | Firefox             | Safari (macOS) | Safari (iOS)         |
| --------------- | ------ | ---- | ------------------- | -------------- | -------------------- |
| Install PWA     | Yes    | Yes  | Windows only (143+) | No             | Home Screen only     |
| Service Workers | Yes    | Yes  | Yes                 | Yes            | Yes                  |
| Web Push        | Yes    | Yes  | Yes                 | Yes            | Yes (installed only) |
| Background Sync | Yes    | Yes  | No                  | No             | No                   |
| Badging API     | Yes    | Yes  | No                  | Partial        | No                   |

### iOS/Safari limitations

- PWAs can only be installed from Safari (not Chrome/Edge on iOS)
- No Background Sync or Periodic Background Sync
- Storage may be purged if the PWA is unused for ~7 days
- `beforeinstallprompt` not supported; install is only via Safari's share menu

## Lighthouse PWA Audit

The Lighthouse PWA audit checks three areas:

**Installable**: valid manifest with required fields, `prefer_related_applications` not set to `true`.

**PWA Optimized**: HTTPS, service worker registered, custom offline page (HTTP 200 when offline),
`theme_color` and proper viewport set, content sized for viewport, Apple touch icon provided.

**Performance**: Time to Interactive under 10 seconds on simulated slow 4G.
Core Web Vitals: LCP < 2.5s, INP < 200ms, CLS < 0.1.

## Build Tooling

### Recommended stack: elm-watch + esbuild + hand-written files

The Elm philosophy is to minimize JS tool dependencies.
A PWA needs only a few static files alongside the Elm build tooling already in use:

```
static/
  index.html              # links manifest, registers SW
  manifest.webmanifest    # static JSON file
  sw.js                   # generated by build-sw.mjs
  elm.js                  # compiled by elm-watch / elm make
  style.css               # compiled by tailwind or hand-written
  icons/
    icon-192.png
    icon-512.png
```

- **[elm-watch](https://lydell.github.io/elm-watch/)** handles Elm compilation with HMR in development
- **[esbuild](https://esbuild.github.io/)** minifies `elm.js` and other JS for production
- **brotli** compresses the output
- **manifest.webmanifest** is a static JSON file, no generation needed
- **sw.js** is generated by `generateSW` (see [step 4](#4-generate-the-service-worker))

This stack requires **zero additional npm dependencies** beyond what the project already uses.

### Other approaches

- **[elm-starter](https://github.com/lucamug/elm-starter)** -- Generates service worker config
  from Elm itself (`Starter/ServiceWorker.elm`). Supports prerendering for SEO.
- **Vite** with [vite-plugin-elm-watch](https://github.com/ryan-haskell/vite-plugin-elm-watch)
  and [vite-plugin-pwa](https://vite-pwa-org.netlify.app/guide/) provides automatic SW generation
  via Workbox, but adds significant JS tooling dependencies.

| Project                                                                                       | Approach                        | Notes                                             |
| --------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------- |
| [dwyl/elm-pwa-example](https://github.com/dwyl/elm-pwa-example)                               | Hand-written SW + PouchDB       | 100% Lighthouse score, offline data via IndexedDB |
| [dennistruemper/elm-land-pwa-example](https://github.com/dennistruemper/elm-land-pwa-example) | elm-land + simple SW            | Recent, deployed on Vercel                        |
| [fpapado/elm-pwa-basic-starter](https://github.com/fpapado/elm-pwa-basic-starter)             | Webpack + offline-plugin        | Webpack-centric, older                            |
| [lucamug/elm-starter](https://github.com/lucamug/elm-starter)                                 | Elm-generated SW + prerendering | SSG approach                                      |
| [halfzebra/elm-scrum-cards-pwa](https://github.com/halfzebra/elm-scrum-cards-pwa)             | create-elm-app                  | Simple example                                    |

## Roadmap

Features planned for future releases:

- **Stale-while-revalidate strategy** — serve from cache immediately while
  updating in the background. Useful for semi-dynamic content (avatars,
  non-critical data). Will be added as a `staleWhileRevalidatePrefixes`
  option in `generateSW`.

- **Background Sync** — queue failed requests (e.g., form submissions) and
  replay them when connectivity returns. Chromium-only but valuable for
  offline-capable apps that write data.

- **Badging API** — set unread counts on the installed app icon.
  Chromium-only, with partial Safari support.

## Demo

A live demo is deployed to Cloudflare Pages at
[elm-pwa-demo.pages.dev](https://elm-pwa-demo.pages.dev).
Deployments are triggered automatically by Cloudflare on each push to `main`.

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
