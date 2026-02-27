module Pwa exposing
    ( Event(..), decodeEvent
    , NotificationPermission(..)
    , acceptUpdate, requestInstall
    , requestNotificationPermission, subscribePush, unsubscribePush
    )

{-| PWA integration for Elm apps.

The app defines two ports:

    port pwaIn : (Decode.Value -> msg) -> Sub msg

    port pwaOut : Encode.Value -> Cmd msg

Then wires them as follows:

    subscriptions _ =
        pwaIn (Pwa.decodeEvent >> GotPwaEvent)

    update msg model =
        case msg of
            GotPwaEvent (Ok event) ->
                -- Handle each Pwa.Event variant
                ...
            AcceptUpdate ->
                ( model, Pwa.acceptUpdate pwaOut )
            RequestInstall -> ...
            ...


# Events

@docs Event, decodeEvent


# Types

@docs NotificationPermission


# Commands

@docs acceptUpdate, requestInstall
@docs requestNotificationPermission, subscribePush, unsubscribePush

-}

import Json.Decode as Decode
import Json.Encode as Encode


{-| Events sent from the JS runtime to Elm via the `pwaIn` port.

  - `ConnectionChanged True` — device went online
  - `ConnectionChanged False` — device went offline
  - `UpdateAvailable` — a new service worker is installed and waiting to activate
  - `InstallAvailable` — the browser's install prompt can be triggered (Chromium only)
  - `Installed` — the app was installed to the home screen / desktop
  - `InstalledInBrowser` — the PWA is installed but the user is viewing the site in the browser (Chromium only)
  - `NotificationPermissionChanged` — the notification permission state changed
  - `PushSubscription` — an active push subscription (opaque JSON to forward to your backend)
  - `PushSubscriptionError` — push subscription failed, carrying an error message
  - `PushUnsubscribed` — the push subscription was removed
  - `NotificationClicked` — a push notification was clicked, carrying the target URL.
    **Caveat**: on Safari 18.4+ with Declarative Web Push, notification clicks are
    handled natively by the browser (navigating directly to the URL) and this event
    will not fire.

-}
type Event
    = ConnectionChanged Bool
    | UpdateAvailable
    | InstallAvailable
    | Installed
    | InstalledInBrowser
    | NotificationPermissionChanged NotificationPermission
    | PushSubscription Encode.Value
    | PushSubscriptionError String
    | PushUnsubscribed
    | NotificationClicked String


{-| The state of the browser's notification permission.

  - `Granted` — notifications are allowed
  - `Denied` — notifications are blocked (the user must change this in browser settings)
  - `Default` — the user has not been asked yet
  - `Unsupported` — the Notification API is not available in this browser

-}
type NotificationPermission
    = Granted
    | Denied
    | Default
    | Unsupported


{-| Decode a JSON value from the `pwaIn` port into an `Event`.

    subscriptions _ =
        pwaIn (Pwa.decodeEvent >> GotPwaEvent)

-}
decodeEvent : Decode.Value -> Result Decode.Error Event
decodeEvent value =
    Decode.decodeValue eventDecoder value


eventDecoder : Decode.Decoder Event
eventDecoder =
    Decode.field "tag" Decode.string
        |> Decode.andThen
            (\tag ->
                case tag of
                    "connectionChanged" ->
                        Decode.field "online" Decode.bool
                            |> Decode.map ConnectionChanged

                    "updateAvailable" ->
                        Decode.succeed UpdateAvailable

                    "installAvailable" ->
                        Decode.succeed InstallAvailable

                    "installed" ->
                        Decode.succeed Installed

                    "installedInBrowser" ->
                        Decode.succeed InstalledInBrowser

                    "notificationPermissionChanged" ->
                        Decode.field "permission" notificationPermissionDecoder
                            |> Decode.map NotificationPermissionChanged

                    "pushSubscription" ->
                        Decode.field "subscription" Decode.value
                            |> Decode.map PushSubscription

                    "pushSubscriptionError" ->
                        Decode.field "error" Decode.string
                            |> Decode.map PushSubscriptionError

                    "pushUnsubscribed" ->
                        Decode.succeed PushUnsubscribed

                    "notificationClicked" ->
                        Decode.field "url" Decode.string
                            |> Decode.map NotificationClicked

                    _ ->
                        Decode.fail ("Unknown PWA event tag: " ++ tag)
            )


notificationPermissionDecoder : Decode.Decoder NotificationPermission
notificationPermissionDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "granted" ->
                        Decode.succeed Granted

                    "denied" ->
                        Decode.succeed Denied

                    "default" ->
                        Decode.succeed Default

                    "unsupported" ->
                        Decode.succeed Unsupported

                    _ ->
                        Decode.fail ("Unknown notification permission: " ++ str)
            )


{-| Tell the waiting service worker to activate, which triggers a page reload.

    update msg model =
        case msg of
            AcceptUpdate ->
                ( model, Pwa.acceptUpdate pwaOut )

-}
acceptUpdate : (Encode.Value -> Cmd msg) -> Cmd msg
acceptUpdate pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "acceptUpdate" ) ])


{-| Trigger the browser's install prompt (Chromium only).

    update msg model =
        case msg of
            RequestInstall ->
                ( model, Pwa.requestInstall pwaOut )

-}
requestInstall : (Encode.Value -> Cmd msg) -> Cmd msg
requestInstall pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "requestInstall" ) ])


{-| Request notification permission from the user.

Triggers a browser permission prompt (unless already granted or denied).
The result arrives as a `NotificationPermissionChanged` event.

    update msg model =
        case msg of
            EnableNotifications ->
                ( model, Pwa.requestNotificationPermission pwaOut )

-}
requestNotificationPermission : (Encode.Value -> Cmd msg) -> Cmd msg
requestNotificationPermission pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "requestNotificationPermission" ) ])


{-| Subscribe to push notifications with the given VAPID public key.

The VAPID key is a base64url-encoded string provided by your backend.
On success, a `PushSubscription` event arrives with the subscription JSON
to forward to your backend via HTTP.

    update msg model =
        case msg of
            SubscribePush ->
                ( model, Pwa.subscribePush pwaOut myVapidPublicKey )

-}
subscribePush : (Encode.Value -> Cmd msg) -> String -> Cmd msg
subscribePush pwaOut vapidPublicKey =
    pwaOut
        (Encode.object
            [ ( "tag", Encode.string "subscribePush" )
            , ( "vapidPublicKey", Encode.string vapidPublicKey )
            ]
        )


{-| Unsubscribe from push notifications.

On success, a `PushUnsubscribed` event arrives.

    update msg model =
        case msg of
            UnsubscribePush ->
                ( model, Pwa.unsubscribePush pwaOut )

-}
unsubscribePush : (Encode.Value -> Cmd msg) -> Cmd msg
unsubscribePush pwaOut =
    pwaOut (Encode.object [ ( "tag", Encode.string "unsubscribePush" ) ])
