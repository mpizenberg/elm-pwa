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

type Msg
    = GotPwaEvent (Result Decode.Error Pwa.Event)
    | AcceptUpdate
    | RequestInstall

subscriptions _ =
    pwaIn (Pwa.decodeEvent >> GotPwaEvent)

update msg model =
    case msg of
        GotPwaEvent (Ok event) ->
            case event of
                Pwa.ConnectionChanged online ->
                    ( { model | isOnline = online }, Cmd.none )

                Pwa.UpdateAvailable ->
                    ( { model | updateAvailable = True }, Cmd.none )

                Pwa.InstallAvailable ->
                    ( { model | installAvailable = True }, Cmd.none )

                Pwa.Installed ->
                    ( { model | installAvailable = False }, Cmd.none )

                Pwa.NotificationPermissionChanged permission ->
                    ( { model | notificationPermission = Just permission }, Cmd.none )

                Pwa.PushSubscription subscription ->
                    ( { model | pushSubscription = Just subscription }, Cmd.none )

                Pwa.PushUnsubscribed ->
                    ( { model | pushSubscription = Nothing }, Cmd.none )

                Pwa.NotificationClicked url ->
                    ( { model | lastNotificationUrl = Just url }, Cmd.none )

        GotPwaEvent (Err _) ->
            ( model, Cmd.none )

        AcceptUpdate ->
            ( model, Pwa.acceptUpdate pwaOut )

        RequestInstall ->
            ( model, Pwa.requestInstall pwaOut )
```

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

### Recommended flow

1. **Request permission** — call `Pwa.requestNotificationPermission pwaOut`. A `NotificationPermissionChanged` event arrives with the result.

2. **Subscribe** — once permission is `Granted`, call `Pwa.subscribePush pwaOut yourVapidPublicKey`. A `PushSubscription` event arrives with an opaque JSON value containing the push endpoint and keys.

3. **Send subscription to your backend** — forward the `PushSubscription` value to your server via HTTP. Your backend uses this to send push messages (via the Web Push protocol with your VAPID keys).

4. **Handle notification clicks** — when the user clicks a notification, a `NotificationClicked` event arrives with the target URL. Use this to navigate within your SPA.

```elm
update msg model =
    case msg of
        EnableNotifications ->
            ( model, Pwa.requestNotificationPermission pwaOut )

        GotPwaEvent (Ok (Pwa.NotificationPermissionChanged Pwa.Granted)) ->
            ( model, Pwa.subscribePush pwaOut myVapidPublicKey )

        GotPwaEvent (Ok (Pwa.PushSubscription subscription)) ->
            ( model, sendSubscriptionToBackend subscription )

        GotPwaEvent (Ok (Pwa.NotificationClicked url)) ->
            ( model, Nav.pushUrl model.key url )

        -- ...
```

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

## Cache busting

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

## How it works

The package uses a tagged JSON protocol over two generic ports:

**JS -> Elm** (`pwaIn`): `{ tag: "connectionChanged", online: true }`, `{ tag: "updateAvailable" }`, `{ tag: "notificationPermissionChanged", permission: "granted" }`, `{ tag: "pushSubscription", subscription: { ... } }`, `{ tag: "notificationClicked", url: "/path" }`, etc.

**Elm -> JS** (`pwaOut`): `{ tag: "acceptUpdate" }`, `{ tag: "requestInstall" }`, `{ tag: "requestNotificationPermission" }`, `{ tag: "subscribePush", vapidPublicKey: "BLkz..." }`, `{ tag: "unsubscribePush" }`

The JS `init()` function registers all browser event listeners and routes events
through `pwaIn`. It subscribes to `pwaOut` and dispatches commands to the
appropriate browser APIs.

The service worker is a separate file (generated by `generateSW`) that handles
caching independently. It also handles incoming push events (showing notifications)
and notification clicks (forwarding the URL to the Elm app via `postMessage`).
The main-page JS communicates with it via the standard `postMessage` /
`controllerchange` APIs for the update flow.
